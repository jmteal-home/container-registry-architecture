---
document_id: DOC-023
title: "Architecture Decision Records (ADR-001 — ADR-015)"
phase: "PH-7 — Governance & Lifecycle"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-023: Architecture Decision Records (ADR-001 — ADR-015)

| Document ID | DOC-023 |
| --- | --- |
| Phase | PH-7 — Governance & Lifecycle |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | All prior documents — see individual ADR dependency references |
| Priority | P0/P1 |

This document contains the Architecture Decision Records for all significant architectural decisions made in designing the Enterprise Container Registry platform. Each ADR documents the context, the decision made, the alternatives considered, and the consequences. Every ADR references the Architecture Principles from [DOC-001](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md) that motivated the decision.

## ADR Index
| **ADR ID** | **Title** | **Status** | **Date** | **Key Documents** |
| --- | --- | --- | --- | --- |
| ADR-001 | Azure Container Registry Premium as the registry platform | Approved | March 2026 | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md) |
| ADR-002 | Single shared registry for all products with namespace isolation | Approved | March 2026 | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-010](../phase-3-entitlement/DOC-010_SDLC_RBAC_Design.md) |
| ADR-003 | ABAC mode enabled from Day 1 — legacy roles deprecated | Approved | March 2026 | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) |
| ADR-004 | Custom Token Broker for customer entitlement-scoped access | Approved | March 2026 | [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) |
| ADR-005 | Cosign + Notation dual-toolchain signing strategy | Approved | March 2026 | [DOC-012](../phase-4-supply-chain/DOC-012_Image_Signing_Provenance.md) |
| ADR-006 | CMK encryption at ACR creation (not retrofitted) | Approved | March 2026 | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) |
| ADR-007 | Connected Registry for Tier 2/3 edge consumers | Pending | April 2026 | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-005](../phase-2-platform/DOC-005_Network_Topology_Connectivity.md) |
| ADR-008 | Azure Container Apps for Token Broker deployment | Approved | March 2026 | [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) |
| ADR-009 | Azure Cache for Redis (managed) for entitlement cache | Approved | March 2026 | [DOC-008](../phase-3-entitlement/DOC-008_Entitlement_Integration_Architecture.md), [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) |
| ADR-010 | OCI Artifact Spec v1.1 for WASM component distribution | Approved | March 2026 | [DOC-007](../phase-2-platform/DOC-007_WASM_Artifact_Registry_Extension.md) |
| ADR-011 | Event-driven cache invalidation over polling | Approved | March 2026 | [DOC-008](../phase-3-entitlement/DOC-008_Entitlement_Integration_Architecture.md) |
| ADR-012 | Tag immutability enforced on all production repositories | Approved | March 2026 | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md) |
| ADR-013 | SLSA Build Level 3 as provenance target | Approved | March 2026 | [DOC-012](../phase-4-supply-chain/DOC-012_Image_Signing_Provenance.md) |
| ADR-014 | Azure Service Bus for entitlement change events | Approved | March 2026 | [DOC-008](../phase-3-entitlement/DOC-008_Entitlement_Integration_Architecture.md) |
| ADR-015 | Workload Identity Federation as the mandatory CI/CD auth standard | Approved | March 2026 | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md), [DOC-015](../phase-5-sdlc/DOC-015_CICD_Pipeline_Integration.md) |

## ADR-001: Azure Container Registry Premium as the Registry Platform
>** ADR-001    Azure Container Registry Premium as the registry platform  Status:   Approved  │    Principle:** P-SEC-1 (Zero Trust), P-REL-1 (Pull availability), [DOC-001](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md) Vision


## Alternatives Considered
| **Alternative** | **Reason Rejected** |
| --- | --- |
| Harbor (self-hosted) | Requires Platform Engineering to operate, patch, and maintain the registry infrastructure. Eliminates managed service benefits. ABAC equivalent requires custom Harbor extensions. Selected against on operational overhead grounds. |
| AWS Elastic Container Registry (ECR) | Not on Azure — contradicts corporate cloud strategy constraint C-001. |
| GitHub Container Registry (GHCR) | No private endpoint support. No geo-replication. No connected registry for edge. Adequate for open source projects, not enterprise distribution. |
| JFrog Artifactory | Supports OCI artifacts and has strong RBAC. Evaluated as second choice. Rejected due to additional licensing cost, separate operations team required, and ACR's native Entra ID ABAC providing equivalent namespace isolation without custom configuration. |

## ADR-002: Single Shared Registry for All Products
>** ADR-002    Single shared registry for all products with namespace isolation  Status:   Approved  │    Principle:** P-OPS-3 (Self-service), P-COST-2 (Right-tier replication), [DOC-001](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md) Vision


## Alternatives Considered
| **Alternative** | **Reason Rejected** |
| --- | --- |
| One registry per product team | Creates N × Azure Registry billing units. Multiplies private endpoint count and DNS configuration complexity by N. Customer entitlement model requires routing customers to different registry endpoints per product — significant credential management complexity. Customer-facing multi-registry architecture is operationally untenable at scale. |
| One registry per product group (department) | Partial compromise. Still multiplies management overhead. ABAC in a shared registry provides equivalent isolation without the operational cost. |

## ADR-004: Custom Token Broker for Customer Entitlement-Scoped Access
>** ADR-004    Custom Token Broker for customer entitlement-scoped access  Status:   Approved  │    Principle:** P-SEC-3 (Entitlement is source of truth), T-E-002 (entitlement escalation mitigation), [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md)


## Alternatives Considered
| **Alternative** | **Reason Rejected** |
| --- | --- |
| ACR non-Entra tokens managed directly by the entitlement system | Requires the entitlement system to have direct ACR management API access. Creates a second system with ACR write access, expanding the attack surface. Entitlement system team would need to implement ACR token lifecycle management — outside their domain expertise. |
| Entra ID Conditional Access with entitlement-system claims | Entra ID Conditional Access cannot dynamically evaluate repository-level entitlements from an external system at token issuance time. The granularity required (specific ACR repository paths) is not achievable with standard Conditional Access policies. |
| Expose ACR catalog API with server-side filtering | No standard mechanism to filter ACR catalog API per-user without a custom proxy layer — which is effectively what the Token Broker is. |

## ADR-007: Connected Registry for Tier 2/3 Edge Consumers
>** ADR-007    Connected Registry for Tier 2/3 edge consumers  Status:   Pending  │    Principle:** P-REL-3 (Edge nodes are intermittently connected), P-COST-1 (Storage lifecycle)


Decision criteria for final resolution: analyze edge site connectivity patterns and pull volume data. Conduct a 30-day cost-benefit analysis comparing Connected Registry billing vs bandwidth cost of direct pull. Decision required before Phase 3 (Entitlement & Access Control) implementation.

## ADR-010: OCI Artifact Spec v1.1 for WASM Component Distribution
>** ADR-010    OCI Artifact Spec v1.1 for WASM component distribution  Status:   Approved  │    Principle:** P-OPS-1 (Infrastructure as Code), [DOC-007](../phase-2-platform/DOC-007_WASM_Artifact_Registry_Extension.md)


## ADR-015: Workload Identity Federation as the Mandatory CI/CD Auth Standard
>** ADR-015    Workload Identity Federation as the mandatory CI/CD auth standard  Status:   Approved  │    Principle:** P-SEC-2 (Principle of least privilege), SC-01 (WIF security control), [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md)


## Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial ADR set — ADR-001 through ADR-015. ADR-007 marked Pending. |
| 1.0 | TBD | First complete approved version |


>** ADR Governance:**  New ADRs are created for every significant architectural decision that: (a) affects security posture, (b) introduces a new dependency, (c) contradicts an existing principle, or (d) represents a trade-off with long-term consequences. ADRs must reference the relevant principles from [DOC-001](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md) and be approved by the Architecture Review Board within 5 days of the decision being made.


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
