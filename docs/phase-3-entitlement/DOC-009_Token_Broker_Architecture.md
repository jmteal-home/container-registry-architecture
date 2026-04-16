---
document_id: DOC-009
title: "Custom Token Broker Architecture"
phase: "PH-3 — Entitlement & Access Control"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-009: Custom Token Broker Architecture

| Document ID | DOC-009 |
| --- | --- |
| Phase | PH-3 — Entitlement & Access Control |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Security Sensitive |
| Status | DRAFT — Pending Architecture Review & Penetration Test Design Review |
| Date | April 2026 |
| Depends On | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) (IAM), [DOC-008](DOC-008_Entitlement_Integration_Architecture.md) (Entitlement Integration) |
| Priority | P0 — Most critical custom component in the architecture |

This document defines the complete architecture of the Custom Token Broker — the most security-critical custom-built component in the Enterprise Container Registry platform. The Token Broker is the single enforcement point that translates customer entitlements into scoped ACR access tokens. It is the 'invisible wall' that ensures customers see only repositories they are entitled to, regardless of how they connect or what tools they use.

# 1. Token Broker Purpose & Design Philosophy
ACR's native access control model grants registry-wide or repository-list access based on Entra ID RBAC. This model is well-suited for SDLC use cases where identity boundaries align with organizational structure. It is not designed for an entitlement-driven customer distribution model where access rights change dynamically based on commercial relationships stored in an external system.

The Token Broker bridges this gap. It is a stateless, horizontally scalable service that:

- Authenticates customers using their Entra ID identity

- Queries the Entitlement System for the customer's current product entitlements

- Translates entitlements into ACR non-Entra scope-map tokens scoped to precisely the entitled repository list

- Issues short-lived ACR refresh tokens that customers use as registry credentials

- Enforces that customers can neither enumerate nor access any repository outside their entitlement scope


>** Design Axiom:**  The Token Broker never trusts client-supplied scope claims. The scope encoded in every issued token is computed server-side from entitlement system data. A client cannot request additional scope, negotiate scope, or manipulate the token content. The scope is what the entitlement system says it is — nothing more.


# 2. Service Architecture

## 2.1 Deployment Architecture
The Token Broker is deployed as an Azure Container Apps (ACA) service for its combination of Kubernetes-native management, auto-scaling, managed identity integration, and private endpoint support without requiring full AKS cluster management overhead.

| **Component** | **Technology** | **Configuration** | **Rationale** |
| --- | --- | --- | --- |
| Token Broker Service | Azure Container Apps — Consumption + Dedicated plan | Min 2 replicas, max 20. Dedicated plan for predictable latency. Custom domain via Azure Front Door. | Stateless service well-suited to ACA. Managed identity integration. Auto-scales on HTTP request count. |
| Entitlement Cache | Azure Cache for Redis — C1 SKU with replica | Private endpoint in snet-tokenbroker. Entra ID auth. TLS port 6380. | Low-latency key-value cache. Managed by Azure. HA via Redis replica. |
| Token Signing Key | Azure Key Vault — RSA-2048 key | Key Vault in rg-container-registry-keyvault. Token Broker MI has Crypto Service Encryption User role. | Key never leaves Key Vault. All signing operations via Key Vault Sign API. Supports key rotation. |
| Inbound Traffic | Azure Front Door Standard/Premium — WAF policy | WAF: OWASP 3.2 Prevention mode. Rate limit: 100 req/60s per IP. Custom domain with Azure-managed TLS. | DDoS protection, WAF, global anycast entry. Hides Token Broker ACA origin IP. |
| Outbound to EMS | Private endpoint or VPN to Entitlement System API | Managed Identity bearer token authentication. | Entitlement system connectivity secured by identity, not network only. |
| Outbound to ACR | Private endpoint to ACR in hub VNet | MI bearer token for ACR Token Writer role. | All Token Broker → ACR traffic stays within Azure private network. |
| Event Handler (Service Bus) | Azure Container Apps — background trigger on Service Bus | Same ACA app, background processor triggered by Service Bus messages. | Integrated with Token Broker service for cache invalidation events. |


## 2.2 Internal Service Components
The Token Broker is a single service with four internal processing modules:

| **Module** | **Responsibility** | **Key Logic** |
| --- | --- | --- |
| Authentication Handler | Receive and validate customer Entra ID JWT on inbound HTTPS request | Validate JWT signature against Entra ID JWKS endpoint. Verify iss, aud, exp claims. Extract customer_id (oid claim). Return 401 if invalid. |
| Entitlement Resolver | Compute ACR scope for validated customer identity | Check Redis cache. On miss: call EMS API. Apply scope derivation rules ([DOC-008 Section 2.2](DOC-008_Entitlement_Integration_Architecture.md)). Cache result. Return scope_list. |
| ACR Token Issuer | Exchange customer entitlement scope for ACR refresh token | Call ACR scope map API (create/update scope map for customer). Call ACR generateCredentials API. Return ACR refresh token. |
| Event Handler | Process entitlement change events from Service Bus | Receive event. Validate event schema. Invalidate Redis cache for affected customer_id. For account.suspended: call ACR token disable API. |

# 3. Complete Token Issuance Flow

## 3.1 Normal Path — Cache Hit
| **1** | **Customer Runtime** | HTTPS POST /token — Authorization: Bearer {entra-id-jwt} to Token Broker endpoint |
| --- | --- | --- |

| **2** | **Azure Front Door** | WAF inspection. Rate limit check. Forward to Token Broker ACA instance. |
| --- | --- | --- |

| **3** | **Token Broker Auth** | Validate JWT: verify signature (Entra ID JWKS), iss, aud, exp. Extract oid → customer_id. Reject if invalid → 401. |
| --- | --- | --- |

| **4** | **Token Broker Cache** | Redis GET 'entitlement:v1:{customer_id}'. Cache HIT: retrieve scope_list and account_status. |
| --- | --- | --- |

| **5a** | **Token Broker — suspended** | IF account_status = suspended: return 403 Forbidden. Audit log: denied. |
| --- | --- | --- |

| **5b** | **Token Broker — normal** | IF account_status = active AND scope_list not empty: proceed to ACR token issuance. |
| --- | --- | --- |

| **6** | **Token Broker → ACR** | Call ACR Token Write API: GET /acr/v1/auth/exchange to get ACR access token using MI. Then PUT /acr/v1/acr/tokens/{customer-scope-map-token} to ensure scope map is current. |
| --- | --- | --- |

| **7** | **Token Broker → ACR** | POST /oauth2/token (ACR auth endpoint) to generate ACR refresh token for the customer's scope map. TTL: 24h (72h for edge requests flagged by 'X-Registry-Edge: true' header). |
| --- | --- | --- |

| **8** | **Token Broker → Audit** | Write token issuance event to audit log: timestamp, customer_id, scope_list, token TTL, source IP, request ID. |
| --- | --- | --- |

| **9** | **Token Broker → Client** | Return JSON: { acr_refresh_token, registry, ttl_seconds, issued_at } |
| --- | --- | --- |

| **10** | **Customer Runtime** | Use acr_refresh_token as password with username '00000000-0000-0000-0000-000000000000' for docker login, imagePullSecret, or WASMCLOUD_OCI_REGISTRY_PASSWORD. |
| --- | --- | --- |


## 3.2 Normal Path — Cache Miss
Steps 1-3 identical to cache hit path. Step 4 is a Redis MISS. Additional steps:

| **4** | **Token Broker Cache** | Redis GET 'entitlement:v1:{customer_id}'. Cache MISS. |
| --- | --- | --- |

| **4a** | **Token Broker → EMS** | GET /api/v1/entitlements?customer_id={customer_id} with MI bearer token. Timeout: 500ms. |
| --- | --- | --- |

| **4b** | **Token Broker — Scope** | Apply scope derivation rules. Build scope_list from entitlement response. |
| --- | --- | --- |

| **4c** | **Token Broker → Cache** | Redis SETEX 'entitlement:v1:{customer_id}' 900 {serialized entry}. (900 = 15 min TTL) |
| --- | --- | --- |

Continue to Step 5a/5b from normal cache-hit path.


## 3.3 Emergency Revocation Path
This path is triggered by an account.suspended event from Service Bus and must complete within 2 minutes of event publication:

| **1** | **Service Bus** | EntitlementChangedEvent {event_type: 'account.suspended', customer_id: '...'} received by Token Broker Event Handler. |
| --- | --- | --- |

| **2** | **Token Broker Cache** | Redis DEL 'entitlement:v1:{customer_id}'. Immediately invalidates cached scope. |
| --- | --- | --- |

| **3** | **Token Broker → Redis** | Redis SET 'entitlement:v1:{customer_id}' {status: suspended} with TTL 86400 (24h). Negative cache entry prevents further token issuance during TTL. |
| --- | --- | --- |

| **4** | **Token Broker → ACR** | List all ACR tokens for customer (GET /acr/v1/acr/tokens?customer={customer_id}). For each token: PATCH /acr/v1/acr/tokens/{token-name} {status: disabled}. Immediate effect. |
| --- | --- | --- |

| **5** | **Token Broker → Audit** | Write emergency revocation event: timestamp, customer_id, revocation_reason, tokens_disabled_count, total_duration_ms. |
| --- | --- | --- |

| **6** | **Token Broker → Alert** | Emit metric: emergency_revocation_triggered. Triggers PagerDuty/Teams notification to security operations. |
| --- | --- | --- |

# 4. Token Broker API Specification

## 4.1 Public Endpoints (Internet-Accessible via Azure Front Door)
| **Endpoint** | **Method** | **Description** | **Auth Required** | **Response** |
| --- | --- | --- | --- | --- |
| POST /v1/token | POST | Issue ACR refresh token for authenticated customer. Body: { 'registry': '{acr-name}.azurecr.io', 'edge': false }. Edge flag extends token TTL to 72h. | Entra ID Bearer JWT (Authorization header) | 200: { acr_refresh_token, registry, username, ttl_seconds, issued_at } │ 401: invalid JWT │ 403: no entitlements or suspended │ 503: EMS unavailable |
| POST /v1/token/revoke | POST | Request immediate invalidation of the caller's current ACR token. Body: { 'token_id': '...' } | Entra ID Bearer JWT | 200: token revoked │ 401: invalid JWT |
| GET /v1/token/scope | GET | Returns the caller's current entitled scope list (repository names only — not token). For customer self-service diagnostics. | Entra ID Bearer JWT | 200: { scope: [...repositories], account_status } │ 401 │ 403 |
| GET /health | GET | Public health check endpoint. Returns service status. | None | 200: { status: 'healthy', version: '...' } │ 503: degraded |
| GET /.well-known/jwks.json | GET | Returns Token Broker's public signing key as JWKS. Used by ACR to verify Token Broker-signed tokens. | None | 200: JWKS JSON |


## 4.2 Internal Endpoints (Private — VNet Only)
| **Endpoint** | **Method** | **Description** | **Auth Required** |
| --- | --- | --- | --- |
| GET /internal/health/detailed | GET | Detailed health including EMS connectivity, Redis connectivity, ACR connectivity, circuit breaker state. | Managed Identity or VNet-origin only |
| POST /internal/cache/invalidate | POST | Force cache invalidation for a customer_id. Used for emergency operations and testing. | Managed Identity — platform admin only |
| GET /internal/metrics | GET | Prometheus metrics endpoint for Token Broker service metrics. | VNet-origin only |
| POST /internal/events/entitlement | POST | Internal webhook endpoint for EMS-registered event delivery (alternative to Service Bus for simpler EMS integrations). | HMAC-signed webhook secret |

# 5. High Availability & Scaling Design

## 5.1 Stateless Design
The Token Broker is architecturally stateless. All state is stored in Azure Cache for Redis (entitlement cache) or ACR (scope maps). Any Token Broker instance can serve any request — no session affinity is required. This enables:

- Horizontal scaling: Azure Front Door distributes requests across all healthy ACA replicas round-robin

- Zero-downtime deployments: new replicas come online, old replicas drain existing connections

- Regional failover: Token Broker instances in East US 2 and West US 2 are independent — Front Door failover routes to the healthy region


## 5.2 Scaling Triggers
| **Metric** | **Scale-Out Trigger** | **Scale-In Trigger** | **Min Replicas** | **Max Replicas** |
| --- | --- | --- | --- | --- |
| HTTP requests per second | > 200 RPS per replica | < 50 RPS per replica sustained for 5 min | 2 (always-on for HA) | 20 |
| CPU utilization | > 70% average across replicas | < 30% sustained for 10 min | 2 | 20 |
| Memory utilization | > 80% | N/A — scale-out only on memory | 2 | 20 |
| Service Bus message queue depth | > 1000 unprocessed messages | < 100 messages | 1 (background processor) | 5 |


## 5.3 Redis HA Configuration
The Redis cache uses Azure Cache for Redis with a replica for HA. Key behaviors:

- Primary-replica replication: all writes go to primary; reads can be served from replica (Token Broker configured to allow replica reads for cache hit path)

- Automatic failover: Azure Cache for Redis promotes replica to primary within 2 minutes of primary failure. Token Broker handles Redis connection errors with retry + circuit breaker.

- Cache loss on failover: a brief period of cache miss after failover is acceptable — Token Broker falls back to EMS queries. The cache warming background job repopulates within 5 minutes.


## 5.4 Multi-Region Token Broker Deployment
| **Region** | **ACA Environment** | **Redis Cache** | **Front Door Origin** | **Notes** |
| --- | --- | --- | --- | --- |
| East US 2 (Primary) | aca-env-tokenbroker-eastus2 | redis-tokenbroker-eastus2 (C1 + replica) | Origin group primary | Serves East US customer traffic and all SDLC traffic |
| West US 2 (Secondary) | aca-env-tokenbroker-westus2 | redis-tokenbroker-westus2 (C1 + replica) | Origin group secondary (equal priority) | Serves West US customer traffic; Front Door failover target for East US 2 |
| West Europe (Phase 2) | aca-env-tokenbroker-westeurope | redis-tokenbroker-westeurope (C1 + replica) | Origin group EU | EU customer traffic; GDPR data residency consideration |


>** Redis Cache Independence:**  Each region's Redis cache is independent — there is no cross-region Redis replication. Cache misses in one region do not affect another region. A customer pulling from West US 2 after their entitlements were cached in East US 2 will experience a cache miss in West US 2 on first request, followed by an EMS lookup and cache population in West US 2.


# 6. Security Design

## 6.1 Authentication Security
| **Security Control** | **Implementation** | **Threat Mitigated** |
| --- | --- | --- |
| JWT signature validation | Token Broker validates every inbound JWT against Entra ID's JWKS endpoint. Keys cached locally with 1-hour refresh. No unsigned or self-signed JWTs accepted. | T-S-001 (customer identity spoofing) |
| JWT claim validation | Mandatory validation of: iss (must match expected Entra ID tenant), aud (must match Token Broker's registered app ID), exp (must be in the future), iat (must not be in the far future — clock skew tolerance: 5 minutes). | T-S-001 |
| Rate limiting | Azure Front Door: 100 requests per 60 seconds per source IP. Token Broker in-process: 10 requests per second per customer_id. Prevents credential stuffing. | T-D-001 (Token Broker DDoS) |
| No scope parameter in request | The requested token scope is never accepted from the client. Scope is always computed server-side from entitlement data. | T-E-002 (entitlement escalation) |
| Request size limits | Maximum request body: 4KB. Rejects oversized payloads at Azure Front Door WAF before reaching Token Broker. | DoS via large payloads |


## 6.2 Token Security
| **Security Control** | **Implementation** | **Notes** |
| --- | --- | --- |
| Short token TTL | ACR refresh tokens: 24h standard, 72h edge. ACR access tokens derived from refresh tokens: 3 hours (ACR platform behavior). | Limits the window during which a stolen token can be used |
| Non-transferable scope | ACR scope-map tokens are bound to the specific scope map created for the customer. The token cannot be used to access repositories outside the scope map definition. | ACR platform guarantee |
| Token revocation on suspension | Emergency path (Section 3.3) immediately disables all ACR tokens for a suspended account via ACR Token API. | Within 2 minutes of account.suspended event |
| Token ID for audit traceability | Every issued ACR token has a unique name pattern: 'customer-{customer_id_hash}-{timestamp}'. Token issuance and use are correlated in audit logs via this ID. | Enables forensic analysis of which token was used for a specific pull event |
| No token caching by Token Broker | Token Broker does not cache issued ACR tokens. Each token request generates a new ACR token. Entitlements are cached; tokens are not. | Ensures every token reflects the current entitlement state at issuance time |


## 6.3 Penetration Test Requirements
Per [DOC-003](../phase-1-foundations/DOC-003_Threat_Model_Security_Posture.md) security control SC-21, the Token Broker must undergo a penetration test focused on the following attack scenarios before production deployment:

- PT-001: Entitlement escalation — attempt to obtain a token for a non-entitled repository by manipulating request parameters, JWT claims, or API behavior

- PT-002: Token scope manipulation — attempt to decode and modify the ACR token scope (should be impossible as scope is ACR-server-side)

- PT-003: Customer identity spoofing — attempt to obtain tokens for other customers by forging or replaying JWTs

- PT-004: Cache poisoning — attempt to inject malicious entitlement data into the Redis cache via timing attacks or API abuse

- PT-005: Denial of service — flood testing against the Token Broker endpoint to validate rate limiting and auto-scaling

- PT-006: Entitlement bypass via stale cache — test behavior when entitlement system is unavailable; verify no over-permission

- PT-007: Emergency revocation latency — verify account.suspended → all tokens disabled within 2-minute SLO under load

# 7. Observability Instrumentation
The Token Broker is the most instrumented component in the registry architecture. Every decision, every call, every cache hit, and every token issuance is tracked. This instrumentation is the primary source of evidence for both operational monitoring and security audit.


## 7.1 OpenTelemetry Traces
| **Trace Span** | **Parent Span** | **Key Attributes** | **Sampling** |
| --- | --- | --- | --- |
| token.issuance | (root span) | customer_id, scope_count, cache_hit, token_ttl, source_ip, user_agent, duration_ms | 100% (all token requests) |
| jwt.validation | token.issuance | jwt_issuer, jwt_audience, jwt_expiry, validation_result | 100% |
| entitlement.cache.lookup | token.issuance | customer_id, cache_hit, cache_ttl_remaining | 100% |
| entitlement.ems.query | token.issuance (on cache miss) | customer_id, ems_response_time_ms, entitlement_count, ems_status_code | 100% |
| acr.scope_map.update | token.issuance | customer_id_hash, scope_hash, acr_response_code, duration_ms | 100% |
| acr.token.generate | token.issuance | customer_id_hash, token_ttl, acr_response_code, duration_ms | 100% |
| event.cache.invalidation | (background) | customer_id, event_type, event_id, duration_ms | 100% |
| acr.token.revoke | (background — emergency) | customer_id_hash, tokens_revoked_count, total_duration_ms | 100% |


## 7.2 Key Metrics (Prometheus)
| **Metric Name** | **Type** | **Labels** | **Alert Threshold** |
| --- | --- | --- | --- |
| token_broker_token_issuances_total | Counter | result (success│denied│error), cache_hit (true│false), token_ttl | — |
| token_broker_token_issuance_duration_seconds | Histogram | cache_hit, result | P99 > 0.5s → P2 alert |
| token_broker_ems_latency_seconds | Histogram | status_code | P99 > 0.2s → P2 alert |
| token_broker_cache_hit_ratio | Gauge | — | < 0.8 sustained 10min → P2 alert (cache miss storm) |
| token_broker_circuit_breaker_state | Gauge | target (ems│acr│redis) | = OPEN → P1 alert |
| token_broker_emergency_revocations_total | Counter | — | Any increment → security alert |
| token_broker_denied_requests_total | Counter | reason (no_entitlements│suspended│invalid_jwt│rate_limited) | Spike > 10x baseline → security alert (potential credential stuffing) |
| token_broker_scope_size | Histogram | — | P99 > 50 repositories (potential over-entitlement anomaly) |

# 8. Deployment Specification

## 8.1 Container Image Requirements
- Base image: distroless (gcr.io/distroless/static or Chainguard equivalent) — no shell, no package manager, minimal attack surface

- Runtime: language-specific runtime layer above distroless (Go binary preferred for low-overhead; alternatively .NET minimal API)

- Non-root execution: USER nonroot:nonroot in Dockerfile — no root execution

- Read-only filesystem: ACA configuration enforces read-only root filesystem; only /tmp is writable

- Image signing: Token Broker image is signed with Cosign (same pipeline as product container images)


## 8.2 Azure Container Apps Configuration
```yaml
```yaml
# Azure Container Apps configuration (Bicep excerpt)
resource tokenBrokerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'tokenbroker'
  location: primaryLocation
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${miTokenBrokerId}': {} } }
  properties: {
  environmentId: acaEnvironmentId
  configuration: {

  ingress: {

  external: false
        // Internal only — exposed via Front Door

  targetPort: 8080

  transport: 'http2'
      }

  secrets: [
        { name: 'redis-connection', keyVaultUrl: '${kvUri}/secrets/redis-connection', identity: miTokenBrokerId }
      ]
    }
  template: {

  containers: [{

  name: 'tokenbroker'

  image: '{registry}.azurecr.io/internal/tokenbroker:{version}'

  resources: { cpu: '0.5', memory: '1Gi' }

  env: [
          { name: 'ACR_NAME', value: acrName }
          { name: 'EMS_API_URL', value: emsApiUrl }
          { name: 'AZURE_CLIENT_ID', value: miTokenBrokerClientId }
          { name: 'OTEL_EXPORTER_OTLP_ENDPOINT', value: otelCollectorUrl }
        ]

  readinessProbe: { httpGet: { path: '/health', port: 8080 } }

  livenessProbe:  { httpGet: { path: '/health', port: 8080 }, initialDelaySeconds: 15 }
      }]

  scale: { minReplicas: 2, maxReplicas: 20, rules: [
        { name: 'http-rule', http: {

metadata: { concurrentRequests: '100' } } }
      ]}
    }   } }
```


# 9. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — service architecture, token issuance flows (3 paths), API spec, HA design, security controls, observability instrumentation, deployment spec |
| 1.0 | TBD | Approved — pending CISO review, Architecture Review Board, and penetration test design sign-off |


>** Required Approvals:**  CISO (primary approver — security design review), Chief Architect, Head of Platform Engineering. Penetration test must be commissioned and results reviewed before DOC-009 version 1.0 is approved for production implementation.


	CONFIDENTIAL | Classification: Internal Architecture — Security Sensitive	Page  of
