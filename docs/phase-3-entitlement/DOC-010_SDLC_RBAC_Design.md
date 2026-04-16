---
document_id: DOC-010
title: "SDLC Fine-Grained RBAC Design"
phase: "PH-3 — Entitlement & Access Control"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-010: SDLC Fine-Grained RBAC Design

| Document ID | DOC-010 |
| --- | --- |
| Phase | PH-3 — Entitlement & Access Control |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) (IAM Architecture), [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md) (ACR Service Architecture) |
| Priority | P0 |

This document defines the complete Role-Based Access Control design for the SDLC toolchain. It specifies the role taxonomy, ABAC condition expressions, pipeline identity bindings, self-service onboarding flow, and GitOps policy definitions that enforce product team namespace isolation. The central guarantee: no product team can affect another team's repositories, and no CI/CD pipeline can access namespaces outside its assigned scope.

# 1. SDLC RBAC Design Principles
The SDLC RBAC model is built on four principles that govern all role assignment decisions:

| **Principle** | **Implementation** |
| --- | --- |
| Namespace-sovereign product teams | Each product team has exclusive write access to their assigned namespace prefix. No identity outside the team (or Platform Engineering) can push to, delete from, or manage that namespace. |
| No standing push access for humans | Developers do not have push access to production namespaces. All production image pushes originate from CI/CD pipelines with Workload Identity Federation. Developer access is pull-only. |
| Least-privilege by default | New product team identities receive the minimum scope needed: push to own namespace, pull base images. Additional permissions require explicit justification and IaC PR. |
| Policy-as-code enforcement | All RBAC role assignments are defined in the platform IaC repository. Manual portal-based assignments are detected by Azure Policy and flagged. No role assignment exists outside of Git. |

# 2. RBAC Role Taxonomy

## 2.1 SDLC Roles Matrix
| **Role** | **Identity Type** | **Namespace Scope** | **Push** | **Pull** | **Delete** | **Tag Manage** | **Catalog List** |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Product CI/CD Push | Managed Identity (WIF) | products/{product}/* | Yes | Yes | No | Yes | No |
| Product CI/CD Full | Managed Identity (WIF — promotion pipelines) | products/{product}/* | Yes | Yes | Yes (own ns) | Yes | No |
| Product Developer Read | Entra ID user (interactive) | products/{product}/* | No | Yes | No | No | No |
| Base Image Manager | Managed Identity (Platform Eng) | base/* | Yes | Yes | Yes | Yes | No |
| Platform Admin | PIM-activated Entra ID | All namespaces | Yes | Yes | Yes | Yes | Yes |
| Security Scanner | Managed Identity (scanner) | All namespaces (read-only) | No | Yes | No | No | Yes |
| GitOps Controller | Managed Identity / imagePullSecret | products/{product}/* or internal/* | No | Yes | No | No | No |


## 2.2 ABAC Condition Expressions
The following ABAC condition expressions are used in role assignments. The format follows Azure ABAC condition syntax for ACR ABAC-enabled registries:


```
// Product CI/CD Push — namespace-scoped write @Resource[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWith 'products/widget/' // Base Image Manager — base namespace only @Resource[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWith 'base/' // Product Developer Read — single namespace read @Resource[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWith 'products/widget/' // Multi-namespace read (for teams managing multiple related products): @Resource[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWith 'products/widget/' OR StringStartsWith 'products/gadget/' // Test namespace — scoped to ephemeral test builds @Resource[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWith 'test/widget/'
```


# 3. Product Team Onboarding Process

## 3.1 Self-Service Onboarding Flow
Product teams onboard new registry namespaces via a self-service IaC PR template. The Platform Engineering team reviews and merges — no manual provisioning is required:

| **1** | **Product Team Lead** | Submits IaC PR using the platform template: 'New Product Namespace Request'. PR includes: product_id, product_name, team_entra_group_id, ci_cd_platform (ADO/GitHub/Jenkins), namespace_prefix. |
| --- | --- | --- |

| **2** | **IaC PR Template** | Automated PR validation: checks namespace_prefix is unique; validates product_id format; confirms team_entra_group_id exists in Entra ID; generates all required Bicep resources. |
| --- | --- | --- |

| **3** | **Platform Engineering** | Reviews and approves PR. Merge triggers platform IaC pipeline. |
| --- | --- | --- |

| **4** | **IaC Pipeline** | Creates: user-assigned Managed Identity (mi-acr-push-{product}-prod); WIF federated credential for CI/CD platform; ABAC role assignment (Repository Writer scoped to products/{product}/*); developer read role for team Entra group. |
| --- | --- | --- |

| **5** | **IaC Pipeline** | Runs namespace isolation test: attempts push to peer namespace using new MI — must return 403. Fails pipeline if test fails. |
| --- | --- | --- |

| **6** | **Notification** | Product team lead notified: MI client ID, namespace prefix, CI/CD configuration instructions. |
| --- | --- | --- |


## 3.2 Namespace Isolation Validation Test
Every new namespace provisioning must pass an automated isolation test as a deployment gate. The test verifies:

- Test 1 — Own namespace write: push test image to products/{product}/test-isolation:test → must succeed (201)

- Test 2 — Peer namespace write: push test image to products/another-team/test-isolation:test → must return 403 Forbidden

- Test 3 — Base namespace write: push to base/test-isolation:test → must return 403 Forbidden

- Test 4 — Own namespace read: pull test image pushed in Test 1 → must succeed

- Test 5 — Peer namespace read: attempt pull from products/another-team/ → must return 403 Forbidden (no read access to peer namespace for CI/CD identity)

# 4. CI/CD Pipeline RBAC Bindings
The following table defines the complete mapping between CI/CD platform identities and their ABAC-scoped ACR roles. This is the source-of-truth binding table maintained in the platform IaC repository:

| **CI/CD Platform** | **Identity Pattern** | **Auth Method** | **ABAC Condition** | **Notes** |
| --- | --- | --- | --- | --- |
| Azure DevOps | mi-acr-push-{product}-prod — federated to ADO service connection | Workload Identity Federation (OIDC) | repositories:name StringStartsWith 'products/{product}/' | Federated credential subject: sc://{org}/{project}/{connection-name} |
| GitHub Actions | mi-acr-push-{product}-prod — federated to GitHub OIDC | Workload Identity Federation (OIDC) | repositories:name StringStartsWith 'products/{product}/' | Federated credential subject: repo:{org}/{repo}:environment:production |
| Jenkins | sp-acr-push-{product} — Service Principal, secret in Key Vault | Service Principal + Key Vault secret | repositories:name StringStartsWith 'products/{product}/' | WIF migration roadmap Q4 2026. Secret rotation: 90 days auto-rotate. |
| ArgoCD / Flux (SDLC) | mi-acr-gitops-{product}-prod — AKS workload identity or imagePullSecret | Managed Identity (AKS attachment) | repositories:name StringStartsWith 'products/{product}/' | Pull-only (Repository Reader role). No write access. |


## 4.1 Pipeline Push Security Requirements
All CI/CD pipelines pushing to the registry must meet the following security requirements:

- No stored credentials in pipeline configuration, environment variables, or source control — all authentication via WIF or Key Vault-referenced secrets

- Image signing is mandatory for all production pushes — pipeline must invoke cosign sign before the push is considered complete

- Vulnerability scan must be passed before promotion to production tags — scan gate enforced by pipeline logic, not registry policy alone

- SBOM generation is mandatory for all production pushes — cosign attest with syft-generated SBOM attached to image digest

- All pushes to production namespaces must include SLSA provenance attestation — wash slsa-generator or GitHub Actions SLSA generator

# 5. GitOps Policy Definitions
The following OPA/Gatekeeper policies enforce the RBAC design at the infrastructure level. These policies run as Azure Policy and within customer Kubernetes clusters as admission webhooks:


```rego
# OPA/Rego policy: enforce namespace isolation for ACR pushes
# Policy: deny any RBAC assignment granting push access to a namespace
# prefix not matching the assigned product namespace for that identity package acr.rbac.namespace_isolation import future.keywords.if deny[msg] {   assignment := input.roleAssignment   assignment.properties.roleDefinitionId == repository_writer_role_id   condition := assignment.properties.condition
# Extract namespace from ABAC condition   namespace := extract_namespace(condition)
# Look up authorized namespace for this principal   authorized_namespace := data.authorized_namespaces[assignment.properties.principalId]
# Deny if assigned namespace differs from authorized namespace   namespace != authorized_namespace   msg := sprintf('Principal %v is not authorized to push to namespace %v', [assignment.properties.principalId, namespace]) }
# CI/CD admission policy: deny images from non-signed sources deny_unsigned_images[msg] {   pod := input.request.object   container := pod.spec.containers[_]   not has_valid_cosign_signature(container.image)   msg := sprintf('Container image %v has no valid Cosign signature', [container.image]) }
```


# 6. RBAC Audit & Compliance

## 6.1 Quarterly RBAC Audit Process
- Azure Resource Graph query: list all role assignments on ACR resource → export to CSV → cross-reference against IaC repository assignments → identify any divergences (potential unauthorized grants)

- Policy compliance report: Azure Policy 'Deny AcrPush/AcrPull legacy roles' compliance report → must show 100% compliant

- Namespace isolation test suite: run automated isolation tests against all production product namespaces → all tests must pass

- Developer access review: Entra ID access review for all users with ACR Repository Reader role → confirm still employed and on correct product team


## 6.2 Exception Process
Any deviation from the RBAC model (e.g., a product team requiring temporary cross-namespace read for a migration) requires:

- Written justification with business case and risk assessment

- Time-bounded exception: maximum 30 days, documented expiry date

- CISO sign-off for exceptions involving write access to non-owned namespaces

- IaC implementation with expiry date enforcement (Azure Policy scheduled remediation to remove expired exception)

- Mandatory audit log review at exception expiry

# 7. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — RBAC taxonomy, ABAC conditions, onboarding flow, CI/CD bindings, GitOps policies, audit process |
| 1.0 | TBD | Approved — pending Architecture Review Board sign-off |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering, CISO (namespace isolation validation). Product Engineering representatives should review namespace onboarding process for operational feasibility.


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
