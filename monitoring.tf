# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name_prefix}-law-${local.primary_location_short}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = local.common_tags

  # Daily cap to control costs
  daily_quota_gb = var.environment == "prod" ? -1 : 10
}

# Data Collection Rules for Azure Monitor Agent
resource "azurerm_monitor_data_collection_rule" "wms" {
  name                = "${local.name_prefix}-dcr"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.common_tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
      name                  = "wms-workspace"
    }
  }

  data_flow {
    streams      = ["Microsoft-Event"]
    destinations = ["wms-workspace"]
  }

  data_sources {
    windows_event_log {
      streams = ["Microsoft-Event"]
      name    = "wms-events"
      x_path_queries = [
        "Application!*[System[(Level=1 or Level=2 or Level=3)]]",
        "System!*[System[(Level=1 or Level=2 or Level=3)]]"
      ]
    }

    performance_counter {
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor(_Total)\\% Processor Time",
        "\\Memory\\Available Bytes",
        "\\LogicalDisk(_Total)\\Disk Reads/sec",
        "\\LogicalDisk(_Total)\\Disk Writes/sec",
        "\\Network Interface(*)\\Bytes Total/sec"
      ]
      name = "wms-perfcounters"
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf"]
    destinations = ["wms-workspace"]
  }
}

# Diagnostic Settings for Key Resources
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name               = "aks-diagnostics"
  target_resource_id = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "sql_primary" {
  name               = "sql-diagnostics"
  target_resource_id = azurerm_mssql_database.wms_primary.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "SQLInsights"
  }

  enabled_log {
    category = "AutomaticTuning"
  }

  enabled_log {
    category = "QueryStoreRuntimeStatistics"
  }

  enabled_log {
    category = "QueryStoreWaitStatistics"
  }

  enabled_log {
    category = "Errors"
  }

  enabled_log {
    category = "DatabaseWaitStatistics"
  }

  enabled_log {
    category = "Timeouts"
  }

  enabled_log {
    category = "Blocks"
  }

  metric {
    category = "Basic"
    enabled  = true
  }

  metric {
    category = "InstanceAndAppAdvanced"
    enabled  = true
  }

  metric {
    category = "WorkloadManagement"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "app_gateway" {
  name               = "appgw-diagnostics"
  target_resource_id = azurerm_application_gateway.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name               = "kv-diagnostics"
  target_resource_id = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Action Groups for Alerting
resource "azurerm_monitor_action_group" "critical" {
  name                = "${local.name_prefix}-critical-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "critical"
  tags                = local.common_tags

  email_receiver {
    name          = "oncall-team"
    email_address = "oncall@example.com"
  }

  sms_receiver {
    name         = "oncall-sms"
    country_code = "1"
    phone_number = "5555555555"
  }

  webhook_receiver {
    name        = "teams-webhook"
    service_uri = "https://outlook.office.com/webhook/..."
  }

  # Azure Function for custom alerting logic
  azure_function_receiver {
    name                     = "alert-processor"
    function_app_resource_id = azurerm_linux_function_app.alert_processor.id
    function_name            = "ProcessAlert"
    http_trigger_url         = "${azurerm_linux_function_app.alert_processor.default_hostname}/api/ProcessAlert"
  }
}

resource "azurerm_monitor_action_group" "warning" {
  name                = "${local.name_prefix}-warning-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "warning"
  tags                = local.common_tags

  email_receiver {
    name          = "ops-team"
    email_address = "ops@example.com"
  }
}

# Alert Rules for WMS-specific Metrics
resource "azurerm_monitor_metric_alert" "high_cpu" {
  name                = "wms-high-cpu"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_windows_virtual_machine_scale_set.wms_legacy.id]
  description         = "High CPU usage on WMS VMSS"
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.warning.id
  }

  severity = 2
}

resource "azurerm_monitor_metric_alert" "high_memory" {
  name                = "wms-high-memory"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_windows_virtual_machine_scale_set.wms_legacy.id]
  description         = "High memory usage on WMS VMSS"
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Available Memory Bytes"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1073741824 # 1GB in bytes
  }

  action {
    action_group_id = azurerm_monitor_action_group.warning.id
  }

  severity = 2
}

resource "azurerm_monitor_metric_alert" "aks_pod_restart" {
  name                = "aks-pod-restarts"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_kubernetes_cluster.main.id]
  description         = "High pod restart rate in AKS"
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "kube_pod_status_ready"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 0.9
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }

  severity = 1
}

resource "azurerm_monitor_metric_alert" "sql_dtu_high" {
  name                = "sql-dtu-high"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_mssql_database.wms_primary.id]
  description         = "High DTU usage on WMS database"
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = "dtu_consumption_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.warning.id
  }

  severity = 2
}

resource "azurerm_monitor_metric_alert" "cosmos_throttling" {
  name                = "cosmos-throttling"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_cosmosdb_account.wms_realtime.id]
  description         = "High throttling rate on CosmosDB"
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.DocumentDB/databaseAccounts"
    metric_name      = "TotalRequestUnits"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10000
  }

  action {
    action_group_id = azurerm_monitor_action_group.critical.id
  }

  severity = 1
}

# Log Analytics Queries for WMS Operations
resource "azurerm_log_analytics_saved_search" "failed_orders" {
  name                       = "WMS-Failed-Orders"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  category                   = "WMS"
  display_name               = "Failed Order Processing"

  query = <<EOF
AppInsights
| where TimeGenerated > ago(1h)
| where AppRoleName contains "order-service"
| where SeverityLevel >= 3
| summarize FailedOrders = count() by bin(TimeGenerated, 5m)
| render timechart
EOF
}

resource "azurerm_log_analytics_saved_search" "inventory_discrepancies" {
  name                       = "WMS-Inventory-Discrepancies"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  category                   = "WMS"
  display_name               = "Inventory Count Discrepancies"

  query = <<EOF
AppInsights
| where TimeGenerated > ago(1h)
| where AppRoleName contains "inventory-service"
| where Message contains "discrepancy"
| extend WarehouseId = tostring(customDimensions["warehouseId"])
| extend SKU = tostring(customDimensions["sku"])
| summarize Discrepancies = count() by WarehouseId, SKU
| order by Discrepancies desc
EOF
}

# Scheduled Query Rules for Complex Alerting
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "order_processing_failure" {
  name                = "order-processing-failure-rate"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  evaluation_frequency = "PT5M"
  window_duration      = "PT10M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 2

  criteria {
    query = <<-QUERY
      AppInsights
      | where TimeGenerated > ago(10m)
      | where AppRoleName contains "order-service"
      | where ResultCode != "200"
      | summarize FailureRate = (count() * 100.0) / toscalar(
          AppInsights
          | where TimeGenerated > ago(10m)
          | where AppRoleName contains "order-service"
          | count()
      )
      | where FailureRate > 5
    QUERY

    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.critical.id]
  }

  description = "Alert when order processing failure rate exceeds 5%"
  enabled     = true
}

# Azure Workbooks for WMS Dashboards
resource "azurerm_application_insights_workbook" "wms_operations" {
  name                = "${local.name_prefix}-wms-operations-workbook"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "WMS Operations Dashboard"
  tags                = local.common_tags

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "AppInsights | where TimeGenerated > ago(1h) | summarize Requests = count() by bin(TimeGenerated, 5m), AppRoleName | render columnchart"
          size = 0
          title = "Request Volume by Service"
          queryType = 0
          resourceType = "microsoft.insights/components"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "AppInsights | where TimeGenerated > ago(1h) | summarize AvgDuration = avg(DurationMs) by AppRoleName | render barchart"
          size = 0
          title = "Average Response Time by Service"
          queryType = 0
          resourceType = "microsoft.insights/components"
        }
      }
    ]
  })

  source_id = azurerm_application_insights.wms.id
}

# Function App for Custom Alert Processing
resource "azurerm_service_plan" "alert_processor" {
  name                = "${local.name_prefix}-asp-alerts"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = local.common_tags
}

resource "azurerm_linux_function_app" "alert_processor" {
  name                = "${local.name_prefix}-func-alerts"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.alert_processor.id
  tags                = local.common_tags

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  site_config {
    application_stack {
      python_version = "3.9"
    }
  }

  app_settings = {
    "AzureWebJobsStorage"               = azurerm_storage_account.main.primary_connection_string
    "FUNCTIONS_WORKER_RUNTIME"          = "python"
    "APPINSIGHTS_INSTRUMENTATIONKEY"    = azurerm_application_insights.wms.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.wms.connection_string
  }

  identity {
    type = "SystemAssigned"
  }
}

# Storage Account for Monitoring Data
resource "azurerm_storage_account" "main" {
  name                     = "${replace(local.name_prefix, "-", "")}stor${local.primary_location_short}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  tags                     = local.common_tags

  min_tls_version = "TLS1_2"

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

# Grafana Dashboard (Optional - if using Azure Managed Grafana)
resource "azurerm_dashboard_grafana" "wms" {
  count                             = var.environment == "prod" ? 1 : 0
  name                              = "${local.name_prefix}-grafana"
  resource_group_name               = azurerm_resource_group.main.name
  location                          = azurerm_resource_group.main.location
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = false
  tags                              = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.main[0].id
  }
}

# Azure Monitor Workspace for Prometheus metrics
resource "azurerm_monitor_workspace" "main" {
  count               = var.environment == "prod" ? 1 : 0
  name                = "${local.name_prefix}-amw"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.common_tags
}

# Data Collection Endpoint
resource "azurerm_monitor_data_collection_endpoint" "wms" {
  name                = "${local.name_prefix}-dce"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "Linux"
  tags                = local.common_tags

  public_network_access_enabled = false
}

# Smart Detection Rules for Application Insights
resource "azurerm_application_insights_smart_detection_rule" "failure_anomalies" {
  name                    = "Failure Anomalies - ${azurerm_application_insights.wms.name}"
  application_insights_id = azurerm_application_insights.wms.id
  enabled                 = true
  send_emails_to_subscription_owners = true

  additional_email_recipients = [
    "ops@example.com",
    "devops@example.com"
  ]
}

# Auto-Scale Settings for monitoring and cost optimization
resource "azurerm_monitor_autoscale_setting" "aks_nodepool" {
  name                = "${local.name_prefix}-aks-autoscale"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_kubernetes_cluster_node_pool.wms_workloads.id
  tags                = local.common_tags

  profile {
    name = "default"

    capacity {
      default = 3
      minimum = 2
      maximum = 20
    }

    rule {
      metric_trigger {
        metric_name        = "cpu_usage_active_millicores"
        metric_resource_id = azurerm_kubernetes_cluster.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "2"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "cpu_usage_active_millicores"
        metric_resource_id = azurerm_kubernetes_cluster.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}
