# Azure Kubernetes Service (AKS) for Containerized WMS Services
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${local.name_prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${local.name_prefix}-aks"
  kubernetes_version  = "1.28"
  tags                = local.common_tags

  # Node Resource Group
  node_resource_group = "${azurerm_resource_group.main.name}-nodes"

  # Default Node Pool
  default_node_pool {
    name                = "system"
    node_count          = var.aks_node_count
    vm_size             = var.aks_node_vm_size
    vnet_subnet_id      = azurerm_subnet.subnets["aks"].id
    type                = "VirtualMachineScaleSets"
    availability_zones  = ["1", "2", "3"]
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 10
    max_pods            = 30

    # Node pool upgrade settings
    upgrade_settings {
      max_surge = "33%"
    }

    # Node pool labels
    node_labels = {
      "node-type" = "system"
    }

    tags = local.common_tags
  }

  # Identity
  identity {
    type = "SystemAssigned"
  }

  # Network Profile
  network_profile {
    network_plugin      = "azure"
    network_policy      = "calico"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
    outbound_type       = "loadBalancer"
    load_balancer_sku   = "standard"
  }

  # API Server Access Profile
  api_server_access_profile {
    vnet_integration_enabled = true
    subnet_id               = azurerm_subnet.subnets["aks"].id
  }

  # Azure Active Directory Integration
  azure_active_directory_role_based_access_control {
    managed                = true
    tenant_id              = data.azurerm_client_config.current.tenant_id
    admin_group_object_ids = []
    azure_rbac_enabled     = true
  }

  # Add-ons
  azure_policy_enabled = true

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  # Auto-scaling
  auto_scaler_profile {
    balance_similar_node_groups      = false
    expander                        = "random"
    max_graceful_termination_sec    = 600
    max_node_provisioning_time      = "15m"
    max_unready_nodes              = 3
    max_unready_percentage         = 45
    new_pod_scale_up_delay         = "10s"
    scale_down_delay_after_add     = "10m"
    scale_down_delay_after_delete  = "20s"
    scale_down_delay_after_failure = "3m"
    scan_interval                  = "10s"
    scale_down_unneeded           = "10m"
    scale_down_unready            = "20m"
    scale_down_utilization_threshold = 0.5
  }

  # Maintenance window
  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [2, 3]
    }
  }

  depends_on = [
    azurerm_subnet.subnets,
    azurerm_log_analytics_workspace.main
  ]
}

# Additional Node Pool for WMS Workloads
resource "azurerm_kubernetes_cluster_node_pool" "wms_workloads" {
  name                  = "wmspool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size              = "Standard_D8s_v3"
  node_count           = 3
  vnet_subnet_id       = azurerm_subnet.subnets["aks"].id
  availability_zones   = ["1", "2", "3"]

  enable_auto_scaling = true
  min_count          = 2
  max_count          = 20
  max_pods           = 30

  node_labels = {
    "workload-type" = "wms"
    "node-type"     = "worker"
  }

  node_taints = [
    "workload=wms:NoSchedule"
  ]

  upgrade_settings {
    max_surge = "33%"
  }

  tags = merge(local.common_tags, {
    NodePool = "wms-workloads"
  })
}

# Virtual Machine Scale Set for Legacy WMS Components
resource "azurerm_windows_virtual_machine_scale_set" "wms_legacy" {
  name                = "${local.name_prefix}-vmss-legacy"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard_D4s_v3"
  instances           = var.vmss_instance_count
  admin_username      = "adminuser"
  admin_password      = random_password.vmss_admin.result
  tags                = local.common_tags

  # Disable password authentication (use certificates instead)
  disable_password_authentication = false

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Premium_LRS"
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

  # Auto-scaling configuration
  automatic_os_upgrade_policy {
    disable_automatic_rollback  = false
    enable_automatic_os_upgrade = true
  }

  upgrade_mode = "Automatic"

  # Health extension
  extension {
    name                 = "health"
    publisher            = "Microsoft.ManagedServices"
    type                 = "ApplicationHealthWindows"
    type_handler_version = "1.0"
    settings = jsonencode({
      protocol    = "http"
      port        = 8080
      requestPath = "/health"
    })
  }

  # Custom script extension for WMS setup
  extension {
    name                 = "CustomScript"
    publisher            = "Microsoft.Compute"
    type                 = "CustomScriptExtension"
    type_handler_version = "1.10"
    settings = jsonencode({
      commandToExecute = "powershell -ExecutionPolicy Unrestricted -File C:\\wms-setup.ps1"
    })
    protected_settings = jsonencode({
      fileUris = ["https://${azurerm_storage_account.main.name}.blob.core.windows.net/scripts/wms-setup.ps1"]
    })
  }

  depends_on = [
    azurerm_subnet.subnets
  ]
}

# Auto-scaling rules for VMSS
resource "azurerm_monitor_autoscale_setting" "vmss" {
  name                = "${local.name_prefix}-autoscale-vmss"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_windows_virtual_machine_scale_set.wms_legacy.id
  tags                = local.common_tags

  profile {
    name = "default"

    capacity {
      default = var.vmss_instance_count
      minimum = 2
      maximum = 10
    }

    # Scale out rule (CPU > 70%)
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

    # Scale in rule (CPU < 30%)
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.wms_legacy.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
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

    # Peak hours profile
    recurrence {
      timezone = "UTC"
      days     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
      hours    = [9]
      minutes  = [0]
    }
  }

  # Peak season profile (Black Friday, Christmas)
  profile {
    name = "peak-season"

    capacity {
      default = 8
      minimum = 5
      maximum = 20
    }

    fixed_date {
      timezone = "UTC"
      start    = "2024-11-15T00:00:00Z"
      end      = "2025-01-15T23:59:59Z"
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.wms_legacy.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT3M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 60
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "3"
        cooldown  = "PT3M"
      }
    }
  }

  notification {
    email {
      send_to_subscription_administrator = true
      custom_emails                      = []
    }
  }
}

# Load Balancer for VMSS
resource "azurerm_lb" "vmss" {
  name                = "${local.name_prefix}-lb-vmss"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  tags                = local.common_tags

  frontend_ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnets["vmss"].id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_lb_backend_address_pool" "vmss" {
  loadbalancer_id = azurerm_lb.vmss.id
  name            = "backend-pool"
}

resource "azurerm_lb_probe" "vmss" {
  loadbalancer_id = azurerm_lb.vmss.id
  name            = "health-probe"
  protocol        = "Http"
  port            = 8080
  request_path    = "/health"
}

resource "azurerm_lb_rule" "vmss" {
  loadbalancer_id                = azurerm_lb.vmss.id
  name                           = "wms-api"
  protocol                       = "Tcp"
  frontend_port                  = 8080
  backend_port                   = 8080
  frontend_ip_configuration_name = "internal"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.vmss.id]
  probe_id                       = azurerm_lb_probe.vmss.id
}

# Container Registry for WMS Images
resource "azurerm_container_registry" "main" {
  name                = "${replace(local.name_prefix, "-", "")}acr${local.primary_location_short}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Premium"
  admin_enabled       = false
  tags                = local.common_tags

  # Geo-replication for disaster recovery
  dynamic "georeplications" {
    for_each = var.enable_disaster_recovery ? [var.location_secondary] : []
    content {
      location                = georeplications.value
      zone_redundancy_enabled = true
      tags                    = local.common_tags
    }
  }

  # Network access
  public_network_access_enabled = false
  network_rule_bypass_option    = "AzureServices"

  # Trust policy
  trust_policy {
    enabled = true
  }

  # Retention policy
  retention_policy {
    days    = 30
    enabled = true
  }
}

# Private endpoint for ACR
resource "azurerm_private_endpoint" "acr" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${local.name_prefix}-pe-acr"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.subnets["private_endpoints"].id
  tags                = local.common_tags

  private_service_connection {
    name                           = "acr-private-connection"
    private_connection_resource_id = azurerm_container_registry.main.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr[0].id]
  }
}

# Random password for VMSS admin
resource "random_password" "vmss_admin" {
  length  = 16
  special = true
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Role assignment for AKS to ACR
resource "azurerm_role_assignment" "aks_acr" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                           = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}
