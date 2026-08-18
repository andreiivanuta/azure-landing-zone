locals {
  # Platform naming from the shared config — used ONLY for the platform RGs + state account.
  # A workload's own region and name come from its tfvars, never from here.
  config = jsondecode(file("${path.module}/../config/project.json"))

  platform_prefix        = local.config.platformPrefix
  platform_location_code = local.config.locationCode

  management_resource_group_name = "rg-${local.platform_prefix}-management-${local.platform_location_code}"
  identity_resource_group_name   = "rg-${local.platform_prefix}-identity-${local.platform_location_code}"

  # A workload may set its own region; otherwise it defaults to the platform region.
  workload_location      = coalesce(var.workload.location, local.config.location)
  workload_location_code = coalesce(var.workload.location_code, local.config.locationCode)
}

# The state account is provisioned by the Bicep seed; its uniqueString-based name can't be derived here, so it's passed in.
data "azurerm_storage_account" "state" {
  name                = var.state_storage_account_name
  resource_group_name = local.management_resource_group_name
}

# Platform pipeline identities (created by the Bicep trust anchor, deterministic names in the management RG).
# They receive read-only Reader on each workload RG so the pipeline can enumerate live contents for the
# destroy blast-radius check and the offboard preview. Looked up here to avoid plumbing principal IDs.
data "azurerm_user_assigned_identity" "vending" {
  name                = "id-${local.platform_prefix}-vending-${local.platform_location_code}"
  resource_group_name = local.management_resource_group_name
}

data "azurerm_user_assigned_identity" "vending_pr" {
  name                = "id-${local.platform_prefix}-vending-pr-${local.platform_location_code}"
  resource_group_name = local.management_resource_group_name
}

# The workload's own resource group — created (and destroyed) by vending, so onboarding needs no manual step.
resource "azurerm_resource_group" "workload" {
  name     = var.workload.resource_group_name
  location = local.workload_location
  tags = merge(
    var.tags,
    { workload = var.workload_name },
    var.workload.owner != null ? { owner = var.workload.owner } : {},
  )
}

# Vend this one workload's identities through the guardrailed module.
module "workload" {
  source = "../modules/workload-identity"

  workload_name                = var.workload_name
  location                     = local.workload_location
  location_code                = local.workload_location_code
  identity_resource_group_name = local.identity_resource_group_name
  workload_resource_group_id   = azurerm_resource_group.workload.id
  state_storage_account_id     = data.azurerm_storage_account.state.id
  subject_prefix               = var.workload.subject_prefix
  identities                   = var.workload.identities
  platform_reader_principal_ids = [
    data.azurerm_user_assigned_identity.vending.principal_id,
    data.azurerm_user_assigned_identity.vending_pr.principal_id,
  ]
  tags = var.tags
}
