---
document_id: DOC-022
title: "Artifact Lifecycle Management Policy"
phase: "PH-7 — Governance & Lifecycle"
priority: P1
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-022: Artifact Lifecycle Management Policy

| Document ID | DOC-022 |
| --- | --- |
| Phase | PH-7 — Governance & Lifecycle |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | [DOC-013](../phase-4-supply-chain/DOC-013_Vulnerability_Scanning_Policy_Gate.md) (Vulnerability Scanning), [DOC-015](../phase-5-sdlc/DOC-015_CICD_Pipeline_Integration.md) (CI/CD Pipeline) |
| Priority | P0/P1 |

This document defines the artifact lifecycle management policies for the Enterprise Container Registry. It specifies tag retention rules, untagged manifest cleanup, quarantine lifecycle, the policy-as-code implementation using Azure Policy and OPA/Gatekeeper, and the WASM component versioning and deprecation standard.

# 1. Lifecycle Policy Framework
The lifecycle policy framework operates on three distinct mechanisms that together prevent unbounded storage growth while preserving artifacts required for operational, compliance, and customer needs:

| **Mechanism** | **ACR Feature** | **Implementation** | **Scope** |
| --- | --- | --- | --- |
| Untagged manifest cleanup | ACR retention policy (retentionPolicy) | Automatically purges untagged manifests after 30 days. Configured as registry-wide policy in IaC ([DOC-004 Section 6.1](../phase-2-platform/DOC-004_ACR_Service_Architecture.md)). | All namespaces — prevents dangling layer accumulation |
| Soft delete protection | ACR soft delete policy (softDeletePolicy) | 90-day recycle bin for deleted images. Accidental deletions recoverable within 90 days. | All namespaces — safety net for lifecycle operations |
| Programmatic lifecycle rules | ACR Tasks + az acr purge | Scheduled ACR Tasks execute az acr purge commands to enforce per-namespace retention rules beyond the simple untagged policy. | Per-namespace — granular control over tagged image retention |

# 2. Retention Policy by Namespace
| **Namespace** | **Tagged Image Retention** | **Untagged Manifest Cleanup** | **WASM Component Retention** | **Special Rules** |
| --- | --- | --- | --- | --- |
| products/{product}/ | Keep: all semver-tagged versions (1.x.y) — last 10 versions. Delete: commit-sha tags > 90 days, dev- tags > 30 days. | 30 days (registry default) | Keep: all semver versions for 12 months; last 5 versions indefinitely | Customer entitlement check: don't delete versions actively entitled to customers — query EMS before purge |
| test/{product}/ | Keep: nothing > 7 days. All test images ephemeral. | 7 days (override registry default via ACR Task) | N/A — no WASM in test namespace | No exceptions — test namespace is always ephemeral |
| base/ | Keep: all versions — no automatic deletion. Platform Engineering reviews annually. | 30 days | N/A — no WASM in base namespace | Base images are shared dependencies. Manual lifecycle management by Platform Engineering. |
| internal/ | Keep: last 5 tagged versions per image. | 30 days | N/A | Internal tools — no customer entitlement dependency |

# 3. Automated Lifecycle ACR Task
The following ACR Task definition implements the programmatic lifecycle policy for product namespaces. This task runs weekly and purges images that exceed the retention policy:

| **Task** | **Schedule** | **Command** | **Safety Check** |
| --- | --- | --- | --- |
| Purge commit-sha tags > 90 days | Weekly — Sunday 02:00 UTC | az acr purge --registry {registry} --filter 'products/.*:.*[0-9a-f]{40}' --ago 90d --untagged --keep 5 | Before purge: verify that no active entitlement in EMS references the affected image tags. If entitlement check unavailable, skip purge and alert. |
| Purge dev- prefixed tags > 30 days | Weekly — Sunday 02:00 UTC | az acr purge --registry {registry} --filter 'products/.*:dev-.*' --ago 30d | No entitlement check needed — dev tags are not distributed to customers. |
| Purge test namespace > 7 days | Daily — 03:00 UTC | az acr purge --registry {registry} --filter 'test/.*:.*' --ago 7d --untagged | No entitlement check — test images are internal only. |
| Purge internal namespace > 60 days (untagged) | Monthly | az acr purge --registry {registry} --filter 'internal/.*:.*' --ago 60d --untagged | Platform Engineering approval required for tagged image deletion. |


>** Entitlement-Aware Purge:**  Before purging any semantically versioned image from a customer-facing product namespace, the lifecycle task must query the EMS API to confirm no active customer entitlement references that image version. This prevents purging an image that a customer is actively entitled to pull. If the EMS API is unavailable, the purge is deferred — safety over efficiency.


# 4. WASM Component Versioning & Deprecation
| **Lifecycle Stage** | **Criteria** | **Action** | **Customer Communication** |
| --- | --- | --- | --- |
| Active | Current production release, actively supported | No action. Standard retention. | N/A |
| Maintenance | Previous major version, security patches only | Retain in registry indefinitely while customers are entitled. Flag as 'maintenance' in release notes. | Notify customers with this version: 'Version X.x is in maintenance mode. Upgrade recommended.' |
| Deprecated | End-of-life announced, > 6 months warning given | Continue to serve for entitled customers. Block new entitlements to deprecated version. | 6-month advance deprecation notice via email and release notes. |
| End of Life | No active customer entitlements remain | Remove from public registry. Archive via oras backup for 12 months. Delete from ACR. | Final notification to any remaining customers before deletion. |

# 5. Policy-as-Code Enforcement
| **Policy** | **Tool** | **Enforcement** | **Violation Action** |
| --- | --- | --- | --- |
| No image older than 90 days without semantic version tag | Azure Policy — custom definition | Audit mode: flags non-compliant images in compliance report | P3 notification to product team; exemption required for images > 90 days without semver tag |
| Test namespace images auto-expire within 7 days | ACR Task (daily) | Automatic deletion — no exceptions | None — test images always ephemeral |
| WASM components must have Cosign signature before retention beyond staging | OPA/Gatekeeper — registry webhook | Webhook validates signature presence before allowing image to graduate from test/ to products/ namespace | Block promotion; alert product team |
| No customer-entitled image may be deleted without EMS entitlement check | Custom ACR Task logic (see Section 3) | Pre-deletion EMS query | Skip deletion if EMS check fails; alert Platform Engineering |

# 6. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — retention policies, automated ACR tasks, WASM lifecycle, policy-as-code |
| 1.0 | TBD | Approved |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering, Legal (customer image retention obligations review).


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
