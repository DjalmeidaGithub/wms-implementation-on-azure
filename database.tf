# SQL Server for WMS Database
resource "azurerm_mssql_server" "primary" {
  name                         = "${local.name_prefix}-sql-${local.primary_location_short}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_server_admin_username
  administrator_login_password = random_password.sql_admin.result
  tags                         = local.common_tags

  # Security configurations
  public_network_access_enabled = false
  minimum_tls_version           = "1.2"

  azuread_administrator {
    login_username = "sql-admin-group"
    object_id      = azuread_group.sql_admins.object_id
  }

  identity {
    type = "SystemAssigned"
  }

  # Transparent Data Encryption
  transparent_data_encryption_key_vault_key_id = azurerm_key_vault_key.sql_tde.id

  depends_on = [
    azurerm_key_vault_access_policy.sql_server
  ]
}

# Secondary SQL Server for Disaster Recovery
resource "azurerm_mssql_server" "secondary" {
  count                        = var.enable_disaster_recovery ? 1 : 0
  name                         = "${local.name_prefix}-sql-${local.secondary_location_short}"
  resource_group_name          = azurerm_resource_group.secondary[0].name
  location                     = var.location_secondary
  version                      = "12.0"
  administrator_login          = var.sql_server_admin_username
  administrator_login_password = random_password.sql_admin.result
  tags                         = local.common_tags

  public_network_access_enabled = false
  minimum_tls_version           = "1.2"

  azuread_administrator {
    login_username = "sql-admin-group"
    object_id      = azuread_group.sql_admins.object_id
  }

  identity {
    type = "SystemAssigned"
  }
}

# WMS Database - Primary
resource "azurerm_mssql_database" "wms_primary" {
  name         = "${local.name_prefix}-wmsdb"
  server_id    = azurerm_mssql_server.primary.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "LicenseIncluded"
  sku_name     = "P2"
  tags         = local.common_tags

  # Backup configuration
  short_term_retention_policy {
    retention_days = 35
  }

  long_term_retention_policy {
    weekly_retention  = "P12W"
    monthly_retention = "P12M"
    yearly_retention  = "P5Y"
    week_of_year      = 1
  }

  # Threat detection
  threat_detection_policy {
    state           = "Enabled"
    email_addresses = []
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Secondary Database for Geo-Replication
resource "azurerm_mssql_database" "wms_secondary" {
  count                       = var.enable_disaster_recovery ? 1 : 0
  name                        = "${local.name_prefix}-wmsdb"
  server_id                   = azurerm_mssql_server.secondary[0].id
  create_mode                 = "Secondary"
  creation_source_database_id = azurerm_mssql_database.wms_primary.id
  tags                        = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

# Failover Group
resource "azurerm_mssql_failover_group" "wms" {
  count     = var.enable_sql_failover_group && var.enable_disaster_recovery ? 1 : 0
  name      = "${local.name_prefix}-fog"
  server_id = azurerm_mssql_server.primary.id
  tags      = local.common_tags

  databases = [
    azurerm_mssql_database.wms_primary.id
  ]

  partner_server {
    id = azurerm_mssql_server.secondary[0].id
  }

  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 60
  }

  readonly_endpoint_failover_policy {
    mode = "Enabled"
  }
}

# Azure SQL Database Elastic Pool for Multiple WMS Tenants
resource "azurerm_mssql_elasticpool" "wms_tenants" {
  name                = "${local.name_prefix}-elastic-pool"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  server_name         = azurerm_mssql_server.primary.name
  license_type        = "LicenseIncluded"
  max_size_gb         = 500
  tags                = local.common_tags

  sku {
    name     = "StandardPool"
    tier     = "Standard"
    capacity = 200
  }

  per_database_settings {
    min_capacity = 0
    max_capacity = 50
  }
}

# Tenant databases in elastic pool
resource "azurerm_mssql_database" "tenant_databases" {
  for_each = var.warehouse_locations

  name           = "${local.name_prefix}-wms-${each.key}"
  server_id      = azurerm_mssql_server.primary.id
  elastic_pool_id = azurerm_mssql_elasticpool.wms_tenants.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  tags           = merge(local.common_tags, {
    Tenant    = each.key
    OnPremises = each.value.on_premises
  })

  short_term_retention_policy {
    retention_days = 7
  }
}

# Private Endpoints for SQL Server
resource "azurerm_private_endpoint" "sql_primary" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${local.name_prefix}-pe-sql-primary"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.subnets["private_endpoints"].id
  tags                = local.common_tags

  private_service_connection {
    name                           = "sql-primary-private-connection"
    private_connection_resource_id = azurerm_mssql_server.primary.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "sql-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql[0].id]
  }
}

resource "azurerm_private_endpoint" "sql_secondary" {
  count               = var.enable_private_endpoints && var.enable_disaster_recovery ? 1 : 0
  name                = "${local.name_prefix}-pe-sql-secondary"
  location            = var.location_secondary
  resource_group_name = azurerm_resource_group.secondary[0].name
  subnet_id           = azurerm_subnet.subnets["private_endpoints"].id
  tags                = local.common_tags

  private_service_connection {
    name                           = "sql-secondary-private-connection"
    private_connection_resource_id = azurerm_mssql_server.secondary[0].id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }
}

# CosmosDB for High-Performance WMS Operations (Inventory, Real-time Tracking)
resource "azurerm_cosmosdb_account" "wms_realtime" {
  name                = "${local.name_prefix}-cosmos-${local.primary_location_short}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  tags                = local.common_tags

  enable_automatic_failover = true
  enable_multiple_write_locations = false

  # Consistency policy for real-time operations
  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  # Primary region
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
    zone_redundant    = true
  }

  # Secondary region for disaster recovery
  dynamic "geo_location" {
    for_each = var.enable_disaster_recovery ? [1] : []
    content {
      location          = var.location_secondary
      failover_priority = 1
      zone_redundant    = true
    }
  }

  # Backup configuration
  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 720
    storage_redundancy  = "Geo"
  }

  # Network access
  public_network_access_enabled = false
  is_virtual_network_filter_enabled = true

  virtual_network_rule {
    id                                   = azurerm_subnet.subnets["aks"].id
    ignore_missing_vnet_service_endpoint = false
  }

  virtual_network_rule {
    id                                   = azurerm_subnet.subnets["vmss"].id
    ignore_missing_vnet_service_endpoint = false
  }

  identity {
    type = "SystemAssigned"
  }
}

# CosmosDB Database for WMS Real-time Data
resource "azurerm_cosmosdb_sql_database" "wms_realtime" {
  name                = "wms-realtime"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.wms_realtime.name
  throughput          = 1000

  autoscale_settings {
    max_throughput = 10000
  }
}

# CosmosDB Containers
resource "azurerm_cosmosdb_sql_container" "inventory_tracking" {
  name                  = "inventory-tracking"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.wms_realtime.name
  database_name         = azurerm_cosmosdb_sql_database.wms_realtime.name
  partition_key_path    = "/warehouseId"
  partition_key_version = 1
  throughput            = 800

  autoscale_settings {
    max_throughput = 8000
  }

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }

  unique_key {
    paths = ["/sku", "/warehouseId"]
  }
}

resource "azurerm_cosmosdb_sql_container" "order_tracking" {
  name                  = "order-tracking"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.wms_realtime.name
  database_name         = azurerm_cosmosdb_sql_database.wms_realtime.name
  partition_key_path    = "/orderId"
  partition_key_version = 1
  throughput            = 600

  autoscale_settings {
    max_throughput = 6000
  }

  # TTL for automatic cleanup of completed orders
  default_ttl = 2592000 # 30 days
}

# Private endpoint for CosmosDB
resource "azurerm_private_endpoint" "cosmos" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${local.name_prefix}-pe-cosmos"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.subnets["private_endpoints"].id
  tags                = local.common_tags

  private_service_connection {
    name                           = "cosmos-private-connection"
    private_connection_resource_id = azurerm_cosmosdb_account.wms_realtime.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "cosmos-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.cosmos[0].id]
  }
}

# Random password for SQL Server admin
resource "random_password" "sql_admin" {
  length  = 16
  special = true
}

# Azure AD Group for SQL Administrators
resource "azuread_group" "sql_admins" {
  display_name     = "${local.name_prefix}-sql-admins"
  owners           = [data.azurerm_client_config.current.object_id]
  security_enabled = true
  description      = "SQL Server administrators for WMS databases"
}

# Data Factory for Data Movement and ETL
resource "azurerm_data_factory" "wms" {
  name                = "${local.name_prefix}-df"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  # Git integration for version control
  vsts_configuration {
    account_name    = "wms-devops"
    branch_name     = "main"
    project_name    = "wms-data-integration"
    repository_name = "wms-data-factory"
    root_folder     = "/data-factory"
    tenant_id       = data.azurerm_client_config.current.tenant_id
  }
}

# Private endpoint for Data Factory
resource "azurerm_private_endpoint" "data_factory" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${local.name_prefix}-pe-df"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.subnets["private_endpoints"].id
  tags                = local.common_tags

  private_service_connection {
    name                           = "df-private-connection"
    private_connection_resource_id = azurerm_data_factory.wms.id
    subresource_names              = ["dataFactory"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "df-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.data_factory[0].id]
  }
}

# Self-hosted Integration Runtime for On-premises Connectivity
resource "azurerm_data_factory_integration_runtime_self_hosted" "onpremises" {
  name            = "${local.name_prefix}-shir"
  data_factory_id = azurerm_data_factory.wms.id
  description     = "Self-hosted IR for on-premises WMS systems"
}

# Linked Service for On-premises SQL Server
resource "azurerm_data_factory_linked_service_sql_server" "onpremises" {
  name            = "onpremises-sql"
  data_factory_id = azurerm_data_factory.wms.id
  description     = "Connection to on-premises SQL Server"

  connection_string = "Server=onprem-sql.contoso.local;Database=WMS_OnPrem;Integrated Security=True;"
  integration_runtime_name = azurerm_data_factory_integration_runtime_self_hosted.onpremises.name
}
