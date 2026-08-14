output "identity_client_ids" {
  description = "Client IDs of the vended identities, keyed by role. Seed these into the workload's GitHub environment variables."
  value       = { for name, identity in azurerm_user_assigned_identity.this : name => identity.client_id }
}

output "identity_principal_ids" {
  description = "Principal (object) IDs of the vended identities, keyed by role."
  value       = { for name, identity in azurerm_user_assigned_identity.this : name => identity.principal_id }
}
