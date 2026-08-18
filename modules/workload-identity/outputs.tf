output "identity_client_ids" {
  description = "Client IDs of the vended identities, keyed by role. Seed these into the workload's GitHub environment variables."
  value       = { for name, identity in azurerm_user_assigned_identity.this : name => identity.client_id }
}

output "identity_principal_ids" {
  description = "Principal (object) IDs of the vended identities, keyed by role."
  value       = { for name, identity in azurerm_user_assigned_identity.this : name => identity.principal_id }
}

output "environment_client_ids" {
  description = "GitHub environment name -> client ID of the identity federated to it. Seed AZURE_CLIENT_ID per environment in the workload repo from this."
  value = {
    for key, fed in local.federations :
    fed.environment => azurerm_user_assigned_identity.this[fed.identity].client_id
  }
}
