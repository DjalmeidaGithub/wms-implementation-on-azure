# Azure Key Vault for Secrets Management
resource "azurerm_key_vault" "main" {
  name                = "${replace(local.name_prefix, "-", "")}kv${local.primary_location_short}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "premium"
  tags                = local.common_tags

  # Security features
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  purge_protection_enabled        = true
  soft_delete_retention_days      = 7

  # Network access
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"

    virtual_network_subnet_ids = [
      azurerm_subnet.subnets["aks"].id,
      azurerm_subnet.subnets["vmss"].id,
      azurerm_subnet.subnets["private_endpoints"].id
    ]

    ip_rules = var.allowed_ip_ranges
  }
}

# Key Vault Access Policies
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Create", "Get", "List", "Update", "Delete", "Backup", "Restore", "Recover", "Purge"
  ]

  secret_permissions = [
    "Set", "Get", "List", "Delete", "Backup", "Restore", "Recover", "Purge"
  ]

  certificate_permissions = [
    "Create", "Get", "List", "Update", "Delete", "ManageContacts", "ManageIssuers",
    "GetIssuers", "ListIssuers", "SetIssuers", "DeleteIssuers", "Backup", "Restore",
    "Recover", "Purge"
  ]
}

resource "azurerm_key_vault_access_policy" "sql_server" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_mssql_server.primary.identity[0].principal_id

  key_permissions = [
    "Get", "WrapKey", "UnwrapKey"
  ]
}

resource "azurerm_key_vault_access_policy" "aks" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].object_id

  secret_permissions = [
    "Get", "List"
  ]
}

# Key Vault Secrets
resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  value        = random_password.sql_admin.result
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

resource "azurerm_key_vault_secret" "vmss_admin_password" {
  name         = "vmss-admin-password"
  value        = random_password.vmss_admin.result
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

resource "azurerm_key_vault_secret" "vpn_shared_key" {
  name         = "vpn-shared-key"
  value        = random_password.vpn_shared_key.result
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

resource "azurerm_key_vault_secret" "redis_auth_string" {
  name         = "redis-auth-string"
  value        = azurerm_redis_cache.primary.auth_string
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# Key for SQL TDE
resource "azurerm_key_vault_key" "sql_tde" {
  name         = "sql-tde-key"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"
  ]

  tags = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# SSL Certificate for Application Gateway
resource "azurerm_key_vault_certificate" "app_gateway" {
  name         = "app-gateway-ssl"
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject_alternative_names {
        dns_names = [
          "${local.name_prefix}-wms.${var.location}.cloudapp.azure.com",
          "*.${local.name_prefix}-wms.com"
        ]
      }

      subject            = "CN=${local.name_prefix}-wms.com"
      validity_in_months = 12
    }
  }

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# Private Endpoint for Key Vault
resource "azurerm_private_endpoint" "keyvault" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "${local.name_prefix}-pe-kv"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.subnets["private_endpoints"].id
  tags                = local.common_tags

  private_service_connection {
    name                           = "keyvault-private-connection"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "keyvault-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.keyvault[0].id]
  }
}

# Azure AD Groups for Role-Based Access Control
resource "azuread_group" "wms_admins" {
  display_name     = "${local.name_prefix}-wms-admins"
  owners           = [data.azurerm_client_config.current.object_id]
  security_enabled = true
  description      = "WMS System Administrators"

  members = [
    data.azurerm_client_config.current.object_id
  ]
}

resource "azuread_group" "wms_operators" {
  display_name     = "${local.name_prefix}-wms-operators"
  owners           = [data.azurerm_client_config.current.object_id]
  security_enabled = true
  description      = "WMS Warehouse Operators"
}

resource "azuread_group" "wms_readonly" {
  display_name     = "${local.name_prefix}-wms-readonly"
  owners           = [data.azurerm_client_config.current.object_id]
  security_enabled = true
  description      = "WMS Read-Only Users (Reporting, Analytics)"
}

# Custom RBAC Role for WMS Operations
resource "azurerm_role_definition" "wms_operator" {
  name        = "WMS Operator"
  scope       = azurerm_resource_group.main.id
  description = "Custom role for WMS operators with specific permissions"

  permissions {
    actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
      "Microsoft.Sql/servers/databases/read",
      "Microsoft.Sql/servers/databases/query/action",
      "Microsoft.DocumentDB/databaseAccounts/readonlykeys/action",
      "Microsoft.DocumentDB/databaseAccounts/read",
      "Microsoft.Cache/redis/read",
      "Microsoft.Insights/metrics/read",
      "Microsoft.Insights/logs/read"
    ]

    not_actions = [
      "Microsoft.Sql/servers/databases/delete",
      "Microsoft.Storage/storageAccounts/delete",
      "Microsoft.DocumentDB/databaseAccounts/delete"
    ]

    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write"
    ]
  }

  assignable_scopes = [
    azurerm_resource_group.main.id
  ]
}

# Role Assignments
resource "azurerm_role_assignment" "wms_admins_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.wms_admins.object_id
}

resource "azurerm_role_assignment" "wms_operators_custom" {
  scope              = azurerm_resource_group.main.id
  role_definition_id = azurerm_role_definition.wms_operator.role_definition_resource_id
  principal_id       = azuread_group.wms_operators.object_id
}

resource "azurerm_role_assignment" "wms_readonly_reader" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azuread_group.wms_readonly.object_id
}

# Managed Identity for WMS Applications
resource "azurerm_user_assigned_identity" "wms_app" {
  name                = "${local.name_prefix}-wms-app-identity"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Key Vault access for WMS App Identity
resource "azurerm_key_vault_access_policy" "wms_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.wms_app.principal_id

  secret_permissions = [
    "Get", "List"
  ]

  key_permissions = [
    "Get", "List"
  ]
}

# Azure Security Center (Defender for Cloud)
resource "azurerm_security_center_subscription_pricing" "vm" {
  tier          = "Standard"
  resource_type = "VirtualMachines"
}

resource "azurerm_security_center_subscription_pricing" "sql" {
  tier          = "Standard"
  resource_type = "SqlServers"
}

resource "azurerm_security_center_subscription_pricing" "storage" {
  tier          = "Standard"
  resource_type = "StorageAccounts"
}

resource "azurerm_security_center_subscription_pricing" "kubernetes" {
  tier          = "Standard"
  resource_type = "KubernetesService"
}

# Security Center Contact
resource "azurerm_security_center_contact" "main" {
  email = "security@example.com"
  phone = "+1-555-555-5555"

  alert_notifications = true
  alerts_to_admins    = true
}

# Private DNS Zones for Private Endpoints
resource "azurerm_private_dns_zone" "keyvault" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "sql" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "cosmos" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.documents.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "storage" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "acr" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "data_factory" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.datafactory.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Link Private DNS Zones to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "keyvault-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "sql-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.sql[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "cosmos-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "storage-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "acr-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "data_factory" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "df-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.data_factory[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = local.common_tags
}

# Azure Policy for Compliance
resource "azurerm_policy_definition" "wms_compliance" {
  name         = "wms-compliance-policy"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "WMS Compliance Policy"
  description  = "Ensures WMS resources comply with security standards"

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field = "type"
          in = [
            "Microsoft.Storage/storageAccounts",
            "Microsoft.Sql/servers",
            "Microsoft.DocumentDB/databaseAccounts"
          ]
        }
      ]
    }
    then = {
      effect = "audit"
      details = {
        type = "Microsoft.Security/assessments"
        name = "4fb67663-9ab9-475d-b026-8c544cced439"
      }
    }
  })

  metadata = jsonencode({
    category = "Security"
  })
}

# Policy Assignment
resource "azurerm_policy_assignment" "wms_compliance" {
  name                 = "wms-compliance-assignment"
  scope                = azurerm_resource_group.main.id
  policy_definition_id = azurerm_policy_definition.wms_compliance.id
  display_name         = "WMS Compliance Policy Assignment"
  description          = "Assigns WMS compliance policy to resource group"

  identity {
    type = "SystemAssigned"
  }

  location = azurerm_resource_group.main.location
}

# Network Watcher for Security Monitoring
resource "azurerm_network_watcher" "main" {
  name                = "${local.name_prefix}-nw-${local.primary_location_short}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Network Security Group Flow Logs
resource "azurerm_network_watcher_flow_log" "main" {
  for_each = azurerm_network_security_group.main

  network_watcher_name = azurerm_network_watcher.main.name
  resource_group_name  = azurerm_resource_group.main.name
  name                 = "${each.key}-flow-log"

  network_security_group_id = each.value.id
  storage_account_id        = azurerm_storage_account.main.id
  enabled                   = true

  retention_policy {
    enabled = true
    days    = 30
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.main.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.main.location
    workspace_resource_id = azurerm_log_analytics_workspace.main.id
    interval_in_minutes   = 10
  }

  tags = local.common_tags
}
