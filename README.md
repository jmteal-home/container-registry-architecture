# Enterprise Container Registry Architecture

> **Classification:** Internal Architecture — Confidential
> **Status:** DRAFT — Pending Architecture Review Board
> **Date:** April 2026

A 25-document architecture corpus for an enterprise Azure Container Registry platform serving internal product teams and external customers, with entitlement-enforced access control, supply chain security, WASM artifact support, and distributed global deployment.

## Quick start

| I want to… | Start here |
|---|---|
| Understand what this architecture is for | [DOC-001 Vision & Goals](docs/phase-1-foundations/DOC-001_Architecture_Vision_Goals.md) |
| Understand the security model | [DOC-003 Threat Model](docs/phase-1-foundations/DOC-003_Threat_Model_Security_Posture.md) |
| Understand how customer access works | [DOC-009 Token Broker](docs/phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) |
| Understand why we made the key decisions | [DOC-023 ADRs](docs/phase-7-governance/DOC-023_Architecture_Decision_Records.md) |
| Check production readiness | [DOC-025 WAF Review](docs/phase-7-governance/DOC-025_WAF_Architecture_Review.md) |

## Document corpus

### Phase 1 — Foundations & Constraints

| Doc | Title | Priority |
|-----|-------|----------|
| [DOC-001](docs/phase-1-foundations/DOC-001_Architecture_Vision_Goals.md) | Architecture Vision & Goals | P0 |
| [DOC-002](docs/phase-1-foundations/DOC-002_Stakeholder_Consumer_Analysis.md) | Stakeholder & Consumer Analysis | P0 |
| [DOC-003](docs/phase-1-foundations/DOC-003_Threat_Model_Security_Posture.md) | Threat Model & Security Posture | P0 |

### Phase 2 — Platform Architecture

| Doc | Title | Priority |
|-----|-------|----------|
| [DOC-004](docs/phase-2-platform/DOC-004_ACR_Service_Architecture.md) | ACR Service Architecture | P0 |
| [DOC-005](docs/phase-2-platform/DOC-005_Network_Topology_Connectivity.md) | Network Topology & Connectivity | P0 |
| [DOC-006](docs/phase-2-platform/DOC-006_IAM_Architecture.md) | IAM Architecture | P0 |
| [DOC-007](docs/phase-2-platform/DOC-007_WASM_Artifact_Registry_Extension.md) | WASM Artifact Registry Extension Design | P1 |

### Phase 3 — Entitlement & Access Control

| Doc | Title | Priority |
|-----|-------|----------|
| [DOC-008](docs/phase-3-entitlement/DOC-008_Entitlement_Integration_Architecture.md) | Entitlement System Integration Architecture | P0 |
| [DOC-009](docs/phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) | Custom Token Broker Architecture | P0 |
| [DOC-010](docs/phase-3-entitlement/DOC-010_SDLC_RBAC_Design.md) | SDLC Fine-Grained RBAC Design | P0 |
| [DOC-011](docs/phase-3-entitlement/DOC-011_Customer_Entitlement_Access_Flow.md) | Customer Entitlement Access Flow Design | P0 |

### Phase 4 — Supply Chain Security

| Doc | Title | Priority |
|-----|-------|----------|
| [DOC-012](docs/phase-4-supply-chain/DOC-012_Image_Signing_Provenance.md) | Image Signing & Provenance Architecture | P0 |
| [DOC-013](docs/phase-4-supply-chain/DOC-013_Vulnerability_Scanning_Policy_Gate.md) | Vulnerability Scanning & Policy Gate Architecture | P0 |
| [DOC-014](docs/phase-4-supply-chain/DOC-014_SBOM_Generation_Distribution.md) | SBOM Generation & Distribution Architecture | P1 |

### Phase 5 — SDLC Integration

| Doc | Title | Priority |
|-----|-------|----------|
| [DOC-015](docs/phase-5-sdlc/DOC-015_CICD_Pipeline_Integration.md) | CI/CD Pipeline Integration Architecture | P0 |
| [DOC-016](docs/phase-5-sdlc/DOC-016_GitOps_Deployment_Integration.md) | GitOps & Deployment Integration Architecture | P1 |
| [DOC-017](docs/phase-5-sdlc/DOC-017_Developer_Experience.md) | Inner Loop Developer Experience Design | P1 |

### Phase 6 — Observability & Operations

| Doc | Title | Priority |
|-----|-------|----------|
| [DOC-018](docs/phase-6-operations/DOC-018_Observability_Architecture.md) | Observability Architecture | P0 |
| [DOC-019](docs/phase-6-operations/DOC-019_Audit_Logging_Compliance.md) | Audit Logging & Compliance Architecture | P0 |
| [DOC-020](docs/phase-6-operations/DOC-020_SLO_SLA_Error_Budget.md) | SLO / SLA Definition & Error Budget Design | P1 |
| [DOC-021](docs/phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) | Disaster Recovery & Business Continuity Architecture | P0 |

### Phase 7 — Governance & Lifecycle

| Doc | Title | Priority |
|-----|-------|----------|
| [DOC-022](docs/phase-7-governance/DOC-022_Artifact_Lifecycle_Policy.md) | Artifact Lifecycle Management Policy | P1 |
| [DOC-023](docs/phase-7-governance/DOC-023_Architecture_Decision_Records.md) | Architecture Decision Records (ADR-001 — ADR-015) | P0 |
| [DOC-024](docs/phase-7-governance/DOC-024_Operating_Model_Runbooks.md) | Operating Model & Runbook Library | P1 |
| [DOC-025](docs/phase-7-governance/DOC-025_WAF_Architecture_Review.md) | Architecture Review & WAF Validation Checklist | P0 |

## Production readiness gates

| Gate | Criterion | Status |
|------|-----------|--------|
| GATE-001 | All P0 documents through Architecture Review Board | 🔄 In Progress |
| GATE-002 | Token Broker penetration test completed | ⬜ Not Started |
| GATE-003 | Chaos engineering test suite (CHAOS-001–007) in staging | ⬜ Not Started |
| GATE-004 | SLO-001 validated at ≥ 99.95% for 30 days in staging | ⬜ Not Started |
| GATE-005 | EMS integration validated with real API | ⬜ Not Started |
| GATE-006 | Pilot customer onboarding (AKS + on-prem K8s + k3s) | ⬜ Not Started |
| GATE-007 | ADR-007 Connected Registry decision resolved | 🔄 In Progress |
| GATE-008 | SOC 2 evidence procedures validated | ⬜ Not Started |

## Architecture overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Front Door (WAF)                        │
└────────────────────────┬────────────────────────────────────────┘
                         │
          ┌──────────────▼──────────────┐
          │        Token Broker          │  ← Custom service
          │  Azure Container Apps (ACA)  │    Entitlement → ACR scope map
          └──────┬───────────┬───────────┘
                 │           │
      ┌──────────▼──┐   ┌───▼─────────────────────────────────┐
      │ Redis Cache │   │    Azure Container Registry Premium  │
      │ 15 min TTL  │   │  ABAC · geo-replicated · quarantine  │
      └─────────────┘   └───────────────────────────────────────┘
                                  │
      ┌────────────────────────────┼────────────────────────────┐
      │                            │                             │
┌─────▼─────┐              ┌───────▼──────┐             ┌───────▼──────┐
│ Cloud AKS │              │  On-prem K8s │             │  k3s / Edge  │
│  (ESO +   │              │  (Vault/ESO) │             │ Connected Reg│
│ imagePull)│              └──────────────┘             └──────────────┘
└───────────┘
```

## Key architectural decisions

| ADR | Decision | Status |
|-----|----------|--------|
| [ADR-001](docs/phase-7-governance/DOC-023_Architecture_Decision_Records.md#adr-001-azure-container-registry-premium-as-the-registry-platform) | Azure Container Registry Premium | ✅ Approved |
| [ADR-002](docs/phase-7-governance/DOC-023_Architecture_Decision_Records.md#adr-002-single-shared-registry-for-all-products) | Single shared registry, ABAC namespace isolation | ✅ Approved |
| [ADR-004](docs/phase-7-governance/DOC-023_Architecture_Decision_Records.md#adr-004-custom-token-broker-for-customer-entitlement-scoped-access) | Custom Token Broker for entitlement-scoped access | ✅ Approved |
| [ADR-007](docs/phase-7-governance/DOC-023_Architecture_Decision_Records.md#adr-007-connected-registry-for-tier-23-edge-consumers) | Connected Registry for edge (Tier 2/3) | ⏳ Pending |
| [ADR-015](docs/phase-7-governance/DOC-023_Architecture_Decision_Records.md#adr-015-workload-identity-federation-as-the-mandatory-cicd-auth-standard) | Workload Identity Federation mandatory for CI/CD | ✅ Approved |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to propose changes, add ADRs, and submit document feedback.

## Classification

This repository contains internal architecture documentation classified as **Confidential**.
Do not share outside the organisation without explicit authorisation.
