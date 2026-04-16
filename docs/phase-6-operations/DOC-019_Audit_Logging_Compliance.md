---
document_id: DOC-019
title: "Audit Logging & Compliance Architecture"
phase: "PH-6 — Observability & Operations"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-019: Audit Logging & Compliance Architecture

| Document ID | DOC-019 |
| --- | --- |
| Phase | PH-6 — Observability & Operations |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | [DOC-018](DOC-018_Observability_Architecture.md) (Observability Architecture) |
| Priority | P0 |

This document defines the audit logging architecture for the Enterprise Container Registry — the tamper-evident, immutable record of every access decision, configuration change, and lifecycle event. It specifies the audit log schema, SIEM integration design, retention policy, and the evidence mapping to SOC 2 Type II and ISO 27001:2022 control requirements.

# 1. Audit Log Architecture
The audit log architecture is designed around a non-repudiable, tamper-evident record of all registry interactions. The architectural decisions that enforce integrity are:

| **Control** | **Implementation** |
| --- | --- |
| Immutable log storage | Azure Monitor Log Analytics workspace with immutable storage policy: logs are write-once, cannot be deleted or modified by any operator, including Platform Engineering and Azure subscription owners. |
| Separation of duty | Registry administrators manage ACR but have no access to the audit Log Analytics workspace. Different resource groups, different RBAC, different subscription admin boundary. |
| Completeness | ACR diagnostic settings configured to route all ContainerRegistryLoginEvents and ContainerRegistryRepositoryEvents to the audit workspace. Token Broker writes supplementary audit events covering the entitlement decision layer. |
| Tamper detection | Log Analytics resource lock (CanNotDelete) prevents workspace deletion. Azure Activity Log captures any attempt to modify the diagnostic settings. |
| Retention | 12 months hot (queryable) + 24 months archive (Azure Storage immutable blob). Total: 36 months. Archive tier costs < 5% of hot tier. |

# 2. Audit Log Schema

## 2.1 ACR Native Audit Events
| **Event Category** | **Log Table** | **Key Fields** | **When Generated** |
| --- | --- | --- | --- |
| ContainerRegistryLoginEvents | AzureDiagnostics | identity, loginServer, resultType, resultDescription, correlationId, clientIpAddress, userAgent | Every authentication attempt to ACR login endpoint — success and failure |
| ContainerRegistryRepositoryEvents | AzureDiagnostics | identity, repository, tag, digest, action (push/pull/delete), resultType, correlationId | Every repository interaction: push, pull, tag creation, manifest delete |


## 2.2 Token Broker Supplementary Audit Events
ACR's native audit log does not capture the entitlement decision context (which entitlement authorized this token). The Token Broker writes supplementary audit events that provide the complete access decision context:


```
// Token Broker Audit Event Schema (written to law-registry-audit) {   'event_id': 'uuid-v4',   'event_type': 'token.issued │ token.denied │ token.revoked │ cache.invalidated',   'timestamp': '2026-04-15T12:00:00.123Z',   'customer_id_hash': 'sha256-truncated(customer_id)',  // Hashed — not raw PII   'customer_account_status': 'active │ suspended',   'scope_repository_count': 3,   'scope_product_list': ['widget', 'gadget'],   // Product names, not customer PII   'token_ttl_seconds': 86400,   'cache_hit': true,   'entitlement_source': 'cache │ ems-live',   'denial_reason': null,  // populated if event_type = token.denied   'source_ip': '198.51.100.0',   'user_agent': 'containerd/1.7 k8s.io',   'request_id': 'correlation-id',   'token_broker_instance': 'tokenbroker-eastus2-replica-2',   'processing_time_ms': 18 }
```


## 2.3 Audit Event Catalog
| **Event Type** | **Source** | **Criticality** | **Retention** |
| --- | --- | --- | --- |
| Customer image pull | ACR ContainerRegistryRepositoryEvents | High | 36 months |
| Customer authentication (token issuance) | Token Broker supplementary audit | High | 36 months |
| Customer authentication denied | Token Broker supplementary audit | High (security event) | 36 months |
| Emergency token revocation | Token Broker supplementary audit | Critical | 36 months |
| Admin PIM activation | Azure AD PIM audit log | Critical | 36 months |
| ACR configuration change | Azure Activity Log | High | 36 months |
| RBAC role assignment change | Azure Activity Log | Critical | 36 months |
| Image push (CI/CD) | ACR ContainerRegistryRepositoryEvents | Medium | 36 months |
| Image signing event | Cosign/Notation pipeline log | High | 36 months |
| Vulnerability scan result | Defender for Cloud audit | High | 36 months |
| Quarantine state change | Defender for Cloud + ACR | High | 36 months |
| Entitlement cache invalidation | Token Broker supplementary audit | Medium | 12 months |

# 3. SIEM Integration
The audit Log Analytics workspace integrates with Microsoft Sentinel (SIEM) for security event correlation, threat detection, and compliance reporting:

| **Integration** | **Configuration** | **Use Case** |
| --- | --- | --- |
| Microsoft Sentinel workspace connection | Sentinel connected to law-registry-audit and law-registry-security workspaces. Data connector: Azure Activity, Microsoft Defender, custom Token Broker tables. | Security incident investigation, threat hunting, compliance evidence collection |
| Custom Sentinel analytics rules | Rule 1: Multiple denied token requests for same customer_id (> 10 in 5 minutes) → credential stuffing alert. Rule 2: Emergency revocation not followed by incident report within 1 hour → compliance alert. Rule 3: PIM activation outside business hours → anomaly alert. Rule 4: ACR configuration change without change management ticket → policy alert. | Automated threat detection and compliance enforcement |
| Sentinel workbook: Registry Compliance | Custom workbook presenting SOC 2 evidence: access log completeness, unauthorized access events (should be 0), audit log integrity (immutable storage health check). | Quarterly SOC 2 audit evidence generation |
| Export to SIEM (external) | For customers or compliance teams requiring external SIEM integration: Log Analytics data export to Azure Event Hub → customer SIEM (Splunk, QRadar, etc.). | Customer security operations integration |

# 4. Compliance Evidence Mapping
| **Control** | **SOC 2 Criteria** | **ISO 27001:2022** | **Evidence Source** | **Evidence Type** |
| --- | --- | --- | --- | --- |
| All registry access is authenticated | CC6.1 | A.9.4.1 | law-registry-audit: zero events with identity=anonymous | Log query export |
| Customer access restricted to entitled repositories | CC6.3 | A.9.1.2 | Token Broker audit: scope_repository_count matches entitlement count; no unauthorized pull events | Log query + Token Broker audit |
| Admin access requires PIM + MFA | CC6.6 | A.9.4.2 | Azure AD PIM audit: all Owner activations include MFA and justification | Azure AD audit log export |
| Audit logs are complete and immutable | CC4.1, CC7.2 | A.12.4.1 | Log Analytics immutable storage policy active; zero deletion events in Activity Log | Azure Policy compliance report + Activity Log |
| Unauthorized access attempts detected | CC7.2 | A.12.4.3 | Sentinel alert: unauthorized_access_denied_rate = 0 for production pull events | Sentinel workbook |
| Images in production are signed | CC7.1 | A.14.2.1 | Cosign verification audit in pipeline logs; admission controller enforcement metrics | Pipeline telemetry + admission webhook logs |
| Vulnerability scanning is continuous | CC7.1 | A.12.6.1 | Defender for Containers scan completion events in Log Analytics | Defender for Cloud report |
| Emergency access (break-glass) is audited | CC6.2 | A.9.2.6 | Azure AD sign-in logs: break-glass account usage triggers immediate alert | Azure AD audit log |

# 5. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — audit log architecture, schema, SIEM integration, compliance evidence mapping |
| 1.0 | TBD | Approved |


>** Required Approvals:**  CISO (audit architecture and compliance mapping), Chief Architect, Compliance team (SOC 2/ISO 27001 evidence review).


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
