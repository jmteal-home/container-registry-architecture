---
document_id: DOC-012
title: "Image Signing & Provenance Architecture"
phase: "PH-4 — Supply Chain Security"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-012: Image Signing & Provenance Architecture

| Document ID | DOC-012 |
| --- | --- |
| Phase | PH-4 — Supply Chain Security |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md) (ACR Service Architecture), [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) (IAM Architecture) |
| Priority | P0 |

This document defines the image signing and supply chain provenance architecture for the Enterprise Container Registry. It specifies the Cosign + Notary v2 dual-toolchain approach, the Azure Key Vault key hierarchy for signing, the SLSA provenance attestation pipeline, and admission controller enforcement in customer Kubernetes clusters. The goal: every container image and WASM component artifact that reaches a customer environment has a verifiable, tamper-evident chain of custody from source commit to deployed workload.

# 1. Supply Chain Signing Architecture Overview
The signing architecture addresses three distinct trust guarantees that together constitute a complete supply chain security posture:

| **Trust Guarantee** | **Toolchain** | **What It Proves** |
| --- | --- | --- |
| Artifact Integrity | Cosign (image signing) + OCI Referrers API | The image or WASM component has not been modified since it was signed by the CI/CD pipeline. Any tampering invalidates the signature. |
| Build Provenance | SLSA Provenance Generator (GitHub Actions / ADO task) + Cosign attest | The artifact was built from a specific source commit, in a specific build environment, by a specific pipeline identity — providing a verifiable audit trail from code to image. |
| Policy Compliance | Notary v2 (Notation CLI) + Azure Key Vault | The artifact meets organisational security policy requirements at time of promotion. Notation provides policy-based signing suitable for enterprise trust store integration. |


>** Toolchain Strategy:**  Both Cosign and Notary v2 (Notation) are maintained — not as redundancy, but for distinct use cases. Cosign is the primary CI/CD signing tool with OCI referrer integration and OIDC keyless support for developer convenience. Notation provides the enterprise policy-layer signing that integrates with corporate trust stores and is the forward-looking CNCF standard for supply chain policy enforcement. The two toolchains are complementary, not competing.


# 2. Signing Key Hierarchy

## 2.1 Key Management Architecture
All signing keys are stored in Azure Key Vault. No private key material ever exists outside Key Vault — all signing operations use the Key Vault Cryptography API. The key hierarchy is organized by purpose and scope:

| **Key Name** | **Type** | **Algorithm** | **Purpose** | **Rotation** | **Key Vault** |
| --- | --- | --- | --- | --- | --- |
| kv-sign-platform-root | Asymmetric | RSA-4096 | Root signing key for the platform. Signs intermediate keys. Offline — rarely used. Only activated for key rotation events. | 3 years | kv-registry-cmk (highly restricted) |
| kv-sign-ci-pipeline | Asymmetric | EC-384 (ECDSA P-384) | Primary CI/CD pipeline signing key. Used by Cosign for all production image and WASM component signatures. | 1 year (automated rotation policy) | kv-registry-signing (Token Broker MI + Platform IaC MI access) |
| kv-sign-notation | Asymmetric | RSA-3072 | Notation (Notary v2) signing key for policy-layer enterprise signing. Integrated with Azure Key Vault Notation plugin. | 1 year | kv-registry-signing |
| kv-sign-token-broker | Asymmetric | RSA-2048 | Token Broker token signing key ([DOC-009 Section 6.2](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md)). Separate from image signing — different purpose and access. | 1 year (automated) | kv-registry-signing |


## 2.2 Key Access Control
| **Key** | **Identities with Sign Permission** | **Identities with Verify Permission** | **Restricted To** |
| --- | --- | --- | --- |
| kv-sign-ci-pipeline | mi-acr-push-{product}-prod (Managed Identity for each product team CI/CD) | All — public key published via JWKS endpoint | CI/CD pipeline only. PIM activation required for human key access. |
| kv-sign-notation | mi-platform-iac (for key rotation only); Notation plugin service identity | All — certificate distributed to customer trust stores | Notation CLI invoked from CI/CD pipeline gate stage. |
| kv-sign-platform-root | Platform Engineering Lead only (PIM — 2 persons max) | N/A — verification uses leaf key certificate | Used only during key rotation ceremony. PIM + dual approval. |

# 3. Cosign Integration

## 3.1 Cosign Signing Pipeline
Cosign signs every production image and WASM component artifact at the post-build, post-push stage of the CI/CD pipeline. Signing is not optional — the promotion pipeline gate will not advance an unsigned artifact.


```
# CI/CD Pipeline — Cosign signing stage (GitHub Actions)
# Executes after:
docker build → vulnerability scan (pass) →
docker push
- name: Sign image with Cosign (Key Vault key)
  env:
  COSIGN_KEY: 'azurekv://{vault-name}/kv-sign-ci-pipeline'
  IMAGE_REF: '${{ env.REGISTRY }}/${{ env.NAMESPACE }}/${{ env.IMAGE }}:${{ github.sha }}'
  run: │

# Get the image digest (sign by digest, not tag — tags are mutable)
    DIGEST=$(crane digest $IMAGE_REF)

# Sign the digest

cosign sign \
      --key $COSIGN_KEY \
      --tlog-upload=true \
      --annotations='build-pipeline=${{ github.workflow }}' \
      --annotations='git-commit=${{ github.sha }}' \
      --annotations='build-timestamp=${{ steps.build-time.outputs.timestamp }}' \
      ${{ env.REGISTRY }}/${{ env.NAMESPACE }}/${{ env.IMAGE }}@$DIGEST
# The signature is stored as an OCI referrer in ACR, linked to the image digest.
# Verification:
cosign verify --key $COSIGN_PUB_KEY $IMAGE_REF
```


## 3.2 Cosign Signature Storage in ACR
Cosign stores signatures as OCI referrers linked to the signed artifact by digest. ACR Premium supports the OCI Referrers API (_oci/1.1/referrers/{digest}), enabling Cosign, admission controllers, and audit tools to discover and verify signatures without any out-of-band storage:

- Signature artifact type: application/vnd.dev.cosign.artifact.sig.v1+json

- Signature stored at: {registry}/{namespace}/{image}:sha256-{digest}.sig (OCI referrer convention)

- SBOM attestation stored at: {registry}/{namespace}/{image}:sha256-{digest}.att

- SLSA provenance stored at: {registry}/{namespace}/{image}:sha256-{digest}.slsa

- All referrers discoverable via: GET {registry}/v2/{namespace}/{image}/referrers/{digest}

# 4. Notation (Notary v2) Integration
Notation provides the enterprise-grade policy layer for image signing. While Cosign handles CI/CD-integrated signing, Notation provides the signing model that aligns with enterprise PKI certificate hierarchies and OCI-native trust store management via the notation trust store and notation trust policy commands.


## 4.1 Notation Azure Key Vault Plugin
The Notation Azure Key Vault plugin (notation-azure-kv) integrates Notation with Azure Key Vault for signing, eliminating local key files:


```
# Notation signing with Azure Key Vault plugin (promotion gate)
# Invoked at the SDLC promotion pipeline gate before production tag is applied
# Install plugin (done once in pipeline environment)
notation plugin install --url https://github.com/Azure/notation-azure-kv/releases/download/v1.2.0/notation-azure-kv_1.2.0_linux_amd64.tar.gz \   --checksum sha256:{checksum}
# Sign the image
notation sign \   --plugin azure-kv \   --id 'https://{vault-name}.vault.azure.net/keys/kv-sign-notation/latest' \   --plugin-config credential_type=ENVIRONMENT \   --signature-manifest-annotations 'io.cncf.notary.x509chain.thumbprint#S256={thumbprint}' \   {registry}/{namespace}/{image}@{digest}
# Verify (customer-side or admission controller)
notation verify \   --policy {trust-policy.json} \   {registry}/{namespace}/{image}@{digest}
```


## 4.2 Trust Policy Distribution to Customers
Customers who deploy Notation-based admission controllers in their Kubernetes clusters require the company's trust policy and signing certificate chain. These are distributed in the customer onboarding bundle:


```json
// notation-trust-policy.json — distributed to customers {   'version': '1.0',   'trustPolicies': [
    {
      'name': '{company}-registry-policy',
      'registryScopes': ['{registry}.azurecr.io/{namespace}/*'],
      'signatureVerification': {
        'level': 'strict'
      },
      'trustStores': ['ca:{company}-ca'],
      'trustedIdentities': [
        'x509.subject: CN={company} Container Registry, O={company}'
      ]
    }   ] }
```


# 5. SLSA Provenance Architecture
SLSA (Supply chain Levels for Software Artifacts) provenance provides a machine-verifiable record of how an artifact was produced. The platform targets SLSA Build Level 3 — the highest build-level guarantee achievable with current tooling.


## 5.1 SLSA Level Targets
| **SLSA Level** | **Requirement** | **Current Status** | **Achieved By** |
| --- | --- | --- | --- |
| L1 — Provenance exists | Build process produces signed provenance | Target — baseline | SLSA GitHub Generator or ADO SLSA task generates provenance attestation for every build |
| L2 — Hosted build | Build runs on hosted build platform, not developer machines | Achieved | All production builds run on Azure DevOps hosted agents or GitHub Actions runners — no local builds promoted to production |
| L3 — Hardened builds | Build platform provides strong security guarantees; provenance is non-falsifiable by build process | Target — advanced | Combination of: GitHub Actions OIDC ephemeral tokens, WIF-bound signing, signed runner environment, Rekor transparency log |
| L4 — Reproducible | Builds are reproducible from source | Roadmap | Reproducible builds require deterministic build environments. Multi-year roadmap item. |


## 5.2 SLSA Provenance Generation Pipeline
```
# GitHub Actions SLSA provenance generation
# Uses the SLSA GitHub Generator (slsa-framework/slsa-github-generator) jobs:
  build:
  outputs:

    image-digest: ${{ steps.build.outputs.digest }}
  provenance:
  needs: [build]
  permissions:

  actions: read

# Required to read workflow run info

    id-token: write
# Required for OIDC token signing

  packages: write
# Required to push provenance to registry
  uses: slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@v2.1.0
  with:

  image: '{registry}/{namespace}/{image}'

  digest: '${{ needs.build.outputs.image-digest }}'

    registry-username: '00000000-0000-0000-0000-000000000000'
  secrets:

    registry-password: '${{ secrets.ACR_TOKEN }}'
# The SLSA generator produces a signed in-toto provenance attestation
# stored as an OCI referrer alongside the image in ACR.
# Verification: slsa-verifier verify-image --source-uri github.com/{org}/{repo} {image}@{digest}
```


# 6. Admission Controller Enforcement
The final enforcement layer is a Kubernetes admission controller (or admission webhook) that verifies image signatures before any pod is scheduled. This ensures that even if a customer's CI/CD system or registry access is compromised, unsigned or improperly-signed images cannot be deployed.


## 6.1 Admission Controller Options
| **Solution** | **Type** | **Integration** | **Recommended For** |
| --- | --- | --- | --- |
| Ratify + OPA/Gatekeeper | Open source — CNCF project | Ratify acts as a Gatekeeper External Data provider. Verifies Cosign signatures and Notation signatures before pod scheduling. | Primary recommendation for customers running standard Kubernetes or AKS |
| Kyverno with Cosign verification | Open source | Kyverno policy engine with built-in Cosign/Notation verification support. Simpler to operate than Ratify+Gatekeeper. | Alternative for customers already using Kyverno for policy management |
| Azure Policy for AKS (built-in) | Azure managed | AKS-integrated policy enforcement using Gatekeeper. Requires custom constraint template for signature verification. | AKS customers preferring fully managed Azure-native solution |
| Sigstore Policy Controller | Open source — Sigstore project | Kubernetes admission controller for Cosign signature policy enforcement. Integrates with Sigstore's transparency infrastructure. | Customers with strong Sigstore ecosystem alignment |


## 6.2 Ratify + Gatekeeper Reference Configuration
The platform provides a reference Ratify + Gatekeeper configuration for customer Kubernetes clusters. This configuration enforces that all images from the company registry must have a valid Cosign signature before scheduling:


```yaml
# Ratify verifier configuration — Cosign signature verification

apiVersion: config.ratify.deislabs.io/v1beta1

kind: Verifier

metadata:
  name: cosign-verifier

spec:
  name:
cosign
  artifactTypes: application/vnd.dev.cosign.artifact.sig.v1+json
  parameters:
  key: '{cosign-public-key-pem}'
# Platform's Cosign public key
  rekorURL: 'https://rekor.sigstore.dev' ---
# Gatekeeper ConstraintTemplate — enforce signature requirement

apiVersion: constraints.gatekeeper.sh/v1beta1

kind: RequireImageSignature

metadata:
  name: require-company-registry-signatures

spec:
  match:
  kinds: [{ apiGroups: [''], kinds: ['Pod'] }]
  parameters:
  registryPrefix: '{registry}.azurecr.io'

# Pods pulling from company registry require valid Cosign signature

# Pods from other registries are exempt (customer's own images)
```


## 6.3 Admission Controller Enforcement Matrix
| **Environment** | **Enforcement Level** | **Enforcement Tool** | **On Failure Action** |
| --- | --- | --- | --- |
| Production Kubernetes (AKS) | Mandatory — hard enforcement | Ratify + Gatekeeper or Kyverno | Pod creation denied. Alert to cluster admin and security team. Audit log entry. |
| Production on-premises Kubernetes | Mandatory — hard enforcement | Ratify + Gatekeeper or Kyverno | Same as AKS production |
| k3s Production | Mandatory — hard enforcement | Kyverno (lighter weight for k3s) | Pod creation denied. Alert. |
| Staging / Pre-production Kubernetes | Advisory — warn only | Ratify/Kyverno in audit mode | Pod created with warning annotation. Alert to product team. |
| Developer local (Docker Desktop / Rancher Desktop) | Voluntary — no enforcement | Developers may run cosign verify manually | N/A — local environments not enforced |
| wasmCloud (Cosmonic Control) | Mandatory — component verification | Cosmonic Control signature verification (built-in) | Component deployment rejected. Alert to platform team. |

# 7. Signing Key Rotation Procedure
Signing key rotation is a security-critical operation that must be coordinated between the platform team and customers to avoid disruption. The rotation procedure must ensure continuous signature verifiability during the transition period.

| **Phase** | **Duration** | **Actions** | **Impact** |
| --- | --- | --- | --- |
| Pre-rotation | 1 week before | Notify customer administrators via email. Update trust policy documentation with new key fingerprint. Verify new key is ready in Key Vault. | None — informational only |
| Dual-sign period | 72 hours | CI/CD pipelines sign with BOTH old key and new key simultaneously. Both signatures are stored as OCI referrers. Admission controllers configured to accept either key. | Zero customer impact — either key validates successfully |
| New-key-only cutover | Day 4 onward | Remove old key from CI/CD signing pipeline. Continue producing only new-key signatures. Update customer trust stores. | Customer admission controllers that haven't updated trust store will fail — monitor alerts |
| Old key retirement | 30 days after cutover | Old key disabled in Key Vault (not deleted — kept for historical verification). Customer trust stores confirmed updated. | Old key no longer valid for new images. Historical images retain their old-key signatures. |

# 8. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — key hierarchy, Cosign integration, Notation integration, SLSA provenance, admission controller, key rotation |
| 1.0 | TBD | Approved — pending CISO review and Architecture Review Board sign-off |


>** Required Approvals:**  CISO (key hierarchy and rotation procedure), Chief Architect, Head of Platform Engineering. Customer trust policy documentation must be reviewed by the Customer Success team before distribution.


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
