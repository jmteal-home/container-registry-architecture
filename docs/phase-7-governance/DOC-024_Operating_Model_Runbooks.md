---
document_id: DOC-024
title: "Operating Model & Runbook Library"
phase: "PH-7 — Governance & Lifecycle"
priority: P1
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-024: Operating Model & Runbook Library

| Document ID | DOC-024 |
| --- | --- |
| Phase | PH-7 — Governance & Lifecycle |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) (Disaster Recovery & BCP) |
| Priority | P0/P1 |

This document defines the Day-2 operating model for the Enterprise Container Registry, including ownership model, escalation paths, change management gates, incident response procedures, and the registry of operational runbooks. Full runbook content is linked from this index — the detailed step-by-step procedures are maintained as living documents in the platform runbook repository.

# 1. Operating Model Overview

## 1.1 RACI Matrix
| **Activity** | **Platform Engineering** | **Security Operations** | **Product Teams** | **Customer Success** | **EMS Team** |
| --- | --- | --- | --- | --- | --- |
| Registry platform uptime | R/A | I | I | I | I |
| Token Broker availability | R/A | C | I | I | I |
| Entitlement integration health | C | I | I | I | R/A |
| RBAC assignment governance | R/A | C | C | I | I |
| Customer credential provisioning | R | I | I | A | C |
| Vulnerability scan triage | C | R/A | R | I | I |
| Image signing key rotation | R/A | C | I | I | I |
| Incident response (P0/P1) | R/A | C | C | C | C |
| SOC 2 audit evidence | C | R/A | I | I | I |
| Namespace lifecycle (product) | C | I | R/A | I | I |
| Customer SBOM requests | C | I | I | R/A | I |

R = Responsible, A = Accountable, C = Consulted, I = Informed

# 2. Change Management Process
| **Change Type** | **Examples** | **Approval Required** | **Change Window** | **Rollback SLO** |
| --- | --- | --- | --- | --- |
| Standard — Low Risk | IaC parameter changes, lifecycle policy updates, dashboard additions | Platform Engineering Lead | Any business hours | 30 minutes |
| Standard — Medium Risk | New namespace provisioning, RBAC assignment changes, ACR policy updates | Platform Engineering Lead + peer review (2 engineers) | Business hours only | 1 hour |
| High Risk | Token Broker version upgrade, signing key rotation, new geo-replica, ABAC mode enable on existing registry | Architecture Review + CISO (security changes) + VP Engineering | Scheduled maintenance window (weekends, off-peak) | 4 hours |
| Emergency | Security incident response, critical vulnerability patch, emergency revocation | CISO or Platform Engineering Lead (emergency authorization) | Any time — no window required | Immediate manual rollback capability required |

# 3. Incident Response Procedure

## 3.1 Severity Definitions
| **Severity** | **Definition** | **Examples** | **Response SLO** | **Escalation Path** |
| --- | --- | --- | --- | --- |
| P0 — Critical | Customer-facing service completely unavailable OR security breach detected | Registry pull down for all customers; Token Broker unavailable; unauthorized access event confirmed | Acknowledge: 5 min. Mitigate: 1 hour. Resolve: 4 hours. | On-call → Platform Lead → VP Engineering → CISO (security) → CTO |
| P1 — High | Significant degradation of customer-facing service OR high-severity security event | Token Broker latency > 5x normal; EMS circuit breaker open; Critical CVE in production image | Acknowledge: 15 min. Mitigate: 2 hours. Resolve: 8 hours. | On-call → Platform Lead → VP Engineering |
| P2 — Medium | Partial degradation; no immediate customer impact; non-critical security issue | One geo-replica degraded; pipeline scanning failures; medium CVE in production image | Acknowledge: 1 hour. Resolve: 1 business day. | On-call → Platform Lead |
| P3 — Low | Minor operational issues; no customer impact | Lifecycle policy missed a cleanup cycle; slow dashboard query; monitoring gap | Acknowledge: next business day. Resolve: 1 week. | On-call → backlog ticket |

# 4. Runbook Library Index
The following runbooks are maintained in the platform runbook repository (platform-engineering/runbooks/registry/). This index provides the runbook reference, scope, and key steps. Detailed step-by-step procedures are in the linked repository documents:

| **Runbook ID** | **Title** | **Scope** | **Key Steps** | **Last Updated** |
| --- | --- | --- | --- | --- |
| RB-OPS-001 | Daily Health Check | Verify registry platform health at start of each business day | 1) Check Grafana Operations Overview dashboard. 2) Verify Token Broker health. 3) Review overnight alerts. 4) Check Defender scan queue. 5) Review error budget status. | Monthly |
| RB-OPS-002 | New Product Namespace Provisioning | Onboard a new product team namespace | 1) Validate PR using namespace-request.yaml template. 2) Run IaC pipeline. 3) Execute isolation test suite. 4) Notify product team. | Quarterly |
| RB-OPS-003 | Customer Credential Provisioning | Issue initial ACR token for new customer | 1) Verify customer entitlements in EMS. 2) Direct customer to Token Broker onboarding guide. 3) Validate first token issuance audit log entry. | Quarterly |
| RB-OPS-004 | Emergency Token Revocation (Manual) | Immediately revoke all access for a customer account | 1) Authenticate to Token Broker admin API. 2) POST /internal/cache/invalidate. 3) Call ACR token disable API for all customer tokens. 4) Verify revocation in audit log. 5) File security incident report. | Monthly |
| RB-OPS-005 | Signing Key Rotation | Rotate CI/CD signing key in Azure Key Vault | 1) Create new RSA-2048 key version in Key Vault. 2) Enter dual-sign period (72h). 3) Update CI/CD pipelines to use new key. 4) Verify new signatures in ACR. 5) Disable old key version. 6) Update customer trust store documentation. | Annual (or when triggered) |
| RB-OPS-006 | Quarantine Release (Manual) | Release a quarantined image after security review | 1) Review CVE findings in Defender for Cloud. 2) CISO/Security Lead approval with documented rationale. 3) az acr quarantine release. 4) Record exception in tracking system with expiry date. | Quarterly |
| RB-OPS-007 | ACR Regional Failover | Respond to ACR regional outage | See [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) RB-DR-001 | Quarterly |
| RB-OPS-008 | Token Broker Recovery | Respond to Token Broker regional failure | See [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) RB-DR-002 | Quarterly |
| RB-OPS-009 | EMS Outage Response | Manage registry operations during EMS unavailability | See [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) RB-DR-003 | Quarterly |
| RB-OPS-010 | Break-Glass Access | Emergency admin access when normal path unavailable | See [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) RB-DR-004 | Quarterly |
| RB-OPS-011 | Capacity Review | Quarterly review of platform capacity vs growth trajectory | 1) Pull Grafana capacity dashboard. 2) Review Token Broker RPS trend. 3) Review Redis memory trend. 4) Review ACR storage trend. 5) Compare against capacity planning triggers ([DOC-020 Section 4](../phase-6-operations/DOC-020_SLO_SLA_Error_Budget.md)). 6) Submit IaC PR for any required capacity changes. | Quarterly |
| RB-OPS-012 | SOC 2 Evidence Collection | Collect quarterly SOC 2 audit evidence package | 1) Export audit log queries from law-registry-audit. 2) Generate Sentinel compliance workbook report. 3) Export Azure Policy compliance report. 4) Document any exceptions and mitigations. 5) Submit evidence package to CISO office. | Quarterly |
| RB-OPS-013 | Security Patch — Token Broker | Deploy critical security patch to Token Broker | 1) Build patched Token Broker image (CI/CD pipeline). 2) Test in staging (1 hour soak). 3) Schedule production deployment (emergency window if P0 vuln). 4) Blue-green deployment via ACA revision management. 5) Monitor for 30 minutes post-deployment. | As needed |
| RB-OPS-014 | RBAC Quarterly Audit | Quarterly reconciliation of all RBAC assignments | 1) Run Azure Resource Graph query: all role assignments on ACR. 2) Compare against IaC repository. 3) Flag divergences. 4) Remediate unauthorized assignments. 5) File compliance report. | Quarterly |
| RB-OPS-015 | Chaos Engineering Exercise | Execute quarterly chaos engineering test suite | 1) Notify on-call team. 2) Execute CHAOS-001 through CHAOS-007 per [DOC-021 Section 4](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md). 3) Record pass/fail and observations. 4) File issues for any test failures. 5) Update DR runbooks based on findings. | Quarterly |

# 5. Capacity Review Cadence
| **Review Type** | **Frequency** | **Metrics Reviewed** | **Output** |
| --- | --- | --- | --- |
| Operational capacity review | Quarterly | Token Broker RPS trend, Redis memory utilization, ACR storage growth, error budget consumption | Capacity planning actions for next quarter |
| Annual platform review | Annual | Full WAF assessment review; SLO performance year review; cost optimization analysis; vendor roadmap review (ACR, Cosmonic, OTEL) | Annual platform investment plan for next fiscal year |
| Incident-triggered review | After any P0 or P1 incident | Error budget impact, architectural gaps revealed by incident, runbook adequacy | Post-incident architecture improvement items |

# 6. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — RACI, change management, incident response, runbook library index (15 runbooks) |
| 1.0 | TBD | Approved |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering, VP Engineering (RACI and escalation path confirmation), Security Operations Lead (incident response procedure review).


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
