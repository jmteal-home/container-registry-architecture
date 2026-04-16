---
document_id: DOC-017
title: "Inner Loop Developer Experience Design"
phase: "PH-5 — SDLC Integration"
priority: P1
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-017: Inner Loop Developer Experience Design

| Document ID | DOC-017 |
| --- | --- |
| Phase | PH-5 — SDLC Integration |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | [DOC-015](DOC-015_CICD_Pipeline_Integration.md) (CI/CD Pipeline Integration) |
| Priority | P1 |

This document defines the inner-loop developer experience for engineers building containerized and WASM products. It covers local registry mirror configuration, authenticated pull for local Docker/k3s/Rancher Desktop, VS Code extension recommendations, CLI tooling reference design for the platform, and the self-service namespace provisioning workflow for new product teams.

# 1. Developer Experience Principles
The inner loop (local development cycle) must not be a security liability while also not being an operational burden. The following principles govern developer experience design:

| **Principle** | **Implementation** |
| --- | --- |
| Frictionless local pull | Developers can pull their product's entitled images to their local workstation with a single az acr login command. No separate credential management. |
| No push from workstations | Developers cannot push to production namespaces from their local machine. Local builds stay local or go to dev/test namespaces only through the pipeline. |
| Local mirrors for performance | Local registry mirrors (via containerd mirror or Docker registry:pull-through configuration) cache frequently-used base images, reducing bandwidth and latency on the developer inner loop. |
| WASM developer toolchain is first-class | wash CLI and related WASM tooling are documented and supported with the same level of guidance as Docker CLI tooling. |

# 2. Developer Workstation Authentication

## 2.1 Interactive az acr login
The primary developer authentication mechanism uses the Azure CLI's interactive browser authentication flow, which is bound to the developer's Entra ID identity. No credentials are stored permanently — the 3-hour session token is managed by the Azure CLI credential cache:


```
# Developer authentication — single command
# Launches browser → Entra ID login → ABAC-scoped ACR token cached by Docker
az acr login --name {registry}
# Pull your product's images (ABAC restricts to your product namespace)
docker pull {registry}.azurecr.io/products/widget/api:1.2.3
# Token expires after 3 hours — re-run
az acr login to refresh
# Or: use the Azure CLI credential helper (docker-credential-acr) for auto-refresh
az acr credential-helper enable --registry {registry}
# After enabling the credential helper,
docker pull auto-refreshes tokens
# without requiring manual re-login
```


## 2.2 Rancher Desktop / Podman / OrbStack
Alternative container runtimes on developer workstations use the same az acr login flow. The Azure CLI credential helper integrates with most OCI-compatible runtimes via the Docker credential store API:

- Rancher Desktop (containerd): use nerdctl login --username 00000000-... --password $(az acr login --expose-token --query accessToken -o tsv) {registry}

- Podman: podman login --username 00000000-... --password $(az acr login --expose-token --query accessToken -o tsv) {registry}

- OrbStack: uses Docker CLI under the hood — standard az acr login works directly

# 3. Local Registry Mirror

## 3.1 Pull-Through Cache for Base Images
A local registry mirror for base images significantly reduces developer inner-loop iteration time. The pull-through cache stores base images locally after the first pull:


```
# Docker daemon.json — configure pull-through cache for base images
# Add to ~/.docker/daemon.json or /etc/docker/daemon.json {   'registry-mirrors': [
    'https://mirror.gcr.io',
        // Google Container Registry mirror (mcr images)
    'http://localhost:5000'
          // Local pull-through cache (see below)   ] }
# Run local registry mirror with pull-through cache
# docker-compose.yml for local dev registry version: '3' services:   registry-mirror:
  image: registry:2
  ports: ['5000:5000']
  environment:

  REGISTRY_PROXY_REMOTEURL: 'https://{registry}.azurecr.io'

  REGISTRY_PROXY_USERNAME: '00000000-0000-0000-0000-000000000000'

  REGISTRY_PROXY_PASSWORD: '${ACR_TOKEN}'
# Token from
az acr login
  volumes:

- ./registry-data:/var/lib/registry
```


## 3.2 k3s Local Development (Rancher Desktop / k3d)
```
# k3s registries.yaml — local development k3s mirror config
# Place at: ~/.k3s/registries.yaml (Rancher Desktop) or /etc/rancher/k3s/registries.yaml mirrors:   '{registry}.azurecr.io':
  endpoint:

- 'http://localhost:5000'

# Local pull-through cache

- 'https://{registry}.azurecr.io'
# Direct fallback configs:   '{registry}.azurecr.io':
  auth:

  username: '00000000-0000-0000-0000-000000000000'

  password: ''
# Populated by:
echo $(az acr login --expose-token -o tsv) > /tmp/acr-token

# And update this field; or use
az acr credential-helper
```


# 4. Developer Tooling Reference

## 4.1 Required CLI Tools
| **Tool** | **Version** | **Installation** | **Purpose** |
| --- | --- | --- | --- |
| Azure CLI (az) | Latest | winget install Microsoft.AzureCLI / brew install azure-cli | ACR authentication, resource management |
| Docker CLI | Latest | docker.com/get-started | Container builds and local testing |
| crane | Latest | go install github.com/google/go-containerregistry/cmd/crane@latest | Fast image inspection, tag listing, manifest inspection — faster than docker pull for metadata |
| cosign | v2.x | brew install cosign / scoop install cosign | Verify image signatures; inspect attestations |
| oras | v1.3+ | brew install oras / scoop install oras | OCI artifact operations; SBOM discovery; WASM component push/pull |
| wash (wasmCloud) | Latest | curl https://packagecloud.io/AtomicJar/wasmcloud/... / brew install wasmcloud/tap/wash | WASM component build, push, pull, local development loop |
| trivy | Latest | brew install trivy / scoop install trivy | Local vulnerability scanning before pushing to registry |
| notation | Latest | brew install notation | Verify Notation (Notary v2) signatures locally |


## 4.2 VS Code Extensions
| **Extension** | **Publisher** | **Purpose** |
| --- | --- | --- |
| Docker | Microsoft | Container image build, push, pull, local registry browsing directly from VS Code |
| Azure Container Registry | Microsoft | Browse ACR repositories, tags, and manifests from VS Code. Requires az login. |
| HashiCorp Terraform / Bicep | Microsoft / HashiCorp | IaC authoring for registry configuration changes |
| wasmCloud wasm-tools | wasmCloud community | WIT interface syntax highlighting and validation for WASM component development |
| YAML | Red Hat | Kubernetes manifest editing with schema validation for wadm manifests and ArgoCD Applications |


## 4.3 Developer Platform CLI Reference
The platform provides a convenience CLI wrapper (platform-cli or pcli) that abstracts common registry operations into developer-friendly commands:


```
# platform-cli — convenience wrapper for registry operations
# Install:
curl https://tools.{company}.com/install.sh │ bash
# Login (wraps
az acr login) pcli registry login
# List your entitled product images pcli registry list products/{product}/
# Pull an image with automatic credential refresh pcli registry pull products/{product}/{image}:1.2.3
# Verify image signature pcli registry verify products/{product}/{image}@sha256:{digest}
# Show SBOM for an image pcli registry sbom products/{product}/{image}:1.2.3
# Scan image locally pcli registry scan products/{product}/{image}:1.2.3
# WASM: push component to test namespace pcli wasm push ./my-component.wasm test/{product}/wasm/{name}:dev
```


# 5. Self-Service Namespace Provisioning

## 5.1 New Product Team Onboarding
Product teams provision their registry namespace by submitting an IaC PR using the platform's namespace request template. The Platform Engineering team reviews and merges within 2 business days:

| **Step** | **Action** | **Tool** | **SLO** |
| --- | --- | --- | --- |
| 1. Request form | Product team lead fills out namespace-request.yaml in the platform-config Git repository using the provided template: product_id, team_entra_group, cicd_platform, namespace_prefix | Git PR (GitHub/ADO) | PR created immediately |
| 2. Automated validation | PR CI validates: namespace_prefix uniqueness; product_id format compliance; team_entra_group exists in Entra ID; no conflicting namespaces | GitHub Actions / ADO pipeline | Automated check within 5 minutes |
| 3. Platform review | Platform Engineering team reviews PR for security and naming convention compliance | Manual review | Within 2 business days |
| 4. Automated provisioning | On merge, IaC pipeline creates: Managed Identity, WIF federated credential, ABAC role assignment, developer read access, test namespace, namespace isolation test validation | Bicep / Terraform pipeline | Within 30 minutes of merge |
| 5. Notification | Product team receives: MI client ID, ABAC namespace prefix, CI/CD configuration guide link, test namespace details | Email notification from IaC pipeline | Automated on provisioning complete |


## 5.2 Namespace Naming Standards
| **Component** | **Pattern** | **Examples** | **Constraints** |
| --- | --- | --- | --- |
| Product namespace | products/{product-id}/ | products/widget/, products/analytics-platform/ | product-id: lowercase alphanumeric + hyphen; 3-30 chars; unique across all products |
| Test namespace | test/{product-id}/ | test/widget/ | Auto-created with product namespace; 7-day retention for untagged images |
| WASM sub-namespace | products/{product-id}/wasm/ | products/widget/wasm/ | Auto-created with product namespace; same ABAC scope as parent namespace |
| Helm sub-namespace | products/{product-id}/charts/ | products/widget/charts/ | Auto-created with product namespace |

# 6. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — developer auth, local mirrors, tooling reference, platform CLI, self-service onboarding |
| 1.0 | TBD | Approved |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering. Developer experience design should be validated with at least 3 product engineering team leads before finalizing platform CLI and onboarding workflow.


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
