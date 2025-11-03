# Core Infrastructure Outputs
output "resource_group_name" {
  description = "Name of the main resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the main resource group"
  value       = azurerm_resource_group.main.location
}

output "secondary_resource_group_name" {
  description = "Name of the secondary resource group (DR)"
  value       = var.enable_disaster_recovery ? azurerm_resource_group.secondary[0].name : null
}

# Networking Outputs
output "vnet_id" {
  description = "Virtual Network ID"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Virtual Network name"
  value       = azurerm_virtual_network.main.name
}

output "subnet_ids" {
  description = "Map of subnet names to subnet IDs"
  value = {
    for k, v in azurerm_subnet.subnets : k => v.id
  }
}

output "vpn_gateway_public_ip" {
  description = "Public IP address of the VPN Gateway"
  value       = azurerm_public_ip.vpn_gateway.ip_address
}

output "application_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.app_gateway.ip_address
}

output "application_gateway_fqdn" {
  description = "FQDN of the Application Gateway"
  value       = azurerm_public_ip.app_gateway.fqdn
}

# Compute Outputs
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "aks_cluster_portal_fqdn" {
  description = "Portal FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.portal_fqdn
}

output "aks_kube_config" {
  description = "Kubernetes configuration for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "vmss_id" {
  description = "ID of the Virtual Machine Scale Set"
  value       = azurerm_windows_virtual_machine_scale_set.wms_legacy.id
}

output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "Login server for the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

# Database Outputs
output "sql_server_name" {
  description = "Name of the primary SQL Server"
  value       = azurerm_mssql_server.primary.name
}

output "sql_server_fqdn" {
  description = "FQDN of the primary SQL Server"
  value       = azurerm_mssql_server.primary.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Name of the WMS database"
  value       = azurerm_mssql_database.wms_primary.name
}

output "sql_failover_group_listener" {
  description = "Failover group listener endpoint"
  value       = var.enable_sql_failover_group && var.enable_disaster_recovery ? azurerm_mssql_failover_group.wms[0].listener_endpoint : null
}

output "cosmosdb_account_name" {
  description = "Name of the CosmosDB account"
  value       = azurerm_cosmosdb_account.wms_realtime.name
}

output "cosmosdb_endpoint" {
  description = "Endpoint of the CosmosDB account"
  value       = azurerm_cosmosdb_account.wms_realtime.endpoint
}

output "cosmosdb_connection_strings" {
  description = "CosmosDB connection strings"
  value       = azurerm_cosmosdb_account.wms_realtime.connection_strings
  sensitive   = true
}

# Cache and Performance Outputs
output "redis_cache_name" {
  description = "Name of the primary Redis cache"
  value       = azurerm_redis_cache.primary.name
}

output "redis_cache_hostname" {
  description = "Hostname of the primary Redis cache"
  value       = azurerm_redis_cache.primary.hostname
}

output "redis_cache_port" {
  description = "Port of the primary Redis cache"
  value       = azurerm_redis_cache.primary.port
}

output "redis_cache_ssl_port" {
  description = "SSL port of the primary Redis cache"
  value       = azurerm_redis_cache.primary.ssl_port
}

output "cdn_profile_name" {
  description = "Name of the CDN profile"
  value       = azurerm_cdn_profile.wms.name
}

output "cdn_endpoint_hostname" {
  description = "Hostname of the CDN endpoint"
  value       = azurerm_cdn_endpoint.wms_static.host_name
}

output "front_door_endpoint_hostname" {
  description = "Hostname of the Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.wms.host_name
}

output "traffic_manager_fqdn" {
  description = "FQDN of the Traffic Manager profile"
  value       = azurerm_traffic_manager_profile.wms.fqdn
}

# Security Outputs
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "managed_identity_id" {
  description = "ID of the WMS application managed identity"
  value       = azurerm_user_assigned_identity.wms_app.id
}

output "managed_identity_client_id" {
  description = "Client ID of the WMS application managed identity"
  value       = azurerm_user_assigned_identity.wms_app.client_id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the WMS application managed identity"
  value       = azurerm_user_assigned_identity.wms_app.principal_id
}

# Azure AD Groups
output "azure_ad_groups" {
  description = "Azure AD groups created for WMS RBAC"
  value = {
    wms_admins   = azuread_group.wms_admins.object_id
    wms_operators = azuread_group.wms_operators.object_id
    wms_readonly = azuread_group.wms_readonly.object_id
    sql_admins   = azuread_group.sql_admins.object_id
  }
}

# Monitoring Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "application_insights_name" {
  description = "Name of Application Insights"
  value       = azurerm_application_insights.wms.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.wms.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.wms.connection_string
  sensitive   = true
}

# Storage Outputs
output "primary_storage_account_name" {
  description = "Name of the primary storage account"
  value       = azurerm_storage_account.main.name
}

output "backup_storage_account_name" {
  description = "Name of the backup storage account"
  value       = azurerm_storage_account.backup.name
}

output "storage_connection_strings" {
  description = "Storage account connection strings"
  value = {
    primary = azurerm_storage_account.main.primary_connection_string
    backup  = azurerm_storage_account.backup.primary_connection_string
  }
  sensitive = true
}

# Cost Management Outputs
output "budget_name" {
  description = "Name of the cost management budget"
  value       = azurerm_consumption_budget_resource_group.wms_monthly.name
}

output "cost_export_name" {
  description = "Name of the cost analysis export"
  value       = azurerm_cost_management_export_resource_group.wms_cost_analysis.name
}

# Data Factory Outputs
output "data_factory_name" {
  description = "Name of the Data Factory"
  value       = azurerm_data_factory.wms.name
}

output "data_factory_identity_principal_id" {
  description = "Principal ID of the Data Factory managed identity"
  value       = azurerm_data_factory.wms.identity[0].principal_id
}

# Environment-specific Outputs
output "environment_configuration" {
  description = "Environment-specific configuration summary"
  value = {
    environment                = var.environment
    primary_location          = var.location
    secondary_location        = var.location_secondary
    disaster_recovery_enabled = var.enable_disaster_recovery
    private_endpoints_enabled = var.enable_private_endpoints
    monitoring_enabled        = var.enable_monitoring
    backup_enabled           = var.enable_backup
    auto_shutdown_enabled    = var.auto_shutdown_enabled
  }
}

# Warehouse-specific Outputs
output "warehouse_configurations" {
  description = "Configuration for each warehouse location"
  value       = var.warehouse_locations
}

output "performance_tiers" {
  description = "Performance tiers assigned to each warehouse"
  value       = local.performance_tiers
}

# Connection Information
output "connection_information" {
  description = "Key connection information for applications"
  value = {
    application_gateway_url = "https://${azurerm_public_ip.app_gateway.fqdn}"
    front_door_url         = "https://${azurerm_cdn_frontdoor_endpoint.wms.host_name}"
    traffic_manager_url    = "https://${azurerm_traffic_manager_profile.wms.fqdn}"
    aks_api_server_url     = azurerm_kubernetes_cluster.main.kube_config.0.host
  }
}

# Private Endpoint Information
output "private_endpoints" {
  description = "Private endpoint configurations"
  value = var.enable_private_endpoints ? {
    key_vault    = azurerm_private_endpoint.keyvault[0].private_service_connection[0].private_ip_address
    sql_server   = azurerm_private_endpoint.sql_primary[0].private_service_connection[0].private_ip_address
    cosmos_db    = azurerm_private_endpoint.cosmos[0].private_service_connection[0].private_ip_address
    container_registry = azurerm_private_endpoint.acr[0].private_service_connection[0].private_ip_address
  } : {}
}

# Security Configuration Summary
output "security_summary" {
  description = "Summary of security configurations"
  value = {
    key_vault_enabled              = true
    private_endpoints_enabled      = var.enable_private_endpoints
    azure_ad_integration_enabled   = true
    network_security_groups_count  = length(azurerm_network_security_group.main)
    custom_rbac_roles_count        = 1
    security_center_enabled        = true
    encryption_at_rest_enabled     = true
    tls_version                   = "1.2"
  }
}

# Scaling Configuration
output "scaling_configuration" {
  description = "Auto-scaling configuration summary"
  value = {
    aks_min_nodes         = 2
    aks_max_nodes         = 20
    vmss_min_instances    = 2
    vmss_max_instances    = 10
    spot_instances_enabled = var.environment == "dev"
    auto_shutdown_enabled = var.auto_shutdown_enabled && var.environment != "prod"
  }
}

# Cost Optimization Summary
output "cost_optimization_summary" {
  description = "Cost optimization features summary"
  value = {
    monthly_budget_limit      = azurerm_consumption_budget_resource_group.wms_monthly.amount
    reserved_instances_enabled = var.reserved_instance_enabled
    spot_instances_enabled    = var.environment == "dev"
    storage_lifecycle_enabled = true
    auto_scaling_enabled     = true
    cost_anomaly_detection   = true
    dev_test_labs_enabled    = var.environment == "dev"
  }
}
