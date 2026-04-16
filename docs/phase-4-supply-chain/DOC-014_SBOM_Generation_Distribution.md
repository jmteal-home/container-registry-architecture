---
document_id: DOC-014
title: "SBOM Generation & Distribution Architecture"
phase: "PH-4 — Supply Chain Security"
priority: P1
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-014: SBOM Generation & Distribution Architecture

| Document ID | DOC-014 |
| --- | --- |
| Phase | PH-4 — Supply Chain Security |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT |
| Date | April 2026 |
| Depends On | [DOC-012](DOC-012_Image_Signing_Provenance.md) (Image Signing), [DOC-013](DOC-013_Vulnerability_Scanning_Policy_Gate.md) (Vulnerability Scanning) |
| Priority | P1 |

This document defines the SBOM (Software Bill of Materials) generation and distribution architecture for the Enterprise Container Registry. It covers Syft/cdxgen SBOM generation in CI/CD pipelines, OCI attachment as referrers, the entitlement-scoped SBOM API for customer access, regulatory compliance alignment (EO 14028, NIS2, CRA), and WASM component SBOM considerations.

# 1. SBOM Architecture Overview
An SBOM is a machine-readable inventory of all components, libraries, and dependencies that compose a software artifact. For container images, this includes OS packages, language runtime packages, application libraries, and transitive dependencies. SBOMs serve three distinct use cases in this architecture:

| **Use Case** | **Consumer** | **Value** |
| --- | --- | --- |
| Internal vulnerability management | Platform Engineering, Security team | Enables rapid identification of all images containing a specific CVE (e.g., 'all images containing log4j 2.14') without re-scanning every image |
| Customer transparency & compliance | Enterprise customers with regulatory SBOM requirements (US Federal EO 14028, EU CRA, NIS2) | Customers can audit the software components in products they license. Increasingly a procurement requirement for regulated industries. |
| License compliance | Legal / IP teams | Identifies open source license obligations (GPL, AGPL, etc.) in distributed container images |

# 2. SBOM Generation Pipeline

## 2.1 Toolchain
| **Tool** | **Version** | **Purpose** | **Output Format** |
| --- | --- | --- | --- |
| Syft | v1.x | Primary SBOM generator for container images. Analyzes Docker image layers for OS packages, language packages, and binary inventory. | SPDX JSON, CycloneDX JSON |
| cdxgen | v10.x | Supplementary SBOM generator with deeper language ecosystem support (Java Maven/Gradle, Node.js npm/yarn, Python pip). Used for application-layer SBOM enrichment. | CycloneDX JSON |
| cosign attest | v2.x | Attaches SBOM to OCI artifact as a signed attestation referrer. Links SBOM to the image digest cryptographically. | OCI referrer (type: application/vnd.cyclonedx+json or application/spdx+json) |
| oras attach | v1.3+ | Alternative to cosign attest for unsigned SBOM attachment. Used where the SBOM itself is covered by the image signature (Cosign signs the attestation). | OCI referrer |
| grype | v0.x | SBOM-based vulnerability scanner. Scans the SBOM (not the image) for known CVEs. Used as a fast complement to Defender for Containers. | SARIF, JSON |


## 2.2 SBOM Generation in CI/CD Pipeline
```
# GitHub Actions — SBOM generation and attachment
# Executes after:
docker build →
trivy scan →
docker push →
cosign sign
- name: Generate SBOM with Syft
  run: │

syft ${{ env.REGISTRY }}/${{ env.NAMESPACE }}/${{ env.IMAGE }}@${{ env.DIGEST }} \
      --output spdx-json=sbom-spdx.json \
      --output cyclonedx-json=sbom-cdx.json
- name: Scan SBOM for additional CVEs (Grype)
  run: │
    grype sbom:sbom-spdx.json --fail-on critical \
      --output sarif --file grype-results.sarif
- name: Attest SBOM with Cosign (signed attachment)
  run: │

cosign attest \
      --key azurekv://{vault-name}/kv-sign-ci-pipeline \
      --predicate sbom-spdx.json \
      --type spdxjson \
      ${{ env.REGISTRY }}/${{ env.NAMESPACE }}/${{ env.IMAGE }}@${{ env.DIGEST }}
# SBOM is now stored as a signed OCI referrer linked to the image digest.
# Retrieve:
cosign download sbom {registry}/{namespace}/{image}@{digest}
# Or:
oras discover --artifact-type application/spdx+json {registry}/{namespace}/{image}@{digest}
```


## 2.3 SBOM Coverage Requirements
| **Artifact Type** | **Required SBOM Format** | **Minimum Coverage** | **Gate Condition** |
| --- | --- | --- | --- |
| Container images (OS base) | SPDX JSON + CycloneDX JSON | OS packages (APT/RPM), language runtimes, installed binaries | SBOM must be generated and attached before image is promoted to production namespace. No SBOM = quarantine maintained. |
| Container images (application layer) | CycloneDX JSON (cdxgen) | Application dependencies (Maven, NPM, pip, etc.) in application layer | SBOM must cover all declared package managers found in image layers. |
| WASM Components | CycloneDX JSON (cdxgen + wasm-specific) | Rust crate dependencies, WIT interface dependencies | WASM SBOM is smaller and more deterministic than container SBOM. Required but not a blocking gate. |
| Helm Charts | CycloneDX JSON (cdxgen helm) | Helm chart dependencies, sub-chart inventory | Required for compliance. Not a blocking gate for chart promotion. |

# 3. SBOM OCI Storage Design
SBOMs are stored as OCI referrers attached to the image digest, not as separate files. This co-location ensures SBOMs are automatically included in any registry operation (copy, tag, export) involving the parent image:

| **OCI Referrer Type** | **Media Type** | **Attached To** | **Discoverable Via** |
| --- | --- | --- | --- |
| SPDX SBOM attestation | application/vnd.dev.cosign.attestation.v1+json (SPDX predicate) | Image manifest digest | oras discover; cosign download sbom; Referrers API |
| CycloneDX SBOM attestation | application/vnd.dev.cosign.attestation.v1+json (CycloneDX predicate) | Image manifest digest | Same as above |
| SLSA Provenance attestation | application/vnd.dev.cosign.attestation.v1+json (SLSA predicate) | Image manifest digest | Same as above |
| Cosign signature | application/vnd.dev.cosign.artifact.sig.v1+json | Image manifest digest | cosign verify; Referrers API |
| Notation signature | application/vnd.cncf.notary.signature | Image manifest digest | notation verify; Referrers API |

# 4. Customer SBOM Access API
Customers with appropriate entitlements can request SBOMs for the product images they license. SBOMs are accessible via two mechanisms: direct OCI referrer access using standard tooling, and a convenience REST API provided by the platform for customers without OCI tooling.


## 4.1 Direct OCI Access (Standard Tooling)
Customers with valid Token Broker credentials can access SBOMs directly using Cosign, ORAS, or any OCI-compliant tool:


```
# Customer retrieves SBOM using
cosign (requires valid ACR pull credentials)
# Option 1:
cosign download (simple)
docker login {registry}.azurecr.io -u '00000000-...' -p '{token-broker-token}'
cosign download sbom {registry}/products/widget/api@sha256:{digest}
# Option 2:
oras discover (shows all referrers)
oras discover --artifact-type application/spdx+json \   {registry}/products/widget/api@sha256:{digest}
# Option 3:
oras pull (download specific referrer)
oras pull {registry}/products/widget/api:sha256-{digest}.att \   --output ./sbom.json
```


## 4.2 SBOM Distribution REST API
A convenience REST API is provided for customers who need SBOM access without OCI tooling (e.g., compliance teams using vulnerability management platforms):

| **Endpoint** | **Auth** | **Response** | **Notes** |
| --- | --- | --- | --- |
| GET /api/v1/sbom/{product}/{image}:{tag} | Token Broker JWT (customer entitlement validated) | JSON: SBOM content in requested format (spdx-json or cyclonedx-json) | Entitlement check: customer must be entitled to {product}. Returns latest SBOM for the specified tag. |
| GET /api/v1/sbom/{product}/{image}@sha256:{digest} | Token Broker JWT | JSON: SBOM for specific digest | Immutable — digest-pinned SBOM for exact audit purposes |
| GET /api/v1/sbom/{product}/{image}:{tag}/verify | Token Broker JWT | JSON: { signature_valid, sbom_hash, signer_identity, signed_at } | Verify SBOM authenticity without downloading content |
| GET /api/v1/sbom/index/{customer_id} | Token Broker JWT (admin scope) | JSON: list of all images + SBOM availability status for customer's entitled products | Bulk SBOM inventory for compliance tooling integration |


## 4.3 SBOM Entitlement Enforcement
The SBOM API applies the same entitlement enforcement as the Token Broker: customers can only access SBOMs for products they are actively entitled to. The Token Broker JWT presented to the SBOM API is validated, and the customer's entitled product list is confirmed before any SBOM content is returned. A customer cannot use the SBOM API to enumerate or access SBOMs for non-entitled products.

# 5. Regulatory Compliance Mapping
SBOM generation and distribution supports compliance with several regulatory frameworks that mandate or recommend SBOM practices for software distributed to customers:

| **Regulation / Framework** | **Requirement** | **Coverage by This Architecture** |
| --- | --- | --- |
| US EO 14028 (Executive Order on Improving the Nation's Cybersecurity) | Federal contractors must provide SBOMs for all software supplied to federal agencies. | SBOM in SPDX or CycloneDX format generated for all container images. Delivered via OCI referrer or SBOM API on customer request. |
| EU Cyber Resilience Act (CRA — effective 2027) | Products with digital elements must document components. Importers and distributors must ensure SBOM availability. | CycloneDX SBOMs generated for all products. Distribution API enables customer SBOM access on demand. |
| NTIA Minimum Elements (2021) | Minimum SBOM data: supplier name, component name, version, unique identifiers, dependency relationships, SBOM author, timestamp. | Syft-generated SBOMs include all NTIA minimum elements. Component relationships captured in SPDX relationship graph. |
| NIS2 Directive (EU) | Enhanced security obligations for critical infrastructure. Supply chain risk management requires artifact provenance. | SLSA provenance attestation + Cosign signing provides verifiable artifact provenance. SBOM enables supply chain component auditing. |
| ISO/IEC 5962:2021 | SBOM data format standard (SPDX). | SBOMs generated in SPDX JSON format per ISO/IEC 5962:2021 specification. |

# 6. SBOM Lifecycle & Retention
| **SBOM Type** | **Retention Period** | **Storage Location** | **Retrieval After ACR Image Deletion** |
| --- | --- | --- | --- |
| Production image SBOM | 12 months minimum (regulatory compliance); then follow parent image lifecycle | OCI referrer in ACR (linked to image digest); archived copy in Azure Blob Storage (immutable) | Azure Blob Storage archive. Blob uses immutable storage policy — cannot be deleted for retention period. |
| Staging/Dev image SBOM | 30 days | OCI referrer in ACR only — no archive | Not retained after image deletion |
| WASM component SBOM | 12 months minimum | Same as production image SBOM | Same as above |
| Helm chart SBOM | 12 months minimum | Same as production image SBOM | Same as above |

# 7. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — SBOM toolchain, generation pipeline, OCI storage, customer SBOM API, regulatory compliance, lifecycle |
| 1.0 | TBD | Approved — pending Architecture Review Board sign-off |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering, Legal/Compliance team (regulatory compliance mapping review), Customer Success team (SBOM API customer experience review).


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
