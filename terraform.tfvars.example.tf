# Example Terraform Variables Configuration
# Copy this file to terraform.tfvars and customize for your environment

# Environment Configuration
environment = "dev"
location = "East US 2"
location_secondary = "West US 2"

# Naming Configuration
company_name = "acme"
project_name = "wms"

# Network Configuration
vnet_address_space = ["10.0.0.0/16"]
on_premises_address_space = ["192.168.0.0/16"]
gateway_subnet_address_prefix = "10.0.1.0/27"

# Allowed IP ranges for management access
allowed_ip_ranges = [
  "203.0.113.0/24",    # Replace with your office public IP range
  "198.51.100.0/24"    # Replace with your VPN exit IP range
]

# Compute Configuration
aks_node_count = 3
aks_node_vm_size = "Standard_D4s_v3"
vmss_instance_count = 2

# Database Configuration
sql_server_admin_username = "sqladmin"
enable_sql_failover_group = true

# Warehouse Locations Configuration
warehouse_locations = {
  "east-coast-dc" = {
    region              = "East US 2"
    on_premises         = false
    expected_daily_orders = 5000
    peak_multiplier     = 3.0
  }
  "west-coast-dc" = {
    region              = "West US 2"
    on_premises         = false
    expected_daily_orders = 3000
    peak_multiplier     = 2.5
  }
  "midwest-warehouse" = {
    region              = "Central US"
    on_premises         = true
    expected_daily_orders = 2000
    peak_multiplier     = 2.0
  }
  "southeast-hub" = {
    region              = "South Central US"
    on_premises         = false
    expected_daily_orders = 1500
    peak_multiplier     = 2.2
  }
  "international-hub" = {
    region              = "North Europe"
    on_premises         = false
    expected_daily_orders = 800
    peak_multiplier     = 1.8
  }
}

# Feature Flags
enable_private_endpoints = true
enable_monitoring = true
enable_backup = true
enable_disaster_recovery = true

# Cost Optimization
auto_shutdown_enabled = true
reserved_instance_enabled = false  # Set to true for production

# Common Tags
common_tags = {
  Project     = "WMS-Modernization"
  Environment = "Development"
  ManagedBy   = "Terraform"
  CostCenter  = "IT-Infrastructure"
  Owner       = "DevOps-Team"
  Department  = "Supply-Chain"
  Application = "Warehouse-Management"
  DataClass   = "Internal"
  Backup      = "Required"
  Monitoring  = "Enabled"
}
