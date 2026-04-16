---
document_id: DOC-008
title: "Entitlement System Integration Architecture"
phase: "PH-3 — Entitlement & Access Control"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-008: Entitlement System Integration Architecture

| Document ID | DOC-008 |
| --- | --- |
| Phase | PH-3 — Entitlement & Access Control |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT — Pending Architecture Review |
| Date | April 2026 |
| Depends On | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) (IAM Architecture) |
| Priority | P0 — Critical path for Token Broker design |

This document defines the architecture for integrating the corporate Entitlement Management System with the Enterprise Container Registry's Token Broker. It specifies the entitlement data model, API contract, synchronization patterns, event-driven cache invalidation design, and failsafe behaviors required to enforce the principle that customer repository visibility is determined exclusively and in real time by active product entitlements.

# 1. Integration Overview
The Entitlement System Integration is the foundational dependency of the Token Broker. Without a functioning entitlement integration, the Token Broker cannot issue correctly scoped tokens — any failure degrades into either a complete service outage or (far worse) an over-permissive fallback. This document establishes the design that prevents both failure modes.


>** Architecture Principle:**  The entitlement system is the sole, authoritative source of truth for customer registry access rights. The Token Broker must never make an access grant decision based on data that is not traceable to a current record in the entitlement system. No hardcoded grants, no override mechanisms, no 'break-glass' customer access outside the entitlement system.


## 1.1 Integration Actors
| **Actor** | **Role in Integration** | **Team Responsible** |
| --- | --- | --- |
| Entitlement Management System (EMS) | Source of truth for all customer product licenses and entitlements. Exposes the Entitlement API consumed by the Token Broker. | Entitlement System Team (integration partner) |
| Token Broker | Consumer of the Entitlement API. Queries customer entitlements on token request and caches results. Reacts to entitlement change events for cache invalidation. | Platform Engineering Team |
| Azure Cache for Redis | Stores Token Broker's entitlement cache. TTL-based expiry as safety net; event-driven invalidation as primary freshness mechanism. | Platform Engineering Team |
| Azure Service Bus / Event Hub | Event stream carrying entitlement change notifications from EMS to Token Broker. | Shared — EMS team publishes; Platform Engineering consumes |
| Corporate Identity System | Provides the customer identity (Entra ID object ID / OIDC sub) that the Token Broker maps to entitlement records. | Identity / IT team |

# 2. Entitlement Data Model
The following data model defines the minimum information the Token Broker requires from the entitlement system to compute a customer's ACR token scope. This is not the EMS's complete data model — it is the interface contract the Token Broker depends on.


## 2.1 Core Entities
```
// Entitlement API response schema (JSON — Token Broker's view of EMS data) // GET /api/v1/entitlements?customer_id={oid} {   'customer_id': 'a1b2c3d4-...',
      // Entra ID object ID (oid claim)   'customer_name': 'Acme Corp',
        // Human-readable — for audit logs only   'account_status': 'active',
          // active │ suspended │ terminated   'entitlements': [
    {
      'entitlement_id': 'ent-uuid-001',
      'product_id': 'widget',
            // Maps to ACR namespace: products/widget/
      'product_name': 'Widget Platform',  // Human-readable — for logs only
      'version_constraint': '>=1.0.0 <3.0.0', // SemVer range or 'all'
      'artifact_types': ['container', 'helm', 'wasm'],  // Which artifact types
      'status': 'active',
                // active │ suspended │ expired
      'effective_from': '2025-01-01T00:00:00Z',
      'effective_until': '2027-01-01T00:00:00Z',  // null = perpetual
      'granted_at': '2024-12-15T10:00:00Z',
      'last_modified': '2025-06-01T08:00:00Z'
    }   ],   'retrieved_at': '2026-04-15T12:00:00Z' }
```


## 2.2 ACR Scope Derivation Rules
The Token Broker applies the following rules to derive the ACR token scope from the entitlement response:

| **Rule** | **Condition** | **Derived ACR Scope** |
| --- | --- | --- |
| Account suspended/terminated | account_status != 'active' | Empty scope — no repositories. Token Broker returns 403 Forbidden to customer. |
| No active entitlements | entitlements array empty or all status != 'active' | Empty scope — no repositories. Token Broker returns 403 Forbidden. |
| Active entitlement, container artifact type | entitlement.status = 'active' AND artifact_types contains 'container' | Add: products/{product_id}/* with actions: content/read, metadata/read, tags/read |
| Active entitlement, helm artifact type | entitlement.status = 'active' AND artifact_types contains 'helm' | Add: products/{product_id}/charts/* with same read actions |
| Active entitlement, wasm artifact type | entitlement.status = 'active' AND artifact_types contains 'wasm' | Add: products/{product_id}/wasm/* with same read actions |
| Entitlement expired (effective_until < now) | effective_until is not null AND effective_until < current timestamp | Exclude — treat as inactive. Expired entitlements do not grant access. |
| Version constraint | version_constraint != 'all' | Token scope covers all tags in the namespace; version enforcement is at pull time via tag naming convention. ACR tokens are not version-tag-aware — version filtering is a roadmap item (see Section 7). |

# 3. Entitlement API Contract
This section defines the minimum viable API contract between the EMS and the Token Broker. This contract must be agreed with the Entitlement System team before Token Broker development begins. Where the EMS does not yet expose this API, the integration adapter pattern in Section 3.3 applies.


## 3.1 Required API Operations
| **Operation** | **Endpoint** | **Method** | **Description** | **Response SLO** | **Authentication** |
| --- | --- | --- | --- | --- | --- |
| Get customer entitlements | GET /api/v1/entitlements | GET | Returns all active and recently-expired entitlements for a customer, identified by Entra ID object ID. This is the primary operation called on every Token Broker token request (or cache miss). | P99 < 50ms from Token Broker network location | Managed Identity bearer token (mi-token-broker) |
| Get entitlements by product | GET /api/v1/entitlements?product_id={id} | GET | Returns all customers actively entitled to a specific product. Used by Token Broker for scope map pre-computation and bulk cache warming on product launch. | P99 < 200ms | Managed Identity bearer token |
| Health check | GET /api/v1/health | GET | Returns EMS API health status. Used by Token Broker to gate entitlement system failover decision. | P99 < 10ms | None (public health endpoint) |
| Event subscription (webhook) | POST /api/v1/webhooks | POST (registration only) | Token Broker registers a webhook endpoint to receive entitlement change events. Used at startup to register the Token Broker's inbound event handler URL. | N/A — registration only | Managed Identity bearer token |


## 3.2 Entitlement Change Event Schema
The EMS publishes entitlement change events to Azure Service Bus when entitlements are created, modified, or revoked. The Token Broker subscribes to these events for cache invalidation:


```
// Entitlement Change Event (Azure Service Bus message body) {   'event_id': 'evt-uuid-001',   'event_type': 'entitlement.revoked',  // entitlement.granted │ entitlement.modified │ entitlement.revoked │ account.suspended   'customer_id': 'a1b2c3d4-...',
        // Entra ID object ID   'product_id': 'widget',
              // null if account-level event   'entitlement_id': 'ent-uuid-001',
    // null if account-level event   'effective_at': '2026-04-15T12:00:00Z',  // When the change takes effect   'published_at': '2026-04-15T11:59:58Z',   'publisher': 'entitlement-management-system',   'schema_version': '1.0' }
```


## 3.3 EMS Integration Adapter Pattern
Risk RISK-001 from [DOC-001](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md) identifies that the EMS API may not exist or may not be mature. If the required API is not available at Token Broker development time, the following adapter pattern is used:

- Step 1: Define the Minimum Viable API contract (Section 3.1) as an OpenAPI 3.0 spec. This becomes the integration contract.

- Step 2: Build the Token Broker against a mock implementation of the contract (running in development/test environments).

- Step 3: EMS team implements the API spec against their backend — or Platform Engineering builds a thin adapter layer that translates the EMS's existing data export (database query, CSV, existing API) into the contract format.

- Step 4: Integration testing validates the adapter against the Token Broker before production deployment.

- Step 5: If the EMS cannot publish real-time events, the Token Broker falls back to polling mode (Section 5.2) with a configurable poll interval.

# 4. Entitlement Cache Design
The Token Broker maintains an in-process cache (backed by Azure Cache for Redis) of recently resolved entitlement decisions. This cache is the primary mechanism for meeting the Token Broker's P99 latency target (< 200ms) without a round-trip to the EMS on every token request.


## 4.1 Cache Data Model
```
// Redis cache key and value structure // Key: customer_id (Entra ID object ID) // Value: serialized EntitlementCacheEntry EntitlementCacheEntry {
  customer_id:
      string
    // Entra ID oid   account_
status:   string
    // active │ suspended │ terminated
  scope_list:
      string[]   // Derived ACR repository scope list
                                // e.g. ['products/widget/*', 'products/gadget/*']
  cached_at:
        timestamp  // When this entry was populated from EMS
  ttl_expires_at:   timestamp  // cached_at + 15 minutes (safety net TTL)
  source_checksum:  string
    // Hash of the raw EMS response — used for change detection } // Cache key pattern: 'entitlement:v1:{customer_id}' // TTL: 15 minutes (safety net — event-driven invalidation is the primary freshness mechanism) // Redis key expiry: set on SETEX — auto-purged by Redis after TTL
```


## 4.2 Cache Hit / Miss Flow
The following sequence defines the Token Broker cache lookup and population flow on every customer token request:

| **1** | **Customer Runtime** | Sends authentication request to Token Broker HTTPS endpoint with Entra ID JWT |
| --- | --- | --- |

| **2** | **Token Broker — Auth** | Validates JWT signature and claims (iss, aud, exp). Extracts customer_id from oid claim |
| --- | --- | --- |

| **3** | **Token Broker — Cache** | Queries Redis cache key 'entitlement:v1:{customer_id}' |
| --- | --- | --- |

| **4a** | **Cache HIT (P99 ****<**** 20ms)** | Returns cached scope_list and account_status. Skip to Step 7 |
| --- | --- | --- |

| **4b** | **Cache MISS** | Proceeds to EMS lookup |
| --- | --- | --- |

| **5** | **Token Broker — EMS** | GET /api/v1/entitlements?customer_id={customer_id} with MI bearer token |
| --- | --- | --- |

| **6** | **Token Broker — Cache** | Populates Redis cache entry with derived scope_list, TTL 15 minutes |
| --- | --- | --- |

| **7** | **Token Broker — ACR** | Creates or updates ACR scope map for customer; calls generateCredentials API |
| --- | --- | --- |

| **8** | **Token Broker — Response** | Returns ACR refresh token (24h TTL) to customer runtime |
| --- | --- | --- |


## 4.3 Cache Sizing
The cache is sized for the customer base, not the entitlement data volume. Each cache entry is small (< 1KB per customer). Sizing assumptions:

- 10,000 active customers at launch → 10MB cache footprint at < 1KB per entry

- Azure Cache for Redis C1 SKU (1GB) is more than sufficient. Scale to C2 (6GB) if customer base exceeds 100,000.

- Redis cluster mode not required — single-node Redis with replica for HA is sufficient for this cache workload

- Cache warming on startup: Token Broker pre-warms cache for all customers with recent token activity (last 24h) on service restart to avoid cold-start thundering herd

# 5. Event-Driven Cache Invalidation

## 5.1 Primary: Azure Service Bus Event Handler
The primary cache invalidation mechanism is event-driven: the EMS publishes entitlement change events to Azure Service Bus, and the Token Broker subscribes and invalidates (or updates) the relevant cache entry within seconds of the event being published.

| **Event Type** | **Cache Action** | **ACR Action** | **SLO** |
| --- | --- | --- | --- |
| entitlement.granted | Delete cached entry for customer_id (force re-fetch from EMS on next request) | Token Broker updates ACR scope map on next token request to include new repository | New access effective within 5 minutes (next token request after cache invalidation) |
| entitlement.revoked | Delete cached entry for customer_id | Token Broker updates ACR scope map to remove repository; existing issued tokens expire within 24h (72h edge) | Cache invalidated within 30 seconds of event; full access revocation within 24h (token TTL) |
| entitlement.modified | Delete cached entry for customer_id | Scope map updated on next token request | Effective within 5 minutes |
| account.suspended | Delete cached entry for customer_id; write negative cache entry (status: suspended) | Token Broker disables all customer ACR tokens via ACR token disable API — immediate effect | EMERGENCY PATH: within 2 minutes. Negative cache entry prevents further token issuance. |
| account.terminated | Delete all cache entries for customer_id | Token Broker disables all ACR tokens; scope maps deleted asynchronously | Within 5 minutes |


## 5.2 Fallback: Polling Mode
If the EMS cannot publish real-time events (legacy system, integration delay), the Token Broker falls back to scheduled polling:

- Poll interval: every 5 minutes for changed entitlements (EMS must support a 'modified since timestamp' query parameter)

- Token Broker queries GET /api/v1/entitlements?modified_since={last_poll_timestamp} to get all changed entitlements since last poll

- For each changed customer_id, Token Broker invalidates the relevant cache entry

- Polling mode is the fallback only — event-driven is the target state. Polling mode SLO: access revocation effective within 5 minutes of poll (worst case 10 minutes after EMS record change)

- Polling is automatically disabled when event subscription is healthy (health check on Service Bus subscription)


## 5.3 Cache Invalidation Flow (Event-Driven)
The following sequence defines the end-to-end event-driven cache invalidation flow:

| **1** | **EMS** | Customer entitlement revoked in EMS database. EMS publishes EntitlementChangedEvent to Azure Service Bus topic 'entitlement-events' |
| --- | --- | --- |

| **2** | **Azure Service Bus** | Event delivered to Token Broker's Service Bus subscription 'tokenbroker-entitlement-sub' (peak delivery < 1 second) |
| --- | --- | --- |

| **3** | **Token Broker — Event Handler** | Receives event. Deserializes and validates event schema and signature |
| --- | --- | --- |

| **4** | **Token Broker — Cache** | DEL redis key 'entitlement:v1:{customer_id}' — cache entry invalidated |
| --- | --- | --- |

| **5** | **Token Broker — Emergency Path** | If event_type = 'account.suspended': additionally call ACR Token API to disable all tokens for customer. SLO: < 2 minutes from event publish |
| --- | --- | --- |

| **6** | **Token Broker — Audit** | Write cache invalidation event to audit log: timestamp, customer_id, event_type, event_id, action_taken |
| --- | --- | --- |

| **7** | **Customer Next Token Request** | On next token request from customer, Token Broker cache miss → EMS lookup → revised scope (or 403 if revoked) |
| --- | --- | --- |

# 6. Failsafe Behaviors & Entitlement System Unavailability
The entitlement system is a critical dependency. The Token Broker must behave correctly and safely when the EMS is unavailable, degraded, or returning errors. The following behaviors are non-negotiable:


## 6.1 EMS Unavailability Behavior
| **Scenario** | **Token Broker Behavior** | **Rationale** | **Duration Limit** |
| --- | --- | --- | --- |
| EMS API returns 500/503 on token request (cache miss) | Serve from stale cache if cache entry exists (even if expired). If no cache entry exists: deny token request with 503 'Service Temporarily Unavailable'. | Fail-closed for new customers (no cache). Fail-open with stale data for known customers — preserves service continuity without granting new access. | Cache staleness: up to 15 min TTL. Token Broker logs every stale cache serve event. |
| EMS API returns 404 for customer (unknown customer) | Deny token request with 403 Forbidden. Do not cache the negative result — EMS may have a transient data issue. | Unknown customer = no entitlements = no access. Cannot grant access to unrecognized identities. | N/A — always deny unknown customers |
| EMS API timeout (> 500ms) | Retry once with 250ms timeout. If still timed out: use stale cache (as above). Log timeout event. | Short circuit on EMS slowness to maintain Token Broker P99 latency target. | Configurable timeout: default 500ms primary, 250ms retry |
| Event Bus unavailable | Fall back to polling mode automatically. Alert Platform Engineering. | Polling maintains eventual consistency. Event Bus failure does not immediately compromise security. | Alert if polling > 30 minutes; P1 incident if > 60 minutes without events |
| Complete EMS outage (all endpoints down) | Serve all requests from cache. After 15-minute cache TTL expires: deny new token requests for customers without cached entries. Customers with valid existing ACR tokens (24h TTL) continue to function. | Cache provides up to 15-minute grace window. After that: fail-closed (deny) for uncached customers. Already-issued tokens continue to function until expiry. | Max acceptable EMS outage with no customer impact: 15 minutes |
| EMS returns invalid/unexpected response schema | Deny token request. Log parsing error with full response for diagnostics. Do not use partial data. | Partial or malformed entitlement data could lead to over-permission or under-permission. Safest response is denial. | N/A — log and escalate |


## 6.2 Circuit Breaker Design
The Token Broker implements a circuit breaker on the EMS API call to prevent cascading failures. The circuit breaker has three states:

- CLOSED (normal): All EMS calls proceed normally. Failure counter tracks consecutive EMS errors.

- OPEN (EMS failure detected): EMS calls are bypassed; Token Broker uses cache exclusively. Circuit opens after 5 consecutive EMS failures within 30 seconds. Alert fired.

- HALF-OPEN (testing recovery): After 60 seconds in OPEN state, one probe request is sent to EMS. If successful, circuit closes. If failed, circuit returns to OPEN and timer resets.


## 6.3 Monitoring & Alerting for EMS Integration
| **Alert** | **Condition** | **Severity** | **Response** |
| --- | --- | --- | --- |
| EMS API High Error Rate | EMS API error rate > 5% over 5-minute window | P2 | On-call engineer investigates; EMS team notified |
| EMS API Latency Degradation | EMS API P99 latency > 200ms (Token Broker's 500ms budget exceeded) | P2 | On-call checks EMS health; escalate to EMS team |
| Circuit Breaker OPEN | Token Broker circuit breaker transitions to OPEN state | P1 | Immediate escalation to EMS team and Platform Engineering |
| Stale Cache Serving | Token Broker serving stale cache entries for > 5 minutes | P2 | Investigate EMS availability; review stale cache volume |
| Event Bus Disconnected | No entitlement events received for > 30 minutes during business hours | P1 | Investigate Service Bus; check EMS event publisher health |
| Emergency Revocation Latency | account.suspended event to ACR token disable > 2 minutes | P0 — SECURITY INCIDENT | Immediate investigation; manual ACR token disable as fallback |

# 7. Known Limitations & Roadmap
| **Limitation** | **Current Mitigation** | **Roadmap Item** |
| --- | --- | --- |
| Version-aware token scoping | Token scope covers entire product namespace (products/widget/*) regardless of version entitlement. Customers could pull any available version, not just their licensed version range. | ACR token scopes are repository-level, not tag-level. Version enforcement requires either: (a) product team creates per-version repositories (operationally complex), or (b) Token Broker implements a pull-time version check proxy. Roadmap: evaluate OCI filter proxy pattern. |
| Entitlement latency during cache warm | First token request after cache entry expiry hits EMS with potential 50-200ms latency, causing Token Broker P99 to exceed 200ms target. | Proactive cache refresh: Token Broker background job refreshes cache entries for recently-active customers before TTL expiry, avoiding on-demand cache miss. |
| EMS API does not exist yet | Integration discovery sprint required. Mock EMS used in development. | EMS team alignment on API contract. Platform Engineering builds adapter layer if needed. Tracked as RISK-001 in [DOC-001](../phase-1-foundations/DOC-001_Architecture_Vision_Goals.md). |
| Multi-tenant entitlement scoping | Some customers may have multiple deployment teams with different entitlement subsets. Current model grants all entitlements under the customer account ID. | Future: support sub-account entitlement scoping (customer_id + deployment_context) for large enterprise customers with multiple teams. |

# 8. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — data model, API contract, cache design, event-driven invalidation, failsafe behaviors, limitations |
| 1.0 | TBD | Approved — pending Architecture Review Board and Entitlement System team sign-off |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering, Entitlement System Team Lead (API contract validation). This document must be reviewed and approved by the Entitlement System team before Token Broker development begins.


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
