---
document_id: DOC-025
title: "Architecture Review & WAF Validation Checklist"
phase: "PH-7 — Governance & Lifecycle"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-025: Architecture Review & WAF Validation Checklist

| Document ID | DOC-025 |
| --- | --- |
| Phase | PH-7 — Governance & Lifecycle |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | ALL prior documents ([DOC-001](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md) through [DOC-024](DOC-024_Operating_Model_Runbooks.md)) |
| Priority | P0/P1 |

This document is the final Well-Architected Framework (WAF) review and validation checklist for the Enterprise Container Registry architecture. It maps the five WAF pillars to the architectural decisions made across the entire document corpus, identifies open risks and residual gaps, provides an overall architecture health assessment, and defines the sign-off requirements for production readiness.

# 1. WAF Assessment Overview
The Azure Well-Architected Framework assessment evaluates the architecture against five pillars: Reliability, Security, Cost Optimization, Operational Excellence, and Performance Efficiency. Each pillar is assessed against the commitments made in [DOC-001 Section 7](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md) (Quality Attributes) and Section 11 (WAF Alignment).

| **WAF Pillar** | **Assessment Score** | **Key Strengths** | **Open Items** |
| --- | --- | --- | --- |
| Reliability | STRONG — 9/10 | Geo-replication (active-active); automatic AZ redundancy; stateless Token Broker with multi-region deployment; 15-minute cache grace window for EMS outages; edge disconnected operation design. | ADR-007 (Connected Registry decision pending); Connected Registry operational complexity; edge Tier 3/4 recovery testing not yet completed. |
| Security | STRONG — 9/10 | Zero Trust network model; ABAC namespace isolation; Token Broker entitlement enforcement; Cosign + Notation dual-toolchain signing; immutable audit logs; PIM for all admin access; penetration test planned. | Token Broker penetration test not yet executed (required before P1.0 approval); WIF migration for Jenkins pending (Q4 2026 deadline). |
| Cost Optimization | GOOD — 7/10 | Traffic-driven geo-replication; automated lifecycle policies; entitlement caching (80%+ EMS call reduction); resource tagging for cost attribution. | ADR-007 (Connected Registry billing analysis pending); no formal cost allocation model yet for per-product-team chargeback; geo-replica placement for EU/APAC not yet traffic-validated. |
| Operational Excellence | STRONG — 8/10 | 100% IaC (Bicep); GitOps configuration management; OTEL instrumentation on all custom components; 15-runbook library; self-service onboarding; RACI defined. | Platform CLI (pcli) not yet built (roadmap Q3 2026); developer experience validation with 3+ product teams not yet conducted; chaos engineering test suite not yet executed. |
| Performance Efficiency | GOOD — 8/10 | ACR Premium concurrent read throughput; Token Broker ACA auto-scaling; Redis cache P99 < 20ms on hit; network-close geo-replication; containerd layer caching. | Pull-through cache for base images is documented but not yet deployed; WASM OCI pull performance not yet benchmarked; edge pull latency optimization for Tier 3 pending. |

# 2. Reliability Pillar Checklist
| **Requirement (from [DOC-001 Section 7.1](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md))** | **Architectural Control** | **Document** | **Status** |
| --- | --- | --- | --- |
| Registry pull availability ≥ 99.95% monthly | ACR Premium geo-replication active-active; AZ automatic redundancy; Traffic Manager failover | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) | Complete |
| Token Broker availability ≥ 99.95% monthly | Multi-region ACA deployment; Front Door active-active; stateless design | [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md), [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) | Complete |
| Entitlement outage tolerance ≤ 15 minutes | Redis entitlement cache with 15-minute TTL; circuit breaker; stale cache serving | [DOC-008](../phase-3-entitlement/DOC-008_Entitlement_Integration_Architecture.md), [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) | Complete |
| RPO ≤ 5 minutes for image push data | ACR geo-replication near-real-time sync; Azure Storage geo-redundancy | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) | Complete |
| RTO ≤ 4 hours for full regional failover | Traffic Manager auto-failover; DR runbook RB-DR-001 | [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) | Complete — chaos test pending |
| Edge nodes: disconnected operation capability | Connected Registry (Tier 2); extended TTL tokens; offline bundle (Tier 3/4) | [DOC-005](../phase-2-platform/DOC-005_Network_Topology_Connectivity.md), [DOC-011](../phase-3-entitlement/DOC-011_Customer_Entitlement_Access_Flow.md), [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) | Complete — ADR-007 pending final decision |

# 3. Security Pillar Checklist
| **Requirement (from [DOC-001 Section 7.2](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md))** | **Architectural Control** | **Document** | **Status** |
| --- | --- | --- | --- |
| Zero Trust — no implicit network trust | Private endpoints; no public ACR endpoint; identity-based auth everywhere | [DOC-003](../phase-1-foundations/DOC-003_Threat_Model_Security_Posture.md) ZT-01, [DOC-005](../phase-2-platform/DOC-005_Network_Topology_Connectivity.md) | Complete |
| No anonymous pull | anonymousPullEnabled: false enforced by Azure Policy | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) | Complete |
| Customer entitlement enforcement | Token Broker server-side scope computation; non-Entra scope-map tokens | [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md), [DOC-011](../phase-3-entitlement/DOC-011_Customer_Entitlement_Access_Flow.md) | Complete — penetration test pending |
| No static CI/CD credentials | Workload Identity Federation mandatory standard (ADR-015) | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md), [DOC-015](../phase-5-sdlc/DOC-015_CICD_Pipeline_Integration.md) | Complete — Jenkins exception documented |
| Image signing mandatory for production | Cosign signing pipeline stage; admission controller enforcement | [DOC-012](../phase-4-supply-chain/DOC-012_Image_Signing_Provenance.md) | Complete |
| Vulnerability scanning gate | Trivy (build-time) + Defender for Containers (registry) + quarantine policy | [DOC-013](../phase-4-supply-chain/DOC-013_Vulnerability_Scanning_Policy_Gate.md) | Complete |
| SBOM for all production images | Syft + cosign attest in pipeline; OCI referrer storage | [DOC-014](../phase-4-supply-chain/DOC-014_SBOM_Generation_Distribution.md) | Complete — Helm/WASM SBOM gate is advisory (not blocking) at launch |
| Admin access via PIM only | PIM role assignments; no standing admin access; break-glass documented | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) | Complete |
| Audit logs tamper-evident + 12 months | Log Analytics immutable storage; 36-month retention; separation of duty | [DOC-019](../phase-6-operations/DOC-019_Audit_Logging_Compliance.md) | Complete |
| CMK encryption | Customer-managed keys via Azure Key Vault at registry creation | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) | Complete |

# 4. Cost Optimization Pillar Checklist
| **Requirement** | **Architectural Control** | **Document** | **Status** |
| --- | --- | --- | --- |
| Automated storage lifecycle management | ACR retention policy (30-day untagged); ACR Tasks for programmatic purge; entitlement-aware purge logic | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-022](DOC-022_Artifact_Lifecycle_Policy.md) | Complete |
| Traffic-driven geo-replication placement | Initial 2-region deployment; quarterly traffic-based review for EU/APAC expansion | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-020](../phase-6-operations/DOC-020_SLO_SLA_Error_Budget.md) | In Progress — initial 2 regions deployed; quarterly review scheduled |
| Token Broker caching reduces EMS API calls | Redis entitlement cache; TTL 15 minutes; event-driven invalidation | [DOC-008](../phase-3-entitlement/DOC-008_Entitlement_Integration_Architecture.md), [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) | Complete |
| Resource tagging for cost attribution | Azure Policy enforces mandatory tags per [DOC-004 Section 8.2](../phase-2-platform/DOC-004_ACR_Service_Architecture.md) | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md) | Complete |

# 5. Operational Excellence Pillar Checklist
| **Requirement** | **Architectural Control** | **Document** | **Status** |
| --- | --- | --- | --- |
| 100% Infrastructure as Code | All infrastructure defined in Bicep; no manual portal changes permitted; Azure Policy enforces | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md) to [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) | Complete — Bicep templates defined; IaC pipeline to be deployed |
| Observability on all custom components | OTEL instrumentation on Token Broker; Log Analytics + Grafana; alert definitions | [DOC-018](../phase-6-operations/DOC-018_Observability_Architecture.md) | Complete |
| GitOps configuration management | RBAC assignments in Git; ADR repository; no direct API mutations | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md), [DOC-010](../phase-3-entitlement/DOC-010_SDLC_RBAC_Design.md), [DOC-016](../phase-5-sdlc/DOC-016_GitOps_Deployment_Integration.md) | Complete |
| Self-service product team onboarding | Namespace request template; automated provisioning pipeline; isolation test suite | [DOC-010](../phase-3-entitlement/DOC-010_SDLC_RBAC_Design.md), [DOC-017](../phase-5-sdlc/DOC-017_Developer_Experience.md) | Complete |
| Runbook library for on-call engineers | 15 runbooks covering all major operational scenarios | [DOC-024](DOC-024_Operating_Model_Runbooks.md) | Complete — runbook content in repository |
| Chaos engineering validates DR design | 7 chaos scenarios defined; quarterly execution cadence | [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) | Defined — execution pending pre-production deployment |

# 6. Performance Efficiency Pillar Checklist
| **Requirement** | **Architectural Control** | **Document** | **Status** |
| --- | --- | --- | --- |
| Pull latency P99 ≤ 500ms from cloud consumers | Network-close ACR placement; Premium tier throughput; geo-replication for regional latency | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-005](../phase-2-platform/DOC-005_Network_Topology_Connectivity.md) | Complete — latency to be validated with synthetic monitoring in staging |
| Token Broker P99 ≤ 200ms (cache hit) | Redis cache P99 < 20ms; stateless ACA instances; Front Door anycast | [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) | Complete — load test to be executed in staging |
| 10,000+ concurrent customer pull endpoints | ACR Premium unlimited concurrent reads; Traffic Manager geographic distribution | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md) | Complete |
| CI/CD push throughput ≤ 10 min for 5GB image | ACR Premium high concurrent write throughput; dedicated agent pools | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md) | Complete |
| Edge pull performance optimization | Layer caching in containerd; pre-pull scheduling; Connected Registry local mirror | [DOC-005](../phase-2-platform/DOC-005_Network_Topology_Connectivity.md), [DOC-011](../phase-3-entitlement/DOC-011_Customer_Entitlement_Access_Flow.md) | Partially complete — Connected Registry decision ADR-007 pending |

# 7. Production Readiness Gate
The following criteria must ALL be satisfied before the registry platform is approved for production customer traffic:

| **Gate** | **Criterion** | **Owner** | **Current Status** |
| --- | --- | --- | --- |
| GATE-001 | All P0-priority documents ([DOC-001](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md), 002, 003, 004, 005, 006, 008, 009, 010, 011, 012, 013, 015, 018, 019, 021) reviewed and approved by Architecture Review Board | Chief Architect | In Progress — documents DRAFT |
| GATE-002 | Token Broker penetration test completed and findings remediated (P0 and P1 findings only — P2+ may be deferred) | CISO | Not Started — pending Token Broker implementation |
| GATE-003 | Chaos engineering test suite CHAOS-001 through CHAOS-007 executed in staging with all tests passing | Head of Platform Engineering | Not Started — pending staging deployment |
| GATE-004 | SLO-001 (registry pull availability) validated at ≥ 99.95% for 30 consecutive days in staging environment | Head of Platform Engineering | Not Started |
| GATE-005 | Entitlement system integration validated: token issuance tested with real EMS API (not mock); revocation SLO tested end-to-end | Head of Platform Engineering + EMS Team Lead | Not Started — pending EMS API availability |
| GATE-006 | Customer onboarding flow validated with 3 pilot customers: AKS (1), on-premises K8s (1), edge k3s (1) | VP Customer Success | Not Started — pending token broker implementation |
| GATE-007 | ADR-007 (Connected Registry) resolved — edge architecture decision confirmed | Chief Architect | In Progress |
| GATE-008 | All SOC 2 Type II evidence collection procedures validated with compliance team | CISO | Not Started |

# 8. Open Risks & Remediation Roadmap
| **Risk ID** | **Description** | **Severity** | **Mitigation Plan** | **Target Resolution** |
| --- | --- | --- | --- | --- |
| RISK-001 | EMS API does not exist or is immature — Token Broker development blocked | Critical | Integration discovery sprint. Build adapter layer against mock API. Accelerate EMS team engagement. | Pre-GATE-005 |
| RISK-002 | WASM OCI artifact standard still evolving — future compatibility break | Medium | Pluggable adapter pattern in [DOC-007](../phase-2-platform/DOC-007_WASM_Artifact_Registry_Extension.md). 90-day review cycle for standard updates. | Ongoing — quarterly review |
| RISK-003 | Token Broker is a new custom service — unknown security vulnerabilities | High | Penetration test (GATE-002) is the primary mitigation. Security code review of Token Broker source. | Pre-GATE-002 |
| RISK-004 | Connected Registry operational complexity may outweigh benefits for smaller edge sites | Medium | ADR-007 cost-benefit analysis. Provide both options with clear decision criteria. | GATE-007 |
| RISK-005 | Jenkins WIF migration may slip beyond Q4 2026 deadline | Low | Track as engineering backlog item. Service principal rotation automation reduces risk during extension period. | Q4 2026 |

# 9. Architecture Corpus Summary
The following table provides a complete index of all 25 architecture documents in this corpus, their phase, status, and approval state:

| **Doc ID** | **Title** | **Phase** | **Priority** | **Status** |
| --- | --- | --- | --- | --- |
| [DOC-001](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md) | Architecture Vision & Goals | PH-1 | P0 | DRAFT |
| [DOC-002](../phase-1-foundations/DOC-002_Stakeholder_Consumer_Analysis.md) | Stakeholder & Consumer Analysis | PH-1 | P0 | DRAFT |
| [DOC-003](../phase-1-foundations/DOC-003_Threat_Model_Security_Posture.md) | Threat Model & Security Posture | PH-1 | P0 | DRAFT |
| [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md) | ACR Service Architecture | PH-2 | P0 | DRAFT |
| [DOC-005](../phase-2-platform/DOC-005_Network_Topology_Connectivity.md) | Network Topology & Connectivity Architecture | PH-2 | P0 | DRAFT |
| [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) | Identity & Access Management Architecture | PH-2 | P0 | DRAFT |
| [DOC-007](../phase-2-platform/DOC-007_WASM_Artifact_Registry_Extension.md) | WASM Artifact Registry Extension Design | PH-2 | P1 | DRAFT |
| [DOC-008](../phase-3-entitlement/DOC-008_Entitlement_Integration_Architecture.md) | Entitlement System Integration Architecture | PH-3 | P0 | DRAFT |
| [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) | Custom Token Broker Architecture | PH-3 | P0 | DRAFT |
| [DOC-010](../phase-3-entitlement/DOC-010_SDLC_RBAC_Design.md) | SDLC Fine-Grained RBAC Design | PH-3 | P0 | DRAFT |
| [DOC-011](../phase-3-entitlement/DOC-011_Customer_Entitlement_Access_Flow.md) | Customer Entitlement Access Flow Design | PH-3 | P0 | DRAFT |
| [DOC-012](../phase-4-supply-chain/DOC-012_Image_Signing_Provenance.md) | Image Signing & Provenance Architecture | PH-4 | P0 | DRAFT |
| [DOC-013](../phase-4-supply-chain/DOC-013_Vulnerability_Scanning_Policy_Gate.md) | Vulnerability Scanning & Policy Gate Architecture | PH-4 | P0 | DRAFT |
| [DOC-014](../phase-4-supply-chain/DOC-014_SBOM_Generation_Distribution.md) | SBOM Generation & Distribution Architecture | PH-4 | P1 | DRAFT |
| [DOC-015](../phase-5-sdlc/DOC-015_CICD_Pipeline_Integration.md) | CI/CD Pipeline Integration Architecture | PH-5 | P0 | DRAFT |
| [DOC-016](../phase-5-sdlc/DOC-016_GitOps_Deployment_Integration.md) | GitOps & Deployment Integration Architecture | PH-5 | P1 | DRAFT |
| [DOC-017](../phase-5-sdlc/DOC-017_Developer_Experience.md) | Inner Loop Developer Experience Design | PH-5 | P1 | DRAFT |
| [DOC-018](../phase-6-operations/DOC-018_Observability_Architecture.md) | Observability Architecture | PH-6 | P0 | DRAFT |
| [DOC-019](../phase-6-operations/DOC-019_Audit_Logging_Compliance.md) | Audit Logging & Compliance Architecture | PH-6 | P0 | DRAFT |
| [DOC-020](../phase-6-operations/DOC-020_SLO_SLA_Error_Budget.md) | SLO / SLA Definition & Error Budget Design | PH-6 | P1 | DRAFT |
| [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) | Disaster Recovery & Business Continuity Architecture | PH-6 | P0 | DRAFT |
| [DOC-022](DOC-022_Artifact_Lifecycle_Policy.md) | Artifact Lifecycle Management Policy | PH-7 | P1 | DRAFT |
| [DOC-023](DOC-023_Architecture_Decision_Records.md) | Architecture Decision Records (ADR-001 through ADR-015) | PH-7 | P0 | DRAFT |
| [DOC-024](DOC-024_Operating_Model_Runbooks.md) | Operating Model & Runbook Library | PH-7 | P1 | DRAFT |
| DOC-025 | Architecture Review & WAF Validation Checklist | PH-7 | P0 | DRAFT |

# 10. Architecture Review Board Sign-Off
This document requires the following sign-offs to transition from DRAFT to APPROVED status. Each approver attests that they have reviewed the architecture corpus, understand the architectural decisions and their trade-offs, and accept the risks documented in this document:

| **Role** | **Name** | **Approval Date** | **Notes** |
| --- | --- | --- | --- |
| Chief Architect |  | TBD | Primary architecture approver. Confirms WAF alignment and architecture coherence across all 25 documents. |
| Chief Information Security Officer |  | TBD | Confirms security posture, threat model coverage, and compliance control mapping are adequate. |
| Head of Platform Engineering |  | TBD | Confirms operational model, runbook coverage, and implementation feasibility. |
| VP of Engineering |  | TBD | Confirms resource allocation for implementation is approved and engineering commitments are realistic. |
| Entitlement System Team Lead |  | TBD | Confirms EMS integration design is achievable and API contract is accepted. |


>** Architecture Status:**  All 25 documents are currently in DRAFT status. Production readiness requires GATES 001-008 to be satisfied. The architecture corpus is complete and ready for Architecture Review Board review. Estimated time to GATE-001 completion: 2-3 weeks of ARB review sessions.


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
