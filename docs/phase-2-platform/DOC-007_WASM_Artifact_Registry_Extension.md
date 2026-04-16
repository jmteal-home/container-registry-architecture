---
document_id: DOC-007
title: "WASM Artifact Registry Extension Design"
phase: "PH-2 — Platform Architecture"
priority: P1
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-007: WASM Artifact Registry Extension Design

| Document ID | DOC-007 |
| --- | --- |
| Phase | PH-2 — Platform Architecture |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT — Pending Architecture Review |
| Date | April 2026 |
| Depends On | [DOC-004](DOC-004_ACR_Service_Architecture.md) (ACR Service Architecture), [DOC-005](DOC-005_Network_Topology_Connectivity.md) (Network) |
| Key Standards | OCI Image Spec v1.1, OCI Distribution Spec v1.1.1, WASM Component Model, WASI 0.2 |
| Priority | P1 |

This document defines the architecture for storing, distributing, and securing WebAssembly (WASM) component artifacts within the Enterprise Container Registry. It covers OCI artifact type specifications, media type registration, the wasmCloud and Cosmonic Control credential integration model, SBOM and signing for WASM components, CI/CD pipeline patterns for WASM builds, and air-gapped deployment strategies for disconnected WASM runtimes.

# 1. WebAssembly in the OCI Ecosystem

## 1.1 Why OCI for WASM Artifacts
WebAssembly components are not container images, but they share a fundamental characteristic: they are portable, immutable, versioned binary artifacts that need to be stored, versioned, distributed, and pulled by a runtime. The OCI ecosystem — the most battle-tested artifact distribution infrastructure in the cloud-native world — is the ideal distribution layer for WASM components.

The CNCF TAG Runtime Wasm Working Group has standardized a WASM OCI Artifact format that enables consistent packaging across runtimes including wasmCloud, containerd runwasi, Spin (Fermyon), and others. Projects like wasmCloud have fully adopted this standard — the wasmCloud CLI (wash) uses OCI registries as the primary distribution mechanism for components, providers, and WIT interfaces.

| **Benefit** | **Description** |
| --- | --- |
| Single registry infrastructure | WASM components and container images coexist in ACR under the same namespace hierarchy, access control model, and lifecycle policies. No separate registry service required. |
| Familiar tooling | wash push/pull, oras push/pull, and cosign sign all work with ACR for WASM artifacts — the same tools used for container image supply chain. |
| Unified entitlement enforcement | The Token Broker's scope-map-based entitlement enforcement is media-type agnostic — a customer entitled to products/widget/* can pull both container images and WASM components from that namespace without separate credential management. |
| OCI Referrers API | SBOM attachments and Cosign signatures for WASM components are stored as OCI referrers linked to the component artifact by digest — same mechanism as for container images. |
| No multiarch complexity | WASM components are architecture-agnostic by design — a single WASM binary runs on any architecture where a WASM runtime is available. No multi-arch manifest lists needed. |


## 1.2 Standards Baseline
The WASM artifact architecture is built on the following standard versions, which are tracked and updated as the ecosystem matures:

| **Standard** | **Version** | **Role in This Architecture** | **Stability** |
| --- | --- | --- | --- |
| OCI Image Specification | v1.1 | Defines the manifest format used for WASM artifacts (artifactType field, empty config descriptor pattern) | Stable GA |
| OCI Distribution Specification | v1.1.1 | Defines the registry API used by ACR, wash, and oras — including the Referrers API (_oci/1.1/referrers/{digest}) | Stable GA |
| WASM OCI Artifact Format | CNCF TAG Runtime spec | Defines config.mediaType = application/vnd.wasm.config.v0+json and layer mediaType conventions for WASM components | Stabilizing — broad adoption in wasmCloud, Spin, containerd runwasi |
| WebAssembly Component Model | WASI 0.2 / WIT | Defines the binary format of WASM components and WIT interface descriptions | WASI 0.2 is stable; WASI 0.3 in development |
| ORAS CLI | v1.3.0+ | Primary tool for pushing/pulling non-container OCI artifacts; backup and restore; air-gapped operations | Stable GA; OCI distribution spec v1.1.1 compliant |
| Cosign | v2.x | WASM component signing and OCI referrer signature attachment | Stable GA |

# 2. WASM Artifact Type Catalog
The following artifact types are stored in the Enterprise Container Registry. Each is an OCI artifact with a distinct media type that enables registries and consumers to identify and process the artifact correctly.


## 2.1 Primary Artifact Types
| **Artifact Type** | **OCI Config mediaType** | **OCI Layer mediaType** | **Produced By** | **Consumed By** | **ACR Namespace Path** |
| --- | --- | --- | --- | --- | --- |
| wasmCloud Component | application/vnd.wasm.config.v0+json | application/wasm | wash build + CI/CD pipeline | wasmCloud host, Cosmonic Control WorkloadDeployment CRD | products/{product}/wasm/{component-name}:{version} |
| wasmCloud Capability Provider | application/vnd.wasmcloud.provider.archive.v1+json (wasmCloud-specific format) | application/vnd.wasmcloud.provider.archive.v1.tar+gz | wash build (provider build) | wasmCloud host (capability provider loader) | products/{product}/wasm/providers/{provider-name}:{version} |
| WIT Interface Package | application/vnd.wasm.config.v0+json | application/vnd.wasm.wit.v0+tar+gz | wash build / wkg publish | wash build (dependency resolution), other component build toolchains | products/{product}/wasm/wit/{interface-name}:{version} |
| Cosign Signature (WASM) | application/vnd.dev.cosign.artifact.sig.v1+json | application/vnd.dev.cosign.simplesigning.v1+json | cosign sign (CI/CD pipeline) | Cosmonic Control (verification), admission webhook, wash pull --verify | OCI referrer attached to component artifact by digest |
| WASM Component SBOM | application/vnd.dev.cosign.attestation.v1+json | application/spdx+json or application/vnd.cyclonedx+json | syft / cdxgen in CI/CD pipeline | Compliance tooling, Cosmonic Control, customer audit requests | OCI referrer attached to component artifact by digest |
| Helm Chart (product packaging) | application/vnd.cncf.helm.chart.config.v1+json | application/vnd.cncf.helm.chart.content.v1.tar+gzip | helm package + helm push | helm install, ArgoCD, Flux CD | products/{product}/charts/{chart-name}:{version} |


>** Media Type Note:**  ACR Premium natively supports arbitrary OCI artifact types via the OCI Artifact Spec v1.1 artifactType field. No additional configuration is required to enable WASM artifact storage. The artifactType field in the OCI manifest is used by ACR for filtering and reporting but does not restrict storage. ORAS v1.3.0+ and wash use this field correctly for all WASM artifact pushes.


# 3. WASM CI/CD Pipeline Integration

## 3.1 WASM Build & Publish Pipeline Stages
The WASM component CI/CD pipeline follows the same staged promotion model as the container image pipeline, with WASM-specific build and signing steps replacing the Dockerfile-based build:

| **Stage** | **Tool** | **Action** | **Gate Condition** | **Output Artifact** |
| --- | --- | --- | --- | --- |
| 1. Build | wash build (Rust: cargo component build; Go: tinygo build; TS: jco) | Compile source code to .wasm binary targeting wasm32-wasip2 | Build success; .wasm binary passes wasm-tools validate | Signed .wasm binary at target/wasm32-wasip2/release/{component}.wasm |
| 2. WIT Validate | wasm-tools component wit | Extract and validate WIT interfaces from compiled component | Interfaces match declared WIT spec; no undeclared imports | WIT export metadata attached to build record |
| 3. SBOM Generate | syft or cdxgen | Generate SBOM for WASM component (components are typically smaller and more deterministic than container images) | SBOM generated successfully | SBOM in SPDX or CycloneDX JSON format |
| 4. Push to Registry | wash push or oras push | Push .wasm binary as OCI artifact to ACR staging namespace with correct mediaType | ACR accepts artifact; digest returned | OCI artifact at products/{product}/wasm/{component}:{build-id} |
| 5. Sign Component | cosign sign | Sign the OCI artifact digest using Key Vault-backed signing key | Cosign signature stored as OCI referrer; Rekor transparency log entry created | Cosign signature attached to artifact via OCI Referrers API |
| 6. Attach SBOM | cosign attest or oras attach | Attach SBOM as OCI referrer to the signed component artifact | SBOM attached as referrer with correct mediaType | SBOM OCI referrer linked to component digest |
| 7. Vulnerability Scan | Defender for Containers (WASM binary analysis) + custom WASM-specific scanner (if required) | Scan WASM binary for known vulnerabilities. Note: WASM binaries have a smaller attack surface than containers — no OS packages, no filesystem. | No critical/high CVEs (per policy); quarantine gate if failures | Scan result attached to artifact record in Log Analytics |
| 8. Promote to Production | oras tag or oras copy | Promote from staging to production tag (e.g., 0.5.1-dev → 0.5.1) | Signing verified; SBOM present; scan passed; all gates green | Semantic version tag applied to artifact digest |


## 3.2 GitHub Actions Pipeline Reference
```
# .github/workflows/wasm-build-publish.yml
# wasmCloud Component CI/CD Pipeline — Enterprise Registry name: Build & Publish WASM Component on:
  push:
  branches: [main]
  pull_request:
  branches: [main] env:
  REGISTRY: '{registry-name}.azurecr.io'
  NAMESPACE: 'products/{product}/wasm'
  COMPONENT: '{component-name}' jobs:   build-sign-publish:

    runs-on: ubuntu-latest
  permissions:

    id-token: write
# Required for WIF OIDC token

  contents: read
  steps:

- uses: actions/checkout@v4

- name: Install
wash CLI

  run:
curl -s https://packagecloud.io/AtomicJar/wasmcloud/script.deb.sh │ sudo bash
          && sudo apt-get install -y
wash

- name: Build WASM Component

  run:
wash build

- name: Azure Login (WIF)

  uses: azure/login@v2

  with:


    client-id: ${{ secrets.AZURE_CLIENT_ID }}


    tenant-id: ${{ secrets.AZURE_TENANT_ID }}


    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

- name: Get ACR Token for wash/oras

  id: acr-token

  run: │
        TOKEN=$(az acr login --name ${{ env.REGISTRY }} --expose-token --query accessToken -o tsv)

echo 'WASH_REG_USER=00000000-0000-0000-0000-000000000000' >> $GITHUB_ENV

echo "WASH_REG_PASSWORD=$TOKEN" >> $GITHUB_ENV

- name: Push WASM Component to ACR

  run: │

wash push $REGISTRY/$NAMESPACE/$COMPONENT:${{ github.sha }} \
          ./target/wasm32-wasip2/release/${{ env.COMPONENT }}.wasm

- name: Sign Component with Cosign (Key Vault key)

  run: │
        DIGEST=$(oras manifest fetch $REGISTRY/$NAMESPACE/$COMPONENT:${{ github.sha }} \
          --descriptor │ jq -r '.digest')

cosign sign --key azurekv://{vault-name}/{key-name} \
          $REGISTRY/$NAMESPACE/$COMPONENT@$DIGEST

- name: Generate and Attach SBOM

  run: │

syft $REGISTRY/$NAMESPACE/$COMPONENT:${{ github.sha }} -o spdx-json=sbom.spdx.json

cosign attest --key azurekv://{vault-name}/{key-name} \
          --type spdx --predicate sbom.spdx.json \
          $REGISTRY/$NAMESPACE/$COMPONENT@$DIGEST
```


## 3.3 wash CLI Authentication with ACR
The wash CLI uses Docker credential conventions for authenticating with ACR. Two authentication patterns are supported:

- Pattern A — Docker login (interactive/CI): docker login {registry}.azurecr.io -u 00000000-0000-0000-0000-000000000000 --password-stdin <<< $(az acr login --expose-token --query accessToken -o tsv). Then wash push uses credentials from ~/.docker/config.json automatically.

- Pattern B — Environment variables (CI/CD): export WASH_REG_USER=00000000-0000-0000-0000-000000000000 && export WASH_REG_PASSWORD=$(az acr login --expose-token --query accessToken -o tsv). Then wash push uses these env vars directly.

- Pattern C — WASMCLOUD_OCI_REGISTRY_USER/PASSWORD env vars (wasmCloud host): used by wasmCloud hosts to pull artifacts from ACR at runtime. Credentials injected via Kubernetes Secret (imagePullSecret convention) or environment variable from Key Vault.

# 4. wasmCloud Host Registry Integration
wasmCloud hosts pull component artifacts and capability providers from OCI registries at application deployment and component update time. This section defines the credential configuration patterns for wasmCloud hosts connected to the Enterprise Registry.


## 4.1 wasmCloud OSS Registry Configuration
wasmCloud OSS hosts configure registry credentials via environment variables or host configuration. For private ACR access, the Token Broker-issued credentials are injected as environment variables when the wasmCloud host starts:


```
# wasmCloud host environment configuration (Kubernetes Deployment or Docker Compose)
# Credentials are pulled from Kubernetes Secret created by External Secrets Operator
# Secret source: Azure Key Vault (Token Broker-issued token, rotated every 24h) env:
- name: WASMCLOUD_OCI_REGISTRY
  value: '{registry-name}.azurecr.io'
- name: WASMCLOUD_OCI_REGISTRY_USER
  valueFrom:

  secretKeyRef:

  name: acr-wasm-pull-credentials

  key: username
- name: WASMCLOUD_OCI_REGISTRY_PASSWORD
  valueFrom:

  secretKeyRef:

  name: acr-wasm-pull-credentials

  key: password
# For multi-registry scenarios (multiple products from different namespaces):
# wasmCloud supports per-artifact credential override via
wash ctl start component
# --config flags, or via wadm manifest annotation.
```


## 4.2 Cosmonic Control Registry Integration
Cosmonic Control aligns with Kubernetes conventions for OCI credentials. Per the Cosmonic documentation, OCI credentials are configured on a per-artifact basis using imagePullSecrets, with a global override available for air-gapped environments:

| **Configuration Pattern** | **Description** | **Use Case** | **Implementation** |
| --- | --- | --- | --- |
| Per-artifact imagePullSecret | Each WorkloadDeployment CRD references a Kubernetes Secret containing ACR credentials in the standard imagePullSecret format | Granular per-component credential scoping; different credentials for different product namespaces | Create Kubernetes Secret with .dockerconfigjson key containing ACR Token Broker-issued credential; reference in WorkloadDeployment spec.imagePullSecrets |
| Global registry override (air-gapped) | global.image.registry and global.image.pullSecrets Helm values applied to all component pulls | Air-gapped customer environments where a local mirror registry replaces all external OCI references | Set global.image.registry to local mirror FQDN; global.image.pullSecrets to local mirror credential Secret |
| External Secrets Operator integration | Cosmonic Control CRDs reference Kubernetes Secret objects; External Secrets Operator syncs Token Broker credentials from Azure Key Vault | Automated credential rotation without manual Secret updates | ExternalSecret CRD → Azure Key Vault provider → Kubernetes Secret → Cosmonic Control WorkloadDeployment |


## 4.3 Cosmonic Control WorkloadDeployment CRD with Registry Credentials
```yaml
# Cosmonic Control WorkloadDeployment CRD — with ACR imagePullSecret

apiVersion: cosmonic.com/v1alpha1

kind: WorkloadDeployment

metadata:
  name: widget-processor-component
  namespace: cosmonic-system

spec:
  component:
  image: '{registry-name}.azurecr.io/products/widget/wasm/processor:0.5.1'
  imagePullSecrets:

- name: acr-entitlement-pull-secret
# Token Broker-issued credential
  replicas: 3
  hostSelector:
  matchLabels:

  environment: production ---
# Kubernetes Secret (created by External Secrets Operator from Azure Key Vault)

apiVersion: v1

kind: Secret

metadata:
  name: acr-entitlement-pull-secret
  namespace: cosmonic-system type: kubernetes.io/dockerconfigjson data:   .dockerconfigjson: <base64-encoded-dockerconfig-json>
# dockerconfig contains:
# { 'auths': { '{registry}.azurecr.io': { 'username': '00000000-...', 'password': '{token-broker-token}' } } }
```


# 5. Air-Gapped WASM Deployment Architecture
Air-gapped and disconnected WASM deployments require a different distribution strategy than connected environments. The ORAS CLI provides the primary mechanism for packaging and transferring OCI artifacts across the network boundary.


## 5.1 Air-Gap Bundle Strategy
ORAS v1.3.0+ introduced the oras backup and oras restore commands, which enable exporting an entire repository (including referrers — signatures and SBOMs) to an OCI image layout on the local filesystem, and restoring to any target registry. This is the recommended approach for air-gapped WASM artifact distribution:

| **Step** | **Command** | **Description** | **Who Performs** |
| --- | --- | --- | --- |
| 1. Export from ACR | oras backup {registry}.azurecr.io/products/{product}/wasm/{component}:{version} --output ./wasm-bundle/ --include-referrers | Export component artifact + Cosign signature + SBOM to local OCI image layout directory. All referrers (signatures, SBOMs) included. | Platform Engineering or product team at bundle generation time |
| 2. Bundle package | tar -czf wasm-bundle-{product}-{version}.tar.gz ./wasm-bundle/ | Package the OCI image layout into a transportable tarball for physical media or SFTP transfer. | Platform Engineering |
| 3. Verify bundle integrity | cosign verify-blob --key {signing-cert} --signature wasm-bundle/signature.sig wasm-bundle-{product}-{version}.tar.gz | Verify the transport tarball has not been tampered with during transfer. Bundle itself is signed with the platform signing key. | Customer (at receiving end) |
| 4. Import to local registry | oras restore ./wasm-bundle/ --to {local-mirror-registry}/{product}/wasm/{component}:{version} | Restore the OCI image layout to the customer's internal registry (e.g., Harbor, local ACR, or oci-registry container). | Customer IT / platform team |
| 5. Configure wasmCloud host | WASMCLOUD_OCI_REGISTRY={local-mirror-registry} in wasmCloud host config | Point wasmCloud host to local mirror registry for all component pulls. | Customer IT |
| 6. Configure Cosmonic Control | global.image.registry={local-mirror-registry} in Helm values | Redirect all Cosmonic Control component pulls to local mirror. | Customer IT |


## 5.2 Local Registry Mirror for WASM
For Tier 3 and Tier 4 edge sites, a local OCI-compatible registry is deployed on-site to serve WASM artifacts without external connectivity. Options in order of preference:

- Option 1 (preferred): oci-registry container — a lightweight OCI Distribution Spec v1.1 compliant registry in a Docker container. Zero external dependencies. Pull from local filesystem after oras restore.

- Option 2: Harbor registry — feature-rich, supports replication, authentication, and scanning. More complex to operate at edge sites.

- Option 3: ACR Connected Registry — for Tier 2 sites with periodic connectivity, the ACR Connected Registry can sync WASM component artifact namespaces alongside container images using the same sync mechanism documented in [DOC-004 Section 7](DOC-004_ACR_Service_Architecture.md).


>** WASM Component Verification at Air-Gapped Sites:**  Even in air-gapped environments, Cosign signature verification must be performed before workload deployment. The signature and its associated Cosign bundle are included in the ORAS backup. Cosign keyless verification requires Rekor transparency log access (unavailable air-gapped) — use key-based verification with the platform's public signing key distributed with the bundle. Configure Cosmonic Control or wasmCloud host to verify signatures against the platform's distributed public key.


# 6. WASM Artifact Lifecycle Management

## 6.1 Versioning Standard
WASM component versioning follows the same semantic versioning standard as container images defined in [DOC-004 Section 3.3](DOC-004_ACR_Service_Architecture.md). Additional WASM-specific considerations:

- WASM components are typically smaller (KB to single-digit MB) than container images — storage cost per version is minimal. Retention policies can be more generous.

- WIT interface compatibility is a versioning dimension beyond semver: a component compiled against wasi:http 0.2.0 is not compatible with a runtime expecting wasi:http 0.3.0. Tag conventions must reflect the WASI version if compatibility is a concern.

- Provider archives (capability providers) have a different release cadence from components — they are infrastructure artifacts. Separate retention policies apply.


## 6.2 Retention Policies for WASM Artifacts
| **Artifact Type** | **Retention Policy** | **Rationale** |
| --- | --- | --- |
| WASM Components (production) | Retain all semver-tagged versions for 12 months; retain last 5 semver versions indefinitely | Customers may be pinned to specific component versions; longer retention than container images given small size |
| WASM Components (dev/staging) | 30 days for untagged; 14 days for dev- prefixed tags | Build artifacts — short-lived; storage cost low but discipline maintained |
| Capability Providers | Retain all semver versions for 24 months | Providers are infrastructure — longer operational lifetime expected; backward compatibility is critical |
| WIT Interface Packages | Retain all versions indefinitely | Interfaces are shared dependencies; deleting an interface version breaks all components that imported it |
| Cosign Signatures (referrers) | Lifetime of parent artifact — auto-deleted when parent is deleted | Signatures are metadata for the signed artifact; no independent lifecycle |
| WASM SBOMs (referrers) | 12 months minimum (compliance); then follow parent artifact lifecycle | Regulatory evidence; retain for audit lookback period |

# 7. WASM Artifact Entitlement & Access Control
WASM component artifacts are subject to identical entitlement enforcement as container images. The Token Broker's scope-map-based access control is media-type agnostic — a customer token scoped to products/widget/* grants access to all artifact types within that namespace, whether container images, WASM components, or Helm charts.

| **Access Scenario** | **Authentication** | **Entitlement Check** | **Notes** |
| --- | --- | --- | --- |
| wasmCloud host pulling component (customer) | Token Broker-issued ACR refresh token (via WASMCLOUD_OCI_REGISTRY_USER/PASSWORD env vars) | Yes — scope map covers products/{product}/wasm/* for entitled customers | Credential injected from Kubernetes Secret (External Secrets Operator). Rotated every 24h. |
| Cosmonic Control pulling component (customer) | imagePullSecret referencing Token Broker-issued credential | Yes — same token mechanism as container images | Per WorkloadDeployment CRD or global override for air-gapped |
| wash push (product team CI/CD) | Entra ID WIF → ABAC Repository Writer scoped to products/{product}/* | ABAC condition — namespace-scoped push for product team | Includes /wasm/ sub-namespace automatically under products/{product}/* |
| wash pull (developer local) | az acr login (interactive Entra ID) → ABAC Repository Reader scoped to product namespace | ABAC condition — developer read-only to own namespace | Same as container image pull for developers |
| oras backup (bundle generation) | Service principal or MI with Repository Reader on the specific namespace | N/A — internal platform operation, not customer-facing | Generates entitlement-gated bundle for customer distribution |
| Air-gapped site (local mirror) | Local mirror credential (not Token Broker — static credential to local registry) | N/A — entitlement enforced at bundle generation; local mirror serves only pre-authorized content | Bundle contents are fixed at generation time by entitlement scope |

# 8. WASM Artifact Observability
WASM artifacts require observability instrumentation at both the registry layer (pull/push events) and the runtime layer (component execution telemetry). This section covers the registry-layer observability. Runtime-layer observability (wasmCloud OTEL) is addressed in [DOC-018](../phase-6-operations/DOC-018_Observability_Architecture.md).

| **Metric/Event** | **Source** | **Target** | **Alert Condition** |
| --- | --- | --- | --- |
| WASM component pull count by customer/product | ACR diagnostic log: ContainerRegistryRepositoryEvents — filtered by artifact mediaType | Log Analytics, Grafana dashboard | Pull failure rate > 1% for any customer/product in 15 minutes |
| WASM component push events (CI/CD) | ACR diagnostic log: ContainerRegistryRepositoryEvents — push events on wasm/ namespace paths | Log Analytics, pipeline telemetry | Push failure; push to unexpected namespace (potential namespace escape) |
| Cosign signature verification failure | Cosmonic Control / wasmCloud host OTEL logs — signature verification result | Log Analytics, SIEM | Any signature verification failure in production (potential tampered artifact — immediate alert) |
| WASM component version distribution | ACR metrics: artifact pull count by tag across wasm/ namespaces | Grafana dashboard | Alert if deprecated versions still being pulled (indicates customer upgrade lag) |
| Air-gapped bundle generation events | Custom audit log in Token Broker / bundle generation service | Log Analytics, immutable audit workspace | Any bundle generated outside change management window; bundle for non-entitled customer |
| OCI Referrers API usage | ACR diagnostic log: referrers endpoint calls | Log Analytics | Unusual referrers API call volume (potential enumeration attack) |

# 9. Known Limitations & Evolution Roadmap
| **Limitation** | **Current Impact** | **Planned Resolution** | **Timeline** |
| --- | --- | --- | --- |
| WASM-specific vulnerability scanning | Microsoft Defender for Containers scans container filesystems (OS packages, binaries). WASM binaries have no OS packages — standard CVE scanning has limited applicability. Custom WASM-specific binary analysis tooling is nascent. | Coverage gap for WASM-specific vulnerabilities (malicious logic in WASM bytecode). Compensating control: Cosign signing with CI/CD trust ensures only platform-built components are deployed. | Evaluate WASM-specific security scanners (e.g., wasmCloud's built-in module signing, Wasm Security Framework). Update [DOC-013](../phase-4-supply-chain/DOC-013_Vulnerability_Scanning_Policy_Gate.md) when tooling matures. | Q3 2026 |
| Capability provider archive OCI format | wasmCloud capability providers use a wasmCloud-specific OCI format (application/vnd.wasmcloud.provider.archive.v1+tar+gz) rather than the CNCF standard WASM OCI artifact format. Tooling parity with standard WASM components is not yet complete. | Providers require wash-specific push/pull commands. Standard oras tooling works for pull but push requires wash. | Monitor wasmCloud provider OCI format evolution toward CNCF standard. Update pipeline templates when alignment is achieved. | H2 2026 |
| WIT interface dependency resolution | WIT interface packages published to ACR cannot currently be resolved as build dependencies via the standard wkg tool — wkg uses WARG-based registries by default. A workaround exists via wash pull + local WIT path configuration. | Developers must manually manage WIT interface dependencies from ACR rather than using wkg auto-resolution. | File feature request with wasmCloud/wkg for OCI registry backend support. Interim: document manual WIT dependency procedure. | H1 2026 |
| Cosmonic Control WASM SBOM verification | Cosmonic Control does not currently natively verify SBOM presence as a deployment gate (unlike signature verification which is supported). | SBOM is stored but not verified before deployment. Compensating control: SBOM presence verified in CI/CD gate before image promotion. | Track Cosmonic Control roadmap for SBOM policy support. Use OPA/Gatekeeper admission webhook as interim enforcement. | Unknown — tracking Cosmonic roadmap |

# 10. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — OCI artifact catalog, CI/CD pipeline, wasmCloud/Cosmonic integration, air-gapped strategy, lifecycle, entitlement, observability, limitations |
| 1.0 | TBD | Approved version — pending Architecture Review Board sign-off |


>** Required Approvals:**  Chief Architect, Head of Platform Engineering. Note: this document covers emerging technology (WASM OCI artifact standards are still stabilizing). Schedule a 90-day review to incorporate standard updates from CNCF TAG Runtime and wasmCloud project.


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
