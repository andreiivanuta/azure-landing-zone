data "azurerm_client_config" "current" {}

locals {
  # Same naming source as every other root; this root stays workload-agnostic.
  config = jsondecode(file("${path.module}/../config/project.json"))

  platform_prefix = local.config.platformPrefix
  location_code   = local.config.locationCode
  location        = local.config.location

  management_resource_group_name = "rg-${local.platform_prefix}-management-${local.location_code}"
  state_storage_account_name     = "st${local.platform_prefix}state${substr(sha1(data.azurerm_client_config.current.subscription_id), 0, 8)}"
}

# Shared platform resources created by the management root; referenced here.
data "azurerm_storage_account" "state" {
  name                = local.state_storage_account_name
  resource_group_name = local.management_resource_group_name
}

# Each workload's own resource group (assumed to exist; created by the trust anchor for now).
data "azurerm_resource_group" "workload" {
  for_each = var.workloads
  name     = each.value.resource_group_name
}

# Vend each workload's identities through the guardrailed module.
module "workload" {
  source   = "../modules/workload-identity"
  for_each = var.workloads

  workload_name                  = each.key
  location                       = local.location
  location_code                  = local.location_code
  management_resource_group_name = local.management_resource_group_name
  workload_resource_group_id     = data.azurerm_resource_group.workload[each.key].id
  state_storage_account_id       = data.azurerm_storage_account.state.id
  subject_prefix                 = each.value.subject_prefix
  identities                     = each.value.identities
  tags                           = var.tags
}
