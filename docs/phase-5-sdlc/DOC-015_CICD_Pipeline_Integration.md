---
document_id: DOC-015
title: "CI/CD Pipeline Integration Architecture"
phase: "PH-5 — SDLC Integration"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-015: CI/CD Pipeline Integration Architecture

| Document ID | DOC-015 |
| --- | --- |
| Phase | PH-5 — SDLC Integration |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) (IAM), [DOC-010](../phase-3-entitlement/DOC-010_SDLC_RBAC_Design.md) (RBAC), [DOC-012](../phase-4-supply-chain/DOC-012_Image_Signing_Provenance.md) (Signing), [DOC-013](../phase-4-supply-chain/DOC-013_Vulnerability_Scanning_Policy_Gate.md) (Scanning) |
| Priority | P0 |

This document defines the integration architecture for CI/CD pipeline toolchains (Azure DevOps, GitHub Actions, Jenkins) with the Enterprise Container Registry. It covers the complete multi-stage pipeline reference architecture, Workload Identity Federation configuration, namespace-scoped push permissions, multi-stage scan/sign/promote flows, and tag lifecycle management policies.

# 1. Pipeline Architecture Principles
The CI/CD pipeline integration is designed around three non-negotiable properties:

| **Principle** | **Implementation** |
| --- | --- |
| No credentials in pipeline configuration | All authentication uses Workload Identity Federation (OIDC) or Azure Key Vault-backed references. No secrets committed to source control or stored in pipeline variables. |
| Security gates are non-bypassable | Vulnerability scan, image signing, and SBOM generation are pipeline stages that cannot be skipped. Pipeline logic enforces gates — not developer conventions. |
| Namespace isolation is automatic | The Managed Identity used by the pipeline is ABAC-scoped to only the product team's namespace. Even if a pipeline is compromised, it cannot affect other product namespaces. |

# 2. Reference Pipeline Architecture

## 2.1 Complete Multi-Stage Pipeline (GitHub Actions)
The following pipeline template represents the complete reference implementation for a product team's container image build and publish pipeline. All required security stages are included and enforced:


```
# .github/workflows/build-publish.yml — Complete Registry Pipeline name: Build, Scan, Sign & Publish on:
  push:
  branches: [main]
  pull_request:
  branches: [main] env:
  REGISTRY: '{registry}.azurecr.io'
  NAMESPACE: 'products/{product}'
  IMAGE_NAME: '{image}' jobs:   build-scan-sign-publish:

    runs-on: ubuntu-latest
  permissions:

    id-token: write
# WIF OIDC

  contents: read

    security-events: write
# SARIF upload
  outputs:

    image-digest: ${{ steps.push.outputs.digest }}

    image-ref: ${{ steps.push.outputs.ref }}
  steps:

- uses: actions/checkout@v4

# ── STAGE 1: BUILD ───────────────────────────────────────────────

- name: Set up Docker Buildx

  uses: docker/setup-buildx-action@v3

- name: Build image (no push yet)

  uses: docker/build-push-action@v6

  with:

  context: .

  push: false

  load: true

  tags: ${{ env.REGISTRY }}/${{ env.NAMESPACE }}/${{ env.IMAGE_NAME }}:${{ github.sha }}


    cache-from: type=gha


    cache-to: type=gha,mode=max

# ── STAGE 2: VULNERABILITY SCAN ──────────────────────────────────

- name: Trivy vulnerability scan (hard gate)

  uses: aquasecurity/trivy-action@master

  with:


    image-ref: ${{ env.REGISTRY }}/${{ env.NAMESPACE }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

  severity: 'CRITICAL,HIGH'


    exit-code: '1'


    ignore-unfixed: 'true'

# ── STAGE 3: AUTHENTICATE & PUSH ─────────────────────────────────

- name: Azure Login (WIF — no stored credentials)

  uses: azure/login@v2

  with:


    client-id: ${{ secrets.AZURE_CLIENT_ID }}


    tenant-id: ${{ secrets.AZURE_TENANT_ID }}


    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

- name: Login to ACR

  run:
az acr login --name ${{ env.REGISTRY }}

- name: Push image

  id: push

  uses: docker/build-push-action@v6

  with:

  push: true

  tags: ${{ env.REGISTRY }}/${{ env.NAMESPACE }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

# ── STAGE 4: SIGN ────────────────────────────────────────────────

- name: Sign image with Cosign (Key Vault)

  run: │

cosign sign --key azurekv://{vault}/kv-sign-ci-pipeline \
          ${{ env.REGISTRY }}/${{ env.NAMESPACE }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }}

# ── STAGE 5: SBOM ────────────────────────────────────────────────

- name: Generate & attach SBOM

  run: │

syft ${{ env.REGISTRY }}/${{ env.NAMESPACE }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }} \
          --output spdx-json=sbom.json

cosign attest --key azurekv://{vault}/kv-sign-ci-pipeline \
          --type spdxjson --predicate sbom.json \
          ${{ env.REGISTRY }}/${{ env.NAMESPACE }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }}

# ── STAGE 6: PROVENANCE ──────────────────────────────────────────
  provenance:
  needs: [build-scan-sign-publish]
  permissions: { actions: read, id-token: write, packages: write }
  uses: slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@v2.1.0
  with:

  image: '{registry}/{namespace}/{image}'

  digest: ${{ needs.build-scan-sign-publish.outputs.image-digest }}
```


## 2.2 Azure DevOps Pipeline Reference
The Azure DevOps equivalent pipeline uses YAML pipeline with a service connection bound to the product team's Managed Identity via Workload Identity Federation:


```
# azure-pipelines.yml — ADO reference pipeline trigger:
  branches:
  include: [main] pool:
  vmImage: ubuntu-latest variables:
  registry: '{registry}.azurecr.io'
  namespace: 'products/{product}'
  imageName: '{image}' stages:
- stage: BuildScanSignPublish
  jobs:
- job: Pipeline
  steps:

- task: Docker@2

  displayName: 'Build image'

  inputs:

  command: build

  repository: '$(namespace)/$(imageName)'

  tags: '$(Build.SourceVersion)'

- script: │

trivy image --severity CRITICAL,HIGH --exit-code 1 \
          $(registry)/$(namespace)/$(imageName):$(Build.SourceVersion)

  displayName: 'Trivy vulnerability scan (hard gate)'

# WIF authentication — service connection bound to Managed Identity

- task: AzureCLI@2

  displayName: 'Login to ACR (WIF)',

  inputs:

  azureSubscription: 'acr-push-{product}-service-connection'

  scriptType: bash

  scriptLocation: inlineScript

  inlineScript:
az acr login --name $(registry)

- task: Docker@2

  displayName: 'Push image'

  inputs:

  command: push

  repository: '$(namespace)/$(imageName)'

  tags: '$(Build.SourceVersion)'

- script: │

cosign sign --key azurekv://{vault}/kv-sign-ci-pipeline \
          $(registry)/$(namespace)/$(imageName)@$(DIGEST)

  displayName: 'Sign image (Cosign + Key Vault)'
```


## 2.3 Tag Lifecycle Management
Tags are managed by the CI/CD pipeline according to the following lifecycle policy. Pipeline logic enforces promotion gates before semantic version tags are applied:

| **Tag Applied By** | **Trigger** | **Namespace** | **Immutable?** | **Lifecycle** |
| --- | --- | --- | --- | --- |
| git-sha tag (e.g. abc1234) | Every merge to main | products/{product}/ | Yes — immutable | Retained 90 days then cleaned by lifecycle policy |
| dev-{branch}-{sha} | PR builds | test/{product}/ | No | Retained 7 days; auto-deleted by retention policy |
| Semantic version (1.2.3) | Manual promotion pipeline trigger after QA sign-off | products/{product}/ | Yes — tag immutability enforced | Retained per [DOC-022](../phase-7-governance/DOC-022_Artifact_Lifecycle_Policy.md) lifecycle policy |
| Environment tag (staging, canary) | Automated promotion pipeline | products/{product}/ | No — mutable pointer | Updated on each promotion; used only for internal routing |

# 3. Pipeline Security Requirements Checklist
Every product team pipeline must satisfy the following security requirements before it is approved for production use. The Platform Engineering team validates compliance during the product namespace onboarding review:

| **Requirement** | **Validation Method** | **Blocking?** |
| --- | --- | --- |
| WIF used for ACR authentication (no static credentials) | Review pipeline YAML for azure/login task with client-id/tenant-id — no stored secrets | Yes |
| Trivy scan stage present and configured with exit-code: 1 for CRITICAL/HIGH | Pipeline YAML review; test by introducing a known vulnerable image | Yes |
| Cosign signing stage present after push | Pipeline YAML review; verify signature exists in ACR after test run | Yes |
| SBOM generation stage present (syft + cosign attest) | Pipeline YAML review; verify SBOM referrer exists in ACR after test run | Yes |
| Pipeline does not push to base/ or other product namespaces | Run namespace isolation test suite ([DOC-010 Section 3.2](../phase-3-entitlement/DOC-010_SDLC_RBAC_Design.md)) | Yes |
| No credentials in pipeline variables or source control | GitHub secret scanning enabled; ADO variable review | Yes |
| SLSA provenance generation (GitHub SLSA generator or ADO equivalent) | Verify provenance attestation in ACR after test run | No — advisory at launch; blocking from Q3 2026 |

# 4. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — reference pipelines, tag lifecycle, security requirements checklist |
| 1.0 | TBD | Approved |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering. Pipeline templates must be reviewed by at least one senior engineer from each active CI/CD platform (ADO, GitHub, Jenkins).


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
