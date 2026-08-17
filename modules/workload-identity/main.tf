locals {
  # Flatten (identity, environment) pairs into one map: one federated credential each.
  federations = merge([
    for id_name, spec in var.identities : {
      for env in spec.environments : "${id_name}:${env}" => {
        identity    = id_name
        environment = env
      }
    }
  ]...)
}

# One user-assigned identity per requested role (plan / deploy / cleanup / ...).
resource "azurerm_user_assigned_identity" "this" {
  for_each = var.identities

  name                = "id-${var.workload_name}-${each.key}-${var.location_code}"
  resource_group_name = var.identity_resource_group_name
  location            = var.location
  tags                = var.tags
}

# GitHub OIDC federation: one credential per (identity, environment), exact subject.
resource "azurerm_federated_identity_credential" "this" {
  for_each = local.federations

  name                      = "github-${each.value.environment}"
  user_assigned_identity_id = azurerm_user_assigned_identity.this[each.value.identity].id
  audience                  = [var.audience]
  issuer                    = var.issuer
  subject                   = "${var.subject_prefix}:environment:${each.value.environment}"
}

# Control-plane RBAC — only ever on the workload's own resource group.
resource "azurerm_role_assignment" "resource_group" {
  for_each = var.identities

  scope                = var.workload_resource_group_id
  role_definition_name = each.value.resource_group_role
  principal_id         = azurerm_user_assigned_identity.this[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

# Data-plane RBAC — only ever on the shared state account.
resource "azurerm_role_assignment" "state" {
  for_each = var.identities

  scope                = var.state_storage_account_id
  role_definition_name = each.value.state_role
  principal_id         = azurerm_user_assigned_identity.this[each.key].principal_id
  principal_type       = "ServicePrincipal"
}
