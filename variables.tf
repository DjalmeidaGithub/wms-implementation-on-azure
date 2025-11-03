# Core Configuration Variables
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US 2"
}

variable "location_secondary" {
  description = "Secondary Azure region for DR and replication"
  type        = string
  default     = "West US 2"
}

variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "wms"
}

variable "company_name" {
  description = "Company name for resource naming"
  type        = string
  default     = "acme"
}

# Network Configuration
variable "vnet_address_space" {
  description = "Address space for the main VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "on_premises_address_space" {
  description = "On-premises network address space"
  type        = list(string)
  default     = ["192.168.0.0/16"]
}

variable "gateway_subnet_address_prefix" {
  description = "Address prefix for Gateway subnet"
  type        = string
  default     = "10.0.1.0/27"
}

# Compute Configuration
variable "aks_node_count" {
  description = "Number of nodes in AKS cluster"
  type        = number
  default     = 3
}

variable "aks_node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "vmss_instance_count" {
  description = "Number of instances in VMSS for legacy systems"
  type        = number
  default     = 2
}

# Database Configuration
variable "sql_server_admin_username" {
  description = "SQL Server administrator username"
  type        = string
  default     = "sqladmin"
  sensitive   = false
}

variable "enable_sql_failover_group" {
  description = "Enable SQL failover group for disaster recovery"
  type        = bool
  default     = true
}

# WMS-Specific Configuration
variable "warehouse_locations" {
  description = "List of warehouse locations and their configurations"
  type = map(object({
    region              = string
    on_premises         = bool
    expected_daily_orders = number
    peak_multiplier     = number
  }))

  default = {
    "east-warehouse" = {
      region              = "East US 2"
      on_premises         = false
      expected_daily_orders = 5000
      peak_multiplier     = 3
    }
    "west-warehouse" = {
      region              = "West US 2"
      on_premises         = false
      expected_daily_orders = 3000
      peak_multiplier     = 2.5
    }
    "central-warehouse" = {
      region              = "Central US"
      on_premises         = true
      expected_daily_orders = 2000
      peak_multiplier     = 2
    }
  }
}

# Security Configuration
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for PaaS services"
  type        = bool
  default     = true
}

# Cost Optimization
variable "auto_shutdown_enabled" {
  description = "Enable auto-shutdown for development VMs"
  type        = bool
  default     = true
}

variable "reserved_instance_enabled" {
  description = "Use reserved instances for cost savings"
  type        = bool
  default     = false
}

# Feature Flags
variable "enable_monitoring" {
  description = "Enable comprehensive monitoring stack"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable backup solutions"
  type        = bool
  default     = true
}

variable "enable_disaster_recovery" {
  description = "Enable disaster recovery configurations"
  type        = bool
  default     = true
}

# Tags
variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "WMS"
    Environment = "dev"
    ManagedBy   = "Terraform"
    CostCenter  = "IT-Infrastructure"
    Owner       = "DevOps-Team"
  }
}
