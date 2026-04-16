---
document_id: DOC-004
title: "ACR Service Architecture"
phase: "PH-2 — Platform Architecture"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-004: ACR Service Architecture

| Document ID | DOC-004 |
| --- | --- |
| Phase | PH-2 — Platform Architecture |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT — Pending Architecture Review |
| Date | April 2026 |
| Depends On | [DOC-001](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md) (Vision), [DOC-003](../phase-1-foundations/DOC-003_Threat_Model_Security_Posture.md) (Threat Model) |
| ACR API Version | 2025-05-01-preview (Bicep reference) |
| Priority | P0 |

This document defines the authoritative service architecture for Azure Container Registry (ACR) as deployed in the Enterprise Container Registry platform. It covers SKU selection, geo-replication topology, availability zone design, namespace hierarchy, ABAC permission model, connected registry for edge, policy configuration, and the Bicep infrastructure-as-code specification. This is the foundational platform document for all subsequent Phase 2 and Phase 3 architecture components.

# 1. Service Tier Selection & Justification
Azure Container Registry is available in three service tiers: Basic, Standard, and Premium. The Enterprise Container Registry requires the Premium tier exclusively. The following table documents the capability requirements that mandate Premium and the ADR reference for this decision.

| **Capability** | **Basic** | **Standard** | **Premium** | **Required For** |
| --- | --- | --- | --- | --- |
| Geo-replication (active-active multi-region) | No | No | Yes | Customer pull availability SLO (99.95%); regional latency targets |
| Private endpoints (Azure Private Link) | No | No | Yes | Zero-Trust network isolation; no public endpoint exposure |
| Zone redundancy (automatic in AZ regions) | No | No | Yes | AZ-level resilience within each region |
| Connected Registry (on-premises/edge replica) | No | No | Yes | Edge Tier 2/3 connectivity pattern (k3s, IoT Edge, Arc) |
| ACR token-based repository permissions | No | No | Yes | Customer scoped token issuance by Token Broker |
| ABAC repository permissions | All tiers | All tiers | All tiers (required for SDLC isolation) | Product team namespace isolation in ABAC mode |
| Quarantine policy | No | No | Yes | Image quarantine gate for vulnerability scanning |
| Soft-delete policy (90-day recycle bin) | No | No | Yes | Accidental deletion recovery; compliance |
| Dedicated agent pools for tasks | No | No | Yes | Isolated build/scan task execution |
| Storage throughput & concurrency | Low | Medium | High (unlimited concurrent reads/writes) | 10,000+ simultaneous customer pull endpoints |
| Export policy (restrict image export) | No | No | Yes | Prevent bulk IP exfiltration via export operations |
| Regional endpoints (private preview) | No | No | Yes | Predictable region-pinned routing for compliance workloads |


>** ADR Reference:**  ADR-001 (Azure Container Registry Premium as the registry platform) documents the formal evaluation of alternatives including Harbor self-hosted, AWS ECR, GitHub Packages, and JFrog Artifactory. ACR Premium was selected on the basis of Azure ecosystem integration, private endpoint support, ABAC repository permissions, geo-replication, and the connected registry feature for edge scenarios.


# 2. High Availability & Resilience Architecture

## 2.1 Architecture Layers
The ACR service architecture provides resilience across three independent layers that protect against different failure scopes:

| **Layer** | **Scope** | **Mechanism** | **Failure Scope Protected** | **Notes** |
| --- | --- | --- | --- | --- |
| Layer 1 — AZ Redundancy | Within an Azure region | Automatic zone distribution of data plane across all availability zones in the region | Single availability zone failure (affects ~33% of regional capacity) | Zone redundancy is now automatic for all registries in supported regions — no explicit configuration required. The zoneRedundancy ARM property is a legacy artifact and will be deprecated. |
| Layer 2 — Geo-replication | Across Azure regions | ACR Premium active-active geo-replication with Azure Traffic Manager routing | Full regional outage (natural disaster, cloud region failure) | Regional endpoints feature (private preview as of Feb 2026) enables explicit region-pinned routing for compliance and troubleshooting scenarios. |
| Layer 3 — Connected Registry | On-premises / edge | Local replica with scheduled sync from parent ACR | Cloud connectivity loss for on-premises/edge consumers | Billing for connected registry started Aug 2025. Deployed as Azure Arc extension or IoT Edge module. |


## 2.2 Geo-Replication Topology
The geo-replication topology is driven by the geographic distribution of customer workloads and the requirement to meet pull latency targets (P99 ≤ 500ms from cloud consumers). The initial deployment targets two primary Azure regions, with additional replicas added based on traffic analysis per the cost optimization principle P-COST-2.

| **Region Role** | **Azure Region** | **Justification** | **AZ Redundancy** | **Private Endpoints** |
| --- | --- | --- | --- | --- |
| Home Region (Primary) | East US 2 | Primary customer and SDLC concentration. Azure management plane operations originate here. | Automatic (3 AZs) | Yes — hub VNet private endpoint |
| Secondary Region | West US 2 | West coast customer coverage; DR failover target for East US 2. | Automatic (3 AZs) | Yes — spoke VNet private endpoint |
| European Replica (Phase 2) | West Europe | EU customer data residency; GDPR boundary compliance consideration. | Automatic (3 AZs) | Yes — EU hub VNet private endpoint |
| Asia Pacific Replica (Phase 3) | Southeast Asia | APAC customer pull latency optimization. Added when APAC pull traffic exceeds 5% of total. | Automatic (3 AZs) | Yes — APAC hub VNet private endpoint |


>** Regional Endpoints (Private Preview):**  ACR Regional Endpoints (--regional-endpoints enabled, feature flag RegionalEndpoints) provide explicit per-region login URLs (e.g., myregistry.eastus2.azurecr.io) alongside the global endpoint. This resolves routing ambiguity for compliance workloads requiring data-residency-pinned pulls and enables region-specific failover testing without Traffic Manager manipulation. Enable for all geo-replicated registries once GA.


## 2.3 ACR Internal Architecture
Understanding ACR's internal component model is essential for designing correct failure handling and monitoring strategies:

| **Component** | **Description** | **Home Region Only?** | **Failover Behavior** |
| --- | --- | --- | --- |
| Control Plane | Registry configuration, authentication configuration, replication policies. Managed by Azure in the home region. | Yes — centralized in home region | Home region outage may impair registry management operations (configuration changes, new replica creation). Data plane pull/push continues from healthy replicas. |
| Data Plane | Container image push and pull operations. Distributed across all regions and AZs. | No — distributed across all replicas | Traffic Manager reroutes to healthy replica within seconds. RPO near-zero (replication lag typically < 1 minute). |
| Storage Layer | Content-addressable Azure Storage. Persists image layers, manifests, OCI artifacts. | No — replicated to all geo-replica regions | Azure Storage geo-redundancy within each region. Cross-region replication via ACR data plane sync. |

# 3. Repository Namespace Hierarchy
The repository namespace hierarchy is one of the most consequential architectural decisions in this platform. It determines how product teams are isolated from each other, how customers navigate their entitled images, and how lifecycle policies are applied. ACR supports nested namespaces as organizational paths but manages all repositories independently — the hierarchy is logical, not hierarchical in a tree-permission sense.


## 3.1 Namespace Design Principles
- Product-first hierarchy: the first namespace segment identifies the product, enabling namespace-scoped ABAC conditions (products/widget/*)

- Environment promotion is handled by tagging convention, not namespace separation — a single namespace contains all environment promotions of a product's images

- Base and shared images use a dedicated root namespace (base/) to signal cross-team usage and apply a different ABAC policy (read-wide, write-restricted)

- WASM component artifacts occupy the same product namespace as container images — the artifact type is distinguished by OCI media type, not namespace

- Helm charts for product packaging are stored in the same product namespace under a charts/ path prefix


## 3.2 Namespace Hierarchy Schema
| **Namespace Pattern** | **Example** | **Contents** | **ABAC Write Scope** | **ABAC Read Scope** |
| --- | --- | --- | --- | --- |
| base/ | base/ubuntu:22.04, base/dotnet:8.0 | Approved base images imported from upstream sources. Not built by product teams — managed by Platform Engineering. | Platform Engineering only | All product team CI/CD identities (pull-only) |
| products/{product}/ | products/widget/api:1.2.3 | Container images for a specific product. Each product team owns their namespace prefix. | Specific product team CI/CD Managed Identity (ABAC condition: repositories:name StartsWith products/widget/) | Token Broker (for customer pull scoping); product team identity (pull) |
| products/{product}/charts/ | products/widget/charts/widget:1.2.3 | Helm charts for deploying the product. Stored as OCI Helm charts. | Specific product team CI/CD Managed Identity | Token Broker; customer with Helm entitlement |
| products/{product}/wasm/ | products/widget/wasm/processor:0.5.1 | wasmCloud/WASM component OCI artifacts for a product. | Specific product team CI/CD Managed Identity | Token Broker; wasmCloud/Cosmonic consumer with WASM entitlement |
| internal/ | internal/tools/scanner:latest | Internal platform tooling and utility images. Not distributed to customers. | Platform Engineering only | Platform Engineering; internal service identities (no Token Broker exposure) |
| test/ | test/widget/integration:pr-1234 | Ephemeral test images from PR/feature branches. Short retention (7 days untagged policy). | Product team CI/CD — test push scope | Product team CI/CD — test pull scope (no customer access) |


## 3.3 Tag Naming Convention
Consistent tag naming enables automated lifecycle policies and provides semantic versioning clarity for customers. The following convention is mandatory for all production repositories:

| **Tag Pattern** | **Example** | **Usage** | **Immutable?** |
| --- | --- | --- | --- |
| {major}.{minor}.{patch} | 1.2.3 | Immutable semantic version tag. Once pushed, cannot be overwritten (tag immutability enforced). | Yes — enforced by ACR tag immutability policy |
| {major}.{minor}.{patch}-{buildid} | 1.2.3-20260415.1 | Full build-qualified version for traceability to CI/CD pipeline run. | Yes |
| {major}.{minor} | 1.2 | Mutable floating tag pointing to latest patch within minor version. Customers with minor-version entitlements use this. | No — mutable; points to latest patch |
| latest | latest | Mutable; points to latest production release. For internal use only — not used in customer pull configurations. | No — explicitly discouraged for customer use |
| sha256:{digest} | sha256:a1b2c3... | Immutable digest reference. Recommended for production GitOps configurations. | N/A — digest is the content address |
| dev-{branch}-{sha} | dev-feature-xyz-abc123 | Development/branch builds. Stored in test/ namespace with 7-day retention. | No — ephemeral |

# 4. ABAC Permission Model
The ACR ABAC permission model is a central architectural decision. As of November 2025, ACR supports the "RBAC Registry + ABAC Repository Permissions" mode, enabling Entra ID-native repository-scoped access control without requiring a separate non-Entra token mechanism for SDLC identities. This section defines the complete ABAC configuration for the Enterprise Registry.


>** Breaking Change Notice:**  When ABAC mode is enabled on an existing ACR registry, legacy data-plane roles (AcrPull, AcrPush, AcrDelete) are no longer honored. All SDLC identities must be migrated to the new ABAC-enabled built-in roles (Container Registry Repository Reader, Repository Writer, Repository Contributor) before ABAC mode is enabled. The Catalog Lister role does not support ABAC conditions — assigning it grants registry-wide catalog list permissions. The Token Broker uses non-Entra ACR scope-map tokens for customer access; these are unaffected by ABAC mode.


## 4.1 ABAC-Enabled Built-in Roles
| **Role** | **Data Plane Permissions** | **ABAC Conditions** | **Primary Use Case** |
| --- | --- | --- | --- |
| Container Registry Repository Reader | Read images, tags, metadata within scoped repositories. Does NOT grant catalog list. | Yes — can be scoped to specific repository or prefix | Customer AKS Managed Identity pull; developer workstation pull; GitOps controller pull |
| Container Registry Repository Writer | Reader permissions + push images, tags, OCI referrers within scoped repositories. | Yes — scoped to specific namespace prefix | CI/CD pipeline Managed Identity (product team push) |
| Container Registry Repository Contributor | Writer permissions + delete images, tags, OCI referrers within scoped repositories. | Yes — scoped to specific namespace prefix | CI/CD pipeline identity with lifecycle management rights; Platform Engineering for namespace management |
| Container Registry Repository Catalog Lister | List all repositories in the registry (registry-wide, no ABAC conditions possible). | No — registry-wide only | Security scanning service (cross-namespace read); Platform Engineering audit tools |
| Container Registry Contributor and Data Access Configuration Administrator | Control plane: create/update/delete registries; manage auth settings. No data plane (push/pull) in ABAC mode. | No — control plane only | Platform Engineering IaC pipelines; registry lifecycle management |


## 4.2 ABAC Role Assignment Matrix
The following table defines the complete ABAC role assignments for all registry identities. Each assignment specifies the Entra identity, the role, and the ABAC condition expression governing repository scope.

| **Identity** | **Role** | **ABAC Condition** | **Justification** |
| --- | --- | --- | --- |
| Product Team A — CI/CD Managed Identity | Container Registry Repository Writer | @Resource[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWith 'products/product-a/' | Push access strictly scoped to Product A namespace. Cannot affect Product B or base/ namespaces. |
| Product Team B — CI/CD Managed Identity | Container Registry Repository Writer | @Resource[...repositories:name] StringStartsWith 'products/product-b/' | Same pattern, isolated to Product B namespace. |
| Platform Engineering — IaC Pipeline MI | Container Registry Repository Contributor | @Resource[...repositories:name] StringStartsWith 'base/' | Platform Engineering manages base image namespace including deletion for lifecycle management. |
| Microsoft Defender for Containers | Container Registry Repository Reader + Catalog Lister | Reader: no ABAC condition (registry-wide read required for scanning) | Security scanner requires cross-namespace read. Read-only. Separate dedicated identity, no push capability. |
| AKS Cluster MI (Internal SDLC) | Container Registry Repository Reader | @Resource[...repositories:name] StringStartsWith 'products/product-a/' | Internal staging AKS cluster for Product A's pre-prod workloads. |
| Developer Workstation (Entra ID interactive) | Container Registry Repository Reader | @Resource[...repositories:name] StringStartsWith 'products/product-a/' | Developer read-only access to their product namespace for local troubleshooting. |
| Token Broker Managed Identity | (non-ABAC token issuance path — see Section 5) | N/A — Token Broker uses ACR scope-map tokens for customer identities, not ABAC | Token Broker operates on ACR's non-Entra token API to issue scoped customer tokens. Separate from ABAC path. |

# 5. Token-Based Customer Access Architecture
External customer consumers do not use Entra ID identities to access ACR directly. Instead, the Token Broker ([DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md)) issues ACR non-Entra scope-map tokens on behalf of customers, with the scope dynamically computed from the customer's current entitlements. This section defines the ACR-side configuration required to support Token Broker-mediated customer access.


## 5.1 ACR Scope Map Design
An ACR scope map defines the repository-level permissions associated with a token. The Token Broker dynamically creates or updates scope maps as customer entitlements change. Each customer receives a dedicated scope map reflecting their current entitled product namespace list.

| **Scope Map Type** | **Scope Map Name Pattern** | **Repositories Covered** | **Actions Permitted** | **Lifecycle** |
| --- | --- | --- | --- | --- |
| Customer Entitlement Scope Map | customer-{customer-id}-scope | All repositories under products/{product}/ for each product the customer is entitled to | repositories/content/read, repositories/metadata/read, repositories/tags/read — pull only | Created when first entitlement granted. Updated event-driven on entitlement change. Deleted when all entitlements revoked. |
| Customer Helm Scope Map | customer-{customer-id}-helm-scope | products/{product}/charts/ for entitled products | repositories/content/read | Created alongside container scope map when Helm entitlement is granted. |
| Customer WASM Scope Map | customer-{customer-id}-wasm-scope | products/{product}/wasm/ for entitled products | repositories/content/read, repositories/metadata/read | Created when WASM component entitlement granted. |
| CI/CD Push Scope Map (non-ABAC fallback) | sdlc-{product}-push-scope | products/{product}/ | repositories/content/write, repositories/metadata/write, repositories/tags/write | Used for CI/CD systems that cannot use WIF/ABAC (e.g., Jenkins). Prefer ABAC for all SDLC where possible. |


## 5.2 Token Issuance Flow (Summary)
The detailed Token Broker design is in [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md). The following summarizes the ACR-side operations the Token Broker performs to issue customer tokens:

- Step 1: Customer authenticates to Token Broker with their Entra ID identity

- Step 2: Token Broker queries entitlement system (or cache) for customer's entitled product list

- Step 3: Token Broker calls ACR Token API to create or retrieve a scope-map-backed ACR token for the customer

- Step 4: Token Broker calls ACR generateCredentials API to issue a time-limited ACR refresh token against the customer's scope map

- Step 5: Token Broker returns the ACR refresh token to the customer — TTL 24 hours (72 hours for edge)

- Step 6: Customer runtime uses the ACR refresh token as the password for docker login or imagePullSecret


## 5.3 Catalog API Visibility Control
A critical security control: customers using Token Broker-issued tokens must not be able to enumerate repositories outside their entitlement scope via the ACR catalog API. The token scope map controls what the catalog API returns:

- A customer token backed by a scope map covering only products/widget/ and products/gadget/ can only list repositories within those prefixes via the catalog API

- The catalog API returns an empty result or a filtered result set — the customer has no indication that other product namespaces exist

- This behavior is inherent to ACR scope-map tokens — confirmed behavior per [DOC-003](../phase-1-foundations/DOC-003_Threat_Model_Security_Posture.md) threat T-I-001 mitigation SC-02

- The Catalog Lister role (ABAC mode) is NOT used for customer tokens — it grants registry-wide catalog visibility which would violate T-I-001 controls

# 6. Registry Policies & Governance Configuration
The following ACR policies are configured at registry creation and enforced as immutable platform standards. All policy configurations are declared in the IaC Bicep template (Section 9).


## 6.1 Required Policy Configuration
| **Policy** | **Configuration** | **Rationale** | **Enforcement** |
| --- | --- | --- | --- |
| Admin User | Disabled (adminUserEnabled: false) | Admin user provides static credentials — violates zero-trust principle P-SEC-2. All access via Entra ID or scoped tokens. | IaC + Azure Policy deny-assignment |
| Anonymous Pull | Disabled (anonymousPullEnabled: false) | Constraint C-005: No anonymous pull. Enforced unconditionally. | IaC + Azure Policy deny-assignment |
| Public Network Access | Disabled (publicNetworkAccess: 'Disabled') | Zero-trust: all access via private endpoints only. Eliminates public attack surface. | IaC + Azure Policy deny-assignment |
| Quarantine Policy | Enabled (quarantinePolicy: {status: 'enabled'}) | Images pushed to registry are quarantined until Defender for Containers scan completes. Prevents unscanned images from being pulled. | IaC |
| Retention Policy (untagged) | 30 days (retentionPolicy: {days: 30, status: 'enabled'}) | Prevents unbounded storage growth from untagged manifests (dangling layers). Supports P-COST-1. | IaC |
| Soft Delete Policy | 90 days (softDeletePolicy: {retentionDays: 90, status: 'enabled'}) | Provides 90-day recovery window for accidentally deleted images. Supports DR and compliance. | IaC |
| Export Policy | Disabled (exportPolicy: {status: 'disabled'}) | Prevents bulk image export operations (az acr export) which could exfiltrate large volumes of IP. Images accessible only via standard pull. | IaC |
| Tag Immutability | Enabled on all production repositories | Prevents tag overwriting — addresses threat T-T-003. Mutable tags (latest, floating minor version) are explicitly excluded. | ACR policy per repository namespace via ACR Tasks / pipeline gate |
| ABAC Permission Mode | RBAC Registry + ABAC Repository Permissions | Enables Entra ID ABAC conditions for namespace-scoped SDLC access. Required before assigning ABAC-enabled roles. | IaC (roleAssignmentPermissionsMode: 'RbacRegistryAndAbacRepository') |
| Customer-Managed Key (CMK) | Enabled — Azure Key Vault key in dedicated Key Vault instance | Constraint C-006: CMK required for enterprise customer contracts. CMK must be configured at registry creation — cannot be added post-creation. | IaC — key created before registry; registry references Key Vault URI |
| Regional Endpoints | Enabled (--regional-endpoints enabled) | Provides per-region login URLs for compliance and troubleshooting. Private preview as of Feb 2026 — enable via feature flag. | IaC + feature flag registration |
| Diagnostic Settings | All categories to Log Analytics workspace | Enables audit logging of ContainerRegistryLoginEvents and ContainerRegistryRepositoryEvents. Required for SC-09 (immutable audit log). | IaC |

# 7. Connected Registry Architecture (Edge)
The ACR Connected Registry feature provides an on-premises or remote replica that synchronizes container images and OCI artifacts with the cloud ACR. It is the primary mechanism for serving Tier 2 and Tier 3 edge consumers (k3s, IoT Edge, Arc-enabled Kubernetes) defined in [DOC-002 Section 8](../phase-1-foundations/DOC-002_Stakeholder_Consumer_Analysis.md).


>** Billing Note:**  Connected registry billing started August 2025. A monthly charge per connected registry resource applies to the Azure subscription of the parent registry. Factor this into edge deployment cost modeling — each remote site with a connected registry incurs a dedicated charge.


## 7.1 Connected Registry Deployment Models
| **Deployment Model** | **Mode** | **Sync Schedule** | **Use Case** | **Auth Mechanism** |
| --- | --- | --- | --- | --- |
| Azure Arc-enabled Kubernetes | ReadOnly (mirror mode) | Continuous or scheduled (cron) | On-premises Kubernetes clusters with Arc management. Recommended for enterprise on-premises deployments. | Non-Entra client tokens (scope-map backed). Sync token for parent sync. |
| Azure IoT Edge Module | ReadOnly (mirror mode) or ReadWrite | Scheduled (maintenance window cron) | Industrial IoT, factory edge devices with hierarchical IoT Edge topology. | Non-Entra client tokens. Sync token with parent ACR or parent connected registry. |
| Hierarchical Connected Registry | ReadOnly (child inherits parent mode) | Child syncs from parent connected registry, parent syncs from cloud ACR | Nested edge hierarchy: cloud ACR → site connected registry → floor-level connected registry. For large industrial deployments with layered network segmentation. | Each level has dedicated sync + client tokens. |
| Standalone Container (Docker Compose) | ReadOnly | Scheduled | Simple edge deployments without IoT Edge or Arc. Connected registry runs as a container on the edge server. | Non-Entra client tokens. |


## 7.2 Connected Registry Repository Sync Configuration
Connected registries sync only the repositories explicitly configured — not the entire registry. Sync configuration is defined per connected registry resource and must be explicitly aligned with customer entitlements:

- Each connected registry resource is configured with the specific product namespace repositories (products/{product}/*) that are entitled for the customer(s) it serves

- The sync token for each connected registry has scope-map permissions only for the repositories it is authorized to sync — defence in depth

- The acr/connected-registry repository must always be included in the sync list — it contains the connected registry runtime image itself

- Sync scheduling uses cron expressions: e.g., '0 2 * * *' for nightly sync during low-traffic window

- For always-connected sites, continuous sync (no schedule) is preferred to minimize replication lag


## 7.3 Connected Registry Security Constraints
>** Important Limitation:**  Connected registries currently use non-Entra ACR tokens for both sync and client authentication — Entra ID authentication is not supported for connected registry client access. Token passwords must be stored securely (Azure Key Vault or equivalent) and rotated per the standard credential rotation policy. This is a known gap vs the ABAC model used for cloud consumers.


- Client token passwords for connected registries are generated once and cannot be retrieved — store immediately in Key Vault at provisioning time

- Sync token must remain active for the connected registry to synchronize — disabling the sync token immediately stops synchronization

- Connected registry disablement: setting the sync token status to 'disabled' deactivates the connected registry — use this for emergency decommission

# 8. Azure Resource Organization

## 8.1 Resource Group Structure
| **Resource Group** | **Resources** | **Purpose** | **Lock** |
| --- | --- | --- | --- |
| rg-container-registry-core | ACR registry resource, ACR private DNS zone, Diagnostic Settings | Core registry service. Isolated to prevent accidental co-deletion with workloads. | CanNotDelete lock |
| rg-container-registry-network | Private endpoints (one per region), VNet links for private DNS | Network isolation resources. Separate from registry to allow network team management. | CanNotDelete lock |
| rg-container-registry-keyvault | Azure Key Vault (CMK), Key Vault private endpoint | CMK key storage. Strict access policy — separate RG prevents registry admin from accessing CMK. | CanNotDelete lock |
| rg-container-registry-monitoring | Log Analytics workspace (audit), Azure Monitor alerts, Grafana dashboard resources | Observability. Separate RG enforces separation of duty — registry admins cannot delete audit logs. | CanNotDelete lock |
| rg-container-registry-tokenbroker | Token Broker ACA/AKS deployment, Token Broker Managed Identity, Redis Cache | Custom Token Broker service. Separate lifecycle from registry — Token Broker can be updated independently. | None (mutable) |


## 8.2 Resource Tagging Standard
All registry-related resources must carry the following mandatory tags for cost attribution, governance, and incident management:

| **Tag Key** | **Example Value** | **Purpose** | **Enforced By** |
| --- | --- | --- | --- |
| platform | container-registry | Identifies resources belonging to the registry platform | Azure Policy |
| environment | production │ staging │ dev | Environment tier for cost attribution and change management | Azure Policy |
| team | platform-engineering | Owning team for incident escalation | Azure Policy |
| cost-center | CC-1234 | Financial chargeback and cost attribution | Azure Policy |
| data-classification | confidential | Data sensitivity level for compliance | Azure Policy |
| managed-by | terraform │ bicep | IaC toolchain managing the resource — prevents manual changes | Convention (not enforced) |
| criticality | tier-1 │ tier-2 | Business criticality for SLA and support prioritization | Convention |

# 9. Infrastructure-as-Code Specification (Bicep)
The following Bicep templates define the authoritative infrastructure configuration for the Enterprise Container Registry. All production infrastructure must be deployed exclusively via these templates through the Platform Engineering CI/CD pipeline. No manual portal changes are permitted in production.


## 9.1 Core Registry Resource
The following Bicep snippet defines the ACR registry with all required security policies. This is the reference configuration — the full parameterized template is maintained in the platform IaC repository.


```json
// ACR Core Registry — Enterprise Container Registry Platform // IaC Repository: platform-engineering/infra/registry/main.bicep // API Version: 2025-05-01-preview
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-05-01-preview' = {
  name: registryName
  location: primaryLocation
  sku: { name: 'Premium' }
  identity: {
  type: 'SystemAssigned'
          // Used for CMK Key Vault access   }
  properties: {
  adminUserEnabled: false
          // MANDATORY — no static admin credentials
  anonymousPullEnabled: false
      // MANDATORY — no anonymous pull
  publicNetworkAccess: 'Disabled'   // MANDATORY — private endpoint only
    // zoneRedundancy: automatic in AZ-supported regions — property deprecated
  roleAssignmentPermissionsMode: 'RbacRegistryAndAbacRepository'  // ABAC mode
  encryption: {


status: 'enabled'

  keyVaultProperties: {

  keyIdentifier: keyVaultKeyUri  // CMK in dedicated Key Vault

  identity: registryIdentityResourceId
      }
    }
  policies: {

  quarantinePolicy:  {

status: 'enabled' }

  retentionPolicy:   { days: 30,

status: 'enabled' }

  softDeletePolicy:  { retentionDays: 90,

status: 'enabled' }

  exportPolicy:
      {

status: 'disabled' }

  trustPolicy:
      {

status: 'enabled', type: 'Notary' }
    }   } }
```


## 9.2 Geo-Replication Resource
```json
// Geo-replication replica — one
resource per additional region
resource registryReplica 'Microsoft.ContainerRegistry/registries/replications@2025-04-01' = {
  parent: containerRegistry
  name: secondaryLocation
  location: secondaryLocation
  properties: {
  zoneRedundancy: 'Enabled'
        // Explicit for replica clarity
  regionEndpointEnabled: true
      // Regional endpoint (private preview)   } }
```


## 9.3 Diagnostic Settings (Audit Logging)
```json
// Diagnostic settings — route all audit categories to Log Analytics
resource acrDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'acr-audit-diagnostics'
  scope: containerRegistry
  properties: {
  workspaceId: auditLogAnalyticsWorkspaceId  // Separate, immutable workspace
  logs: [
      { category: 'ContainerRegistryRepositoryEvents', enabled: true, retentionPolicy: { days: 365, enabled: true } }
      { category: 'ContainerRegistryLoginEvents',

  enabled: true, retentionPolicy: { days: 365, enabled: true } }
    ]
  metrics: [
      { category: 'AllMetrics', enabled: true }
    ]   } }
```


## 9.4 ABAC Role Assignment Example
```json
// ABAC-scoped role assignment — Product Team A CI/CD push access // Role: Container Registry Repository Writer (ABAC-enabled)
resource productAWriterAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, productAManagedIdentityId, repositoryWriterRoleId)
  scope: containerRegistry
  properties: {
  roleDefinitionId: repositoryWriterRoleId
  principalId: productAManagedIdentityId
  principalType: 'ServicePrincipal'
  condition: '@Resource[Microsoft.ContainerRegistry/registries/repositories:name]
                StringStartsWith \'products/product-a/\'
                '
  conditionVersion: '2.0'   } }
```


# 10. Capacity & Performance Model

## 10.1 Storage Capacity Planning
| **Variable** | **Estimate** | **Basis** | **Review Trigger** |
| --- | --- | --- | --- |
| Initial product portfolio size | 20 products at launch, growing to 50 within 24 months | Product containerization roadmap | Quarterly review against roadmap |
| Average image size | 800 MB per image (includes base OS + runtime + app layers) | Baseline from existing application size analysis | Revise after first 3 months of production push data |
| Image versions retained per product | 10 active versions per product (lifecycle policy enforces max) | Retention policy in [DOC-022](../phase-7-governance/DOC-022_Artifact_Lifecycle_Policy.md) | Policy review triggers if storage grows >20% in a quarter |
| Total active image storage (launch) | 20 products × 10 versions × 800MB = 160 GB | Calculation | — |
| Total active image storage (24 months) | 50 products × 10 versions × 800MB = 400 GB | Projection | Quarterly capacity review |
| Geo-replication storage multiplier | 2× primary (East US 2 + West US 2) = 800 GB at 24 months | Per-region replication | — |
| ACR Premium storage limit | N/A — ACR Premium has no hard storage cap; storage is metered | Azure pricing documentation | — |


## 10.2 Throughput Targets
| **Metric** | **Target** | **Sizing Implication** |
| --- | --- | --- |
| Concurrent customer pull endpoints | 10,000 simultaneous at peak | ACR Premium: unlimited concurrent reads. Traffic Manager distributes across geo-replicas. No hard concurrency limit. |
| Peak pull requests per second | 5,000 RPS across all regions | ACR Premium handles this at scale — monitor via Azure Monitor StorageUsage and SuccessfulPullCount metrics. |
| CI/CD concurrent image pushes | 50 simultaneous product team builds | ACR Premium: high concurrent write throughput. Agent pool sizing for dedicated build tasks: 2-4 pools of S1/S2 agents. |
| Token Broker token issuances per second | 1,000 RPS sustained; 5,000 RPS burst | Token Broker sizing — 3 replicas × 2 vCPU, 4 GB RAM baseline. Scales horizontally on Azure Container Apps. |
| Maximum single image size | 5 GB | Layer pull optimization required for images >2 GB — document multi-stage build guidance. |

# 11. Key Architecture Decisions
The following Architecture Decision Records are directly associated with this document and must be reviewed alongside it:

| **ADR** | **Decision** | **Status** |
| --- | --- | --- |
| ADR-001 | Azure Container Registry Premium as the registry platform (vs Harbor, ECR, GitHub Packages, JFrog) | Approved |
| ADR-002 | Single shared registry for all products (vs per-product registry) with namespace isolation | Approved |
| ADR-003 | ABAC mode enabled from Day 1 — legacy AcrPull/AcrPush roles not used | Approved |
| ADR-004 | Customer access via Token Broker-issued non-Entra scope-map tokens (vs Entra ID customer identities in ACR directly) | Approved |
| ADR-005 | Tag immutability enforced on all production repositories | Approved |
| ADR-006 | CMK encryption with Key Vault — configured at registry creation (cannot be added post-creation) | Approved |
| ADR-007 | Connected Registry for Tier 2/3 edge consumers (vs direct pull over extended TTL) | Pending review — cost vs operational complexity trade-off |

# 12. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — service tier, HA topology, namespace hierarchy, ABAC model, connected registry, IaC specification |
| 1.0 | TBD | Approved version — pending Architecture Review Board sign-off and ADR-007 resolution |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering, CISO (ABAC and CMK configuration review), Product Engineering representative (namespace hierarchy validation).


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
