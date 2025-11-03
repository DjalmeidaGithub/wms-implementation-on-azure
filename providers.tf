# Provider Configurations
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {
  # Azure AD provider configuration
}

provider "random" {
  # Random provider for generating passwords and IDs
}

provider "time" {
  # Time provider for scheduling and delays
}
