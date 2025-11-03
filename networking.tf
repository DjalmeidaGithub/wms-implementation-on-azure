# Resource Groups
resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg-${local.primary_location_short}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "secondary" {
  count    = var.enable_disaster_recovery ? 1 : 0
  name     = "${local.name_prefix}-rg-${local.secondary_location_short}"
  location = var.location_secondary
  tags     = local.common_tags
}

# Virtual Network - Primary Region
resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet-${local.primary_location_short}"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

# Virtual Network - Secondary Region (DR)
resource "azurerm_virtual_network" "secondary" {
  count               = var.enable_disaster_recovery ? 1 : 0
  name                = "${local.name_prefix}-vnet-${local.secondary_location_short}"
  address_space       = ["10.1.0.0/16"]
  location            = var.location_secondary
  resource_group_name = azurerm_resource_group.secondary[0].name
  tags                = local.common_tags
}

# Subnets
resource "azurerm_subnet" "subnets" {
  for_each = local.subnets

  name                 = each.value.name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = each.value.address_prefixes

  # Delegate specific subnets
  dynamic "delegation" {
    for_each = each.key == "database" ? [1] : []
    content {
      name = "Microsoft.Sql/managedInstances"
      service_delegation {
        name    = "Microsoft.Sql/managedInstances"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action", "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
      }
    }
  }

  # Private endpoint subnet configuration
  private_endpoint_network_policies_enabled = each.key == "private_endpoints" ? false : true
}

# Network Security Groups
resource "azurerm_network_security_group" "main" {
  for_each = {
    aks = "aks"
    vmss = "vmss"
    database = "database"
  }

  name                = "${local.name_prefix}-nsg-${each.key}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# NSG Rules
resource "azurerm_network_security_rule" "rules" {
  for_each = {
    for combination in flatten([
      for nsg_key in keys(azurerm_network_security_group.main) : [
        for rule_key, rule in local.nsg_rules : {
          nsg_key = nsg_key
          rule_key = rule_key
          rule = rule
        }
      ]
    ]) : "${combination.nsg_key}-${combination.rule_key}" => combination
  }

  name                        = each.value.rule.name
  priority                    = each.value.rule.priority + (each.value.nsg_key == "database" ? 1000 : each.value.nsg_key == "vmss" ? 500 : 0)
  direction                   = each.value.rule.direction
  access                      = each.value.rule.access
  protocol                    = each.value.rule.protocol
  source_port_range           = each.value.rule.source_port_range
  destination_port_range      = each.value.rule.destination_port_range
  source_address_prefix       = each.value.rule.source_address_prefix
  destination_address_prefix  = each.value.rule.destination_address_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main[each.value.nsg_key].name
}

# Associate NSGs with Subnets
resource "azurerm_subnet_network_security_group_association" "main" {
  for_each = {
    aks      = azurerm_subnet.subnets["aks"].id
    vmss     = azurerm_subnet.subnets["vmss"].id
    database = azurerm_subnet.subnets["database"].id
  }

  subnet_id                 = each.value
  network_security_group_id = azurerm_network_security_group.main[each.key].id
}

# Route Table for Hybrid Connectivity
resource "azurerm_route_table" "main" {
  name                = "${local.name_prefix}-rt-main"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  route {
    name           = "ToOnPremises"
    address_prefix = var.on_premises_address_space[0]
    next_hop_type  = "VirtualNetworkGateway"
  }
}

# Associate Route Table with Subnets
resource "azurerm_subnet_route_table_association" "main" {
  for_each = {
    aks  = azurerm_subnet.subnets["aks"].id
    vmss = azurerm_subnet.subnets["vmss"].id
  }

  subnet_id      = each.value
  route_table_id = azurerm_route_table.main.id
}

# Public IP for VPN Gateway
resource "azurerm_public_ip" "vpn_gateway" {
  name                = "${local.name_prefix}-pip-vpngw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# VPN Gateway for Hybrid Connectivity
resource "azurerm_virtual_network_gateway" "main" {
  name                = "${local.name_prefix}-vpngw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  active_active       = false
  enable_bgp          = true
  sku                 = "VpnGw2"
  tags                = local.common_tags

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.subnets["gateway"].id
  }

  bgp_settings {
    asn = 65515
  }
}

# Local Network Gateway (On-Premises)
resource "azurerm_local_network_gateway" "onpremises" {
  name                = "${local.name_prefix}-lng-onprem"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  gateway_address     = "203.0.113.1" # Placeholder - replace with actual on-premises public IP
  address_space       = var.on_premises_address_space
  tags                = local.common_tags

  bgp_settings {
    asn                 = 65001
    bgp_peering_address = "192.168.1.1"
  }
}

# VPN Connection
resource "azurerm_virtual_network_gateway_connection" "onpremises" {
  name                = "${local.name_prefix}-vpn-connection"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  type                = "IPsec"

  virtual_network_gateway_id = azurerm_virtual_network_gateway.main.id
  local_network_gateway_id   = azurerm_local_network_gateway.onpremises.id

  shared_key = random_password.vpn_shared_key.result
  enable_bgp = true
  tags       = local.common_tags
}

# Random password for VPN connection
resource "random_password" "vpn_shared_key" {
  length  = 32
  special = true
}

# VNet Peering (Primary to Secondary for DR)
resource "azurerm_virtual_network_peering" "primary_to_secondary" {
  count                     = var.enable_disaster_recovery ? 1 : 0
  name                      = "${local.name_prefix}-peer-primary-to-secondary"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.main.name
  remote_virtual_network_id = azurerm_virtual_network.secondary[0].id
  allow_gateway_transit     = true
  use_remote_gateways       = false
}

resource "azurerm_virtual_network_peering" "secondary_to_primary" {
  count                     = var.enable_disaster_recovery ? 1 : 0
  name                      = "${local.name_prefix}-peer-secondary-to-primary"
  resource_group_name       = azurerm_resource_group.secondary[0].name
  virtual_network_name      = azurerm_virtual_network.secondary[0].name
  remote_virtual_network_id = azurerm_virtual_network.main.id
  allow_gateway_transit     = false
  use_remote_gateways       = true

  depends_on = [azurerm_virtual_network_gateway.main]
}

# Application Gateway Public IP
resource "azurerm_public_ip" "app_gateway" {
  name                = "${local.name_prefix}-pip-agw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Web Application Firewall Policy
resource "azurerm_web_application_firewall_policy" "main" {
  name                = "${local.name_prefix}-waf-policy"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.common_tags

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}

# Application Gateway
resource "azurerm_application_gateway" "main" {
  name                = "${local.name_prefix}-agw"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.common_tags

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.subnets["app_gateway"].id
  }

  frontend_port {
    name = "https-port"
    port = 443
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config"
    public_ip_address_id = azurerm_public_ip.app_gateway.id
  }

  backend_address_pool {
    name = "wms-backend-pool"
  }

  backend_http_settings {
    name                  = "wms-backend-settings"
    cookie_based_affinity = "Disabled"
    path                  = "/health"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "health-probe"
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-config"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "wms-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "wms-backend-pool"
    backend_http_settings_name = "wms-backend-settings"
    priority                   = 100
  }

  probe {
    name                = "health-probe"
    protocol            = "Http"
    path                = "/health"
    interval            = 30
    timeout             = 20
    unhealthy_threshold = 3
    host                = "127.0.0.1"
    match {
      status_code = ["200-399"]
    }
  }

  firewall_policy_id = azurerm_web_application_firewall_policy.main.id

  autoscale_configuration {
    min_capacity = 2
    max_capacity = 10
  }
}
