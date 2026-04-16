---
document_id: DOC-016
title: "GitOps & Deployment Integration Architecture"
phase: "PH-5 — SDLC Integration"
priority: P1
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-016: GitOps & Deployment Integration Architecture

| Document ID | DOC-016 |
| --- | --- |
| Phase | PH-5 — SDLC Integration |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | [DOC-011](../phase-3-entitlement/DOC-011_Customer_Entitlement_Access_Flow.md) (Customer Access Flow), [DOC-015](DOC-015_CICD_Pipeline_Integration.md) (CI/CD Pipeline) |
| Priority | P1 |

This document defines the GitOps integration architecture for both internal SDLC environments and customer Kubernetes deployments. It covers ArgoCD and Flux CD integration patterns, image pull secret injection via External Secrets Operator, image update automation policies, WASM component deployment via Cosmonic Control with ArgoCD, and the wadm manifest GitOps pattern.

# 1. GitOps Architecture Overview
GitOps is the operational model where the desired state of deployed applications is declared in Git, and a continuous reconciliation controller (ArgoCD or Flux CD) ensures the live environment matches the declared state. For the Container Registry, GitOps integration has two distinct tracks:

| **Track** | **Owner** | **Registry Interaction** | **GitOps Tool** |
| --- | --- | --- | --- |
| Track A — Internal SDLC | Platform Engineering + Product teams | Pull images from ACR for staging and pre-production deployments. ArgoCD Image Updater triggers on new image tags in ACR. | ArgoCD with Image Updater; Flux CD with Image Automation |
| Track B — Customer Deployment | Customer IT / DevOps teams | Pull entitled images from ACR using Token Broker credentials. External Secrets Operator manages credential rotation. | Customer's choice of ArgoCD, Flux CD, or Helm; company provides integration guidance |

# 2. ArgoCD Integration (Track A — Internal SDLC)

## 2.1 ArgoCD Application Repository Pattern
The platform uses the GitOps monorepo pattern with separate application and configuration repositories:

- Application repository: source code, Dockerfiles, Helm charts. CI/CD pipeline builds and pushes images to ACR.

- Config repository: Kubernetes manifests, Helm values files, Kustomize overlays. ArgoCD watches this repository for changes.

- Image tag promotion: when a new image is available in ACR, the CI/CD pipeline or ArgoCD Image Updater updates the image tag reference in the config repository, triggering ArgoCD reconciliation.


## 2.2 ACR-to-ArgoCD Image Updater Integration
ArgoCD Image Updater polls ACR for new image tags and automatically updates Helm values or Kustomize image references in the config repository:


```yaml
# ArgoCD Application with Image Updater annotations

apiVersion: argoproj.io/v1alpha1

kind: Application

metadata:
  name: widget-api-staging
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/image-list: │
      widget-api={registry}.azurecr.io/products/widget/api
    argocd-image-updater.argoproj.io/widget-api.update-strategy: semver
    argocd-image-updater.argoproj.io/widget-api.allow-tags: 'regexp:^[0-9]+\.[0-9]+\.[0-9]+$'
    argocd-image-updater.argoproj.io/write-back-method: git

spec:
  project: default
  source:
  repoURL: https://git.{company}.com/platform/widget-config
  targetRevision: main
  path: staging/widget-api
  destination:
  server: https://kubernetes.default.svc
  namespace: widget-staging
```


## 2.3 ACR Webhook to ArgoCD
ACR webhooks trigger ArgoCD sync on new image push, providing near-real-time deployment updates rather than waiting for the Image Updater poll interval:

- ACR webhook configured on production namespace (products/{product}/*) to fire on imageTagged event

- Webhook target: ArgoCD API server /api/v1/applications/{app-name}/sync

- Webhook authentication: ArgoCD API token stored in Azure Key Vault, referenced by ACR webhook configuration

- Limitation: ACR webhooks are not scoped per-repository; entire registry fires one webhook. Filtering logic in the webhook receiver routes events to the correct ArgoCD application.

# 3. External Secrets Operator (ESO) Integration
External Secrets Operator is the recommended mechanism for managing imagePullSecret lifecycle in customer Kubernetes clusters. ESO syncs ACR refresh tokens from Azure Key Vault to Kubernetes Secrets, automatically rotating them before expiry:


```yaml
# ClusterSecretStore — Azure Key Vault provider (customer cluster)

apiVersion: external-secrets.io/v1beta1

kind: ClusterSecretStore

metadata:
  name: azure-keyvault-store

spec:
  provider:
  azurekv:

  tenantId: '{customer-entra-tenant-id}'

  vaultUrl: 'https://{customer-keyvault}.vault.azure.net'

  authType: WorkloadIdentity

  serviceAccountRef:

  name: external-secrets-sa

  namespace: external-secrets ---
# ExternalSecret — syncs Token Broker token to imagePullSecret

apiVersion: external-secrets.io/v1beta1

kind: ExternalSecret

metadata:
  name: acr-pull-credentials
  namespace: production

spec:
  refreshInterval: '1h'
  secretStoreRef:
  name: azure-keyvault-store

kind: ClusterSecretStore
  target:
  name: acr-imagepullsecret
  template:

  type: kubernetes.io/dockerconfigjson

  engineVersion: v2

  data:
        .dockerconfigjson: │
          {"auths":{"{registry}.azurecr.io":{"username":"00000000-0000-0000-0000-000000000000","password":"{{ .acrToken }}"}}}
  data:

- secretKey: acrToken

  remoteRef:

  key: acr-entitlement-token
```


## 3.1 Token Renewal CronJob
A CronJob in each customer cluster refreshes the ACR token in Azure Key Vault every 12 hours (before the 24h TTL expires), enabling the ESO to always sync a valid token:


```yaml
# CronJob — refreshes Token Broker credential in Key Vault every 12h

apiVersion: batch/v1

kind: CronJob

metadata:
  name: acr-token-refresh
  namespace: external-secrets

spec:
  schedule: '0 */12 * * *'
  jobTemplate:

spec:

  template:


spec:

  serviceAccountName: token-renewal-sa
# WIF-enabled SA

  containers:

- name: token-refresher

  image: mcr.microsoft.com/azure-cli:latest

  command:

- /bin/bash
            - -c

- │

# Get Entra ID token via WIF
              ENTRA_TOKEN=$(az account get-access-token --resource {token-broker-app-id} --query accessToken -o tsv)

# Call Token Broker
              ACR_TOKEN=$(curl -s -X POST https://token-broker.{company}.com/v1/token \
                -H "Authorization: Bearer $ENTRA_TOKEN" \
                -d '{"registry":"{registry}.azurecr.io"}' │ jq -r '.acr_refresh_token')

# Store in Key Vault

az keyvault secret set --vault-name {keyvault} --name acr-entitlement-token --value "$ACR_TOKEN"

  restartPolicy: OnFailure
```


# 4. WASM Component GitOps (Cosmonic Control + ArgoCD)
Cosmonic Control integrates natively with ArgoCD and Flux CD for declarative WASM component management. The integration follows the same Git-as-source-of-truth pattern as container workloads:


```yaml
# wadm-manifest.yaml — wasmCloud application manifest in Git
# Managed by ArgoCD as a standard Kubernetes
resource

apiVersion: core.oam.dev/v1beta1

kind: Application

metadata:
  name: widget-processor
  annotations:
  version: v0.5.1

spec:
  components:

- name: processor

  type: component

  properties:

  image: '{registry}.azurecr.io/products/widget/wasm/processor:0.5.1'

  traits:

- type: spreadscaler

  properties:

  instances: 3

- name: http-server

  type: capability

  properties:

  image: 'ghcr.io/wasmcloud/http-server:0.23.1' ---
# ArgoCD Application pointing to the wadm manifest

apiVersion: argoproj.io/v1alpha1

kind: Application

metadata:
  name: widget-wasm-workloads
  namespace: argocd

spec:
  project: default
  source:
  repoURL: https://git.{company}.com/customer/widget-wasm-config
  path: production/wadm
  destination:
  server: https://kubernetes.default.svc
  namespace: cosmonic-system
  syncPolicy:
  automated:

  prune: true

  selfHeal: true
```


# 5. Image Update Automation Policy
| **Environment** | **Update Strategy** | **ArgoCD Image Updater Policy** | **Promotion Gate Required** |
| --- | --- | --- | --- |
| Development | Automatic — pull latest on every commit-sha push | update-strategy: latest — any new tag | None — automatic |
| Staging | Automatic — semver patch updates only | update-strategy: semver, allow-tags: '^[0-9]+\.[0-9]+\.[0-9]+$' — pins to latest patch for current minor | CI/CD green build only |
| Pre-production | Manual promotion — explicit version pin | No Image Updater — manual Helm values update | QA sign-off + product team approval |
| Production | Manual promotion — pinned by digest | No Image Updater — pinned by sha256 digest in Helm values | CISO + product team approval; change management ticket |

# 6. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — ArgoCD/Flux integration, ESO credential rotation, WASM GitOps, image automation policy |
| 1.0 | TBD | Approved |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering, VP Customer Success (customer GitOps guidance review).


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
