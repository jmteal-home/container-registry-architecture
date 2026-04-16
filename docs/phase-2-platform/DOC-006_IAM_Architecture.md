---
document_id: DOC-006
title: "IAM Architecture"
phase: "PH-2 — Platform Architecture"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-006: IAM Architecture

| Document ID | DOC-006 |
| --- | --- |
| Phase | PH-2 — Platform Architecture |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Security Sensitive |
| Status | DRAFT — Pending CISO Review |
| Date | April 2026 |
| Depends On | [DOC-003](../phase-1-foundations/DOC-003_Threat_Model_Security_Posture.md) (Threat Model), [DOC-004](DOC-004_ACR_Service_Architecture.md) (ACR Service Arch), [DOC-005](DOC-005_Network_Topology_Connectivity.md) (Network) |
| Priority | P0 |

This document defines the complete Identity and Access Management architecture for the Enterprise Container Registry. It covers the Entra ID integration design, Workload Identity Federation for SDLC pipelines, Managed Identity assignments, ABAC role assignment specifications, service principal design, Privileged Identity Management for administrators, and the custom Token Broker identity model. This is a security-sensitive document — distribution restricted to architecture team and CISO office.

# 1. IAM Architecture Overview
The IAM architecture is built on three distinct identity planes, each serving a different class of consumer and using a different authentication mechanism. The architecture eliminates static, long-lived credentials wherever technically feasible and enforces the principle of least privilege at every identity boundary.

| **Identity Plane** | **Consumers** | **Auth Mechanism** | **Credential Type** | **Enforced By** |
| --- | --- | --- | --- | --- |
| Plane 1 — Internal SDLC | CI/CD pipelines, developer workstations, GitOps controllers, internal AKS clusters | Workload Identity Federation (OIDC) or Entra ID interactive | No static credentials. OIDC tokens (minutes TTL) or browser session tokens. | Entra ID + ABAC role assignments |
| Plane 2 — Platform Administration | Platform Engineering admins, break-glass accounts | Entra ID + MFA + PIM just-in-time activation | Session tokens — no standing privileged access. PIM activation required for admin roles. | Entra ID PIM + Conditional Access Policies |
| Plane 3 — External Customer | Customer Kubernetes, k3s, Docker, Portainer, wasmCloud | Token Broker-mediated: customer Entra ID External Identity → Token Broker → ACR scope-map token | Short-lived ACR refresh tokens (24h / 72h edge). No Entra ID direct ACR access for customers. | Token Broker + ACR non-Entra token API + Entitlement system |

# 2. Workload Identity Federation (WIF)
Workload Identity Federation enables CI/CD pipelines to authenticate to Azure services without storing any secrets. The pipeline's OIDC identity provider (Azure DevOps, GitHub, etc.) issues a short-lived JWT token that is exchanged for an Azure access token via a federated credential on a Managed Identity. This eliminates the entire class of credential theft and rotation failures.


## 2.1 WIF Design Principles
- Each product team's CI/CD pipeline uses a dedicated Managed Identity — no shared pipeline credentials

- The federated credential subject binding is scoped as tightly as possible (specific repository + branch or pipeline) to prevent token reuse by other pipelines

- The Managed Identity is granted ABAC-scoped write access only to the product team's repository namespace prefix in ACR

- No secrets are stored in the pipeline variables, key vaults referenced by pipelines, or source control


## 2.2 Azure DevOps WIF Configuration
Azure DevOps uses an OIDC-based Service Connection that federates with a Managed Identity. The subject claim in the OIDC token from Azure DevOps contains the service connection GUID, which is bound in the federated credential configuration.

| **Component** | **Configuration** | **Notes** |
| --- | --- | --- |
| Managed Identity | User-assigned MI: mi-acr-push-{product-name}-prod | One MI per product team. User-assigned (not system-assigned) for explicit lifecycle management. |
| Federated Credential Subject | sc://{ado-org}/{ado-project}/{service-connection-name} | Bound to specific ADO service connection. Token from a different service connection cannot use this MI. |
| ABAC Role Assignment | Container Registry Repository Writer — condition: repositories:name StringStartsWith 'products/{product}/' | Scoped to product namespace. MI cannot push to other namespaces. |
| Service Connection | Azure Service Connection of type 'Workload Identity federation' in Azure DevOps project settings | Configured with subscription ID and MI client ID. No secrets stored. |


```json
# Bicep: Federated credential on product team Managed Identity
resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: productAManagedIdentity
  name: 'ado-product-a-service-connection'
  properties: {
  audiences: ['api://AzureADTokenExchange']
  issuer: 'https://vstoken.dev.azure.com/{ado-org-id}'
  subject: 'sc://{ado-org}/{ado-project}/acr-push-product-a'   } }
```


## 2.3 GitHub Actions WIF Configuration
GitHub Actions uses OIDC tokens issued by the GitHub Actions OIDC provider. The subject claim encodes the repository, branch, and environment, enabling precise binding.

| **Component** | **Configuration** | **Notes** |
| --- | --- | --- |
| Managed Identity | User-assigned MI: mi-acr-push-{product-name}-prod | Same MI pattern as ADO. Different federated credentials for ADO vs GitHub if both are in use. |
| Federated Credential Subject | repo:{github-org}/{repo-name}:environment:production | Bound to specific repo + environment. PRs cannot use this MI — only production environment deployments. |
| Federated Credential Issuer | https://token.actions.githubusercontent.com | GitHub's OIDC provider endpoint |
| ABAC Role Assignment | Same as ADO — Container Registry Repository Writer scoped to product namespace | Identical ACR permissions regardless of CI/CD platform. |


```
# GitHub Actions workflow: authenticate with WIF and push to ACR
- name: Azure Login (WIF)
  uses: azure/login@v2
  with:

    client-id: ${{ secrets.AZURE_CLIENT_ID }}

# MI client ID — not a secret

    tenant-id: ${{ secrets.AZURE_TENANT_ID }}

# Tenant ID — not a secret

    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
- name: Login to ACR
  run:
az acr login --name {registry-name}

# Uses WIF token — no password
- name: Build and Push Image
  run: │

docker build -t {registry}.azurecr.io/products/product-a/api:${{ github.sha }} .

docker push {registry}.azurecr.io/products/product-a/api:${{ github.sha }}
```


## 2.4 Jenkins WIF Fallback (Service Principal)
Jenkins does not natively support OIDC Workload Identity Federation. The fallback design uses an Entra ID Service Principal with a client secret stored in Azure Key Vault, retrieved by the Jenkins pipeline via the Azure Key Vault Jenkins plugin at runtime. This eliminates static secrets in Jenkins credentials store.

- Service principal: sp-acr-push-{product-name} — dedicated per product team

- Client secret stored in Azure Key Vault: kv-{env}/secrets/jenkins-{product}-acr-push-sp-secret

- Secret rotation: automated 90-day rotation via Azure Key Vault auto-rotation with Key Vault event notification to Jenkins

- Jenkins plugin: Azure Credentials Plugin retrieves the secret from Key Vault at pipeline runtime — no static credential in Jenkins

- WIF adoption roadmap: Jenkins pipeline migration to WIF is tracked as a modernization backlog item (TARGET: Q4 2026)

# 3. Managed Identity Catalog
The following table is the authoritative catalog of all Managed Identities in the registry platform. This catalog is maintained in the IaC repository and reconciled quarterly against the Azure IAM baseline.

| **MI Name** | **Type** | **Purpose** | **ACR Role** | **Other Role Assignments** | **Lifecycle** |
| --- | --- | --- | --- | --- | --- |
| mi-acr-push-{product}-prod | User-assigned | Product team CI/CD push (ADO + GitHub WIF) | Repository Writer — products/{product}/* | None | Created at product team onboarding; deleted when product is decommissioned |
| mi-acr-gitops-{product}-prod | User-assigned | GitOps controller (ArgoCD/Flux) pull from ACR for SDLC staging | Repository Reader — products/{product}/* | AKS Kubelet Identity link for cluster attachment | Created at cluster provisioning; one per SDLC cluster per product |
| mi-acr-scanner | User-assigned | Microsoft Defender for Containers + supplementary scanners | Repository Reader (no ABAC condition — registry-wide read) + Repository Catalog Lister | Microsoft Defender for Cloud auto-provisioned assignment | Created at platform provisioning; never deleted |
| mi-token-broker | User-assigned | Token Broker service identity — calls ACR token issuance API | Container Registry Token Writer (control plane role for non-Entra token management — limited scope) | Redis Cache Data Contributor (for cache read/write); Key Vault Secrets User (for signing key) | Created at platform provisioning; never deleted |
| mi-acr-registry (system-assigned) | System-assigned | ACR's own identity for Key Vault CMK access | N/A — this is the registry resource itself | Key Vault Crypto Service Encryption User on CMK key | Auto-created with registry; lifecycle tied to registry resource |
| mi-platform-iac | User-assigned | IaC deployment pipeline (Bicep/Terraform) for platform infrastructure | Container Registry Contributor and Data Access Configuration Administrator (control plane) | Contributor on rg-container-registry-core, rg-container-registry-network | Created at platform provisioning; restricted to deployment service connection |
| mi-monitoring | User-assigned | Monitoring and observability agents (Log Analytics, Prometheus scraper) | Container Registry Configuration Reader and Data Access Configuration Reader | Monitoring Reader on registry resource group | Created at platform provisioning |
| mi-bastion-admin | User-assigned | Administrative access via Azure Bastion (jump host) for emergency access | None — admin uses their own PIM-activated identity, not this MI | Virtual Machine Contributor on admin jump host VMs | Created at platform provisioning |

# 4. Privileged Identity Management (PIM)
No standing privileged access to the registry platform is permitted. All elevated roles are governed by Entra ID Privileged Identity Management (PIM) with just-in-time activation, mandatory justification, and multi-factor authentication. This directly mitigates threat T-S-004 (Admin identity impersonation) from [DOC-003](../phase-1-foundations/DOC-003_Threat_Model_Security_Posture.md).


## 4.1 PIM-Governed Roles
| **Role** | **Scope** | **Eligible Principals** | **Activation Duration** | **MFA Required** | **Approver Required** | **Alert Trigger** |
| --- | --- | --- | --- | --- | --- | --- |
| Owner | rg-container-registry-core | Platform Engineering Lead (max 2 persons) | Max 4 hours | Yes | Yes — CISO or peer PE Lead | Any activation outside 06:00-22:00 UTC workdays |
| Container Registry Contributor and Data Access Configuration Administrator | ACR resource | Platform Engineering team (max 5 persons) | Max 8 hours | Yes | No — self-approval with justification | Any weekend or holiday activation |
| Key Vault Administrator | kv-registry-cmk | Platform Engineering Lead + Security Lead (max 3 persons) | Max 2 hours | Yes | Yes — dual approval (PE Lead + Security) | Any activation (always alerted) |
| Log Analytics Contributor (audit workspace) | rg-container-registry-monitoring | Security Operations team (max 3 persons) | Max 4 hours | Yes | Yes — Security Lead | Any activation |
| User Access Administrator | rg-container-registry-core | Platform Engineering Lead only (max 1 person) | Max 2 hours | Yes | Yes — CISO | Any activation (always alerted) |


## 4.2 PIM Conditional Access Policies
PIM activation is additionally gated by the following Conditional Access Policies to ensure admin operations originate from known, compliant devices:

- Policy CAP-001: PIM activation for Owner role requires compliant device (Microsoft Intune enrolled) AND named location (corporate network or approved VPN)

- Policy CAP-002: All admin roles require FIDO2 security key or Windows Hello for Business for MFA (phishing-resistant MFA)

- Policy CAP-003: Sign-in risk policy — high-risk sign-ins blocked from PIM activation regardless of other approvals

- Policy CAP-004: Session lifetime for PIM-activated sessions is limited to 4 hours — no persistent tokens


## 4.3 Break-Glass Accounts
Two break-glass accounts (emergency access accounts) are maintained for scenarios where the normal PIM activation path is unavailable (e.g., Entra ID authentication outage):

- break-glass-01@{tenant}: Owner on rg-container-registry-core. Credentials in physical safe, accessible only to CTO and CISO.

- break-glass-02@{tenant}: Owner on rg-container-registry-core. Backup — stored separately from break-glass-01.

- Break-glass accounts are excluded from all Conditional Access Policies (required for emergency access)

- Break-glass account usage triggers immediate SIEM alert and mandatory incident report within 24 hours

- Break-glass credentials are verified (not used) every 90 days to ensure they function

# 5. Customer Identity: Entra ID External Identities
External customers authenticate to the Token Broker using Entra ID External Identities (formerly Azure AD B2C or External Identities for B2B). This section defines the customer identity design and its integration with the Token Broker authentication flow.


## 5.1 Identity Model for Customers
| **Identity Scenario** | **Mechanism** | **Token Broker Integration** | **Notes** |
| --- | --- | --- | --- |
| Enterprise customer with Entra ID tenant | B2B Guest invitation — customer's corporate Entra ID identity federated as Guest in the company's Entra ID tenant | Token Broker validates the federated Entra ID JWT. Customer ID extracted from preferred_username or object_id claim. | Preferred for enterprise customers. Customer manages their own MFA. No password synchronization. |
| Enterprise customer without Entra ID | Entra ID External Identities (CIAM) — email + password or social IdP federation | Token Broker validates the CIAM-issued JWT. Customer ID from sub claim. | Used for customers without their own corporate IdP. Company manages the CIAM tenant. |
| Service account / machine identity | Service Principal in customer's own Entra ID tenant, federated as Guest | Token Broker validates SP token. Used for fully automated pull scenarios (CI/CD at customer, AKS workload identity). | Recommended for automated pulls — no human-interactive login required. |
| API key / shared secret (legacy) | Not supported. Deprecated pattern — all access must be through Entra ID or Token Broker-issued tokens. | N/A | API keys are explicitly prohibited by security principle P-SEC-2 (no long-lived credentials). No exceptions. |


## 5.2 Customer Identity Claim Mapping
The Token Broker extracts the customer identifier from the incoming JWT to query the entitlement system. The following claim mapping is used:


```
// Token Broker: customer identity extraction from validated JWT // Priority order for customer ID extraction: 1. oid (object_id) claim  — Entra ID object ID (stable, even if email changes) 2. sub claim
              — Subject identifier (CIAM / social IdP fallback) 3. appid claim
            — Application ID for service principal authentication // The customer ID is then used to query the entitlement system: // GET /api/v1/entitlements?customer_id={oid} // Response: { customer_id, products: [{product_id, version_range, active}] }
```


# 6. Token Broker Identity Architecture
The Token Broker's own identity architecture is a critical security design. The Token Broker must authenticate to ACR, Key Vault, Redis, and the Entitlement System using its Managed Identity — never using stored secrets.


## 6.1 Token Broker Authentication Flows
| **Target Service** | **Auth Method** | **Role / Permission** | **Token TTL** | **Notes** |
| --- | --- | --- | --- | --- |
| ACR (token issuance API) | Managed Identity (mi-token-broker) → Entra ID IMDS token exchange | Container Registry Token Writer — limited to non-Entra token management API | Entra ID access token: 1 hour, auto-refreshed | Token Writer role enables: list scope maps, create tokens, generateCredentials. Does NOT grant AcrPush, AcrPull, or any data plane access. |
| Azure Key Vault (signing key) | Managed Identity → Key Vault RBAC | Key Vault Crypto Service Encryption User on the token signing key | Key Vault access token: 1 hour | Token Broker signs its issued tokens with an RSA-2048 key stored in Key Vault. ACR validates the signature before accepting the token. Key rotation: 1 year with auto-rotation policy. |
| Azure Cache for Redis (entitlement cache) | Managed Identity → Redis RBAC (Entra ID authentication) | Redis Cache Data Contributor | Redis connection: persistent (connection pool) | Redis TLS port 6380. Connection string uses MI-based Entra ID token (no static Redis password). |
| Entitlement System API | Managed Identity → Entra ID + Entitlement system trusts the MI | Custom API scope registered in Entitlement system's app registration | Short-lived bearer token: 1 hour | Entitlement System team must register the Token Broker MI as an authorized caller. |
| Azure Monitor / OpenTelemetry | Managed Identity → Azure Monitor RBAC | Monitoring Metrics Publisher | OTel export: per-batch | Telemetry export for observability. Does not interact with registry data plane. |


## 6.2 Token Broker Token Signing Architecture
The Token Broker issues its own signed tokens (not raw ACR tokens) as the first factor of the customer authentication flow. These tokens are intermediary credentials that carry the customer's entitlement scope and are exchanged for ACR refresh tokens. The signing architecture ensures tokens cannot be forged:

- Signing algorithm: RS256 (RSA-2048 with SHA-256) — asymmetric; public key published as JWKS endpoint for verification

- Signing key: RSA-2048 private key in Azure Key Vault (kv-registry-cmk). Never leaves Key Vault — all signing operations use Key Vault Sign API

- Token claims: iss (issuer: token-broker.{company}.com), sub (customer ID), aud (ACR FQDN), iat, exp (24h / 72h), scope (space-separated repository list)

- Key rotation: annual automated rotation. Old key retained in Key Vault for 48h verification window. JWKS endpoint serves both old and new public key during rotation window

- ACR validation: ACR verifies the token signature using the published JWKS endpoint before accepting any scope-map token exchange

# 7. Identity Lifecycle Management

## 7.1 SDLC Identity Lifecycle
| **Event** | **Action** | **Responsible** | **SLO** | **Automated?** |
| --- | --- | --- | --- | --- |
| New product team onboarded | Create user-assigned MI for CI/CD; configure WIF federated credential; assign ABAC role to product namespace | Platform Engineering (self-service via IaC PR template) | 48 hours from approved request | Partially — IaC template automates MI + role assignment; PR review is manual |
| Product team namespace expansion (new product) | Update ABAC condition on existing MI to include new namespace prefix, OR create additional MI | Product team submits IaC PR; Platform Engineering approves | 24 hours | Partially |
| CI/CD pipeline moved to new tool (e.g., Jenkins → GitHub Actions) | Add new federated credential to MI for GitHub OIDC; deprecate old Service Principal if Jenkins was used | Platform Engineering + Product team | 48 hours | Partially |
| Product team offboarded / product decommissioned | Delete MI; remove ABAC role assignment; delete product namespace repositories (lifecycle policy) | Platform Engineering | 48 hours after approval | Partially — IaC PR destruction plan |
| Developer leaves company | Entra ID account disabled by HR/IT → all Entra ID tokens immediately invalidated; developer ACR access automatically revoked | HR/IT automated Entra ID lifecycle | Immediate (Entra ID account disable) | Yes — Entra ID lifecycle automation |


## 7.2 Customer Identity Lifecycle
| **Event** | **Action** | **Trigger** | **SLO** | **Notes** |
| --- | --- | --- | --- | --- |
| New customer account created | Entra ID External Identity account provisioned; no registry access granted yet (entitlement-driven) | Entitlement system account creation event | Immediate | Customer cannot pull any image until an entitlement is granted — default-deny model |
| Entitlement granted | Token Broker entitlement cache invalidated; next token request includes new repository scope | Entitlement system webhook → Token Broker event handler | Token effective on next pull (within 5 minutes) | Customers do not need new credentials — existing tokens updated on next refresh |
| Entitlement revoked | Token Broker cache entry for customer invalidated; ACR scope map updated to remove repository | Entitlement system webhook → Token Broker | Within 5 minutes for cache invalidation; current ACR token expires within 24h (72h for edge) | Running workloads are NOT interrupted — only new pulls are blocked post-token-expiry |
| Emergency account suspension | Token Broker immediately invalidates all tokens for customer; ACR scope map disabled | Manual emergency action or automated fraud detection trigger | Within 2 minutes | Emergency path bypasses cache TTL — direct ACR token disable API call |
| Customer offboarded | Entra ID External Identity account disabled; all Token Broker tokens immediately invalidated | Entitlement system account closure event | Immediate | Complete access revocation on account closure |


## 7.3 Identity Audit & Reconciliation
The following quarterly reconciliation processes ensure the IAM configuration remains accurate and does not drift from the IaC-defined baseline:

- RBAC Audit: automated Azure Policy compliance report for all ABAC role assignments — identifies any role assignments not present in IaC Git repository (potential unauthorized grants)

- Managed Identity Audit: Azure Resource Graph query listing all user-assigned MIs in registry resource groups — cross-reference against IaC catalog in Section 3

- PIM Eligible Assignment Audit: enumerate all PIM-eligible role assignments — compare against approved list in Section 4.1

- Customer Token Audit: Token Broker admin API exposes active token count per customer — review for anomalies (customers with tokens for decommissioned products)

- Service Principal Audit: Azure Entra ID app registrations for Jenkins service principals — verify none have excess permissions beyond ABAC role

# 8. Azure Policy Enforcement
The following Azure Policies enforce the IAM architecture as guardrails that prevent drift from the intended configuration. These policies are assigned at the resource group level of each registry-related resource group:

| **Policy Name** | **Effect** | **Condition** | **Rationale** |
| --- | --- | --- | --- |
| Deny ACR Admin User Enabled | Deny | If ACR resource adminUserEnabled = true | Constraint C-005: admin user provides static credentials. Enforced at provisioning time. |
| Deny ACR Anonymous Pull | Deny | If ACR resource anonymousPullEnabled = true | Zero-trust: no anonymous access. Enforced at provisioning time. |
| Deny ACR Public Network Access | Deny | If ACR resource publicNetworkAccess = Enabled | Private endpoints only. Enforced at provisioning time. |
| Deny AcrPush/AcrPull Role Assignment (ABAC mode) | Audit + Deny | If role assignment roleDefinitionId = AcrPush or AcrPull on ACR resources | Legacy roles not honored in ABAC mode. Prevent accidental misconfiguration. |
| Require CMK on ACR | Audit | If ACR resource does not have encryption.keyVaultProperties configured | Constraint C-006: CMK mandatory. Audit (not deny) because CMK must be configured at creation — post-creation deny would block updates. |
| Deny Owner/Contributor on Token Broker MI | Deny | If role assignment assigns Owner or Contributor to mi-token-broker principal | Prevent Token Broker MI privilege escalation (threat T-E-003 mitigation SC-20). |
| Require Resource Lock on Core Registry RG | Audit | If CanNotDelete lock not present on rg-container-registry-core | Prevent accidental registry deletion. |
| Deny Export Policy Disabled on ACR | Audit | If ACR exportPolicy.status = enabled | Prevent bulk image export. Audit (not deny) to allow emergency operational flexibility. |

# 9. Complete IAM Role Assignment Specification
This section provides the complete, authoritative role assignment specification for all registry platform identities. This table is the IaC source of truth for all ABAC role assignments and should be reconciled against the live Azure IAM configuration quarterly.

| **Identity** | **Role** | **Scope** | **ABAC Condition** | **Justification** |
| --- | --- | --- | --- | --- |
| mi-acr-push-{product}-prod (per product) | Container Registry Repository Writer | ACR resource | repositories:name StringStartsWith 'products/{product}/' | CI/CD push access — namespace isolated per product team |
| mi-acr-gitops-{product}-prod (per cluster) | Container Registry Repository Reader | ACR resource | repositories:name StringStartsWith 'products/{product}/' | GitOps pull for SDLC environments — namespace isolated |
| mi-acr-scanner | Container Registry Repository Reader | ACR resource | None (registry-wide) | Security scanning requires cross-namespace read |
| mi-acr-scanner | Container Registry Repository Catalog Lister | ACR resource | N/A — catalog lister is always registry-wide | Security scanner enumerates all repositories for compliance |
| mi-token-broker | Container Registry Token Writer | ACR resource | N/A — control plane role, not ABAC-eligible | Token Broker issues non-Entra scope-map tokens for customers |
| mi-platform-iac | Container Registry Contributor and Data Access Configuration Administrator | rg-container-registry-core | N/A — control plane only in ABAC mode | IaC pipeline manages registry configuration (policies, replication) |
| mi-monitoring | Container Registry Configuration Reader and Data Access Configuration Reader | rg-container-registry-core | N/A — read-only control plane | Observability tooling reads registry configuration metrics |
| mi-token-broker | Key Vault Crypto Service Encryption User | Key Vault CMK key | N/A — key-scoped role | Token signing key operations |
| mi-acr-registry (system-assigned) | Key Vault Crypto Service Encryption User | Key Vault CMK key | N/A | ACR CMK wrap/unwrap operations |
| mi-token-broker | Redis Cache Data Contributor | Redis Cache resource | N/A | Entitlement cache read/write operations |
| Platform Engineering (PIM-eligible) | Container Registry Contributor and Data Access Configuration Administrator | ACR resource | N/A — PIM elevated | Configuration management during change windows |
| Security Operations (PIM-eligible) | Log Analytics Contributor | Audit Log Analytics workspace | N/A — PIM elevated | Security investigation and log query access |
| Break-glass accounts (permanent) | Owner | rg-container-registry-core | N/A — break-glass exception | Emergency access when PIM path unavailable |

# 10. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — WIF design, MI catalog, PIM configuration, customer identity model, Token Broker identity, IAM lifecycle, Azure Policy, role assignment specification |
| 1.0 | TBD | Approved version — pending CISO review and Architecture Review Board sign-off |


>** Required Approvals:**  Chief Information Security Officer (primary approver — all IAM and PIM design), Chief Architect, Head of Platform Engineering. This document is SECURITY SENSITIVE — distribution restricted to architecture team, CISO office, and senior platform engineering.


	CONFIDENTIAL | Classification: Internal Architecture — Security Sensitive	Page  of
