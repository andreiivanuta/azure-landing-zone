data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "bootstrap" {
  name = local.bootstrap_resource_group_name
}

locals {
  # Single source of truth for shared naming inputs, read by every tool.
  config = jsondecode(file("${path.module}/../config/project.json"))

  # Derived to match the Bicep trust anchor; override via var.bootstrap_resource_group_name.
  bootstrap_resource_group_name = coalesce(var.bootstrap_resource_group_name, "rg-${local.config.projectPrefix}-bootstrap-${local.config.locationCode}")

  # Deterministic, globally-unique name: a subscription hash avoids disclosing the ID.
  state_storage_account_name = "st${local.config.projectPrefix}state${substr(sha1(data.azurerm_client_config.current.subscription_id), 0, 8)}"

  common_tags = merge(var.tags, {
    lifecycle = "persistent"
    purpose   = "terraform-state"
  })
}

resource "azurerm_storage_account" "state" {
  name                = local.state_storage_account_name
  resource_group_name = data.azurerm_resource_group.bootstrap.name
  location            = data.azurerm_resource_group.bootstrap.location

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
