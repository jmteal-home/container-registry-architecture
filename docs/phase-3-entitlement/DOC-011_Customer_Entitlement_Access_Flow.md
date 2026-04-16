---
document_id: DOC-011
title: "Customer Entitlement Access Flow Design"
phase: "PH-3 — Entitlement & Access Control"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-011: Customer Entitlement Access Flow Design

| Document ID | DOC-011 |
| --- | --- |
| Phase | PH-3 — Entitlement & Access Control |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | [DOC-009](DOC-009_Token_Broker_Architecture.md) (Token Broker), [DOC-008](DOC-008_Entitlement_Integration_Architecture.md) (Entitlement Integration), [DOC-002](../phase-1-foundations/DOC-002_Stakeholder_Consumer_Analysis.md) (Consumer Analysis) |
| Priority | P0 — Customer-facing access design |

This document defines the end-to-end customer access flow for every consumer runtime type defined in [DOC-002](../phase-1-foundations/DOC-002_Stakeholder_Consumer_Analysis.md). For each runtime, it specifies the authentication path, pull secret provisioning design, credential rotation mechanism, edge connectivity handling, and WASM runtime integration. This is the operational reference document for customer onboarding and support teams.

# 1. Universal Access Flow Overview
Despite the diversity of customer runtime types (AKS, on-premises Kubernetes, k3s, Docker, Portainer, wasmCloud), the customer access flow follows a consistent four-stage pattern. The runtime-specific sections (Sections 3-9) document the implementation details for each runtime while the core flow remains invariant:

| **Stage** | **Description** | **Universal Components** |
| --- | --- | --- |
| Stage 1 — Authentication | Customer runtime or human authenticates to Token Broker using their Entra ID identity | Entra ID JWT; Token Broker HTTPS endpoint; Azure Front Door WAF |
| Stage 2 — Entitlement Resolution | Token Broker resolves customer's entitled product list from EMS or cache | Entitlement cache (Redis); EMS API; Scope derivation rules ([DOC-008](DOC-008_Entitlement_Integration_Architecture.md)) |
| Stage 3 — Token Issuance | Token Broker issues scoped ACR refresh token covering entitled repositories only | ACR scope map API; ACR generateCredentials API; Token TTL policy |
| Stage 4 — Image Pull | Customer runtime uses ACR refresh token to authenticate and pull entitled images | ACR registry (private endpoint or internet HTTPS); OCI protocol; containerd/Docker pull |

# 2. Customer Onboarding Flow
Before any customer runtime can pull images, the customer account must be activated and credentials provisioned. This onboarding flow is triggered by entitlement system account creation:

| **1** | **Entitlement System** | New customer account created in EMS. Entitlements assigned for licensed products. EMS publishes entitlement.granted event. |
| --- | --- | --- |

| **2** | **Token Broker** | Receives entitlement.granted event. Pre-warms Redis cache with customer's initial scope. |
| --- | --- | --- |

| **3** | **Customer IT Team** | Receives onboarding email with: Token Broker endpoint URL, authentication instructions per runtime type, links to per-runtime configuration guides. |
| --- | --- | --- |

| **4** | **Customer IT Team** | Authenticates to Token Broker using their corporate Entra ID identity (B2B guest or CIAM account). Calls POST /v1/token to obtain initial ACR refresh token. |
| --- | --- | --- |

| **5** | **Customer IT Team** | Provisions ACR refresh token as runtime-specific credential (imagePullSecret, Docker config, k3s registries.yaml, etc.) per runtime-specific guides in Sections 3-9. |
| --- | --- | --- |


>** Self-Service Token Renewal:**  Customers can request new tokens at any time by calling POST /v1/token with their Entra ID JWT. The Token Broker always reflects current entitlements. There is no separate renewal API — every call to /v1/token issues a fresh token with the current scope.


# 3. Azure Kubernetes Service (AKS) Access Flow

## 3.1 Recommended: AKS Workload Identity + External Secrets
The recommended pattern for AKS uses Workload Identity Federation for machine authentication to Token Broker, with External Secrets Operator managing imagePullSecret lifecycle:

| **1** | **Customer AKS Setup** | Enable OIDC issuer on AKS cluster. Enable Workload Identity add-on. Create Kubernetes Service Account annotated with the customer's Entra ID application (Service Principal) client ID. |
| --- | --- | --- |

| **2** | **External Secrets Operator** | Install External Secrets Operator (ESO) in AKS cluster. Configure ClusterSecretStore with Azure Key Vault provider. |
| --- | --- | --- |

| **3** | **Token Renewal Job** | Deploy a CronJob (every 12 hours) that: authenticates to Token Broker using Workload Identity OIDC token, calls POST /v1/token, stores returned token in Azure Key Vault. |
| --- | --- | --- |

| **4** | **External Secrets Operator** | ExternalSecret resource syncs ACR token from Azure Key Vault to Kubernetes Secret (type: kubernetes.io/dockerconfigjson) in each namespace that requires image pulls. |
| --- | --- | --- |

| **5** | **Kubernetes Scheduler** | Pod spec references imagePullSecret. Kubelet uses credentials to authenticate with ACR for image pull at pod scheduling time. |
| --- | --- | --- |


```yaml
# ExternalSecret
resource — syncs Token Broker token from Key Vault to K8s Secret

apiVersion: external-secrets.io/v1beta1

kind: ExternalSecret

metadata:
  name: acr-pull-secret
  namespace: production

spec:
  refreshInterval: 1h
  secretStoreRef:
  name: azure-keyvault-store

kind: ClusterSecretStore
  target:
  name: acr-imagepullsecret
  template:

  type: kubernetes.io/dockerconfigjson

  data:
        .dockerconfigjson: │
          {'auths':{{registry}:{{'username':'00000000-0000-0000-0000-000000000000','password':'{{ .token }}'}}}}
  data:

- secretKey: token

  remoteRef:

  key: acr-customer-token

# Key Vault secret name

  version: latest
```


# 4. Self-Managed Kubernetes (On-Premises) Access Flow
On-premises Kubernetes clusters use a similar External Secrets Operator pattern, with connectivity to Azure Key Vault via VPN or ExpressRoute:

- Authentication: Service Principal (client credentials flow) against Entra ID. SP credentials stored in on-premises secret management (HashiCorp Vault or equivalent). SP used to authenticate to Token Broker and to Azure Key Vault.

- Token Broker call: POST /v1/token with SP-acquired Entra ID JWT (client_credentials grant, audience = Token Broker app ID). Token stored in on-premises Vault.

- imagePullSecret provisioning: External Secrets Operator with HashiCorp Vault provider (or Azure Key Vault via VPN). Auto-rotates imagePullSecret before 24h TTL expires.

- Alternative (simpler): CronJob in cluster calls Token Broker every 12h, updates imagePullSecret via kubectl. No ESO dependency.

# 5. k3s (Edge) Access Flow

## 5.1 Tier 1 — Always Connected k3s
For always-connected k3s sites, the standard Token Broker flow applies with k3s-specific credential injection:

- Token acquisition: automated shell script or systemd timer calls Token Broker API with stored Entra ID client credentials. Stores token in /etc/rancher/k3s/registries.yaml.

- Token TTL: 72 hours (edge TTL) — request with X-Registry-Edge: true header to Token Broker. Reduces rotation frequency for edge nodes.

- Rotation: systemd timer every 48h (before 72h expiry). k3s auto-reloads registries.yaml without restart.


## 5.2 Tier 2 — Intermittent k3s (Connected Registry)
For intermittent-connectivity k3s sites, a Connected Registry is deployed as the local pull source:

- Connected Registry deployed via Azure Arc extension on the k3s node or separate server on site LAN

- Sync token: non-Entra ACR token stored securely; used by Connected Registry to sync entitled repositories from cloud ACR during connectivity windows

- k3s registries.yaml: configured to use Connected Registry local IP as mirror; falls back to cloud ACR if connected

- Client tokens: non-Entra ACR client tokens for k3s nodes to authenticate with Connected Registry. Rotate via Token Broker-coordinated process during connectivity windows.


> # /etc/rancher/k3s/registries.yaml — k3s Connected Registry configuration mirrors:   '{registry}.azurecr.io':     endpoint:       - 'https://192.168.1.100'          # Connected Registry local IP (Tier 2)       - 'https://{registry}.azurecr.io'  # Cloud fallback (when connected) configs:   '192.168.1.100':     auth:       username: '{connected-registry-client-token-username}'       password: '{connected-registry-client-token-password}'     tls:       ca_file: /etc/k3s/connected-registry-ca.crt   '{registry}.azurecr.io':     auth:       username: '00000000-0000-0000-0000-000000000000'       password: '{token-broker-issued-72h-token}'


# 6. Portainer Access Flow
Portainer supports registry configuration via its UI and API. The customer experience is:

- Step 1: Customer IT authenticates to Token Broker → obtains ACR refresh token

- Step 2: In Portainer → Settings → Registries → Add Registry → Custom Registry. Enter: Registry URL = {registry}.azurecr.io, Username = 00000000-0000-0000-0000-000000000000, Password = {token-broker-token}

- Step 3: Portainer stores credentials securely. When deploying stacks or containers referencing the registry, Portainer injects credentials at pull time.

- Token rotation challenge: Portainer does not natively integrate with External Secrets. Provide customers with a rotation script using the Portainer API: curl -X PUT /api/registries/{id} with updated password. Script called by cron/Task Scheduler every 12h.

# 7. Docker (Bare Metal / VM) Access Flow
Docker standalone deployments use the standard docker login flow with automated credential rotation:


> #!/bin/bash # /usr/local/bin/refresh-acr-credentials.sh # Called by systemd timer every 12 hours (before 24h token TTL) # Acquire Entra ID token using managed identity (if Azure VM) or SP credentials ENTRA_TOKEN=$(curl -s -X POST 'https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token' \   --data-urlencode 'grant_type=client_credentials' \   --data-urlencode 'client_id={sp_client_id}' \   --data-urlencode 'client_secret={sp_secret_from_vault}' \   --data-urlencode 'scope={token_broker_app_id}/.default' │ jq -r '.access_token') # Call Token Broker ACR_TOKEN=$(curl -s -X POST 'https://token-broker.{company}.com/v1/token' \   -H "Authorization: Bearer $ENTRA_TOKEN" \   -H 'Content-Type: application/json' \   -d '{"registry":"{registry}.azurecr.io"}' │ jq -r '.acr_refresh_token') # Update Docker credentials echo $ACR_TOKEN │ docker login {registry}.azurecr.io \   -u '00000000-0000-0000-0000-000000000000' --password-stdin echo 'ACR credentials refreshed at '$(date)


# 8. wasmCloud / Cosmonic Control Access Flow
WASM runtime consumers use the same Token Broker authentication as container runtimes, with WASM-specific credential injection patterns:


## 8.1 wasmCloud OSS Host
- Token acquisition: systemd service or init container calls Token Broker API. Token stored in environment file or Kubernetes Secret.

- Credential injection: WASMCLOUD_OCI_REGISTRY, WASMCLOUD_OCI_REGISTRY_USER, WASMCLOUD_OCI_REGISTRY_PASSWORD environment variables. Set in Kubernetes Pod spec from Secret.

- Token rotation: same rotation pattern as container imagePullSecrets. wasmCloud host re-reads credentials on next component pull.


## 8.2 Cosmonic Control
- Per-artifact credential: imagePullSecret in WorkloadDeployment CRD (see [DOC-007 Section 4.3](../phase-2-platform/DOC-007_WASM_Artifact_Registry_Extension.md)). External Secrets Operator syncs Token Broker token to Kubernetes Secret.

- Air-gapped override: global.image.registry and global.image.pullSecrets in Cosmonic Helm values. Point to local mirror populated by ORAS backup/restore workflow.

- OIDC-integrated deployment: Cosmonic Control supports OIDC for platform access; component-level OCI pull still uses imagePullSecret convention.

# 9. Air-Gapped / Offline Bundle Provisioning
For fully disconnected customer deployments, the following offline bundle flow is used:

| **1** | **Customer IT** | Requests offline bundle for entitled product(s) via the customer portal or support ticket. Specifies: product list, version range, target platform (container / wasm / helm). |
| --- | --- | --- |

| **2** | **Platform Engineering** | Validates request against entitlement system — confirms customer is entitled to all requested products. Generates bundle using oras backup for each entitled namespace. |
| --- | --- | --- |

| **3** | **Platform Engineering** | Signs the bundle manifest with the platform signing key. Packages bundle tarball with manifest, signature, and platform public key for offline verification. |
| --- | --- | --- |

| **4** | **Secure Distribution** | Bundle delivered via secure SFTP, encrypted email attachment, or physical media (USB) depending on customer security requirements. |
| --- | --- | --- |

| **5** | **Customer IT** | Verifies bundle signature using bundled public key. Runs oras restore to import to local registry or docker load for direct import. |
| --- | --- | --- |

| **6** | **Customer IT** | Configures runtime (Docker, k3s, wasmCloud) to reference local registry or pre-loaded images. No ongoing registry connectivity required. |
| --- | --- | --- |

# 10. Credential Rotation Summary
The following table consolidates credential rotation patterns across all customer runtime types:

| **Runtime** | **Token TTL** | **Rotation Trigger** | **Rotation Mechanism** | **Rotation Failure Impact** |
| --- | --- | --- | --- | --- |
| AKS (External Secrets) | 24h | ESO refreshInterval (1h checks) | ESO CronJob calls Token Broker → updates Kubernetes Secret automatically | Pod scheduling failures if Secret not updated before TTL; ESO alerts on failure |
| On-Premises K8s | 24h | CronJob every 12h | CronJob calls Token Broker → kubectl patch secret | New pod pull failures until rotation completes; existing pods unaffected (cached layers) |
| k3s Tier 1 | 72h (edge) | systemd timer every 48h | Shell script calls Token Broker → updates registries.yaml | k3s pull failures during 72h window after token expiry; retries on next timer |
| k3s Tier 2 (Connected) | N/A — Connected Reg | Maintenance window sync | Connected Registry sync during connectivity window | Local mirror serves cached images; no new pulls from cloud until reconnected |
| Portainer | 24h | cron script every 12h | Portainer API PATCH /api/registries/{id} with new token | New deployments fail until rotation; existing containers unaffected |
| Docker standalone | 24h | systemd timer every 12h | Shell script calls Token Broker → docker login | docker pull failures after TTL; existing containers unaffected |
| wasmCloud / Cosmonic | 24h | ESO or K8s CronJob | Same as AKS or standalone K8s pattern | New component deployments fail; running components unaffected (already pulled) |
| Air-gapped / offline | N/A — bundle validity | Manual bundle request | ORAS backup/restore + secure distribution | No impact during bundle validity; customer must request new bundle before expiry |

# 11. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — universal flow, onboarding, AKS/on-prem/k3s/Portainer/Docker/wasmCloud/air-gapped per-runtime flows, credential rotation summary |
| 1.0 | TBD | Approved — pending Architecture Review Board sign-off and Customer Success team review |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering, VP Customer Success (customer-facing flow review), Customer Operations Team Lead (onboarding procedure review).


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
