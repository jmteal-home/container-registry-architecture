---
document_id: DOC-020
title: "SLO / SLA Definition & Error Budget Design"
phase: "PH-6 — Observability & Operations"
priority: P1
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-020: SLO / SLA Definition & Error Budget Design

| Document ID | DOC-020 |
| --- | --- |
| Phase | PH-6 — Observability & Operations |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | [DOC-018](DOC-018_Observability_Architecture.md) (Observability Architecture) |
| Priority | P0 |

This document defines the Service Level Objectives, Service Level Agreements, error budget policies, burn rate alert thresholds, and capacity planning triggers for the Enterprise Container Registry platform. These SLOs are the operational commitments that underpin customer contracts and internal platform reliability governance.

# 1. SLO Definitions

## 1.1 Customer-Facing SLOs
These SLOs represent commitments to external customers and may be reflected in contractual SLA terms. Breach of these SLOs has direct commercial and reputational impact:

| **SLO ID** | **Service** | **Metric** | **Target** | **Measurement Window** | **Measurement Method** |
| --- | --- | --- | --- | --- | --- |
| SLO-001 | Registry Pull Availability | Percentage of valid pull requests that succeed (HTTP 2xx response within 30 seconds) | 99.95% per calendar month | Monthly rolling window | Synthetic monitoring: probe from 3 geographic regions every 60 seconds + ACR metrics SuccessfulPullCount / TotalPullCount |
| SLO-002 | Token Broker Availability | Percentage of valid token requests that receive a response (2xx or 4xx — not 5xx or timeout) within 5 seconds | 99.95% per calendar month | Monthly rolling window | Azure Front Door health probe + Token Broker /health synthetic probe |
| SLO-003 | Token Broker P99 Latency | 99th percentile token issuance latency for cache-hit requests | ≤ 500ms | Daily rolling 24-hour window | Prometheus histogram: token_broker_token_issuance_duration_seconds P99 |
| SLO-004 | Entitlement Revocation Latency | Time from account.suspended event publication to all customer ACR tokens disabled | ≤ 2 minutes (emergency path) | Per-incident measurement | Token Broker audit log: revocation_start_timestamp → last_token_disabled_timestamp |


## 1.2 Internal Platform SLOs
These SLOs govern platform quality and are used for internal reliability governance, sprint planning, and on-call performance:

| **SLO ID** | **Service** | **Metric** | **Target** | **Measurement Window** |
| --- | --- | --- | --- | --- |
| SLO-005 | CI/CD Push Pipeline | Percentage of pipeline image push attempts that succeed | ≥ 99.5% per week | Weekly rolling window |
| SLO-006 | Vulnerability Scan Latency | Time from image push to quarantine release for passing images | P99 ≤ 10 minutes | Weekly rolling window |
| SLO-007 | Token Broker P99 Latency (cache miss) | 99th percentile latency including EMS lookup (cache miss path) | ≤ 1,000ms | Daily rolling 24-hour window |
| SLO-008 | Edge Connected Registry Sync | Percentage of scheduled sync windows that complete successfully | ≥ 95% per month | Monthly rolling window |

# 2. Error Budget Design

## 2.1 Error Budget Calculation
An error budget represents the permitted quantity of unreliability within the SLO window before the reliability target is breached:

| **SLO** | **Target** | **Error Budget (monthly)** | **Equivalent Downtime (monthly)** | **Equivalent Request Failures (at 1M pulls/month)** |
| --- | --- | --- | --- | --- |
| SLO-001 Pull Availability | 99.95% | 0.05% of requests may fail | ~21.9 minutes downtime equivalent | ~500 failed pulls |
| SLO-002 Token Broker Availability | 99.95% | 0.05% of token requests may fail | ~21.9 minutes downtime equivalent | ~250 failed token requests |
| SLO-003 Token Broker P99 Latency | ≤ 500ms P99 | 1% of requests (the P99 tail) may exceed 500ms | N/A — not downtime-based | ~10,000 slow requests |


## 2.2 Error Budget Policies
| **Error Budget Consumed** | **Policy** | **Action Required** |
| --- | --- | --- |
| < 25% | Green — normal operations | No action. Continue planned feature work and improvements. |
| 25-50% | Yellow — elevated risk | Platform Engineering reviews recent incidents. Consider delaying risky changes in the remaining error budget window. |
| 50-75% | Orange — caution | Freeze non-critical changes. Prioritize reliability work. Daily error budget review in standup. |
| > 75% | Red — reliability incident | Change freeze: no non-emergency deployments. All engineering focus on reliability improvements. Weekly CISO + VP Engineering briefing. |
| 100% (SLO breached) | SLA breach — escalation | Mandatory post-incident review (blameless). Root cause and remediation plan to CISO + VP Engineering within 5 business days. Customer notification per contract terms. |

# 3. Burn Rate Alert Thresholds
Burn rate alerts provide early warning that error budget is being consumed faster than the budget window can replenish. These alert at specified multiples of the nominal burn rate:

| **Alert** | **Burn Rate Multiple** | **Detection Window** | **Severity** | **Meaning** |
| --- | --- | --- | --- | --- |
| Fast Burn Alert | 14x burn rate | 1 hour | P1 | At current rate, 100% of monthly budget consumed in ~2.1 days. Immediate investigation required. |
| Moderate Burn Alert | 6x burn rate | 6 hours | P2 | At current rate, 100% of monthly budget consumed in ~5 days. On-call review within 2 hours. |
| Slow Burn Alert | 3x burn rate | 24 hours | P3 | At current rate, budget consumed before end of month. Non-urgent review within 1 business day. |

# 4. Capacity Planning Triggers
| **Metric** | **Warning Threshold** | **Action Trigger** | **Response** |
| --- | --- | --- | --- |
| Token Broker RPS (per region) | 1,000 RPS (50% of 2,000 max) | 1,500 RPS sustained 30 minutes | Review auto-scaling configuration; pre-provision additional ACA replicas for expected growth |
| Redis cache memory utilization | > 60% | > 80% | Evaluate upgrading Redis SKU (C1 → C2). Review cache entry size and TTL configuration. |
| ACR storage utilization | > 70% of soft limit | > 85% | Emergency lifecycle policy run; review base image bloat; evaluate storage expansion |
| EMS API P99 latency | > 100ms | > 200ms (Token Broker P99 budget breached) | Escalate to EMS team. Evaluate increasing cache TTL as temporary mitigation. |
| Customer count active tokens | 5,000 | 8,000 | Review Token Broker ACA max replicas and Redis cache sizing for 10,000+ customer scale |

# 5. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — SLO definitions, error budget design, burn rate alerts, capacity planning triggers |
| 1.0 | TBD | Approved |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering, VP Engineering (SLO commitments review), CISO (SLO-004 revocation latency commitment).


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
