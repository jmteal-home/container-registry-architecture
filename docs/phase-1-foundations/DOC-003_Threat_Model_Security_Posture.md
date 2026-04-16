---
document_id: DOC-003
title: "Threat Model & Security Posture"
phase: "PH-1 — Foundations & Constraints"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-003: Threat Model & Security Posture

| Document ID | DOC-003 |
| --- | --- |
| Phase | PH-1 — Foundations & Constraints |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — SECURITY SENSITIVE |
| Status | DRAFT — Pending CISO Review |
| Date | April 2026 |
| Depends On | [DOC-001](DOC-001_Architecture_Vision_Goals.md) (Vision & Goals), [DOC-002](DOC-002_Stakeholder_Consumer_Analysis.md) (Consumer Analysis) |
| Methodology | STRIDE per Element (SpE) + DREAD risk scoring |
| Priority | P0 — Blocking all Phase 2 security design |

This document delivers a comprehensive STRIDE-based threat model for the Enterprise Container Registry. It identifies all trust boundaries, threat actors, attack vectors, and required security controls. The threat register established here governs the security requirements for all downstream architecture components and is the primary evidence artifact for SOC 2 and ISO 27001 control mapping.

# 1. Scope & Methodology

## 1.1 Threat Modeling Scope
This threat model covers the complete attack surface of the Enterprise Container Registry, including:

- Azure Container Registry (ACR) service and its management plane

- Token Broker service — the custom entitlement-enforcement authentication intermediary

- Entitlement System integration channel

- CI/CD pipeline identity and push path (SDLC consumers)

- Customer pull path — all consumer types defined in [DOC-002](DOC-002_Stakeholder_Consumer_Analysis.md)

- Network perimeter — private endpoints, VNet configuration, edge connectivity

- Key management — Azure Key Vault, signing keys, customer-managed encryption keys

- Observability and audit pipeline

- WASM artifact storage and distribution


## 1.2 Methodology: STRIDE per Element
This threat model applies the STRIDE per Element (SpE) methodology, systematically evaluating each data flow and component in the system architecture against all six STRIDE threat categories:

| **STRIDE Category** | **Threat Type** | **Registry-Specific Concern** |
| --- | --- | --- |
| S — Spoofing | Identity impersonation | Impersonating a CI/CD pipeline identity to push malicious images; impersonating a customer to pull unauthorized images |
| T — Tampering | Data integrity violation | Modifying container images or manifests in transit or at rest; injecting malicious layers into the build pipeline |
| R — Repudiation | Denial of actions | A product team denying an unauthorized push; a customer denying a pull that contributed to a security incident |
| I — Information Disclosure | Unauthorized data access | A customer discovering the existence or contents of repositories they are not entitled to; credential exfiltration |
| D — Denial of Service | Availability disruption | Overwhelming the Token Broker or ACR with requests to prevent legitimate customer pulls; storage exhaustion |
| E — Elevation of Privilege | Access escalation | A product team member gaining push access to another team's namespace; a customer gaining access to non-entitled images |


## 1.3 Risk Scoring (DREAD)
Each threat is scored using a simplified DREAD model to determine the risk level:

| **Risk Level** | **Score Range** | **Response SLO** |
| --- | --- | --- |
| CRITICAL | DREAD 9–10 — Severe business impact, high likelihood, broad scope | Must be addressed before production deployment. Architecture review gate. |
| HIGH | DREAD 7–8 — Significant impact, moderate-high likelihood | Must be addressed before production deployment. Documented exception required if deferred. |
| MEDIUM | DREAD 4–6 — Moderate impact or low likelihood | Must be addressed within 90 days of initial deployment. |
| LOW | DREAD 1–3 — Limited impact, low likelihood | Addressed in backlog. Documented and accepted residual risk. |

# 2. System Decomposition & Trust Boundaries

## 2.1 System Components
The following components are in scope for this threat model. Each represents a potential attack target or trust transition point:

| **Component ID** | **Component** | **Type** | **Trust Level** | **Key Assets** |
| --- | --- | --- | --- | --- |
| C-01 | Azure Container Registry (ACR) | Azure PaaS Service | Trusted — Azure-managed | Image layers, manifests, artifact metadata, repository namespace structure |
| C-02 | Token Broker Service | Custom-built microservice | Semi-trusted — company-operated, internet-adjacent | Entitlement cache, token signing keys, customer identity mappings |
| C-03 | Entitlement Management System | Corporate system (external dependency) | Trusted — corporate-controlled | Customer entitlement records, product license data |
| C-04 | Azure Key Vault (Signing & CMK) | Azure PaaS Service | Trusted — Azure-managed, customer-controlled keys | Cosign signing keys, Token Broker signing keys, ACR CMK |
| C-05 | CI/CD Pipeline Infrastructure | Azure DevOps / GitHub / Jenkins | Semi-trusted — company-operated | Pipeline OIDC tokens, build artifacts, Dockerfile source |
| C-06 | Customer Kubernetes / Runtime | External — customer-operated | Untrusted perimeter — external | imagePullSecrets, deployed container workloads |
| C-07 | Edge Nodes (k3s, Docker, Portainer) | External — customer-operated | Untrusted perimeter — external, low-trust network | Local image cache, credential configuration files |
| C-08 | Developer Workstations | Internal — employee devices | Low-trust — endpoints, subject to compromise | az acr login tokens, Docker credentials |
| C-09 | Azure Monitor / Log Analytics | Azure PaaS Service | Trusted — Azure-managed | Audit logs, access telemetry, security events |
| C-10 | wasmCloud / Cosmonic Control Runtime | External — customer-operated | Untrusted perimeter — external | WASM component artifacts, OCI credentials, capability configurations |


## 2.2 Trust Boundaries
The following trust boundaries define where authentication and authorization decisions must be enforced. Data flows crossing a trust boundary are the primary focus of STRIDE analysis:

| **Boundary ID** | **Trust Boundary** | **Crosses Between** | **Authentication Required** | **Key Risk** |
| --- | --- | --- | --- | --- |
| TB-01 | Internet / ACR Private Endpoint | Public internet → Azure Private Network | Yes — TLS mutual + Entra ID token | Unauthenticated access; credential relay attacks |
| TB-02 | Token Broker → Entitlement System | Token Broker VNet → Entitlement API endpoint | Yes — mutual TLS + service identity | Entitlement data poisoning; API abuse |
| TB-03 | Token Broker → ACR | Token Broker → ACR management API | Yes — Managed Identity | Token Broker privilege escalation; ACR admin key exposure |
| TB-04 | CI/CD Agent → ACR | Corporate VNet / GitHub public → ACR private endpoint | Yes — Workload Identity Federation / Service Principal | Namespace escape; credential theft from pipeline |
| TB-05 | Customer Runtime → Token Broker | Customer network (VPN/internet) → Token Broker endpoint | Yes — customer identity + entitlement validation | Identity spoofing; entitlement bypass |
| TB-06 | Customer Runtime → ACR | Customer network → ACR private endpoint / public | Yes — ACR refresh token (issued by Token Broker) | Token relay; token theft and replay |
| TB-07 | Edge Node → Registry | Intermittent/low-trust network → registry/Token Broker | Yes — Token Broker credential (extended TTL) | Credential exposure on low-trust network; stale token abuse |
| TB-08 | Admin Workstation → Azure Management Plane | Corporate network → Azure Resource Manager | Yes — PIM-activated Entra ID + MFA | Admin credential theft; unauthorized configuration change |
| TB-09 | ACR → Key Vault | ACR service → Azure Key Vault (CMK operations) | Yes — Managed Identity | CMK access revocation; key exfiltration |

# 3. Threat Actor Profiles
Threat actors are characterized by motivation, capability, and access level. Each threat in the register is associated with one or more of the following actor profiles.

| **Actor ID** | **Actor Type** | **Motivation** | **Capability** | **Access Level** | **Example TTPs** |
| --- | --- | --- | --- | --- | --- |
| TA-01 | External Adversary (Nation State / APT) | Intellectual property theft, supply chain compromise, competitive intelligence | Very High — sophisticated tooling, patience, resources | No legitimate access — targets public-facing endpoints and supply chain | Spear phishing of CI/CD engineers; SolarWinds-style build pipeline injection; credential stuffing against Token Broker |
| TA-02 | External Adversary (Cybercriminal) | Financial gain, ransomware, credential resale | High — commodity tooling, automation | No legitimate access — opportunistic | Credential stuffing; token theft via malicious public images; registry enumeration for competitive intel |
| TA-03 | Malicious Customer (Entitlement Abuse) | Access to non-entitled products without paying | Medium — technical customer, API knowledge | Partial — legitimate customer identity with limited entitlements | Token replay from expired entitlement; registry enumeration to discover non-entitled products; horizontal privilege escalation |
| TA-04 | Malicious Insider (Product Team Member) | Access to peer product team intellectual property; sabotage | Medium-High — legitimate internal access, pipeline knowledge | Partial — legitimate namespace access, VNet access | Namespace escape via RBAC misconfiguration; malicious image injection into own namespace affecting downstream CI |
| TA-05 | Malicious Insider (Platform Admin) | Full registry access, evidence destruction | High — privileged access to all components | High — admin access via PIM | Token issuance manipulation; audit log tampering; unauthorized entitlement grant |
| TA-06 | Compromised CI/CD Pipeline | Automated supply chain attack via hijacked build agent | Medium — automated pipeline execution | Partial — namespace-scoped push credentials | Malicious layer injection during build; image tag mutation post-push; exfiltration of pipeline OIDC tokens |
| TA-07 | Compromised Customer Runtime | Lateral movement from a compromised customer cluster | Medium — Kubernetes exploitation techniques | Partial — pull credentials for entitled images | imagePullSecret exfiltration from Kubernetes etcd; credential reuse across clusters; pull-to-execute of backdoored image |

# 4. STRIDE Threat Register
The following threat register documents all identified threats, organized by STRIDE category. Each threat entry includes the affected component, attack surface, associated threat actor, likelihood, impact, risk level, and required security controls.


>** Risk Level Key:**  CRITICAL (must fix before production) │ HIGH (must fix before production, exception if deferred) │ MEDIUM (fix within 90 days) │ LOW (accepted residual risk, documented)


## 4.1 Spoofing Threats
>** T-S-001    [CRITICAL]    Customer identity spoofing to obtain non-entitled registry tokens  STRIDE:   Spoofing**   │  Attacker: TA-02 (Cybercriminal), TA-03 (Malicious Customer)


>** T-S-002    [CRITICAL]    CI/CD pipeline identity impersonation to push malicious images to product namespace  STRIDE:   Spoofing**   │  Attacker: TA-01 (APT), TA-04 (Malicious Insider), TA-06 (Compromised Pipeline)


>** T-S-003    [HIGH]    Token Broker service impersonation — rogue Token Broker serving malicious scoped tokens  STRIDE:   Spoofing**   │  Attacker: TA-01 (APT), TA-06 (Compromised Pipeline)


>** T-S-004    [CRITICAL]    Platform admin identity impersonation via stolen Entra ID credentials  STRIDE:   Spoofing**   │  Attacker: TA-01 (APT), TA-05 (Malicious Insider)


## 4.2 Tampering Threats
>** T-T-001    [CRITICAL]    Container image layer tampering in transit between ACR and customer runtime  STRIDE:   Tampering**   │  Attacker: TA-01 (APT), TA-02 (Cybercriminal)


>** T-T-002    [CRITICAL]    Malicious image injection into product namespace by compromised CI/CD pipeline  STRIDE:   Tampering**   │  Attacker: TA-06 (Compromised Pipeline), TA-04 (Malicious Insider)


>** T-T-003    [HIGH]    Image tag mutation — overwriting an existing image tag with a different manifest post-promotion  STRIDE:   Tampering**   │  Attacker: TA-04 (Malicious Insider), TA-06 (Compromised Pipeline)


>** T-T-004    [HIGH]    Audit log tampering to conceal malicious registry activity  STRIDE:   Tampering**   │  Attacker: TA-05 (Malicious Platform Admin)


>** T-T-005    [HIGH]    WASM component tampering — substitution of wasmCloud component with malicious version  STRIDE:   Tampering**   │  Attacker: TA-01 (APT), TA-06 (Compromised Pipeline)


## 4.3 Repudiation Threats
>** T-R-001    [MEDIUM]    Product team denies unauthorized image push — insufficient push attribution  STRIDE:   Repudiation**   │  Attacker: TA-04 (Malicious Insider)


>** T-R-002    [MEDIUM]    Customer denies registry pull event contributing to security incident  STRIDE:   Repudiation**   │  Attacker: TA-03 (Malicious Customer), TA-07 (Compromised Customer Runtime)


## 4.4 Information Disclosure Threats
>** T-I-001    [HIGH]    Repository enumeration — customer discovers existence of non-entitled product repositories  STRIDE:   Information Disclosure**   │  Attacker: TA-03 (Malicious Customer)


>** T-I-002    [HIGH]    Credential exfiltration from customer Kubernetes cluster — imagePullSecret theft  STRIDE:   Information Disclosure**   │  Attacker: TA-07 (Compromised Customer Runtime)


>** T-I-003    [CRITICAL]    Entitlement data exfiltration from Token Broker cache  STRIDE:   Information Disclosure**   │  Attacker: TA-01 (APT), TA-05 (Malicious Admin)


>** T-I-004    [MEDIUM]    Container image intellectual property exfiltration via entitled customer  STRIDE:   Information Disclosure**   │  Attacker: TA-03 (Malicious Customer), TA-07 (Compromised Customer Runtime)


>** T-I-005    [MEDIUM]    Edge node credential file exposure on low-trust network or compromised device  STRIDE:   Information Disclosure**   │  Attacker: TA-02 (Cybercriminal), TA-01 (APT)


## 4.5 Denial of Service Threats
>** T-D-001    [CRITICAL]    Token Broker DDoS — overwhelming authentication endpoint to prevent customer pull access  STRIDE:   Denial of Service**   │  Attacker: TA-01 (APT), TA-02 (Cybercriminal)


>** T-D-002    [MEDIUM]    Registry storage exhaustion — attacker pushes large volumes of data to exhaust ACR storage quota  STRIDE:   Denial of Service**   │  Attacker: TA-04 (Malicious Insider), TA-06 (Compromised Pipeline)


>** T-D-003    [HIGH]    ACR regional availability failure impacting customer pulls  STRIDE:   Denial of Service**   │  Attacker: Environmental (Azure region outage), TA-01 (APT — region-targeted)


## 4.6 Elevation of Privilege Threats
>** T-E-001    [HIGH]    Product team namespace escape — CI/CD identity gaining push access to peer product namespace  STRIDE:   Elevation of Privilege**   │  Attacker: TA-04 (Malicious Insider), TA-06 (Compromised Pipeline)


>** T-E-002    [CRITICAL]    Customer entitlement escalation — obtaining tokens for non-entitled repositories  STRIDE:   Elevation of Privilege**   │  Attacker: TA-03 (Malicious Customer)


>** T-E-003    [CRITICAL]    Token Broker service account privilege escalation to ACR admin  STRIDE:   Elevation of Privilege**   │  Attacker: TA-01 (APT), TA-05 (Malicious Admin)


>** T-E-004    [MEDIUM]    Kubernetes workload escape — container breakout to access imagePullSecret or node credentials  STRIDE:   Elevation of Privilege**   │  Attacker: TA-07 (Compromised Customer Runtime)


# 5. Security Control Catalog
The following table consolidates all security controls referenced in the threat register, mapping each to the threats it mitigates, the responsible architecture component, and the implementing document.

| **Control ID** | **Control** | **Threat(s) Mitigated** | **Component** | **Implementing Document** |
| --- | --- | --- | --- | --- |
| SC-01 | Workload Identity Federation for CI/CD pipelines (no long-lived credentials) | T-S-002, T-I-002 | CI/CD → ACR (TB-04) | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md), [DOC-015](../phase-5-sdlc/DOC-015_CICD_Pipeline_Integration.md) |
| SC-02 | Token Broker: server-side scope computation from entitlement system | T-E-002, T-S-001, T-I-001 | Token Broker (C-02) | [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) |
| SC-03 | ACR scoped refresh tokens (cryptographically signed, server-issued) | T-S-003, T-E-002 | Token Broker → ACR (TB-05, TB-06) | [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) |
| SC-04 | ACR ABAC repository permissions for namespace isolation | T-E-001, T-S-002 | ACR (C-01) | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md), [DOC-010](../phase-3-entitlement/DOC-010_SDLC_RBAC_Design.md) |
| SC-05 | Cosign image signing with Key Vault-backed keys | T-T-001, T-T-002, T-T-003, T-T-005 | CI/CD → Key Vault → ACR | [DOC-012](../phase-4-supply-chain/DOC-012_Image_Signing_Provenance.md) |
| SC-06 | OCI manifest digest verification by container runtime | T-T-001 | Customer runtime (C-06, C-07) | [DOC-011](../phase-3-entitlement/DOC-011_Customer_Entitlement_Access_Flow.md) |
| SC-07 | Admission controller: enforce signature verification before scheduling | T-T-002, T-S-002 | Customer Kubernetes (C-06) | [DOC-012](../phase-4-supply-chain/DOC-012_Image_Signing_Provenance.md) |
| SC-08 | ACR tag immutability policy on production repositories | T-T-003, T-T-005 | ACR (C-01) | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md) |
| SC-09 | Immutable Log Analytics workspace + immutable audit log storage | T-T-004, T-R-001, T-R-002 | Log Analytics (C-09) | [DOC-019](../phase-6-operations/DOC-019_Audit_Logging_Compliance.md) |
| SC-10 | Entra ID PIM + MFA + Conditional Access for admin identities | T-S-004, T-E-003 | Azure Management Plane (TB-08) | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) |
| SC-11 | Private endpoints for ACR — no public endpoint | T-S-001, T-D-001, T-I-002 | ACR network (TB-01) | [DOC-005](../phase-2-platform/DOC-005_Network_Topology_Connectivity.md) |
| SC-12 | Azure DDoS Protection + API Management rate limiting for Token Broker | T-D-001 | Token Broker (C-02) | [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) |
| SC-13 | Token Broker entitlement cache with event-driven invalidation (TTL ≤ 15 min) | T-D-001, T-E-002, T-S-001 | Token Broker (C-02) | [DOC-008](../phase-3-entitlement/DOC-008_Entitlement_Integration_Architecture.md), [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) |
| SC-14 | ACR geo-replication (active-active, ≥ 2 regions) | T-D-003 | ACR (C-01) | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-021](../phase-6-operations/DOC-021_Disaster_Recovery_BCP.md) |
| SC-15 | Short-lived tokens: customer 24h / edge 72h | T-I-002, T-I-005, T-E-004 | Token Broker (C-02) | [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) |
| SC-16 | Customer-managed encryption keys (CMK) via Azure Key Vault | T-I-003, T-I-004 | ACR + Key Vault (C-01, C-04) | [DOC-004](../phase-2-platform/DOC-004_ACR_Service_Architecture.md), [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) |
| SC-17 | Emergency token revocation via entitlement system event | T-I-002, T-S-001, T-E-002 | Token Broker + Entitlement (C-02, C-03) | [DOC-008](../phase-3-entitlement/DOC-008_Entitlement_Integration_Architecture.md), [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) |
| SC-18 | SLSA provenance attestation in CI/CD pipeline | T-T-002, T-R-001 | CI/CD pipeline (C-05) | [DOC-012](../phase-4-supply-chain/DOC-012_Image_Signing_Provenance.md), [DOC-015](../phase-5-sdlc/DOC-015_CICD_Pipeline_Integration.md) |
| SC-19 | Vulnerability scanning gate (Defender for Containers) — blocks on Critical/High CVE | T-T-002 | CI/CD → ACR pipeline | [DOC-013](../phase-4-supply-chain/DOC-013_Vulnerability_Scanning_Policy_Gate.md) |
| SC-20 | Token Broker Managed Identity: ACR Token Writer role only (least privilege) | T-E-003 | Token Broker → ACR (TB-03) | [DOC-006](../phase-2-platform/DOC-006_IAM_Architecture.md) |
| SC-21 | Token Broker penetration test + entitlement boundary regression tests | T-E-002, T-S-001 | Token Broker (C-02) | [DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md) (test annex) |
| SC-22 | Separation of duty: ACR admins cannot administer audit log workspace | T-T-004 | Log Analytics (C-09) | [DOC-019](../phase-6-operations/DOC-019_Audit_Logging_Compliance.md) |
| SC-23 | External Secrets Operator for imagePullSecret management in Kubernetes | T-I-002, T-E-004 | Customer Kubernetes (C-06) | [DOC-011](../phase-3-entitlement/DOC-011_Customer_Entitlement_Access_Flow.md) |
| SC-24 | WASM component signing (Cosign) + Cosmonic Control signature verification | T-T-005 | wasmCloud / Cosmonic (C-10) | [DOC-007](../phase-2-platform/DOC-007_WASM_Artifact_Registry_Extension.md), [DOC-012](../phase-4-supply-chain/DOC-012_Image_Signing_Provenance.md) |

# 6. Zero-Trust Architecture Assumptions
The threat model is grounded in the following zero-trust assumptions. These are architecture axioms — no downstream design may assume these are false:

| **Assumption ID** | **Zero-Trust Assumption** | **Implication** |
| --- | --- | --- |
| ZT-01 | Network location is not a trust signal | Private endpoint access or VNet membership does not grant any registry access. Authentication and authorization are required regardless of network path. |
| ZT-02 | All credentials are considered potentially compromised | Architecture must assume that any static credential (service principal, admin password) may be exfiltrated. Dynamic credentials (WIF, short-lived tokens, PIM) are required for all privileged operations. |
| ZT-03 | All CI/CD pipelines are potentially compromised | Build artifacts must be validated for integrity independently of the build pipeline. Image signing happens outside the build agent. SLSA provenance provides verifiable build environment attestation. |
| ZT-04 | All customer runtimes are potentially compromised | The registry must not trust any signal from the customer runtime about its own trustworthiness. Entitlement decisions are made exclusively at the Token Broker, not based on client-reported attributes. |
| ZT-05 | All edge nodes are operating in hostile network environments | Edge credential design assumes the credential file may be readable by a network adversary. Short TTL and limited scope are the compensating controls — not network security. |
| ZT-06 | The entitlement system is authoritative and auditable | The entitlement system is trusted as the source of truth for customer access rights. Any discrepancy between the entitlement system and registry access is a security incident. |
| ZT-07 | Insider threat is a credible and persistent threat model | PIM, ABAC namespace isolation, and separation of duty controls are not optional — they are required architectural controls against insider threat, not just external adversaries. |

# 7. Compliance Control Mapping
The following table maps the security controls in this threat model to the relevant control frameworks. This mapping is the basis for the compliance evidence matrix in [DOC-019](../phase-6-operations/DOC-019_Audit_Logging_Compliance.md).

| **Control** | **SOC 2 Type II** | **ISO 27001:2022** | **NIST CSF 2.0** | **CIS Controls v8** |
| --- | --- | --- | --- | --- |
| SC-01 WIF / No long-lived credentials | CC6.1, CC6.6 | A.9.2.3, A.9.4.2 | PR.AA-01 | CIS 5.6 |
| SC-02/03 Token Broker scope enforcement | CC6.1, CC6.3 | A.9.4.1 | PR.AA-05 | CIS 6.7 |
| SC-04 ABAC namespace isolation | CC6.3 | A.9.1.2 | PR.AA-05 | CIS 6.1 |
| SC-05/07 Image signing + admission control | CC7.1 | A.14.2.1 | PR.DS-06 | CIS 2.5 |
| SC-09 Immutable audit logs | CC7.2, CC4.1 | A.12.4.1, A.12.4.3 | DE.CM-03 | CIS 8.2, 8.11 |
| SC-10 PIM + MFA | CC6.1, CC6.6 | A.9.4.2 | PR.AA-03 | CIS 5.5, 6.5 |
| SC-11 Private endpoints | CC6.6 | A.13.1.3 | PR.IR-01 | CIS 12.3 |
| SC-14 Geo-replication | A.1.1 | A.17.2.1 | RC.RP-04 | CIS 11.3 |
| SC-17 Emergency revocation | CC6.2 | A.9.2.6 | PR.AA-05 | CIS 5.3 |
| SC-19 Vulnerability scanning | CC7.1 | A.12.6.1 | ID.RA-01 | CIS 7.4 |

# 8. Security Posture Statement
Upon full implementation of all security controls identified in this threat model, the Enterprise Container Registry will achieve the following security posture:


> *The registry enforces a Zero Trust access model in which no consumer — internal or external — receives any repository access without explicit, verified authentication and authorization. Customer repository visibility is cryptographically enforced at the token layer: customers cannot enumerate, discover, or access any repository to which they do not hold an active entitlement. All image artifacts are signed, scanned, and provenance-attested before distribution. Audit records are immutable, complete, and retained for forensic and compliance purposes. The architecture presents no single point of failure for either availability or security enforcement.*


Security posture is validated through:

- Pre-production penetration test focused on Token Broker entitlement enforcement and namespace isolation

- Continuous security scanning of all deployed components via Microsoft Defender for Containers and Defender for Cloud

- Quarterly RBAC and permission audit against the principle of least privilege

- Semi-annual chaos engineering exercises validating resilience under attack conditions

- Annual third-party security assessment against SOC 2 and ISO 27001 criteria

# 9. Residual Risk Register
The following residual risks are documented and formally accepted by the architecture. They represent threats where the implemented controls reduce but do not eliminate risk, and where the residual risk has been consciously accepted given cost, feasibility, or inherent trade-off constraints.

| **Risk ID** | **Description** | **Residual Level** | **Acceptance Rationale** | **Review Period** |
| --- | --- | --- | --- | --- |
| RR-01 | IP extraction by entitled customer (T-I-004) | MEDIUM | Entitled customers legitimately possess images. Registry cannot prevent extraction. Product-layer controls (obfuscation, license enforcement in application) are the appropriate mitigations outside registry scope. | Annual |
| RR-02 | 72h revocation lag for Tier 2 edge nodes (T-I-005) | MEDIUM | Extended TTL is operationally necessary for intermittently-connected edge nodes. Compensating controls: scope limitation, physical device security guidance, incident response procedure for compromised edge nodes. | Quarterly |
| RR-03 | Customer cluster container escape enabling credential theft (T-E-004) | MEDIUM | Customer cluster security posture is outside registry control. Registry-side mitigations (short TTL, External Secrets Operator guidance, emergency revocation) are implemented. Customer responsibility documented. | Semi-annual |
| RR-04 | Air-gapped bundle with no automated revocation (T-I-005 Tier 4) | HIGH — Accepted | Air-gapped deployments have no connectivity for revocation. Compensating controls: physical media destruction procedure, strict bundle issuance governance, contract terms requiring customer bundle management. | Annual |
| RR-05 | Sophisticated supply chain injection (T-T-002) not detected by signature/scan | MEDIUM | Novel zero-day malware or obfuscated supply chain attacks may evade signature-based scanning. Compensating controls: SLSA provenance, build reproducibility, anomaly detection, rapid response capability. | Quarterly |

# 10. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial threat model — STRIDE per Element analysis, threat register, control catalog, compliance mapping, residual risk register |
| 1.0 | TBD | First approved version — pending CISO review and Architecture Review Board sign-off |


>** Required Approvals:**  Chief Information Security Officer (primary approver), Chief Architect, Head of Platform Engineering. This document is SECURITY SENSITIVE — distribution restricted to architecture team, CISO office, and senior engineering leadership.


	CONFIDENTIAL | Classification: Internal Architecture — SECURITY SENSITIVE	Page  of
