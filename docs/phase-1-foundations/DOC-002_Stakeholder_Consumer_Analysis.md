---
document_id: DOC-002
title: "Stakeholder & Consumer Analysis"
phase: "PH-1 — Foundations & Constraints"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-002: Stakeholder & Consumer Analysis

| Document ID | DOC-002 |
| --- | --- |
| Phase | PH-1 — Foundations & Constraints |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT — Pending Architecture Review |
| Date | April 2026 |
| Depends On | [DOC-001](DOC-001_Architecture_Vision_Goals.md) — Architecture Vision & Goals |
| Priority | P0 — Blocking downstream access control design |

This document defines every stakeholder group and consumer type that interacts with the Enterprise Container Registry. It establishes the complete access pattern matrix, WASM workload taxonomy, and edge topology map that drive fine-grained access control, entitlement enforcement, and observability design in subsequent architecture documents.

# 1. Purpose & Scope
A thorough understanding of every actor that interacts with the registry is the foundation for every security, access control, and observability decision. This document establishes the authoritative consumer taxonomy, replacing informal assumptions with documented, reviewable personas and access patterns. The outputs drive the following downstream documents directly:

- [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) — IAM Architecture: identity types, authentication methods, and privilege levels per consumer

- [DOC-008](../phase-3-entitlement/DOC-008_Entitlement_Integration_Architecture.md) — Entitlement Integration: entitlement relationship between consumers and repositories

- [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) — Token Broker: token scope requirements per consumer class

- [DOC-011](../phase-3-entitlement/DOC-011_Customer_Entitlement_Access_Flow.md) — Customer Access Flow: per-runtime pull secret and credential provisioning design

- [DOC-018](../phase-6-operations/DOC-018_Observability_Architecture.md) — Observability Architecture: telemetry requirements per consumer type


>** Scope Note:**  This document identifies WHO interacts with the registry, HOW they authenticate, WHAT they can access, and WHEN / HOW OFTEN they do so. The technical implementation of these access patterns is addressed in downstream Phase 2–3 documents.


# 2. Stakeholder Map
The registry platform has stakeholders across four distinct organizational domains. The following table identifies each stakeholder group, their primary interest in the registry, and their influence over architectural decisions.

| **Stakeholder Group** | **Primary Interest** | **Architectural Influence** | **Engagement** |
| --- | --- | --- | --- |
| Platform Engineering Team | Operates the registry. Owns platform reliability, security posture, and lifecycle management. | High — owns architecture and implementation | Primary author & decision maker |
| Product Engineering Teams (×N) | Uses the registry as the SDLC push target. Owns images within their namespace. | Medium — drives namespace model and pipeline integration requirements | Requirement input & acceptance testing |
| Chief Information Security Officer | Ensures the registry meets security policy, audit, and compliance requirements. | High — veto authority on security controls | Security review & sign-off |
| Chief Architect | Ensures the registry architecture is consistent with enterprise standards and roadmap. | High — architecture review authority | Architecture Review Board |
| VP Product Engineering | Ensures SDLC integration does not impede product team velocity. | Medium — drives self-service and onboarding requirements | Requirement review & approval |
| VP Customer Success | Ensures customers can access entitled products with minimal friction. | Medium — drives customer UX and entitlement accuracy requirements | Requirement review & UAT |
| Entitlement System Team | Provides the entitlement API that the Token Broker consumes. | High — integration dependency owner | Integration design partner |
| Customer IT / DevOps Teams | Configures pull credentials and registry endpoints in customer infrastructure. | Low (influencer) — drives pull secret and credential rotation UX | External advisory input |
| Compliance & Legal | Ensures data handling, audit retention, and licensing controls are satisfied. | Medium — compliance requirements input | Review & sign-off |
| External Customers | Pulls entitled container images and artifacts to deploy licensed products. | Low (consumer) — drives reliability, latency, and credential UX requirements | UAT, feedback |

# 3. Consumer Taxonomy
Registry consumers are organized into two primary classes — Internal SDLC Consumers and External Customer Consumers — each subdivided by runtime environment and identity type. This taxonomy is the reference model for all subsequent access control and entitlement design.

| **Consumer Class** | **Members** |
| --- | --- |
| CLASS A — Internal SDLC Consumers | A1 Azure DevOps Build Agents │ A2 GitHub Actions Runners │ A3 Jenkins Pipeline Agents │ A4 Security Scanning Services │ A5 Platform Engineering Admins │ A6 Developer Workstations │ A7 GitOps Controllers (ArgoCD / Flux) |
| CLASS B — External Customer Consumers | B1 Azure Kubernetes Service (AKS) │ B2 Self-Managed Kubernetes (on-premises) │ B3 k3s (Edge / Lightweight Kubernetes) │ B4 Portainer (Docker & Kubernetes) │ B5 Docker (Bare Metal / VM) │ B6 wasmCloud / Cosmonic Control │ B7 Air-Gapped / Disconnected Deployments |

# 4. Internal Consumer Personas (Class A)
Each persona represents a distinct identity type, authentication mechanism, and access scope. The identity model defined here feeds directly into the IAM Architecture ([DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md)) and SDLC RBAC Design ([DOC-010](../phase-3-entitlement/DOC-010_SDLC_RBAC_Design.md)).


>** A1    Azure DevOps Build Agents** *CI/CD pipeline runner — build, scan, sign, push container images*


>** A2    GitHub Actions Runners** *CI/CD pipeline runner via GitHub-hosted or self-hosted runners*


>** A3    Jenkins Pipeline Agents** *Legacy CI/CD pipeline runner for products not yet migrated to ADO/GitHub*


>** A4    Security Scanning Services** *Automated vulnerability scanning, compliance checking, and SBOM generation services*


>** A5    Platform Engineering Admins** *Human operators responsible for registry platform management, configuration, and incident response*


>** A6    Developer Workstations** *Individual product engineers pulling images for local development and testing*


>** A7    GitOps Controllers (ArgoCD / Flux CD)** *Continuous deployment controllers that pull and reconcile image state against Git-declared desired state*


# 5. External Customer Consumer Personas (Class B)
External customer consumers are the primary revenue-critical consumers of the registry. All Class B personas are subject to entitlement enforcement via the Token Broker ([DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md)). The defining characteristic of Class B consumers is that their repository visibility is determined exclusively by their current entitlements in the corporate entitlement management system.


>** Entitlement Enforcement Rule:**  No Class B consumer may enumerate, pull, or inspect any repository, manifest, or tag for a product they do not have an active entitlement to. This must be enforced at the Token Broker layer — not relying solely on ACR native RBAC, which does not have entitlement-system awareness.


>** B1    Azure Kubernetes Service (AKS)** *Customer-managed AKS clusters in Azure pulling entitled product images for deployment*


>** B2    Self-Managed Kubernetes (On-Premises)** *Customer-operated Kubernetes clusters running on-premises hardware or private cloud pulling entitled images*


>** B3    k3s (Edge / Lightweight Kubernetes)** *Lightweight Kubernetes runtime for edge, IoT, and resource-constrained deployment targets*


>** B4    Portainer (Docker   &   Kubernetes Backend)** *Portainer-managed container environments — both Docker standalone and Kubernetes backends*


>** B5    Docker (Bare Metal / VM)** *Docker Engine on standalone Linux or Windows hosts — non-Kubernetes deployments*


>** B6    wasmCloud / Cosmonic Control** *WASM component runtime pulling OCI-stored WebAssembly artifacts for wasmCloud host execution*


>** B7    Air-Gapped / Disconnected Deployments** *Completely isolated deployments with no external network access — images pre-staged at deployment time*


# 6. Access Pattern Matrix
The following matrix consolidates the critical access pattern dimensions for every consumer type. This matrix is the primary input to the Token Broker scope design ([DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md)) and the IAM role definitions ([DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md)).

| **Consumer** | **Auth Method** | **Push** | **Pull Scope** | **Token TTL** | **Connectivity** | **Entitlement** | **Criticality** |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A1 ADO Agent | WIF / OIDC | Namespace push | Base images only | Short (1h) | Always-on VNet | None — internal | High |
| A2 GH Actions | WIF / OIDC | Namespace push | Base images only | Short (1h) | Always-on / public | None — internal | High |
| A3 Jenkins | SPN + KV | Namespace push | Base images only | Medium (8h) | Always-on VNet | None — internal | Medium |
| A4 Scanners | MI — read-only | None | All repos | Long (24h) | Always-on Azure | None — cross-ns | High |
| A5 Platform Admin | PIM + MFA | Full admin | All repos | Session (1h) | On-demand | None — admin | Critical |
| A6 Dev Workstation | Interactive Entra | None | Own namespace | 3h browser | On-demand | None — dev | Low |
| A7 GitOps (ArgoCD) | MI / Pull Secret | None | Product namespace | 24h rotation | Always-on | None — internal | High |
| B1 AKS | Token Broker | None | Entitled only | 24h + rotation | Always-on Azure | Full entitlement | Critical |
| B2 On-Prem K8s | Token Broker | None | Entitled only | 24h + rotation | VPN / ExpressRoute | Full entitlement | Critical |
| B3 k3s Edge | Token Broker | None | Entitled only | 72h extended | Intermittent | Full entitlement | High |
| B4 Portainer | Token Broker | None | Entitled only | 72h manual | Always-on varies | Full entitlement | Medium-High |
| B5 Docker | Token Broker | None | Entitled only | 24h rotation | On-demand | Full entitlement | Medium |
| B6 wasmCloud | Token Broker | None | Entitled WASM+OCI | 24h rotation | Always-on / edge | Full entitlement | Medium-High |
| B7 Air-Gapped | Offline bundle | None | Entitled bundle | Time-limited | Disconnected | Point-in-time | Medium |

# 7. WASM Workload Taxonomy
WebAssembly workloads represent a distinct artifact type within the registry. This section defines the taxonomy of WASM artifacts, their OCI representation, and the specific registry interactions they generate. This taxonomy is the foundation for [DOC-007](../phase-2-platform/DOC-007_WASM_Artifact_Registry_Extension.md) (WASM Artifact Registry Extension Design).


## 7.1 WASM Artifact Types
| **Artifact Type** | **OCI Media Type** | **Produced By** | **Consumed By** | **Registry Treatment** |
| --- | --- | --- | --- | --- |
| wasmCloud Component | application/wasm (OCI Artifact Spec v1.1) | Product CI/CD pipeline (wash build, cargo component build) | wasmCloud hosts, Cosmonic Control deployment | Stored as OCI artifact in product namespace. Subject to same signing and scanning policy as container images. |
| WASM Component SBOM | application/spdx+json (OCI attachment) | CI/CD pipeline (Syft, Cosign attach) | Compliance tooling, Cosmonic Control | Attached to component artifact as OCI referrer. Not independently pullable — retrieved via referrers API. |
| Cosign Signature | application/vnd.dev.cosign.simplesigning.v1+json | CI/CD pipeline (cosign sign) | Admission controller, Cosmonic Control | OCI referrer attachment. Cosmonic Control verifies on pull. |
| wasmCloud Provider Archive | application/vnd.wasmcloud.provider.archive | Product CI/CD pipeline (wash build) | wasmCloud hosts | Stored as OCI artifact. Provider archives are binary capability providers — treated as high-trust artifacts requiring mandatory signing. |
| Helm Chart (product packaging) | application/vnd.cncf.helm.chart.content.v1.tar+gzip | Product CI/CD pipeline (helm package, helm push) | Customer Kubernetes (helm install), ArgoCD | Stored in ACR OCI-compatible Helm registry. Subject to entitlement enforcement — chart pull is equivalent to image pull. |


## 7.2 WASM Consumer Interaction Patterns
The following interaction patterns describe how WASM-specific consumers interact with the registry, supplementing the general consumer personas in Section 5.

| **Interaction** | **Triggered By** | **Registry Operation** | **Credential Source** | **Entitlement Check** |
| --- | --- | --- | --- | --- |
| Component deploy (Cosmonic Control) | wadm manifest apply or Cosmonic Control CRD | OCI pull: component artifact + referrers (SBOM, signature) | imagePullSecret (Token Broker token) | Yes — at token issuance. Component namespace must be in customer entitlement. |
| Component update | New artifact version available, GitOps trigger | OCI pull: new component version manifest + layers | Same as above | Yes — re-validated at token refresh |
| Air-gapped component staging | Pre-deployment bundle request | OCI pull via oras CLI to local store, then import | Token Broker offline bundle | Yes — bundle contents constrained to entitlements at bundle generation time |
| Developer local testing | wash push / wash pull during development | OCI push (dev registry or local) / OCI pull from staging | Developer interactive Entra ID token | N/A — developer registry namespace; no customer entitlement |
| Provider archive deploy | wasmCloud host configuration | OCI pull: provider archive artifact | wasmCloud host credential configuration | Yes — provider archives in customer namespace subject to entitlement |

# 8. Edge Topology Map
Edge deployments introduce unique connectivity, credential, and reliability challenges that distinguish them from cloud-native consumers. This section defines the topology patterns for edge consumers and the registry connectivity model for each.


## 8.1 Edge Connectivity Tiers
| **Tier** | **Description** | **Connectivity** | **Registry Access Model** | **Consumers** |
| --- | --- | --- | --- | --- |
| Tier 1 — Always Connected | Edge nodes with reliable, high-bandwidth connectivity to corporate network or internet | Permanent VPN, ExpressRoute, or high-quality internet | Standard pull with Token Broker-issued credentials. Same as cloud consumer. | k3s at well-connected retail/branch, Portainer on corporate-LAN edge |
| Tier 2 — Intermittently Connected | Edge nodes with scheduled or opportunistic connectivity windows | VPN during maintenance windows, 4G/5G with variable availability | Pre-pull scheduling: pull entitled images during connectivity windows. Local containerd cache serves runtime pulls. Token TTL extended to 72 hours. | Industrial edge, remote monitoring, field-deployed k3s |
| Tier 3 — Rarely Connected | Edge nodes with connectivity measured in days or weeks | Occasional satellite, sneakernet, or scheduled sync | Image bundle: pre-staged tarball of entitled images loaded via docker load / ctr import. No live registry connectivity. Token is embedded in bundle metadata for audit purposes. | Offshore, classified, or extremely remote deployments |
| Tier 4 — Permanently Disconnected | Air-gapped deployments with no external network access | None — fully isolated network | Offline bundle distribution via physical media (USB, internal artifact server). Full image + signature + SBOM bundle. Signed bundle manifest for integrity verification. | Government classified, industrial control systems, secure facilities |


## 8.2 Edge Token & Credential Management
>** Edge Challenge:**  Standard OAuth2 token rotation (short-lived tokens refreshed via network call) is not viable for Tier 2–4 edge nodes. The architecture must define extended TTL tokens and offline bundle strategies that maintain security guarantees while tolerating connectivity gaps.


| **Edge Tier** | **Token Strategy** | **TTL** | **Revocation Model** | **Risk** |
| --- | --- | --- | --- | --- |
| Tier 1 | Standard Token Broker token in imagePullSecret | 24 hours — auto-rotated by External Secrets Operator | Immediate — on next pull attempt after revocation | Low — standard cloud model |
| Tier 2 | Extended-TTL Token Broker token in k3s registries.yaml / containerd config | 72 hours — manually rotated or scripted rotation during connectivity window | Deferred — detected at next token refresh. Node continues running cached images for up to 72h post-revocation. Risk accepted. | Medium — 72h window post-revocation. Documented and accepted risk. |
| Tier 3 | Offline bundle with embedded time-limited token. Bundle signed by Token Broker. | Bundle validity period — typically 30 days | No live revocation. Bundle expiry is the revocation mechanism. New bundle required after expiry. | Medium-High — 30-day revocation lag. Compensating control: customer must destroy expired bundles. |
| Tier 4 | Offline bundle — no token. Bundle authenticated by Cosign signature. | Permanent (until new bundle issued) | Physical media destruction / image purge. No automated mechanism. | High — accepted risk for use case. Compensating control: physical security controls + strict bundle issuance governance. |

# 9. Entitlement Relationship Model
This section defines the logical relationship between customers, their entitlements, and registry repository access. This model is the conceptual foundation for the Entitlement System Integration Architecture ([DOC-008](../phase-3-entitlement/DOC-008_Entitlement_Integration_Architecture.md)) and Token Broker design ([DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md)).


## 9.1 Entitlement Entity Relationships
| **Entity** | **Description** | **Cardinality** | **Registry Mapping** |
| --- | --- | --- | --- |
| Customer | An organization with one or more product licenses | 1 per contract | Maps to a set of entitled repository namespaces |
| Entitlement | A record linking a Customer to a specific Product and version range | N per Customer | Maps to a set of repository tags / version ranges within a product namespace |
| Product | A containerized product distributed via the registry | 1 per product team namespace | Maps to an ACR repository namespace (e.g., products/widget/) |
| Product Version | A specific release of a product, represented by one or more image tags | N per Product | Maps to specific image tags within the product repository |
| Consumer Identity | The credential identity used by a customer runtime to pull images | N per Customer (one per deployment) | Maps to Token Broker-issued scoped token with repository list derived from Customer entitlements |
| Repository Scope | The set of ACR repository paths a consumer identity is authorized to pull from | Derived from entitlements | Encoded in Token Broker-issued ACR refresh token as repository permission list |


## 9.2 Entitlement State Transitions
The registry access control layer must respond correctly to the following entitlement state transitions:

| **Transition** | **Trigger** | **Required Registry Response** | **Response Time SLO** |
| --- | --- | --- | --- |
| New entitlement granted | Customer purchases new product license | New repository scope added to customer's token on next token request. Existing tokens updated on next refresh. | Next token refresh (≤ 24h), or immediate on explicit token request |
| Entitlement revoked | License expiry, customer cancellation, or payment failure | Repository scope removed from customer token at next Token Broker validation. Running workloads continue until next image pull attempt (cached images unaffected). | ≤ 5 minutes from revocation event to Token Broker cache invalidation |
| Product version entitlement changed | Upgrade or downgrade to different version range | Token scope updated to reflect new version entitlement range. Old version tags removed from scope. | ≤ 5 minutes (event-driven cache invalidation) |
| Customer account suspended | Security incident, legal hold, or administrative suspension | All tokens for customer immediately invalidated. Token Broker returns 401 for all customer pull attempts. | ≤ 2 minutes (emergency revocation path — elevated priority) |
| New product added to portfolio | New product team onboards namespace | No impact to existing customers. New namespace invisible until entitlements are granted. | Immediate — new namespace has no customer entitlements by default |

# 10. Telemetry Requirements per Consumer Type
Each consumer type generates distinct telemetry requirements that feed into the Observability Architecture ([DOC-018](../phase-6-operations/DOC-018_Observability_Architecture.md)) and Audit Logging design ([DOC-019](../phase-6-operations/DOC-019_Audit_Logging_Compliance.md)). This section defines the minimum telemetry requirements per consumer class.

| **Consumer** | **Required Metrics** | **Required Logs** | **Required Traces** | **Alert Conditions** |
| --- | --- | --- | --- | --- |
| A1-A3 CI/CD Agents | Push success/failure rate, push latency P50/P99, image size pushed | Push event: timestamp, agent identity, namespace, image tag, size, duration | Push pipeline trace: build → scan → sign → push | Push failure rate > 2% in 1h; push latency P99 > 5min |
| A4 Scanners | Scan completion rate, CVE detection rate, scan latency | Scan result: image, CVEs found by severity, scan duration, pass/fail | Scan job trace | Scan failure; Critical CVE detected in promoted image |
| A5 Platform Admins | Admin action count, PIM activation rate | Full admin audit log: action, identity, PIM justification, timestamp, change delta | N/A | PIM activation outside business hours; admin action on production without change ticket |
| A7 GitOps Controllers | Reconciliation success rate, image update frequency | Image pull: cluster, namespace, image tag, pull duration | ArgoCD sync trace | Reconciliation failure; image pull 401 (token expiry) |
| B1-B2 Cloud/On-Prem K8s | Pull success rate per customer, pull latency P50/P99/P99.9, token issuance rate | Pull event: customer ID, product namespace, image tag, k8s cluster ID, pull duration, HTTP status | Token issuance trace, pull authorization trace | Pull failure rate > 0.1% per customer in 15min; entitlement resolution latency > 500ms |
| B3 Edge k3s | Connectivity event rate, pre-pull success rate, token expiry events | Pull event (when connected), pre-pull schedule execution, token refresh | N/A — edge telemetry asynchronous | Token expiry without successful refresh; pre-pull failure during connectivity window |
| B6 wasmCloud/Cosmonic | Component pull rate, WASM artifact pull latency | Component pull: customer, component name, version, wasmCloud host ID | Component pull trace including OCI referrers fetch | Component pull failure; signature verification failure |

# 11. Key Outputs & Downstream Document Impact
| **Output** | **Used By** | **Usage** |
| --- | --- | --- |
| Consumer taxonomy (Section 3) | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md), [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md), [DOC-011](../phase-3-entitlement/DOC-011_Customer_Entitlement_Access_Flow.md) | Identity types and authentication methods per consumer drive IAM design and Token Broker scope specifications |
| Access pattern matrix (Section 6) | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md), [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md), [DOC-010](../phase-3-entitlement/DOC-010_SDLC_RBAC_Design.md) | Token TTL requirements, push/pull scope, and entitlement flags drive RBAC role definitions and Token Broker token issuance parameters |
| WASM workload taxonomy (Section 7) | [DOC-007](../phase-2-platform/DOC-007_WASM_Artifact_Registry_Extension.md) | OCI media types, interaction patterns, and credential models drive the WASM artifact extension design |
| Edge topology map (Section 8) | [DOC-005](../phase-2-platform/DOC-005_Network_Topology_Connectivity.md), [DOC-011](../phase-3-entitlement/DOC-011_Customer_Entitlement_Access_Flow.md), [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) | Tier definitions drive network connectivity design, pull secret provisioning patterns, and DR edge-case handling |
| Entitlement relationship model (Section 9) | [DOC-008](../phase-3-entitlement/DOC-008_Entitlement_Integration_Architecture.md), [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) | Entity relationships and state transitions define the entitlement API contract and Token Broker cache invalidation design |
| Telemetry requirements (Section 10) | [DOC-018](../phase-6-operations/DOC-018_Observability_Architecture.md), [DOC-019](../phase-6-operations/DOC-019_Audit_Logging_Compliance.md) | Per-consumer telemetry requirements feed directly into observability architecture and audit log schema design |

# 12. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial draft — full consumer taxonomy, access matrix, WASM taxonomy, edge topology, entitlement model, telemetry requirements |
| 1.0 | TBD | First approved version — pending Architecture Review Board sign-off |


>** Required Approvals:**  Platform Engineering Lead, CISO (security review of consumer access patterns), VP Customer Success (customer persona validation), Entitlement System Team (entitlement model review).


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
