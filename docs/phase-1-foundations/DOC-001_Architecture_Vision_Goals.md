---
document_id: DOC-001
title: "Architecture Vision & Goals"
phase: "PH-1 — Foundations & Constraints"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-001: Architecture Vision & Goals

| **Document ID** | DOC-001 |
| --- | --- |
| **Phase** | PH-1 — Foundations & Constraints |
| **Version** | 1.0 — Initial Release |
| **Classification** | Internal Architecture — Confidential |
| **Status** | DRAFT — Pending Architecture Review |
| **Date** | April 2026 |
| **Depends On** | None — Entry Point Document |
| **Priority** | P0 — Blocking all downstream documents |

**Abstract**

This document establishes the authoritative architecture vision, guiding principles, success criteria, and constraints for a new Enterprise Container Registry platform. The registry will serve as mission-critical shared infrastructure supporting the full portfolio of company products as they progressively adopt container-based deployment. It must satisfy the competing demands of an internal software development life cycle (SDLC) toolchain requiring fine-grained write isolation between product teams, and an external customer-facing distribution model that enforces entitlement-based repository visibility. The platform must natively support cloud-native Kubernetes, on-premises Kubernetes, lightweight edge runtimes (k3s, Portainer, Docker), and emerging WebAssembly (WASM) workloads via the wasmCloud / Cosmonic Control ecosystem. This document is the north star reference for all subsequent architecture, design, and implementation decisions.

# 1. Executive Summary
The company is in the midst of a strategic initiative to containerize its portfolio of products, transitioning from traditional delivery mechanisms to a container-based distribution model. This shift fundamentally changes the relationship between the company, its product teams, and its customers — products are now consumed as container images and artifacts pulled from a registry rather than installed from discrete packages or file downloads.

A critical enabler of this transformation is a robust, secure, and scalable Container Registry platform. This platform must function simultaneously as:

- An internal SDLC asset — enabling product engineering teams to build, scan, sign, and promote container images within a well-governed CI/CD pipeline while maintaining strict isolation between product namespaces.

- An external product distribution channel — providing customers with authenticated, entitlement-enforced access to precisely the container images and artifacts corresponding to the products and versions they have licensed.

- A forward-looking WASM artifact registry — supporting the emerging paradigm of WebAssembly component artifacts for customers adopting wasmCloud-based or Cosmonic Control-based deployment targets alongside traditional containers.

The architecture must be grounded in the Azure Well-Architected Framework's five pillars — Reliability, Security, Cost Optimization, Operational Excellence, and Performance Efficiency — while accommodating a heterogeneous deployment target landscape ranging from hyperscale cloud Kubernetes clusters to resource-constrained edge nodes.


>** Strategic Imperative:**  The Container Registry is not a supporting service — it is a product distribution pipeline. Its availability, security, and access control correctness are directly customer-facing and revenue-critical. Architectural decisions must reflect this classification.


# 2. Business Context & Drivers

## 2.1 Strategic Business Drivers
The following primary drivers motivate the investment in enterprise-grade container registry infrastructure:

| **Driver** | **Description** | **Priority** |
| --- | --- | --- |
| Portfolio Containerization | The company is systematically containerizing its product portfolio. The registry is the distribution nexus for this initiative — without it, containerized products cannot reach customers. | Critical |
| Customer Entitlement Enforcement | Customers must only access containers for products they have licensed. Regulatory and contractual obligations require that access control be provably enforced and auditable. | Critical |
| SDLC Modernization | Product engineering teams require governed, self-service access to push images in their own namespaces without risk of cross-team interference or unauthorized access to peer product registries. | High |
| Edge & Hybrid Deployment | Customers deploy at the edge (k3s, Docker, Portainer) and in air-gapped or bandwidth-constrained environments. The registry must support efficient, reliable artifact delivery to these contexts. | High |
| WASM Adoption Enablement | Emerging container-adjacent workloads using WebAssembly (wasmCloud, Cosmonic Control) require OCI-compatible artifact storage and distribution, positioning the company for next-generation delivery patterns. | Medium |
| Regulatory Compliance | SOC 2 Type II, ISO 27001, and customer security questionnaire requirements mandate comprehensive access logging, image provenance, and supply chain controls for any software distribution channel. | High |


## 2.2 Organizational Context
The registry will be operated as shared platform infrastructure, managed by a central Platform Engineering team, but consumed by multiple product engineering teams. Each product team has sovereign responsibility for images within their own registry namespace. The central team is responsible for the underlying platform, security posture, access control framework, observability, and lifecycle policies.

External customers interact with the registry exclusively for image pull operations. They never interact with the SDLC push path. Customer credentials and access scope are derived entirely from the corporate entitlement management system — no manual provisioning of customer registry access is permitted.

# 3. Architecture Vision Statement
>** *An enterprise-grade, entitlement-aware container registry platform that provides every product team a governed, isolated SDLC pipeline and every customer an access-controlled, frictionless container distribution experience — across cloud, on-premises, edge, and WebAssembly runtimes — with comprehensive observability, provable supply chain security, and five-nines reliability.***


## 3.1 Vision Decomposition
The vision statement encodes five distinct architectural commitments:

| **Vision Element** | **Architectural Commitment** |
| --- | --- |
| Enterprise-grade | Azure Container Registry Premium tier with geo-replication, availability zones, private endpoints, and 99.95% SLA. Custom-built components meet the same bar via HA design. |
| Entitlement-aware | A custom Token Broker service sits between customers and ACR, issuing repository-scoped tokens derived in real time from the corporate entitlement system. Customers cannot enumerate repositories they are not entitled to. |
| Governed, isolated SDLC | Hierarchical repository namespaces with Attribute-Based Access Control (ABAC) enforce that each product team can only push to their own namespace. CI/CD pipelines authenticate via Workload Identity Federation — no static credentials. |
| Frictionless distribution | Customers use standard OCI tooling (docker pull, helm pull, kubectl, etc.) with no custom client-side tooling required. Pull secret provisioning for Kubernetes, k3s, and Portainer is automated via the entitlement integration. |
| Cloud, on-premises, edge, WASM | ACR private endpoints serve cloud and on-premises consumers. Edge connectivity patterns support k3s and Docker in bandwidth-constrained environments. OCI artifact extensions support wasmCloud component artifacts. |
| Provable supply chain security | Every image is signed (Cosign + Notary v2), scanned (Defender for Containers), and carries a machine-readable SBOM. Admission controllers in customer clusters enforce signature verification before scheduling. |

# 4. Architecture Principles
The following principles are non-negotiable constraints that govern all architectural decisions. When tradeoffs arise, these principles define the priority ordering.


## 4.1 Security Principles
| **Principle** | **Implication** |
| --- | --- |
| P-SEC-1: Zero Trust Access | No implicit trust is granted based on network location. Every pull and push request must be authenticated and authorized. Private endpoints do not substitute for authentication. |
| P-SEC-2: Principle of Least Privilege | Every identity — human, service principal, managed identity, customer credential — receives only the minimum permissions required for its function. Pull-only access for customers; scoped namespace push for CI/CD. |
| P-SEC-3: Entitlement is the Source of Truth | Customer repository visibility is derived exclusively from the corporate entitlement system. The registry platform must not maintain a separate entitlement store. All grants must be traceable to an entitlement record. |
| P-SEC-4: Supply Chain Integrity by Default | No unsigned image may be pulled to a production environment. SBOM generation and vulnerability scanning are mandatory gates in the SDLC pipeline, not optional enhancements. |
| P-SEC-5: Complete Audit Trail | Every authentication, authorization decision, pull, push, and admin action is logged in a tamper-evident audit log. Logs are immutable, retained for no less than 12 months, and queryable within 5 minutes. |
| P-SEC-6: Defence in Depth | Security controls are layered: network isolation, identity-based access control, token scoping, admission control, image signing, and runtime scanning are all active simultaneously. Failure of any single layer does not create a breach. |


## 4.2 Reliability Principles
| **Principle** | **Implication** |
| --- | --- |
| P-REL-1: Registry Pull is Always Available | The ability for existing customers to pull entitled images must achieve 99.95% monthly uptime. This drives geo-replication, private endpoint redundancy, and stateless Token Broker design. |
| P-REL-2: Entitlement Failure must not Block Pull | The Token Broker must implement a short-lived entitlement decision cache. A transient entitlement system outage of up to 15 minutes must not prevent entitled customers from pulling images. |
| P-REL-3: Edge Nodes are Intermittently Connected | Architecture must support edge consumers (k3s, Docker, Portainer) that cannot maintain continuous registry connectivity. Pre-pull strategies and local mirror patterns are first-class design considerations. |
| P-REL-4: Regional Isolation | A failure in one Azure region must not degrade registry availability in other regions. Geo-replication is active-active; no single region is the sole authority for any repository. |


## 4.3 Operational Excellence Principles
| **Principle** | **Implication** |
| --- | --- |
| P-OPS-1: Infrastructure as Code | All registry infrastructure — ACR, networking, IAM, Token Broker, monitoring — is defined in Bicep/Terraform and deployed via CI/CD pipeline. No manual portal-based configuration is permitted in production. |
| P-OPS-2: Observability by Design | Every custom component emits OpenTelemetry traces, metrics, and structured logs from day one. Observability is not retrofitted — it is a first-class requirement of every component specification. |
| P-OPS-3: Product Team Self-Service | Product teams can onboard new repositories, manage their namespace lifecycle, and access their own telemetry without engaging the Platform team for routine operations. Self-service is gated by policy, not blocked by process. |
| P-OPS-4: GitOps for Configuration | RBAC assignments, repository policies, and Token Broker entitlement mappings are managed as code in Git, with audit trail and peer review. No direct API mutations without a corresponding Git commit. |


## 4.4 Cost Optimization Principles
| **Principle** | **Implication** |
| --- | --- |
| P-COST-1: Storage Lifecycle Management | Automated retention policies purge untagged manifests, superseded versions, and quarantined images on defined schedules. Unbounded storage growth is architecturally prevented. |
| P-COST-2: Right-tier Geo-replication | Geo-replicas are placed only where pull traffic warrants them. Regional capacity and traffic data drive replication decisions — not speculative placement. |
| P-COST-3: Token Broker Efficiency | The Token Broker is designed as a stateless, horizontally scalable service with aggressive entitlement caching to minimize both latency and the number of entitlement system API calls, which may carry per-call cost. |

# 5. Success Criteria & Key Performance Indicators
Architecture success is measured against the following objective criteria. These KPIs are the basis for SLO definitions in [DOC-020](../phase-6-operations/DOC-020_SLO_SLA_Error_Budget.md) and the WAF review checklist in [DOC-025](../phase-7-governance/DOC-025_WAF_Architecture_Review.md).


## 5.1 Availability & Reliability KPIs
| **KPI** | **Target** | **Measurement Method** |
| --- | --- | --- |
| Registry pull availability (customer-facing) | ≥ 99.95% monthly | Synthetic monitoring, external probes from each supported region |
| Token Broker availability | ≥ 99.95% monthly | Azure Load Balancer health probe + Application Insights availability tests |
| Entitlement outage tolerance | ≤ 15 min with cached decisions | Chaos engineering test: entitlement system outage injection |
| Pull request latency P99 (cloud) | ≤ 500ms for auth + token | Distributed tracing via OpenTelemetry |
| Pull request latency P99 (edge) | ≤ 2000ms for first-byte | Edge synthetic probe monitoring |
| Recovery Time Objective (RTO) | ≤ 4 hours for full regional failover | DR drill, tested semi-annually |
| Recovery Point Objective (RPO) | ≤ 5 minutes for image push data | Geo-replication lag monitoring |


## 5.2 Security & Compliance KPIs
| **KPI** | **Target** | **Measurement Method** |
| --- | --- | --- |
| Unauthorized repository access events | 0 per quarter | Audit log analysis, SIEM alerting |
| Images in production without valid signature | 0 at any time | Admission controller enforcement metrics |
| Critical/High CVEs in production images | 0 unacknowledged > 72 hours | Defender for Containers scan results dashboard |
| Audit log completeness | 100% of pull/push events | Log analytics query vs ACR diagnostic metrics |
| Entitlement decision accuracy | 100% — no false positives, no false negatives | Monthly reconciliation audit vs entitlement system |
| Time to revoke customer access | ≤ 5 minutes from entitlement removal | Automated revocation test, post-entitlement-change probe |


## 5.3 Operational Excellence KPIs
| **KPI** | **Target** | **Measurement Method** |
| --- | --- | --- |
| New product namespace onboarding time | ≤ 2 business days (self-service) | ServiceNow ticket cycle time |
| Infrastructure change deployment time | ≤ 30 minutes via CI/CD pipeline | Pipeline duration metrics in Azure DevOps |
| Mean Time to Detect (MTTD) anomaly | ≤ 10 minutes | Alert firing latency from log ingestion to notification |
| Mean Time to Recover (MTTR) | ≤ 60 minutes for P1 incidents | Incident management system data |
| SDLC pipeline push success rate | ≥ 99.5% | Pipeline telemetry |
| Documentation currency | All ADRs updated within 5 days of decision | ADR repository commit timestamps |

# 6. Scope Definition

## 6.1 In Scope
- Azure Container Registry (ACR) Premium tier service design, configuration, and operational model

- Custom Token Broker service architecture and implementation specification

- Integration design with the corporate entitlement management system

- Fine-grained RBAC model for SDLC product team namespace isolation

- Network architecture: VNet, private endpoints, DNS, and edge connectivity

- Identity and Access Management: Entra ID, workload identity, managed identities, service principals

- CI/CD pipeline integration patterns for Azure DevOps, GitHub Actions, and Jenkins

- GitOps integration patterns for ArgoCD and Flux CD

- Supply chain security: image signing (Cosign + Notary v2), vulnerability scanning, SBOM generation

- Observability architecture: OpenTelemetry instrumentation, Log Analytics, Prometheus, Grafana

- Audit logging and compliance evidence collection

- Artifact lifecycle management policies

- Disaster recovery and business continuity design

- OCI artifact extension support for WASM components (wasmCloud / Cosmonic Control)

- Consumer support for: Azure Kubernetes Service (AKS), self-managed Kubernetes, k3s, Docker, Portainer

- Architecture Decision Records for all significant decisions


## 6.2 Out of Scope
- The corporate entitlement management system itself (consumed as an integration dependency)

- Internal developer portal (IDP) or Backstage implementation (integration patterns only)

- CI/CD toolchain selection (Azure DevOps, GitHub Actions assumed as standards — toolchain governance is out of scope)

- Customer identity provider implementation (Entra ID External Identities is an integration point)

- Kubernetes cluster provisioning and management (registry integration patterns are in scope; cluster lifecycle is not)

- Application-level containerization work (the registry serves images; how applications are containerized is out of scope)

- Cost model and budget approval (cost architecture and right-sizing are in scope; FinOps budget governance is not)


## 6.3 Boundary Conditions & Assumptions
>** ASSUMPTION-001:**  The corporate entitlement system exposes a well-defined API for querying customer product entitlements. This API supports event-driven notifications when entitlements change. Where this API does not exist, an integration layer must be built — this is explicitly noted as a risk in Section 8.


>** ASSUMPTION-002:**  Azure Container Registry Premium tier is the selected registry platform. This decision is captured in ADR-001. Alternatives (Harbor, AWS ECR, GitHub Packages) were evaluated and rejected on the basis of Azure ecosystem integration, private endpoint support, and geo-replication capabilities.


>** ASSUMPTION-003:**  WASM artifact support via OCI artifact extensions is an emerging capability. The architecture must accommodate wasmCloud component artifacts stored as OCI artifacts. Cosmonic Control's use of imagePullSecrets for private registry credentials aligns with the standard Kubernetes pull secret pattern.


# 7. Quality Attributes (Non-Functional Requirements)
The following quality attributes establish binding non-functional requirements that architecture solutions must satisfy. They are organized by the Azure Well-Architected Framework pillars.


## 7.1 Reliability
| **Attribute** | **Requirement** |
| --- | --- |
| Availability | Registry pull service: 99.95% monthly uptime. Token Broker: 99.95% monthly uptime. Measured independently per region. |
| Fault Tolerance | Failure of any single Azure availability zone must not impact service availability. Failure of any single region must trigger automatic failover within 4 hours. |
| Data Durability | All pushed images and manifests are durably stored with geo-redundant replication. Zero tolerance for data loss of any committed image push. |
| Graceful Degradation | Entitlement system unavailability must degrade to cached-decision mode, not to a full outage. Token Broker must serve valid, recently-cached entitlement decisions for up to 15 minutes during entitlement system unavailability. |
| Edge Resilience | Edge nodes must continue to run on locally-cached images during registry connectivity loss. Architecture must not require continuous registry connectivity for running workloads. |


## 7.2 Security
| **Attribute** | **Requirement** |
| --- | --- |
| Authentication | All registry access (push and pull) requires authentication. Anonymous pull is disabled globally. No credentials are stored in CI/CD pipeline configuration — Workload Identity Federation is mandatory. |
| Authorization Granularity | Repository-level authorization is enforced. Customers receive read-only access to specific repositories matching their entitlements. Product teams receive push access only to their assigned namespace prefix. |
| Network Security | Registry endpoints are accessible only via Azure Private Endpoints within authorized VNets. Public endpoint access is disabled for production registries. Edge access traverses VPN or ExpressRoute where feasible; otherwise uses token-scoped access over TLS. |
| Encryption | All data in transit uses TLS 1.2 minimum (TLS 1.3 preferred). All data at rest is encrypted with customer-managed keys (CMK) stored in Azure Key Vault with RBAC-controlled access. |
| Secrets Management | No long-lived credentials are used for SDLC pipelines. Customer pull secrets are short-lived tokens issued by the Token Broker (maximum 24-hour validity) and automatically rotated. |
| Vulnerability Management | All images pushed to the registry are scanned by Microsoft Defender for Containers. Images with Critical or High CVEs are quarantined automatically pending triage. Production pull is blocked for quarantined images. |


## 7.3 Performance Efficiency
| **Attribute** | **Requirement** |
| --- | --- |
| Pull Latency | Token authentication and authorization: P99 ≤ 500ms from cloud consumers. First byte of image manifest: P99 ≤ 300ms from co-located Azure region. Layer pull throughput must not become a bottleneck for images ≤ 2GB. |
| Throughput | Registry must support concurrent pulls from up to 10,000 simultaneous customer endpoints without performance degradation. This drives geo-replication placement and agent pool sizing. |
| Push Throughput | CI/CD build pipelines must be able to push images of up to 5GB within 10 minutes over a standard Azure backbone connection. |
| Token Broker Latency | Entitlement resolution and token issuance: P99 ≤ 200ms under normal load. Cache hit response: P99 ≤ 20ms. |
| Edge Pull Performance | For edge consumers on constrained connections, architecture must support delta/layer pull optimization and pre-pull scheduling to minimize live-path bandwidth consumption. |


## 7.4 Operational Excellence
| **Attribute** | **Requirement** |
| --- | --- |
| Deployability | Full infrastructure deployment from scratch must complete in under 2 hours via automated pipeline. Incremental changes must deploy in under 30 minutes. |
| Observability | Every component must emit structured logs to Log Analytics, metrics to Azure Monitor / Prometheus, and distributed traces via OpenTelemetry. No blind spots in the telemetry pipeline. |
| Supportability | On-call engineers must be able to diagnose and triage P1 incidents using only the documented runbooks and observability tooling — no tribal knowledge required. |
| Auditability | All access decisions, configuration changes, and lifecycle events are logged with sufficient context to reconstruct the sequence of events for a 12-month lookback. |
| Testability | Chaos engineering scenarios — entitlement system outage, Token Broker failure, single-region ACR failure — are documented and executable without impacting production customers. |


## 7.5 Cost Optimization
| **Attribute** | **Requirement** |
| --- | --- |
| Storage Cost Management | Automated lifecycle policies must prevent unbounded storage growth. Untagged manifests are purged within 7 days. Superseded image versions are retained for no more than 90 days unless pinned by an active entitlement. |
| Replication Efficiency | Geo-replication is deployed only to regions with active customer pull traffic. Traffic-based rightsizing reviews occur quarterly. |
| Token Broker Efficiency | Entitlement caching must reduce entitlement system API call volume by at least 80% compared to uncached operation. Cache invalidation is event-driven, not polling-based. |
| Cost Visibility | All registry resource costs are tagged by product team namespace and consumer type (SDLC vs customer) to enable cost attribution and chargeback reporting. |

# 8. Constraints & Risks Register

## 8.1 Hard Constraints
The following constraints are non-negotiable and cannot be traded off by architectural decisions:

| **Constraint** | **Rationale** |
| --- | --- |
| C-001: Azure as the cloud platform | Corporate cloud strategy mandates Azure. No multi-cloud registry architecture is in scope. |
| C-002: Entitlement system is the sole source of truth for customer access | Contractual and regulatory obligation. Entitlement bypass, even for operational convenience, is prohibited. |
| C-003: All images must traverse vulnerability scanning before production promotion | Security policy mandate. No mechanism for bypassing the scan gate in the promotion pipeline is permitted. |
| C-004: Customer audit logs are immutable and retained for 12 months minimum | Regulatory and contractual obligation. Log tampering detection is a compliance requirement. |
| C-005: No anonymous pull access | Zero-trust security policy. Authentication is required for all registry interactions without exception. |
| C-006: Customer-managed encryption keys | Data sovereignty requirement for enterprise customer contracts. ACR must use CMK via Azure Key Vault. |


## 8.2 Architecture Risk Register
| **Risk ID** | **Description** | **Likelihood** | **Impact** | **Mitigation** |
| --- | --- | --- | --- | --- |
| RISK-001 | Entitlement system API does not exist or is not mature enough to support real-time integration | Medium | Critical | Early integration discovery sprint. Define minimum viable API contract; build adapter layer if required. |
| RISK-002 | WASM OCI artifact format standards are still evolving, creating future compatibility risk | High | Medium | Adopt OCI Artifact Spec v1.1 as the baseline. Design WASM extension layer as pluggable — versioned adapter pattern. |
| RISK-003 | Token Broker becomes a single point of failure for all customer pulls | Low | Critical | Stateless multi-instance Token Broker behind Azure Load Balancer with health probes. Entitlement cache allows continued operation during partial failures. |
| RISK-004 | Edge connectivity to registry is unreliable or blocked by customer network policy | Medium | High | Document supported connectivity patterns. Provide local mirror/cache guidance. Pre-pull scheduling design in edge architecture. |
| RISK-005 | Fine-grained ABAC for product team namespace isolation is not natively supported at required granularity | Medium | High | Evaluate ACR's Entra ID ABAC repository permissions. Design custom scope enforcement in Token Broker as fallback. |
| RISK-006 | Customer entitlement cache becomes stale, resulting in access after entitlement revocation | Low | Critical | Event-driven cache invalidation on entitlement change. Maximum cache TTL of 15 minutes. Revocation test in continuous monitoring. |

# 9. Consumer Landscape
The registry serves two fundamentally distinct consumer classes with different access patterns, security requirements, and connectivity characteristics. Each class is further segmented by runtime environment.


## 9.1 Internal Consumers — SDLC Toolchain
| **Consumer** | **Access Pattern **&** Requirements** |
| --- | --- |
| Azure DevOps Build Agents | Push images to product-scoped namespaces. Authenticate via Workload Identity Federation (no stored credentials). Must only push to their assigned namespace prefix. Trigger scan gates before promotion. |
| GitHub Actions Runners | Same as Azure DevOps. OIDC token exchange with ACR via Workload Identity Federation. Namespace-scoped push permission. |
| Jenkins Pipelines | Service principal authentication where WIF is not supported. Scoped credentials stored in Azure Key Vault, injected at pipeline runtime. Push only to assigned namespace. |
| Security Scanning Tools | Read access across all namespaces for vulnerability scanning and compliance reporting. Dedicated read-only service principal. Audit logged separately. |
| Platform Engineering Team | Administrative access for platform management. Entra ID Privileged Identity Management (PIM) with just-in-time activation. All admin actions audit logged. |
| Developer Workstations | Pull access for local development using az acr login via Entra ID interactive authentication. No push access from workstations to production registry. |


## 9.2 External Consumers — Customer Distribution
| **Consumer Runtime** | **Access Pattern **&** Requirements** |
| --- | --- |
| Azure Kubernetes Service (AKS) | Pull via imagePullSecrets or ACR attachment with AKS-managed identity. Token Broker issues scoped tokens. Entitlement-controlled repository visibility. Supports cluster-level pull caching. |
| Self-Managed Kubernetes (on-premises) | Pull via imagePullSecrets containing Token Broker-issued scoped tokens. Standard Kubernetes credential management. Private endpoint or VPN connectivity. |
| k3s (Edge/Lightweight Kubernetes) | Standard containerd registry mirror configuration. imagePullSecrets via k3s credential helper or registries.yaml. Supports disconnected operation with pre-pulled images. |
| Portainer | Registry configuration via Portainer UI or API. Pull credentials derived from Token Broker. Supports both Docker and Kubernetes runtimes within Portainer. |
| Docker (bare metal/VM) | Standard docker login with Token Broker-issued credentials. Docker config.json credential storage. Token rotation handled by credential helper. |
| wasmCloud / Cosmonic Control | OCI credential configuration via imagePullSecrets (Cosmonic Control alignment). Registry credentials configured per artifact. Air-gapped environment support via global registry override. WASM component OCI artifacts stored alongside container images. |

# 10. WebAssembly Workload Architecture Considerations
The emergence of WebAssembly as a deployment target represents a significant architectural consideration for the Container Registry platform. The following principles and constraints guide the WASM integration design, which is elaborated in detail in [DOC-007](../phase-2-platform/DOC-007_WASM_Artifact_Registry_Extension.md).


## 10.1 WASM in the OCI Ecosystem
WebAssembly components distributed via wasmCloud and Cosmonic Control are stored and distributed as OCI artifacts — binary payloads that conform to the OCI Image Spec with WASM-specific media types. This means ACR is architecturally compatible with WASM artifact storage without requiring a separate registry service. Key considerations include:

- WASM component artifacts use the OCI Artifact Specification (oras.land) with media type application/wasm. ACR Premium supports arbitrary OCI artifact types.

- Cosmonic Control aligns with Kubernetes conventions: OCI credentials are configured on a per-artifact basis using imagePullSecrets, with a global override for air-gapped environments — making Token Broker-issued pull secrets directly applicable.

- wasmCloud hosts pull components from OCI registries using the same credential mechanisms as container runtimes, enabling unified entitlement enforcement.

- WASM component SBOMs are smaller and more deterministic than container SBOMs due to the capability-based security model — WASM components explicitly declare all external capabilities via WIT interfaces. This makes supply chain integrity verification more tractable.


## 10.2 WASM-Specific Architectural Requirements
| **Requirement** | **Architectural Response** |
| --- | --- |
| WASM artifact type support | ACR must be configured to accept OCI artifacts with WASM media types. Artifact type allow-listing is a registry configuration concern addressed in [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md). |
| WASM component versioning | OCI tags for WASM components must follow the same semantic versioning convention as container images. Lifecycle management policies in [DOC-022](../phase-7-governance/DOC-022_Artifact_Lifecycle_Policy.md) cover WASM component retention. |
| Entitlement enforcement for WASM | WASM component pulls are subject to identical entitlement enforcement as container image pulls. The Token Broker does not distinguish between artifact types — scope is namespace-based. |
| Air-gapped WASM deployment | Cosmonic Control supports a global registry override for air-gapped environments. The architecture must document the pull secret configuration pattern for air-gapped wasmCloud hosts. |
| WASM SBOM requirements | WASM components from Cosmonic Control ship with Chainguard-built images and SBOMs by default. The registry architecture must accommodate SBOM OCI attachment for WASM components. |

# 11. Azure Well-Architected Framework Alignment
This architecture is explicitly designed against the five pillars of the Azure Well-Architected Framework. The following table maps the primary architectural decisions to WAF pillar objectives. A full WAF assessment is conducted in [DOC-025](../phase-7-governance/DOC-025_WAF_Architecture_Review.md).

| **WAF Pillar** | **Key Architectural Decisions** | **Primary Documents** |
| --- | --- | --- |
| Reliability | ACR Premium geo-replication across ≥2 Azure regions. Availability zone deployment for all custom components. Token Broker entitlement caching for graceful degradation. RPO ≤ 5 min, RTO ≤ 4 hrs. | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) |
| Security | Zero Trust network model with private endpoints. Token Broker enforcing entitlement-scoped repository access. Cosign + Notary v2 supply chain signing. CMK encryption. PIM-gated admin access. | [DOC-003](DOC-003_Threat_Model_Security_Posture.md), [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md), [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md), [DOC-012](../phase-4-supply-chain/DOC-012_Image_Signing_Provenance.md) |
| Cost Optimization | Traffic-driven geo-replication placement. Automated lifecycle policies. Token Broker caching to minimize entitlement API calls. Resource tagging for cost attribution. | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-022](../phase-7-governance/DOC-022_Artifact_Lifecycle_Policy.md) |
| Operational Excellence | 100% IaC (Bicep/Terraform). GitOps configuration management. OpenTelemetry instrumentation. Self-service product team onboarding. Structured runbook library. | [DOC-015](../phase-5-sdlc/DOC-015_CICD_Pipeline_Integration.md), [DOC-018](../phase-6-operations/DOC-018_Observability_Architecture.md), [DOC-024](../phase-7-governance/DOC-024_Operating_Model_Runbooks.md) |
| Performance Efficiency | Network-close registry placement. Premium tier for concurrent read/write bandwidth. Token Broker P99 ≤ 200ms. Layer pull optimization for edge consumers. | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-005](../phase-2-platform/DOC-005_Network_Topology_Connectivity.md), [DOC-020](../phase-6-operations/DOC-020_SLO_SLA_Error_Budget.md) |

# 12. Document Dependencies & Work Plan Context
This document (DOC-001) is the entry-point document for the entire architecture corpus. It has no upstream dependencies. The following documents directly depend on the vision, principles, and constraints established here:

| **Dependent Document** | **Dependency on DOC-001** |
| --- | --- |
| [DOC-002](DOC-002_Stakeholder_Consumer_Analysis.md): Stakeholder & Consumer Analysis | Builds on the consumer landscape established in Section 9. Expands into detailed access pattern matrices and edge topology maps. |
| [DOC-003](DOC-003_Threat_Model_Security_Posture.md): Threat Model & Security Posture | Security principles in Section 4.1 define the security posture that the threat model must defend. Constraints in Section 8.1 establish non-negotiable security requirements. |
| [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md): Azure Container Registry Service Architecture | Service architecture must satisfy the quality attributes in Section 7, the WAF alignment in Section 11, and the KPIs in Section 5. |
| [DOC-025](../phase-7-governance/DOC-025_WAF_Architecture_Review.md): Architecture Review & WAF Checklist | Final WAF review is conducted against the quality attributes and KPIs established in this document. DOC-001 Section 11 is the starting point for the WAF checklist. |
| All ADRs ([DOC-023](../phase-7-governance/DOC-023_Architecture_Decision_Records.md)) | Every Architecture Decision Record must reference the principle(s) from Section 4 that motivated the decision. |

# 13. Revision History & Approvals
| **Version** | **Date** | **Description** |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial draft — architecture vision, principles, KPIs, constraints, and consumer landscape. |
| 1.0 | TBD | First approved version — pending Architecture Review Board sign-off. |


## 13.1 Required Approvals
This document requires sign-off from the following roles before status can be updated from DRAFT to APPROVED:

- Chief Architect / Head of Platform Engineering

- Chief Information Security Officer (or delegate)

- VP of Product Engineering (confirming SDLC scope alignment)

- VP of Customer Success (confirming customer distribution requirements)


>** Note:**  Upon approval, this document becomes the constitutional baseline for all Container Registry architecture decisions. Amendments require a formal Change Request and re-approval from all original signatories.


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
