# Local Values for Resource Naming and Configuration
locals {
  # Naming convention: {company}-{project}-{environment}-{location}-{resource}
  name_prefix = "${var.company_name}-${var.project_name}-${var.environment}"

  # Primary region short name for naming
  location_short = {
    "East US"       = "eus"
    "East US 2"     = "eus2"
    "West US"       = "wus"
    "West US 2"     = "wus2"
    "Central US"    = "cus"
    "North Central US" = "ncus"
    "South Central US" = "scus"
    "West Central US"  = "wcus"
  }

  primary_location_short   = lookup(local.location_short, var.location, "unk")
  secondary_location_short = lookup(local.location_short, var.location_secondary, "unk")

  # Common tags merged with environment-specific tags
  common_tags = merge(var.common_tags, {
    Environment = var.environment
    Location    = var.location
    Timestamp   = timestamp()
  })

  # Network configuration
  subnets = {
    gateway = {
      name             = "GatewaySubnet"
      address_prefixes = [var.gateway_subnet_address_prefix]
    }
    aks = {
      name             = "${local.name_prefix}-aks-subnet"
      address_prefixes = ["10.0.10.0/24"]
    }
    vmss = {
      name             = "${local.name_prefix}-vmss-subnet"
      address_prefixes = ["10.0.20.0/24"]
    }
    database = {
      name             = "${local.name_prefix}-db-subnet"
      address_prefixes = ["10.0.30.0/24"]
    }
    private_endpoints = {
      name             = "${local.name_prefix}-pe-subnet"
      address_prefixes = ["10.0.40.0/24"]
    }
    app_gateway = {
      name             = "${local.name_prefix}-agw-subnet"
      address_prefixes = ["10.0.50.0/24"]
    }
  }

  # Security configuration
  nsg_rules = {
    allow_https = {
      name                       = "Allow-HTTPS"
      priority                   = 1000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
    allow_http = {
      name                       = "Allow-HTTP"
      priority                   = 1001
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
    allow_wms_api = {
      name                       = "Allow-WMS-API"
      priority                   = 1100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "8080-8090"
      source_address_prefix      = "10.0.0.0/16"
      destination_address_prefix = "*"
    }
    allow_ssh = {
      name                       = "Allow-SSH"
      priority                   = 1200
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = join(",", var.allowed_ip_ranges)
      destination_address_prefix = "*"
    }
  }

  # WMS-specific configurations
  wms_components = {
    inventory_service = {
      name = "inventory"
      port = 8080
      replicas = 3
    }
    order_service = {
      name = "orders"
      port = 8081
      replicas = 3
    }
    picking_service = {
      name = "picking"
      port = 8082
      replicas = 2
    }
    shipping_service = {
      name = "shipping"
      port = 8083
      replicas = 2
    }
    reporting_service = {
      name = "reporting"
      port = 8084
      replicas = 1
    }
  }

  # Performance tiers based on warehouse configuration
  performance_tiers = {
    for k, v in var.warehouse_locations : k => {
      compute_tier = v.expected_daily_orders > 4000 ? "high" : v.expected_daily_orders > 1500 ? "medium" : "low"
      storage_tier = v.expected_daily_orders > 4000 ? "Premium_LRS" : "Standard_LRS"
      db_tier     = v.expected_daily_orders > 4000 ? "P2" : v.expected_daily_orders > 1500 ? "S2" : "S1"
    }
  }
}
