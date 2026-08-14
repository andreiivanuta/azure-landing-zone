# The shared contract the vending root and every workload consume.

output "management_resource_group_name" {
  description = "Persistent resource group holding the state account and CI identities."
  value       = data.azurerm_resource_group.management.name
}

output "state_storage_account_name" {
  description = "Storage account name for Terraform state backends."
  value       = azurerm_storage_account.state.name
}

output "state_storage_account_id" {
  description = "Storage account resource ID (scope for state data-plane roles)."
  value       = azurerm_storage_account.state.id
}

output "state_container_name" {
  description = "Blob container holding Terraform state."
  value       = azurerm_storage_container.tfstate.name
}

output "location" {
  description = "Azure region for the platform."
  value       = local.location
}
