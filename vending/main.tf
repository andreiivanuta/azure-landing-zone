locals {
  # Platform naming from the shared config — used ONLY for the management RG + state account.
  # A workload's own region and name come from its tfvars, never from here.
  config = jsondecode(file("${path.module}/../config/project.json"))

  platform_prefix        = local.config.platformPrefix
  platform_location_code = local.config.locationCode

  management_resource_group_name = "rg-${local.platform_prefix}-management-${local.platform_location_code}"
}

# The state account is provisioned by the Bicep seed; its uniqueString-based name can't be derived here, so it's passed in.
data "azurerm_storage_account" "state" {
  name                = var.state_storage_account_name
  resource_group_name = local.management_resource_group_name
}

# The workload's own resource group (assumed to already exist).
data "azurerm_resource_group" "workload" {
  name = var.workload.resource_group_name
}

# Vend this one workload's identities through the guardrailed module.
module "workload" {
  source = "../modules/workload-identity"

  workload_name                  = var.workload_name
  location                       = var.workload.location
  location_code                  = var.workload.location_code
  management_resource_group_name = local.management_resource_group_name
  workload_resource_group_id     = data.azurerm_resource_group.workload.id
  state_storage_account_id       = data.azurerm_storage_account.state.id
  subject_prefix                 = var.workload.subject_prefix
  identities                     = var.workload.identities
  tags                           = var.tags
}
