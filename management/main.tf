data "azurerm_client_config" "current" {}

locals {
  # Single source of truth for shared naming inputs, read by every tool.
  config = jsondecode(file("${path.module}/../config/project.json"))

  platform_prefix = local.config.platformPrefix
  location_code   = local.config.locationCode
  location        = local.config.location

  management_resource_group_name = coalesce(var.management_resource_group_name, "rg-${local.platform_prefix}-management-${local.location_code}")

  # Deterministic, globally-unique name: a subscription hash avoids disclosing the ID.
  state_storage_account_name = "st${local.platform_prefix}state${substr(sha1(data.azurerm_client_config.current.subscription_id), 0, 8)}"

  common_tags = merge(var.tags, {
    lifecycle = "persistent"
    purpose   = "terraform-state"
  })
}

data "azurerm_resource_group" "management" {
  name = local.management_resource_group_name
}

# The one shared state backend, consumed by every workload's Terraform (each via its own key).
resource "azurerm_storage_account" "state" {
  name                = local.state_storage_account_name
  resource_group_name = data.azurerm_resource_group.management.name
  location            = data.azurerm_resource_group.management.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  public_network_access_enabled   = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}
