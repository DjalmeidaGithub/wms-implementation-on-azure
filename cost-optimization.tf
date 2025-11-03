# Azure Cost Management and Budgets
resource "azurerm_consumption_budget_resource_group" "wms_monthly" {
  name              = "${local.name_prefix}-monthly-budget"
  resource_group_id = azurerm_resource_group.main.id

  amount     = 5000
  time_grain = "Monthly"

  time_period {
    start_date = "2024-01-01T00:00:00Z"
    end_date   = "2025-12-31T23:59:59Z"
  }

  filter {
    dimension {
      name = "ResourceId"
      values = [
        azurerm_resource_group.main.id
      ]
    }
  }

  notification {
    enabled        = true
    threshold      = 80.0
    operator       = "EqualTo"
    threshold_type = "Actual"

    contact_emails = [
      "finance@example.com",
      "ops@example.com"
    ]

    contact_groups = []
    contact_roles = [
      "Owner",
      "Contributor"
    ]
  }

  notification {
    enabled        = true
    threshold      = 100.0
    operator       = "EqualTo"
    threshold_type = "Forecasted"

    contact_emails = [
      "finance@example.com",
      "ops@example.com"
    ]
  }
}

# DevTest Labs for Development Environments
resource "azurerm_dev_test_lab" "wms" {
  count               = var.environment == "dev" ? 1 : 0
  name                = "${local.name_prefix}-devtestlab"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  # Cost management policies
  storage_type                 = "Standard"
  premium_data_disk_enabled    = false
  lab_encryption_enabled       = true
  extended_properties = {
    "EnvironmentPermission" = "Reader"
  }
}

# Auto-shutdown policy for development VMs
resource "azurerm_dev_test_global_vm_shutdown_schedule" "wms_dev_shutdown" {
  count              = var.auto_shutdown_enabled && var.environment != "prod" ? 1 : 0
  location           = azurerm_resource_group.main.location
  virtual_machine_id = azurerm_windows_virtual_machine_scale_set.wms_legacy.id

  daily_recurrence_time = "1900"
  timezone             = "Pacific Standard Time"
  enabled              = true

  notification_settings {
    enabled         = true
    time_in_minutes = "30"
    webhook_url     = "https://sample-webhook-url.example.com"
    email           = "ops@example.com"
  }

  tags = local.common_tags
}

# Reserved Instance recommendations via Policy
resource "azurerm_policy_definition" "reserved_instance_recommendation" {
  name         = "wms-reserved-instance-policy"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "WMS Reserved Instance Recommendation"
  description  = "Recommends reserved instances for consistent workloads"

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field = "type"
          equals = "Microsoft.Compute/virtualMachines"
        },
        {
          field = "Microsoft.Compute/virtualMachines/sku.name"
          in = ["Standard_D4s_v3", "Standard_D8s_v3"]
        }
      ]
    }
    then = {
      effect = "audit"
      details = {
        type = "Microsoft.Advisor/recommendations"
      }
    }
  })

  metadata = jsonencode({
    category = "Cost Optimization"
  })
}

# Azure Advisor Cost Recommendations
resource "azurerm_advisor_suppressions" "vm_right_sizing" {
  name                     = "vm-right-sizing-suppression"
  recommendation_id        = "*"
  resource_id              = azurerm_windows_virtual_machine_scale_set.wms_legacy.id
  suppression_id           = "${local.name_prefix}-vm-right-sizing"
  ttl                      = "00:00:00"
}

# Storage lifecycle management for cost optimization
resource "azurerm_storage_management_policy" "wms_lifecycle" {
  storage_account_id = azurerm_storage_account.main.id

  rule {
    name    = "wms-data-lifecycle"
    enabled = true

    filters {
      prefix_match = ["wms-documents/", "backup/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than          = 2555 # 7 years
      }

      snapshot {
        change_tier_to_cool_after_days_since_creation    = 30
        change_tier_to_archive_after_days_since_creation = 90
        delete_after_days_since_creation_greater_than    = 90
      }

      version {
        change_tier_to_cool_after_days_since_creation    = 30
        change_tier_to_archive_after_days_since_creation = 90
        delete_after_days_since_creation                 = 90
      }
    }
  }

  rule {
    name    = "temp-data-cleanup"
    enabled = true

    filters {
      prefix_match = ["temp/", "logs/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 30
      }
    }
  }
}

# Azure Hybrid Benefit configuration
locals {
  # Enable Azure Hybrid Benefit for Windows Server licenses
  hybrid_benefit_enabled = var.environment == "prod" && var.reserved_instance_enabled

  # Spot instance configuration for non-critical workloads
  spot_instance_config = var.environment != "prod" ? {
    eviction_policy = "Delete"
    max_bid_price   = -1 # Use current pay-as-you-go price
  } : null
}

# Spot Virtual Machine Scale Set for cost-effective development
resource "azurerm_windows_virtual_machine_scale_set" "wms_spot" {
  count               = var.environment == "dev" ? 1 : 0
  name                = "${local.name_prefix}-vmss-spot"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard_D2s_v3"
  instances           = 1
  admin_username      = "adminuser"
  admin_password      = random_password.vmss_admin.result
  tags                = merge(local.common_tags, { "CostOptimized" = "Spot" })

  priority        = "Spot"
  eviction_policy = "Delete"
  max_bid_price   = 0.05 # Maximum bid price per hour

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS" # Use cheaper storage for dev
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "internal"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.subnets["vmss"].id
    }
  }

  # Scale-in policy to remove oldest instances first
  scale_in_policy = "OldestVM"

  # Automatic OS upgrades disabled for spot instances
  upgrade_mode = "Manual"
}

# Azure Cost Analysis Export for detailed billing
resource "azurerm_cost_management_export_resource_group" "wms_cost_analysis" {
  name                    = "${local.name_prefix}-cost-export"
  resource_group_id       = azurerm_resource_group.main.id
  recurrence_type         = "Monthly"
  recurrence_period_start = "2024-01-01T00:00:00Z"
  recurrence_period_end   = "2025-12-31T23:59:59Z"

  export_data_storage_location {
    container_id     = "${azurerm_storage_account.main.id}/blobServices/default/containers/${azurerm_storage_container.cost_reports.name}"
    root_folder_path = "/cost-reports"
  }

  export_data_options {
    type       = "ActualCost"
    time_frame = "MonthToDate"
  }
}

# Storage container for cost reports
resource "azurerm_storage_container" "cost_reports" {
  name                  = "cost-reports"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Function App for Cost Optimization Automation
resource "azurerm_service_plan" "cost_optimizer" {
  name                = "${local.name_prefix}-asp-cost"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan for cost efficiency
  tags                = local.common_tags
}

resource "azurerm_linux_function_app" "cost_optimizer" {
  name                = "${local.name_prefix}-func-cost"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.cost_optimizer.id
  tags                = local.common_tags

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  site_config {
    application_stack {
      python_version = "3.9"
    }

    # CORS for web dashboard
    cors {
      allowed_origins = [
        "https://portal.azure.com",
        "https://${local.name_prefix}-wms.azurewebsites.net"
      ]
    }
  }

  app_settings = {
    "AzureWebJobsStorage"               = azurerm_storage_account.main.primary_connection_string
    "FUNCTIONS_WORKER_RUNTIME"          = "python"
    "APPINSIGHTS_INSTRUMENTATIONKEY"    = azurerm_application_insights.wms.instrumentation_key
    "SUBSCRIPTION_ID"                   = data.azurerm_client_config.current.subscription_id
    "RESOURCE_GROUP_NAME"               = azurerm_resource_group.main.name
    "ENVIRONMENT"                       = var.environment
  }

  identity {
    type = "SystemAssigned"
  }
}

# Role assignment for cost optimization function
resource "azurerm_role_assignment" "cost_optimizer_reader" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Cost Management Reader"
  principal_id         = azurerm_linux_function_app.cost_optimizer.identity[0].principal_id
}

resource "azurerm_role_assignment" "cost_optimizer_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.cost_optimizer.identity[0].principal_id
}

# Database auto-scaling for cost optimization
resource "azurerm_mssql_database_extended_auditing_policy" "wms_primary_audit" {
  database_id            = azurerm_mssql_database.wms_primary.id
  storage_endpoint       = azurerm_storage_account.main.primary_blob_endpoint
  retention_in_days      = 30
  log_monitoring_enabled = true
}

# Auto-scaling rules for cost optimization during off-hours
resource "azurerm_monitor_autoscale_setting" "cost_optimized_scaling" {
  name                = "${local.name_prefix}-cost-optimized-scaling"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_windows_virtual_machine_scale_set.wms_legacy.id
  tags                = local.common_tags

  # Business hours profile (higher capacity)
  profile {
    name = "business-hours"

    capacity {
      default = var.vmss_instance_count
      minimum = 2
      maximum = 10
    }

    recurrence {
      timezone = "Pacific Standard Time"
      days     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
      hours    = [8]
      minutes  = [0]
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.wms_legacy.id
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
  }

  # Off-hours profile (reduced capacity for cost savings)
  profile {
    name = "off-hours"

    capacity {
      default = 1
      minimum = 1
      maximum = 3
    }

    recurrence {
      timezone = "Pacific Standard Time"
      days     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
      hours    = [18]
      minutes  = [0]
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.wms_legacy.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 80
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  # Weekend profile (minimal capacity)
  profile {
    name = "weekend"

    capacity {
      default = 1
      minimum = 1
      maximum = 2
    }

    recurrence {
      timezone = "Pacific Standard Time"
      days     = ["Saturday", "Sunday"]
      hours    = [0]
      minutes  = [0]
    }
  }
}

# Tag-based cost allocation
resource "azurerm_policy_definition" "cost_center_tagging" {
  name         = "enforce-cost-center-tags"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Enforce Cost Center Tags"
  description  = "Ensures all resources have cost center tags for proper chargeback"

  policy_rule = jsonencode({
    if = {
      anyOf = [
        {
          field = "tags['CostCenter']"
          exists = "false"
        },
        {
          field = "tags['Project']"
          exists = "false"
        },
        {
          field = "tags['Environment']"
          exists = "false"
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })

  metadata = jsonencode({
    category = "Tags"
  })
}

resource "azurerm_policy_assignment" "cost_center_tagging" {
  name                 = "enforce-cost-tags"
  scope                = azurerm_resource_group.main.id
  policy_definition_id = azurerm_policy_definition.cost_center_tagging.id
  display_name         = "Enforce Cost Center Tagging"

  parameters = jsonencode({
    tagName = {
      value = "CostCenter"
    }
  })

  identity {
    type = "SystemAssigned"
  }
}

# Logic App for automated cost optimization workflows
resource "azurerm_logic_app_workflow" "cost_optimization" {
  name                = "${local.name_prefix}-cost-optimization-workflow"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  # Workflow definition for cost optimization tasks
  # This would contain the actual workflow JSON, but keeping it simple here
  workflow_schema   = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version  = "1.0.0.0"

  # Sample workflow parameters
  parameters = {
    "subscription_id" = {
      type         = "string"
      defaultValue = data.azurerm_client_config.current.subscription_id
    }
  }
}

# Cost anomaly detection alert
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "cost_anomaly" {
  name                = "cost-anomaly-detection"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  evaluation_frequency = "P1D" # Daily
  window_duration      = "P7D" # 7-day window
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 2

  criteria {
    query = <<-QUERY
      AzureCosts
      | where TimeGenerated > ago(7d)
      | where ResourceGroup == "${azurerm_resource_group.main.name}"
      | summarize CurrentCost = sum(CostInBillingCurrency) by bin(TimeGenerated, 1d)
      | extend PreviousWeekCost = prev(CurrentCost, 7)
      | extend CostIncrease = (CurrentCost - PreviousWeekCost) / PreviousWeekCost * 100
      | where CostIncrease > 20
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
    action_groups = [azurerm_monitor_action_group.warning.id]
  }

  description = "Alert when daily costs increase by more than 20% compared to previous week"
  enabled     = true
}
