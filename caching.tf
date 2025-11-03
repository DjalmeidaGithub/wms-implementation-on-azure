# Azure Cache for Redis - Primary Instance
resource "azurerm_redis_cache" "primary" {
  name                = "${local.name_prefix}-redis-${local.primary_location_short}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  capacity            = 3
  family              = "P"
  sku_name            = "Premium"
  tags                = local.common_tags

  # Enable non-SSL port for legacy applications
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"

  # Redis configuration for WMS workloads
  redis_configuration {
    maxmemory_reserved = 200
    maxmemory_delta    = 200
    maxmemory_policy   = "allkeys-lru"

    # Enable persistence for inventory data
    rdb_backup_enabled            = true
    rdb_backup_frequency          = 60
    rdb_backup_max_snapshot_count = 1
    rdb_storage_connection_string = azurerm_storage_account.backup.primary_connection_string

    # AOF persistence for critical operations
    aof_backup_enabled = true
    aof_storage_connection_string_0 = azurerm_storage_account.backup.primary_connection_string
  }

  # Private network access
  public_network_access_enabled = false
  subnet_id                     = azurerm_subnet.subnets["private_endpoints"].id

  # Geo-replication for disaster recovery
  dynamic "redis_configuration" {
    for_each = var.enable_disaster_recovery ? [1] : []
    content {
      # Additional configuration for geo-replication
      notify_keyspace_events = "Ex"
    }
  }

  # Patch schedule
  patch_schedule {
    day_of_week    = "Sunday"
    start_hour_utc = 2
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_storage_account.backup
  ]
}

# Secondary Redis Cache for Disaster Recovery
resource "azurerm_redis_cache" "secondary" {
  count               = var.enable_disaster_recovery ? 1 : 0
  name                = "${local.name_prefix}-redis-${local.secondary_location_short}"
  location            = var.location_secondary
  resource_group_name = azurerm_resource_group.secondary[0].name
  capacity            = 3
  family              = "P"
  sku_name            = "Premium"
  tags                = local.common_tags

  enable_non_ssl_port = false
  minimum_tls_version = "1.2"

  redis_configuration {
    maxmemory_reserved = 200
    maxmemory_delta    = 200
    maxmemory_policy   = "allkeys-lru"
  }

  public_network_access_enabled = false

  patch_schedule {
    day_of_week    = "Sunday"
    start_hour_utc = 3
  }

  identity {
    type = "SystemAssigned"
  }
}

# Redis Enterprise for High-Performance Scenarios
resource "azurerm_redis_enterprise_cluster" "wms_enterprise" {
  name                = "${local.name_prefix}-redisenterprise"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_name            = "Enterprise_E20-4"
  tags                = local.common_tags

  zones = ["1", "2", "3"]
}

resource "azurerm_redis_enterprise_database" "wms_sessions" {
  name                = "sessions"
  resource_group_name = azurerm_resource_group.main.name
  cluster_id          = azurerm_redis_enterprise_cluster.wms_enterprise.id

  client_protocol   = "Encrypted"
  clustering_policy = "EnterpriseCluster"
  eviction_policy   = "VolatileLRU"
  port              = 10000

  module {
    name = "RedisJSON"
  }

  module {
    name = "RedisTimeSeries"
  }
}

resource "azurerm_redis_enterprise_database" "wms_cache" {
  name                = "cache"
  resource_group_name = azurerm_resource_group.main.name
  cluster_id          = azurerm_redis_enterprise_cluster.wms_enterprise.id

  client_protocol   = "Encrypted"
  clustering_policy = "EnterpriseCluster"
  eviction_policy   = "AllKeysLRU"
  port              = 10001

  module {
    name = "RediSearch"
  }

  module {
    name = "RedisBloom"
  }
}

# CDN Profile for Static Content and Global Distribution
resource "azurerm_cdn_profile" "wms" {
  name                = "${local.name_prefix}-cdn"
  location            = "Global"
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard_Microsoft"
  tags                = local.common_tags
}

# CDN Endpoint for WMS Static Assets
resource "azurerm_cdn_endpoint" "wms_static" {
  name                = "${local.name_prefix}-static"
  profile_name        = azurerm_cdn_profile.wms.name
  location            = azurerm_cdn_profile.wms.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  origin_host_header = azurerm_storage_account.main.primary_blob_host

  origin {
    name      = "wms-storage"
    host_name = azurerm_storage_account.main.primary_blob_host
  }

  # Caching behavior
  global_delivery_rule {
    cache_expiration_action {
      behavior = "Override"
      duration = "1.12:00:00" # 1 day, 12 hours
    }

    cache_key_query_string_action {
      behavior   = "IgnoreQueryString"
      parameters = "version,timestamp"
    }
  }

  delivery_rule {
    name  = "Static Assets"
    order = 1

    url_file_extension_condition {
      operator         = "LessThan"
      match_values     = ["css", "js", "png", "jpg", "jpeg", "gif", "ico", "svg", "woff", "woff2"]
      transforms       = ["Lowercase"]
      negate_condition = false
    }

    cache_expiration_action {
      behavior = "Override"
      duration = "7.00:00:00" # 7 days
    }

    response_header_action {
      action      = "Append"
      header_name = "Cache-Control"
      value       = "public, max-age=604800, immutable"
    }
  }

  # API responses - shorter cache
  delivery_rule {
    name  = "API Responses"
    order = 2

    url_path_condition {
      operator     = "BeginsWith"
      match_values = ["/api/"]
      transforms   = ["Lowercase"]
    }

    cache_expiration_action {
      behavior = "Override"
      duration = "0.00:05:00" # 5 minutes
    }

    response_header_action {
      action      = "Append"
      header_name = "Cache-Control"
      value       = "public, max-age=300"
    }
  }
}

# Front Door for Global Load Balancing and Performance
resource "azurerm_cdn_frontdoor_profile" "wms" {
  name                = "${local.name_prefix}-frontdoor"
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Premium_AzureFrontDoor"
  tags                = local.common_tags

  response_timeout_seconds = 60
}

# Front Door Origin Group
resource "azurerm_cdn_frontdoor_origin_group" "wms" {
  name                     = "wms-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.wms.id
  session_affinity_enabled = true

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }

  health_probe {
    protocol            = "Http"
    interval_in_seconds = 100
    request_type        = "HEAD"
    path                = "/health"
  }
}

# Front Door Origins
resource "azurerm_cdn_frontdoor_origin" "wms_primary" {
  name                          = "wms-primary"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.wms.id
  enabled                       = true

  certificate_name_check_enabled = true
  host_name                      = azurerm_public_ip.app_gateway.fqdn
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = azurerm_public_ip.app_gateway.fqdn
  priority                       = 1
  weight                         = 1000
}

resource "azurerm_cdn_frontdoor_origin" "wms_secondary" {
  count                         = var.enable_disaster_recovery ? 1 : 0
  name                          = "wms-secondary"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.wms.id
  enabled                       = true

  certificate_name_check_enabled = true
  host_name                      = "wms-secondary.${var.location_secondary}.cloudapp.azure.com"
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = "wms-secondary.${var.location_secondary}.cloudapp.azure.com"
  priority                       = 2
  weight                         = 100
}

# Front Door Endpoint
resource "azurerm_cdn_frontdoor_endpoint" "wms" {
  name                     = "${local.name_prefix}-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.wms.id
  enabled                  = true
  tags                     = local.common_tags
}

# Front Door Route
resource "azurerm_cdn_frontdoor_route" "wms" {
  name                          = "wms-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.wms.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.wms.id
  enabled                       = true

  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]

  cdn_frontdoor_origin_ids = [
    azurerm_cdn_frontdoor_origin.wms_primary.id
  ]

  link_to_default_domain = true

  # Caching configuration
  cache {
    query_string_caching_behavior = "IgnoreSpecifiedQueryStrings"
    query_strings                 = ["utm_source", "utm_medium", "utm_campaign"]
    compression_enabled           = true
    content_types_to_compress = [
      "application/eot",
      "application/font",
      "application/font-sfnt",
      "application/javascript",
      "application/json",
      "application/opentype",
      "application/otf",
      "application/pkcs7-mime",
      "application/truetype",
      "application/ttf",
      "application/vnd.ms-fontobject",
      "application/xhtml+xml",
      "application/xml",
      "application/xml+rss",
      "application/x-font-opentype",
      "application/x-font-truetype",
      "application/x-font-ttf",
      "application/x-httpd-cgi",
      "application/x-javascript",
      "application/x-mpegurl",
      "application/x-opentype",
      "application/x-otf",
      "application/x-perl",
      "application/x-ttf",
      "font/eot",
      "font/ttf",
      "font/otf",
      "font/opentype",
      "image/svg+xml",
      "text/css",
      "text/csv",
      "text/html",
      "text/javascript",
      "text/js",
      "text/plain",
      "text/richtext",
      "text/tab-separated-values",
      "text/xml",
      "text/x-script",
      "text/x-component",
      "text/x-java-source"
    ]
  }
}

# Storage Account for Cache Backups and Static Content
resource "azurerm_storage_account" "backup" {
  name                     = "${replace(local.name_prefix, "-", "")}backup${local.primary_location_short}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.enable_disaster_recovery ? "GRS" : "LRS"
  account_kind             = "StorageV2"
  tags                     = local.common_tags

  # Security configurations
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false

  # Blob properties
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    # Container delete retention
    container_delete_retention_policy {
      days = 30
    }

    # Blob delete retention
    delete_retention_policy {
      days = 30
    }

    # Restore policy
    restore_policy {
      days = 29
    }
  }

  # Network rules
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]

    virtual_network_subnet_ids = [
      azurerm_subnet.subnets["aks"].id,
      azurerm_subnet.subnets["vmss"].id,
      azurerm_subnet.subnets["private_endpoints"].id
    ]
  }

  identity {
    type = "SystemAssigned"
  }
}

# Storage containers
resource "azurerm_storage_container" "redis_backups" {
  name                  = "redis-backups"
  storage_account_name  = azurerm_storage_account.backup.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "static_assets" {
  name                  = "static-assets"
  storage_account_name  = azurerm_storage_account.backup.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "wms_documents" {
  name                  = "wms-documents"
  storage_account_name  = azurerm_storage_account.backup.name
  container_access_type = "private"
}

# Private endpoint for backup storage
resource "azurerm_private_endpoint" "backup_storage" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${local.name_prefix}-pe-backup-storage"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.subnets["private_endpoints"].id
  tags                = local.common_tags

  private_service_connection {
    name                           = "backup-storage-private-connection"
    private_connection_resource_id = azurerm_storage_account.backup.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "backup-storage-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage[0].id]
  }
}

# Application Insights for Performance Monitoring
resource "azurerm_application_insights" "wms" {
  name                = "${local.name_prefix}-ai"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main.id
  tags                = local.common_tags

  # Retention and sampling
  retention_in_days   = 90
  daily_data_cap_in_gb = 10
  daily_data_cap_notifications_disabled = false
  sampling_percentage = 100

  # Disable IP masking for better analytics
  disable_ip_masking = false

  # Web tests for availability monitoring
  force_customer_storage_for_profiler = false
}

# Availability test for WMS endpoints
resource "azurerm_application_insights_web_test" "wms_availability" {
  name                    = "${local.name_prefix}-availability-test"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  application_insights_id = azurerm_application_insights.wms.id
  kind                    = "ping"
  frequency               = 300
  timeout                 = 60
  enabled                 = true
  geo_locations           = ["us-fl-mia-edge", "us-ca-sjc-azr", "us-tx-sn1-azr"]
  tags                    = local.common_tags

  configuration = <<XML
<WebTest Name="WMS Health Check" Id="ABD48585-0831-40CB-9069-682EA6BB3583" Enabled="True" CssProjectStructure="" CssIteration="" Timeout="60" WorkItemIds="" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010" Description="" CredentialsUserName="" CredentialsPassword="" PreAuthenticate="True" Proxy="default" StopOnError="False" RecordedResultFile="" ResultsLocale="">
  <Items>
    <Request Method="GET" Guid="a5f10126-e4cd-570d-961c-cea43999a200" Version="1.1" Url="${azurerm_cdn_frontdoor_endpoint.wms.host_name}/health" ThinkTime="0" Timeout="60" ParseDependentRequests="False" FollowRedirects="True" RecordResult="True" Cache="False" ResponseTimeGoal="0" Encoding="utf-8" ExpectedHttpStatusCode="200" ExpectedResponseUrl="" ReportingName="" IgnoreHttpStatusCode="False" />
  </Items>
</WebTest>
XML
}

# Performance optimization with Azure Traffic Manager (Global Load Balancing)
resource "azurerm_traffic_manager_profile" "wms" {
  name                   = "${local.name_prefix}-tm"
  resource_group_name    = azurerm_resource_group.main.name
  traffic_routing_method = "Performance"
  tags                   = local.common_tags

  dns_config {
    relative_name = "${local.name_prefix}-wms"
    ttl           = 100
  }

  monitor_config {
    protocol                     = "HTTPS"
    port                         = 443
    path                         = "/health"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3

    expected_status_code_ranges = [
      "200-202",
      "301-302"
    ]
  }
}

# Traffic Manager endpoints
resource "azurerm_traffic_manager_azure_endpoint" "primary" {
  name               = "primary"
  profile_id         = azurerm_traffic_manager_profile.wms.id
  weight             = 100
  target_resource_id = azurerm_public_ip.app_gateway.id
}

resource "azurerm_traffic_manager_azure_endpoint" "secondary" {
  count              = var.enable_disaster_recovery ? 1 : 0
  name               = "secondary"
  profile_id         = azurerm_traffic_manager_profile.wms.id
  weight             = 50
  target_resource_id = azurerm_public_ip.app_gateway.id
}
