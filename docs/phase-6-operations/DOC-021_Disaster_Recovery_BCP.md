---
document_id: DOC-021
title: "Disaster Recovery & Business Continuity Architecture"
phase: "PH-6 — Observability & Operations"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-021: Disaster Recovery & Business Continuity Architecture

| Document ID | DOC-021 |
| --- | --- |
| Phase | PH-6 — Observability & Operations |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | [DOC-020](DOC-020_SLO_SLA_Error_Budget.md) (SLO/SLA Design) |
| Priority | P0 |

This document defines the disaster recovery and business continuity architecture for the Enterprise Container Registry. It specifies RTO/RPO targets per component, the geo-replication failover design, Token Broker regional failover, edge node disconnected operation, entitlement system outage handling with cached decisions, and the chaos engineering test plan that validates all recovery scenarios.

# 1. RTO / RPO Matrix
The following RTO and RPO targets define the recovery requirements for each platform component. These targets drive the HA architecture decisions documented throughout this corpus:

| **Component** | **RTO** | **RPO** | **Recovery Mechanism** | **Tested Frequency** |
| --- | --- | --- | --- | --- |
| ACR image pull availability | < 4 hours for full regional failover; < 2 minutes for AZ failure | < 5 minutes (geo-replication lag) | Azure Traffic Manager auto-routes to healthy replica. No manual intervention for AZ failure. Regional failover may require traffic manager configuration update. | Semi-annual DR drill |
| Token Broker availability | < 5 minutes for instance failure; < 30 minutes for full regional failure | Stateless — zero RPO | Azure Front Door auto-removes unhealthy origins. ACA platform auto-restarts failed instances. Multi-region deployment provides regional failover. | Quarterly chaos drill |
| Entitlement cache (Redis) | < 3 minutes for primary failure; < 10 minutes for full Redis instance failure | < 30 seconds (replica lag) | Azure Cache for Redis auto-promotes replica on primary failure. Token Broker reconnects on next request. Cache warm-up via background EMS query. | Quarterly chaos drill |
| ACR management plane (control plane) | < 24 hours (home region outage may impair configuration changes; data plane unaffected) | N/A — management plane is stateless configuration | Geo-replicated data plane continues serving during management plane unavailability. Configuration changes queued. | Annual DR drill |
| Entitlement System (external) | Per EMS team SLA — not owned by Platform Engineering | N/A — external dependency | Token Broker cache provides up to 15-minute operation during EMS outage. Polling mode fallback. | Per EMS team — not registry DR drill |

# 2. Regional Failover Architecture

## 2.1 ACR Geo-Replication Failover
ACR geo-replication uses Azure Traffic Manager to route pull requests to the nearest healthy replica. Failover is largely automatic, but the following procedure documents the complete failover scenario:

| **Step** | **Trigger** | **Action** | **Responsible** | **Duration** |
| --- | --- | --- | --- | --- |
| Detection | Azure Traffic Manager health probe fails for East US 2 ACR endpoint (3 consecutive failures over 90 seconds) | Traffic Manager automatically stops routing to East US 2. Pull traffic reroutes to West US 2 replica. | Automatic (Azure platform) | < 2 minutes from first probe failure |
| Validation | Platform Engineering receives P0 alert: 'ACR East US 2 health probe failed' | Validate that West US 2 is serving pull traffic. Check ACR control plane availability. | On-call engineer | Within 15 minutes |
| Communication | Regional outage confirmed as > 15 minutes duration | Customer notification via status page. Internal escalation to VP Engineering. | Platform Engineering + Customer Success | Within 30 minutes of outage confirmation |
| DNS / Private Endpoint (if needed) | Private endpoint DNS resolution may cache East US 2 IP | Update private DNS A records if Azure Private DNS auto-failover is not triggered. Force DNS refresh on connected VNets. | Platform Engineering | Within 1 hour |
| Recovery | East US 2 region recovers | Azure Traffic Manager re-enables East US 2 after health probe recovery. Replication lag resolves automatically (RPO < 5 min). | Automatic (Azure platform) | < 15 minutes after region recovery |


## 2.2 Token Broker Multi-Region Failover
The Token Broker is deployed active-active in East US 2 and West US 2. Azure Front Door provides global load balancing and automatic failover:

- Front Door health probes: every 30 seconds to Token Broker /health endpoint in each region

- Automatic failover: Front Door removes unhealthy origin from routing within 90 seconds of health probe failure (3 consecutive failures)

- State independence: Token Broker is stateless. West US 2 Redis cache is independent. Customers routed to West US 2 may experience a cache miss on first request (EMS lookup), adding ~50-200ms latency, but requests succeed.

- Manual failover: Platform Engineering can force 100% traffic to a single region via Front Door origin weight adjustment (emergency operations procedure in runbook library)

# 3. Edge Node Disconnected Operation
Edge nodes are designed to operate disconnected from the registry. The following recovery scenarios define the expected behavior during and after connectivity loss:

| **Scenario** | **Duration** | **Behavior** | **Recovery Action** | **Impact** |
| --- | --- | --- | --- | --- |
| Token Broker unreachable (Tier 1 edge) | < 24 hours | k3s serves images from containerd cache. No new pulls require registry. Token TTL not yet expired. | No action — transparent to workloads | None if workloads don't require new images |
| Token Broker unreachable (Tier 1 edge) | 24-72 hours | Token TTL expired. New pod scheduling requiring new image pulls will fail. | Restore connectivity. Token auto-refreshes on reconnect (72h edge TTL provides additional buffer for edge-flagged tokens). | New deployments blocked; existing workloads unaffected |
| ACR unreachable (Tier 2 — Connected Registry) | Any duration | Connected Registry serves images from local mirror. Sync paused but local cache serves all previously synced images. | No action during outage. Sync resumes automatically on reconnect. | None for cached images; new versions unavailable until sync |
| Complete site disconnection (Tier 3/4) | Extended (days-months) | Site operates from local Connected Registry or pre-loaded image bundle. No registry dependency for running workloads. | New images: request offline bundle via support channel. Existing workloads: no impact. | New image versions require offline bundle process |

# 4. Chaos Engineering Test Plan
Chaos engineering tests validate the DR architecture under controlled failure conditions. The following tests are executed semi-annually (production) and quarterly (staging):

| **Test ID** | **Scenario** | **Injection Method** | **Expected Behavior** | **Success Criteria** |
| --- | --- | --- | --- | --- |
| CHAOS-001 | ACR availability zone failure | Azure zone redundancy validation — query ACR while one AZ is simulated unavailable via Azure chaos studio | ACR data plane continues serving. No customer-visible impact. | Zero pull failures during AZ simulation. ACR metrics show no drop in SuccessfulPullCount. |
| CHAOS-002 | Token Broker instance failure | Kill one Token Broker ACA replica. Verify ACA auto-restart and Front Door rerouting. | Front Door routes to healthy instances. Auto-restart within 60 seconds. | No > 5-second gap in token issuance capability. ACA replica restarted within 60 seconds. |
| CHAOS-003 | Redis primary failure | Simulate Redis primary failure using Azure Redis chaos action. | Redis promotes replica to primary within 2 minutes. Token Broker reconnects. Cache miss spike then resolves. | Token Broker availability maintained. P99 latency spike < 60 seconds. Cache hit ratio recovers within 5 minutes. |
| CHAOS-004 | EMS API outage (15 minutes) | Block Token Broker → EMS traffic via NSG rule. Simulate 15-minute EMS outage. | Token Broker circuit breaker opens. Serves from cache for up to 15 minutes. New uncached customers get 503. | Zero token issuance failures for cached customers during 15-minute outage window. Alert fires within 2 minutes. |
| CHAOS-005 | Emergency revocation under load | Trigger account.suspended event for a test customer during simulated 500 RPS load on Token Broker. | Emergency revocation completes within 2 minutes even under load. Revocation does not impact other customer token issuances. | Revocation SLO (< 2 minutes) met. Zero impact on non-revoked customer token issuances during the same window. |
| CHAOS-006 | ACR regional failover | Simulate East US 2 ACR endpoint failure by disabling the Traffic Manager East US 2 endpoint. | Pulls route to West US 2 within 2 minutes. No customer-visible impact. | Zero pull failures > 2 minutes after failover trigger. P99 latency < 500ms from West US 2. |
| CHAOS-007 | Token Broker full regional failure | Disable all Token Broker instances in East US 2. | Front Door routes all traffic to West US 2. West US 2 Token Broker auto-scales to handle full load. | Token issuance P99 < 2x normal during failover. Auto-scale completes within 3 minutes. |

# 5. Business Continuity Runbooks
The following high-level runbooks are referenced in DR scenarios. Full runbooks are maintained in the platform runbook library ([DOC-024](../phase-7-governance/DOC-024_Operating_Model_Runbooks.md)):

| **Runbook Name** | **Scenario** | **Key Steps** | **Escalation Path** |
| --- | --- | --- | --- |
| RB-DR-001: ACR Regional Failover | East US 2 ACR region unavailable | 1) Confirm Traffic Manager failover to West US 2. 2) Validate pull traffic health. 3) Update private DNS if needed. 4) Customer communication. 5) Monitor for recovery. | Platform Lead → VP Engineering → CISO (if > 2 hours) |
| RB-DR-002: Token Broker Recovery | Token Broker fully unavailable in one region | 1) Confirm Front Door failover. 2) Validate West US 2 Token Broker health. 3) Check Redis cache hit rate. 4) Monitor auto-scale. 5) Root cause analysis. | Platform Lead → VP Engineering |
| RB-DR-003: EMS Outage Response | Entitlement System API unavailable | 1) Confirm circuit breaker OPEN. 2) Notify EMS team. 3) Monitor stale cache serving. 4) After 15 minutes: alert customers with known pull failures. 5) Coordinate EMS recovery. | Platform Lead → EMS Team Lead → VP Engineering (if > 30 minutes) |
| RB-DR-004: Emergency Access (Break-Glass) | Normal admin access path unavailable | 1) Retrieve break-glass credentials from physical safe. 2) Authenticate with break-glass account. 3) Document all actions taken. 4) Mandatory incident report within 24 hours. | CISO + CTO must authorize break-glass activation |

# 6. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — RTO/RPO matrix, regional failover, edge disconnected operation, chaos test plan, runbooks |
| 1.0 | TBD | Approved |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering, CISO (emergency revocation DR test design). Chaos engineering tests must be reviewed by the Security Operations team before production execution.


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
