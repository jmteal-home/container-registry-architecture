---
document_id: DOC-005
title: "Network Topology & Connectivity"
phase: "PH-2 — Platform Architecture"
priority: P0
status: DRAFT
classification: "Internal Architecture — Confidential"
date: "April 2026"
corpus: "Enterprise Container Registry Architecture"
---

# DOC-005: Network Topology & Connectivity

| Document ID | DOC-005 |
| --- | --- |
| Phase | PH-2 — Platform Architecture |
| Version | 1.0 — Initial Release |
| Classification | Internal Architecture — Confidential |
| Status | DRAFT — Pending Architecture Review |
| Date | April 2026 |
| Depends On | [DOC-004](DOC-004_ACR_Service_Architecture.md) (ACR Service Architecture) |
| Priority | P0 |

This document defines the complete network architecture for the Enterprise Container Registry platform. It covers the hub-spoke VNet topology, private endpoint configuration per region, Azure Private DNS zones, DNS resolution flows, firewall rules, and connectivity patterns for all consumer types including cloud Kubernetes, on-premises, edge, and external customer networks.

# 1. Network Architecture Principles
The network architecture is governed by the zero-trust principle ZT-01 (network location is not a trust signal) from [DOC-003](../phase-1-foundations/DOC-003_Threat_Model_Security_Posture.md). Private endpoints are a defence-in-depth control, not a substitute for authentication and authorization. The following principles govern all network design decisions:

| **Principle** | **Implication** |
| --- | --- |
| No public endpoints for production ACR | Public network access is disabled (publicNetworkAccess: 'Disabled'). All ACR, Key Vault, and Token Broker access routes through private endpoints within authorized VNets. |
| Private DNS for all Azure service endpoints | Azure Private DNS zones resolve registry FQDNs to private IP addresses. Public DNS resolution returns private IPs only for authorized VNets — not internet-routable addresses. |
| Network segmentation by function | Separate subnets for: ACR private endpoints, Token Broker service, management/bastion, and CI/CD agent pools. Subnet-level NSGs enforce east-west traffic control. |
| Hub-spoke topology for corporate network | Corporate VNets use hub-spoke topology. Registry private endpoints are deployed in the hub VNet with spoke peering for CI/CD and management traffic. |
| Customer network connectivity is external | Customer networks are never peered with the corporate VNet. Customers access the Token Broker and ACR via public internet with TLS — protected by authentication and DDoS controls. |
| Edge site connectivity is customer-managed | Edge sites connect via customer-managed VPN, ExpressRoute, or internet. The registry architecture documents supported patterns but does not manage customer network infrastructure. |

# 2. Hub-Spoke VNet Topology

## 2.1 VNet Design Overview
The Enterprise Container Registry uses a hub-spoke VNet topology in each Azure region where ACR is deployed. The hub VNet hosts shared services including private endpoints, DNS resolvers, and network security perimeter. Spoke VNets connect to the hub for access to registry services.

| **SPOKE — CI/CD** vnet-cicd-eastus2 10.10.0.0/22 ADO / GitHub / Jenkins agents | **HUB VNet** vnet-registry-hub-eastus2 10.0.0.0/22 ACR private endpoints Token Broker ACA Key Vault private endpoint Azure Private DNS Resolver Azure Firewall (optional) | **SPOKE — Management** vnet-mgmt-eastus2 10.20.0.0/24 Bastion, admin jump hosts, monitoring agents |
| --- | --- | --- |

↑ Hub-spoke topology — one hub VNet per Azure region, containing all private endpoints and shared network services. CI/CD and management spoke VNets peer to the hub for registry access.


## 2.2 VNet Address Space Allocation
| **VNet** | **Region** | **Address Space** | **Subnets** | **Purpose** |
| --- | --- | --- | --- | --- |
| vnet-registry-hub-eastus2 | East US 2 | 10.0.0.0/22 | snet-acr-pe (10.0.0.0/27), snet-tokenbroker (10.0.1.0/27), snet-keyvault-pe (10.0.2.0/29), snet-dnsresolver (10.0.3.0/28) | Hub: private endpoints for ACR, Key Vault; Token Broker ACA; DNS Resolver |
| vnet-registry-hub-westus2 | West US 2 | 10.1.0.0/22 | snet-acr-pe (10.1.0.0/27), snet-tokenbroker (10.1.1.0/27), snet-keyvault-pe (10.1.2.0/29), snet-dnsresolver (10.1.3.0/28) | Hub: Western region replica private endpoints + Token Broker |
| vnet-cicd-eastus2 | East US 2 | 10.10.0.0/22 | snet-ado-agents (10.10.0.0/24), snet-github-runners (10.10.1.0/24), snet-jenkins (10.10.2.0/24) | CI/CD pipeline agent pools — peered to hub for ACR push access |
| vnet-mgmt-eastus2 | East US 2 | 10.20.0.0/24 | snet-bastion (10.20.0.0/26), snet-admin (10.20.0.64/26) | Management and operations — admin access to registry management plane |
| vnet-registry-hub-westeurope | West Europe | 10.2.0.0/22 | snet-acr-pe (10.2.0.0/27), snet-tokenbroker (10.2.1.0/27), snet-dnsresolver (10.2.3.0/28) | Hub: EU region replica (Phase 2) |

# 3. Private Endpoint Configuration

## 3.1 Private Endpoint Overview
Private endpoints inject a private NIC into the designated subnet with a private IP address from the subnet's address space. All traffic to ACR, Key Vault, and Token Broker routes through these private IPs without traversing the public internet — even when the source is within Azure.

| **Resource** | **Private Endpoint Name** | **Subnet** | **DNS Zone** | **Private IP** | **Sub-resource** |
| --- | --- | --- | --- | --- | --- |
| ACR (East US 2) | pe-acr-eastus2 | snet-acr-pe (hub) | privatelink.azurecr.io | 10.0.0.4 | registry |
| ACR (East US 2) — data endpoint | pe-acr-data-eastus2 | snet-acr-pe (hub) | privatelink.eastus2.data.azurecr.io | 10.0.0.5 | registry_data (data plane) |
| ACR (West US 2) | pe-acr-westus2 | snet-acr-pe (hub-westus2) | privatelink.azurecr.io | 10.1.0.4 | registry |
| ACR (West US 2) — data endpoint | pe-acr-data-westus2 | snet-acr-pe (hub-westus2) | privatelink.westus2.data.azurecr.io | 10.1.0.5 | registry_data |
| Key Vault (CMK) | pe-keyvault-eastus2 | snet-keyvault-pe (hub) | privatelink.vaultcore.azure.net | 10.0.2.4 | vault |
| Key Vault (CMK secondary) | pe-keyvault-westus2 | snet-keyvault-pe (hub-westus2) | privatelink.vaultcore.azure.net | 10.1.2.4 | vault |
| Azure Cache for Redis (Token Broker) | pe-redis-eastus2 | snet-tokenbroker (hub) | privatelink.redis.cache.windows.net | 10.0.1.20 | redisCache |


>** ACR Data Endpoint:**  ACR requires TWO private endpoints per region: one for the registry login server (authentication) and one for the regional data endpoint (layer blob download). Both must be configured or image pulls will fail — authentication succeeds but layer download fails. Use az acr show --query 'loginServer,dataEndpointEnabled' to verify configuration.


# 4. Azure Private DNS Zone Architecture

## 4.1 DNS Zone Design
Azure Private DNS zones resolve private endpoint FQDNs to their private IP addresses for resources within linked VNets. Without correct DNS configuration, clients resolve the FQDN to the public IP (which is blocked by the firewall) rather than the private IP.

| **Private DNS Zone** | **Linked VNets** | **Records** | **Purpose** |
| --- | --- | --- | --- |
| privatelink.azurecr.io | All hub VNets (all regions), CI/CD spoke VNets, management spoke VNets | A record: {registry-name}.azurecr.io → private IP of pe-acr-* per region | Resolves ACR login server FQDN to private IP for authentication (docker login, az acr login, token issuance) |
| privatelink.eastus2.data.azurecr.io | hub-eastus2, CI/CD spoke | A record: {registry-name}.eastus2.data.azurecr.io → 10.0.0.5 | Resolves ACR data endpoint for East US 2 layer blob downloads |
| privatelink.westus2.data.azurecr.io | hub-westus2 | A record: {registry-name}.westus2.data.azurecr.io → 10.1.0.5 | Resolves ACR data endpoint for West US 2 |
| privatelink.vaultcore.azure.net | All hub VNets, management spoke | A record: {vault-name}.vault.azure.net → private IP | Resolves Key Vault FQDN for CMK operations and Token Broker secret access |
| privatelink.redis.cache.windows.net | hub-eastus2, hub-westus2 | A record: {redis-name}.redis.cache.windows.net → private IP | Resolves Redis cache for Token Broker entitlement cache |
| privatelink.azurecontainerapps.io | hub VNets | A record: Token Broker ACA endpoint → private IP | Resolves Token Broker endpoint for internal consumers (CI/CD VNet resolution) |


## 4.2 DNS Resolution Architecture
Correct DNS resolution is critical — if a client resolves ACR to its public IP (which is blocked), pulls fail silently with a connection refused or timeout error rather than an authentication error. The following resolution chain must be correct for all client paths:

| **Client Location** | **DNS Resolution Path** | **Expected Resolution** | **Validation Check** |
| --- | --- | --- | --- |
| Azure VNet (hub or spoke, linked) | Azure DNS (168.63.129.16) → Private DNS Zone privatelink.azurecr.io | Private IP (e.g., 10.0.0.4) | nslookup {registry}.azurecr.io from within VNet returns private IP |
| CI/CD Agent (spoke VNet, peered to hub) | Azure DNS → spoke inherits hub DNS zone links via VNet peering | Private IP via hub DNS zone | nslookup from agent runner returns private IP |
| On-premises (via ExpressRoute/VPN) | On-premises DNS → Azure Private DNS Resolver (forwarding rule to hub) | Private IP | Requires DNS forwarding rule on-premises → Azure Private DNS Resolver IP in hub |
| External customer (internet) | Public DNS (Azure DNS global) | NXDOMAIN or public IP (blocked by firewall) | Customer does NOT need to resolve ACR directly — pulls are authenticated via Token Broker which is internet-accessible |
| Edge site (connected registry) | Local DNS or direct IP reference to connected registry local endpoint | Connected registry local IP | Connected registry has its own local IP — no ACR FQDN resolution needed at edge for runtime pulls |


## 4.3 Azure Private DNS Resolver
The Azure Private DNS Resolver (in the hub VNet) handles DNS forwarding for on-premises clients connecting via ExpressRoute or VPN. On-premises DNS servers forward registry-related queries to the Private DNS Resolver inbound endpoint, which resolves them against the linked Private DNS zones.

- Inbound endpoint: deployed in snet-dnsresolver subnet (10.0.3.4) in hub VNet

- Forwarding ruleset: configured on on-premises DNS server to forward *.azurecr.io queries to the inbound endpoint IP

- Outbound endpoint: used if Azure resources need to resolve on-premises DNS names — required for Token Broker → entitlement system DNS resolution if entitlement system is on-premises

# 5. Network Security Group & Firewall Rules

## 5.1 Subnet NSG Rules
Network Security Groups enforce subnet-level traffic control. The following table defines the NSG rules for each key subnet. Rules are listed in priority order — lower numbers take precedence.


## snet-acr-pe (ACR Private Endpoint Subnet)
| **Priority** | **Direction** | **Source** | **Destination** | **Port** | **Protocol** | **Action** | **Purpose** |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 100 | Inbound | 10.0.0.0/8 (corporate RFC1918) | 10.0.0.4/32, 10.0.0.5/32 | 443 | TCP | Allow | HTTPS from corporate VNets to ACR private endpoints |
| 110 | Inbound | AzureCloud service tag | 10.0.0.4/32 | 443 | TCP | Allow | Azure Traffic Manager health probes to ACR |
| 4000 | Inbound | Any | Any | Any | Any | Deny | Default deny — block all other inbound |
| 100 | Outbound | 10.0.0.4/32 | 10.0.2.4/32 | 443 | TCP | Allow | ACR private endpoint → Key Vault for CMK operations |
| 4000 | Outbound | Any | Any | Any | Any | Deny | Default deny outbound |


## snet-tokenbroker (Token Broker Subnet)
| **Priority** | **Direction** | **Source** | **Destination** | **Port** | **Protocol** | **Action** | **Purpose** |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 100 | Inbound | Internet | Token Broker ACA IP | 443 | TCP | Allow | Customer authentication requests from internet (via Azure Front Door WAF) |
| 110 | Inbound | 10.0.0.0/8 | Token Broker ACA IP | 443 | TCP | Allow | Internal callers (CI/CD health checks, monitoring) |
| 4000 | Inbound | Any | Any | Any | Any | Deny | Default deny |
| 100 | Outbound | Token Broker ACA IP | 10.0.0.4/32 | 443 | TCP | Allow | Token Broker → ACR private endpoint for token issuance API |
| 110 | Outbound | Token Broker ACA IP | Entitlement System IP / FQDN | 443 | TCP | Allow | Token Broker → Entitlement system (adjust to actual IP range or use FQDN-based rule via Azure Firewall) |
| 120 | Outbound | Token Broker ACA IP | 10.0.2.4/32 | 443 | TCP | Allow | Token Broker → Key Vault for token signing key |
| 130 | Outbound | Token Broker ACA IP | 10.0.1.20/32 | 6380 | TCP | Allow | Token Broker → Redis Cache (TLS port 6380) |
| 140 | Outbound | Token Broker ACA IP | AzureMonitor service tag | 443 | TCP | Allow | OpenTelemetry export to Azure Monitor |
| 4000 | Outbound | Any | Any | Any | Any | Deny | Default deny |


## 5.2 Azure Firewall Integration (Optional)
For environments requiring FQDN-based filtering or centralized egress control (e.g., for Token Broker → Entitlement system connectivity or CI/CD agent internet access), Azure Firewall is deployed in the hub VNet:

- Azure Firewall Standard or Premium in hub VNet — dedicated AzureFirewallSubnet (10.0.0.128/26)

- Application rule collection: allow *.azurecr.io (login + data endpoints) for CI/CD agents and on-premises

- Network rule collection: allow ACR service tag on port 443 as fallback for non-FQDN resolution scenarios

- CI/CD spoke VNets route 0.0.0.0/0 via Azure Firewall UDR — all internet egress from agents is inspected

- Azure Firewall is not in the data path for customer pulls (external customer → Token Broker → ACR is external-facing, not via corporate Firewall)

# 6. Consumer Connectivity Patterns

## 6.1 Internal SDLC Consumers
| **Consumer** | **Connectivity Path** | **DNS Resolution** | **Auth Flow** | **Network Controls** |
| --- | --- | --- | --- | --- |
| Azure DevOps Hosted Agents | Azure DevOps SaaS → Internet → Azure Front Door → Token Broker → ACR private endpoint via VNet | ADO agent resolves ACR FQDN — may require ACR IP allow-list if not using private endpoint from ADO | OIDC WIF token → Token Broker (no — ADO agents use direct ABAC)… actually ADO agents use WIF direct to ACR | Note: Azure-hosted ADO agents originate from the public internet. Consider self-hosted agents in the CI/CD spoke VNet for private endpoint access. See ADR reference. |
| Self-hosted ADO Agents (in CI/CD spoke VNet) | CI/CD spoke VNet → VNet peering → Hub VNet → ACR private endpoint | Azure DNS → Private DNS zone → private IP (10.0.0.4) | WIF OIDC → Entra ID → ABAC-scoped ACR token | NSG snet-ado-agents: allow 443 outbound to snet-acr-pe; private DNS zone linked to CI/CD spoke |
| GitHub Actions (Azure-hosted) | GitHub SaaS → Internet → ACR. Public endpoint is disabled — GitHub Actions must use self-hosted runners in VNet. | N/A — requires self-hosted runner in VNet | WIF → Entra ID → ABAC token | GitHub IP ranges can be allow-listed as exception, but self-hosted runners in VNet are strongly preferred (see ADR) |
| Self-hosted GitHub Runners (in CI/CD spoke) | Same as self-hosted ADO agents | Same | Same | Same NSG rules |
| Jenkins (in CI/CD spoke VNet) | CI/CD spoke VNet → Hub → ACR private endpoint | Private DNS zone via hub DNS | Service Principal → Key Vault → ACR push token | NSG rules same as above |
| Developer Workstation | Corporate LAN → ExpressRoute/VPN → Hub VNet → ACR private endpoint | On-premises DNS forwards *.azurecr.io to Azure Private DNS Resolver in hub | az acr login (Entra ID interactive) → ABAC pull token | ExpressRoute/VPN as corporate network boundary; on-premises DNS forwarding mandatory |


## 6.2 External Customer Consumers
External customers do not access ACR private endpoints directly. The customer connectivity model routes through the public-facing Token Broker, which acts as the sole customer-accessible entry point to the registry ecosystem:

| **Consumer** | **Connectivity to Token Broker** | **Token Broker → ACR** | **Customer → ACR (post-token)** | **Network Controls** |
| --- | --- | --- | --- | --- |
| AKS (in Azure, customer subscription) | Customer Azure VNet → Internet → Azure Front Door WAF → Token Broker ACA (public-facing) | Token Broker in hub VNet → ACR private endpoint (private path) | Customer AKS → Internet → ACR FQDN (public DNS, but public endpoint disabled — requires VNet integration or PE in customer sub) | For customers using ACR with their own AKS: ACR private endpoint can be created in customer subscription via ACR Private Link cross-subscription. Documented in customer onboarding guide. |
| On-premises Kubernetes | Customer datacenter → Internet or ExpressRoute → Token Broker → Token received → On-prem K8s → Internet/ExpressRoute → ACR | Token Broker (private path to ACR) | On-prem K8s → Internet HTTPS to ACR FQDN. ACR public endpoint is disabled — customer must have VPN/ExpressRoute or use Token Broker-issued credential for HTTPS pull over internet. | Customer must have internet HTTPS access to ACR on port 443. Consider advising customer to configure local DNS override for ACR FQDN if using dedicated internet egress with source IP allow-listing. |
| k3s (Edge) | Edge site → Internet → Token Broker (token refresh during connectivity) | Token Broker private path | k3s node → Internet HTTPS → ACR (during connectivity window) | Extended TTL token (72h) reduces frequency of Token Broker connectivity requirement |
| Docker / Portainer | Same as on-premises Kubernetes | Same | Same | Same |
| wasmCloud (Cosmonic) | Same — OCI pull uses standard registry protocol | Same | Same | WASM OCI artifacts pulled over same path as container images |


>** Customer ACR Connectivity Note:**  ACR's public network access is disabled. External customers pulling images over the public internet require either: (a) the company to enable ACR public endpoint (not recommended — violates constraint C-003's spirit), or (b) customers to use a Token Broker-issued credential with HTTPS pull over the internet using the ACR data endpoint (which resolves publicly to a CDN-backed endpoint when public access is enabled for the data plane only). Architecture team to confirm ACR behavior when publicNetworkAccess is Disabled but dataEndpointEnabled is true — this may allow data plane pulls while blocking management plane.


# 7. On-Premises & Hybrid Connectivity

## 7.1 ExpressRoute Integration
For enterprise customers with ExpressRoute connectivity to Azure, the registry connectivity is optimal: the customer's on-premises network routes to the Azure hub VNet via ExpressRoute, and ACR's private endpoint is accessible from the on-premises network as if it were a private on-premises service.

| **Component** | **Configuration** | **Notes** |
| --- | --- | --- |
| ExpressRoute Circuit | Customer-managed — connects to nearest Azure region | Company does not manage customer ExpressRoute circuits |
| VNet Gateway / ExpressRoute Gateway | Customer-provisioned in customer Azure VNet or direct peering to hub VNet | For company on-premises (CI/CD, admin): ExpressRoute gateway in hub VNet connects to corporate ER circuit |
| Route Advertisement | ACR private endpoint IPs (10.0.0.4, 10.0.0.5) advertised via BGP over ExpressRoute if hub VNet is directly connected | On-premises routers learn the private endpoint IPs and route traffic accordingly |
| DNS Forwarding | On-premises DNS forward zone *.azurecr.io to Azure Private DNS Resolver inbound endpoint IP | Without DNS forwarding, on-premises hosts resolve ACR to public IP which is blocked |
| Firewall / Proxy Rules | On-premises egress firewall must allow outbound HTTPS (443) to ACR private endpoint IPs or DNS name | Most corporate firewalls permit HTTPS egress; confirm no SSL inspection that would break certificate trust |


## 7.2 VPN Connectivity (Site-to-Site)
For smaller on-premises sites or customer deployments where ExpressRoute is not available, IPSec site-to-site VPN connectivity to the hub VNet provides access to ACR private endpoints. The architecture is identical to ExpressRoute from a registry perspective — only the underlying WAN transport differs.

- VPN Gateway: VpnGw2 or higher in hub VNet for production. GatewaySubnet (10.0.3.128/27) in hub VNet.

- Customer sites: standard IPSec IKEv2 site-to-site VPN. RBGP route advertisement of hub VNet prefix (10.0.0.0/22) to on-premises.

- DNS forwarding: same requirement as ExpressRoute — on-premises DNS must forward *.azurecr.io to Private DNS Resolver.

- Throughput consideration: VPN Gateway maximum throughput is ~10 Gbps (GatewayMax SKU). Large image pulls by multiple on-premises clients may require throughput planning.

# 8. Edge Connectivity Patterns
Edge deployments present unique network challenges: intermittent connectivity, bandwidth constraints, and diverse network types. The registry architecture supports four edge connectivity patterns aligned with the edge topology tiers defined in [DOC-002 Section 8](../phase-1-foundations/DOC-002_Stakeholder_Consumer_Analysis.md).

| **Tier** | **Pattern** | **Registry Endpoint** | **DNS** | **Connectivity Requirement** | **Bandwidth Consideration** |
| --- | --- | --- | --- | --- | --- |
| Tier 1 — Always Connected | Direct pull (standard consumer pattern) | ACR FQDN (public DNS + HTTPS) | Public DNS resolution to ACR CDN endpoint | Permanent internet or VPN | Standard — image layers cached after first pull, subsequent pulls only fetch changed layers |
| Tier 2 — Intermittently Connected | Connected registry (local mirror) + Token Broker for credential refresh | Local connected registry IP (e.g., 192.168.1.100:5000) | Local DNS or /etc/hosts entry for connected registry IP | Periodic connectivity during sync window | Bandwidth consumed only during sync window. Pre-pull of entitled images during maintenance window. |
| Tier 2 — Intermittently Connected (alt) | Direct pull with extended TTL token during connectivity windows | ACR FQDN | Public DNS | Connectivity during pull window | Simpler than connected registry but requires periodic registry contact. Token TTL 72h limits required frequency. |
| Tier 3 — Rarely Connected | Scheduled sync (connected registry with cron schedule) or offline bundle | Local connected registry IP or docker load from file | N/A — no DNS needed for offline bundle | Occasional — once per sync window (days) | Low — sync only entitled repositories. Bundle distribution via SFTP or physical. |
| Tier 4 — Disconnected | Offline bundle (docker load / ctr images import) | N/A — no registry connectivity | N/A | None | N/A — offline distribution only |


## 8.1 Connected Registry Network Configuration
The connected registry itself requires a small set of network ports for operation:

- Client pull port: 443 (HTTPS) or 5000 (HTTP with TLS for internal lab scenarios). Default is 443. Configure with a valid TLS certificate (Let's Encrypt or corporate CA).

- Sync port (outbound from connected registry to parent ACR): 443 (HTTPS) to {registry}.azurecr.io and {registry}.{region}.data.azurecr.io

- ACR sync gateway port: the connected registry communicates with a dedicated gateway port on ACR. Ensure outbound 443 is not blocked by the edge site firewall on the sync path.

- Local firewall rule: allow inbound 443 to connected registry IP from k3s/Docker nodes on the site LAN


## 8.2 k3s Registry Mirror Configuration
k3s supports registry mirrors and credential injection via the /etc/rancher/k3s/registries.yaml configuration file. The following configuration directs k3s to use the connected registry as a pull-through mirror for entitled product namespaces:


> # /etc/rancher/k3s/registries.yaml — k3s registry configuration # Deployed to edge nodes during provisioning via Ansible/cloud-init mirrors:   '{registry-name}.azurecr.io':     endpoint:       - 'https://192.168.1.100'   # Connected registry local IP       - 'https://{registry-name}.azurecr.io'  # Fallback to cloud ACR when connected configs:   '192.168.1.100':     auth:       username: {connected-registry-client-token-username}       password: {connected-registry-client-token-password}  # From Key Vault / secret store     tls:       cert_file: /etc/ssl/certs/connected-registry.crt       key_file:  /etc/ssl/private/connected-registry.key       ca_file:   /etc/ssl/certs/ca-bundle.crt   '{registry-name}.azurecr.io':     auth:       username: '00000000-0000-0000-0000-000000000000'  # Token Broker-issued token       password: {token-broker-issued-refresh-token}


## 8.3 Docker Registry Configuration (Standalone Edge)
For Tier 2/3 edge nodes using Docker Engine without k3s, the following configuration directs Docker to use the connected registry or directly authenticate with Token Broker-issued credentials:


> # /etc/docker/daemon.json — Docker registry mirrors {   'registry-mirrors': ['https://192.168.1.100'],   'insecure-registries': []   // Never add ACR to insecure-registries } # ~/.docker/config.json — credential store # Populated by: echo {token} │ docker login {registry}.azurecr.io -u 00000000-0000-0000-0000-000000000000 --password-stdin # Or: managed by the ACR credential helper (docker-credential-acr) {   'auths': {     '{registry-name}.azurecr.io': { 'auth': '{base64-encoded-user:token}' }   } }


# 9. Token Broker Network Exposure
The Token Broker is the only registry-ecosystem component that is intentionally internet-accessible. Its public exposure is limited to the authentication endpoint only — no direct ACR management plane or data plane access is exposed externally.

| **Component** | **Internet Accessible?** | **Azure Front Door?** | **WAF?** | **DDoS Protection?** |
| --- | --- | --- | --- | --- |
| Token Broker authentication endpoint | Yes — required for customer authentication | Yes — Azure Front Door Standard/Premium as global entry point | Yes — Azure Web Application Firewall with OWASP 3.2 rule set | Yes — Azure DDoS Network Protection on hub VNet |
| Token Broker entitlement cache (Redis) | No — private endpoint only | No | No | NSG only |
| ACR login endpoint | No — private endpoint only, public access disabled | No | No — protected by private endpoint + NSG |
| ACR data endpoint | Conditionally — see Section 6.2 discussion | No — direct or via CDN for data plane | No — protected by token authentication |
| Key Vault | No — private endpoint only | No | No |
| Entitlement system API | No — private connectivity from Token Broker | No | Managed by Entitlement System team |


## 9.1 Azure Front Door Configuration for Token Broker
- Origin group: Token Broker Azure Container Apps instances in East US 2 and West US 2 (multi-region active-active)

- Health probes: HTTPS GET /health every 30 seconds — remove unhealthy origins automatically

- WAF policy: OWASP 3.2 rule set in Prevention mode. Custom rule: rate limit 100 requests/60 seconds per client IP

- Caching: disabled — authentication endpoints must not be cached

- Custom domain: token-broker.{company-domain}.com with Azure-managed TLS certificate

- Response headers: HSTS (max-age=31536000; includeSubDomains; preload) enforced

# 10. Firewall Rule Matrix Summary
The following matrix consolidates all required network flows across the registry architecture for reference during firewall implementation and review:

| **Flow** | **Source** | **Destination** | **Port** | **Protocol** | **Required For** |
| --- | --- | --- | --- | --- | --- |
| CI/CD → ACR private endpoint | CI/CD spoke VNet (10.10.0.0/22) | snet-acr-pe (10.0.0.4) | 443 | TCP/HTTPS | Image push from CI/CD pipelines |
| CI/CD → ACR data endpoint | CI/CD spoke VNet | 10.0.0.5 | 443 | TCP/HTTPS | Layer blob upload during push |
| Token Broker → ACR | snet-tokenbroker (10.0.1.0/27) | 10.0.0.4 | 443 | TCP/HTTPS | Token issuance API calls |
| Token Broker → Entitlement System | snet-tokenbroker | Entitlement system FQDN/IP | 443 | TCP/HTTPS | Entitlement lookup for token scoping |
| Token Broker → Key Vault | snet-tokenbroker | 10.0.2.4 | 443 | TCP/HTTPS | Token signing key retrieval |
| Token Broker → Redis | snet-tokenbroker | 10.0.1.20 | 6380 | TCP/TLS | Entitlement cache read/write |
| Internet → Token Broker (via AFD) | 0.0.0.0/0 (customer networks) | Azure Front Door IP ranges | 443 | TCP/HTTPS | Customer authentication |
| On-premises → ACR (via ER/VPN) | Corporate on-prem IP ranges | 10.0.0.4, 10.0.0.5 | 443 | TCP/HTTPS | Developer pull, admin access |
| ACR → Key Vault (CMK) | ACR MI (Azure-internal) | 10.0.2.4 | 443 | TCP/HTTPS | Customer-managed key wrap/unwrap |
| Connected Registry → ACR sync | Edge site public IP | ACR FQDN (cloud) | 443 | TCP/HTTPS | Content synchronization |
| Edge k3s/Docker → Connected Registry | Edge site LAN | Connected registry local IP | 443 | TCP/HTTPS | Runtime image pulls at edge |
| Management → Azure ARM | snet-admin | Azure Resource Manager (AzureResourceManager service tag) | 443 | TCP/HTTPS | IaC deployments, admin operations |
| Monitoring → Log Analytics | All subnets | AzureMonitor service tag | 443 | TCP/HTTPS | Telemetry export |

# 11. Revision History & Approvals
| Version | Date | Description |
| --- | --- | --- |
| 0.1 DRAFT | April 2026 | Initial release — hub-spoke VNet design, private endpoints, DNS zones, NSG rules, consumer connectivity patterns, edge configuration, firewall matrix |
| 1.0 | TBD | Approved version — pending Architecture Review Board and Network Engineering review |


>** Required Approvals:**  Chief Architect, Network Engineering Lead, Head of Platform Engineering, CISO (firewall rule matrix review). Network Engineering team must validate all subnet address allocations against the corporate IP address management (IPAM) system before implementation.


	CONFIDENTIAL | Classification: Internal Architecture	Page  of
