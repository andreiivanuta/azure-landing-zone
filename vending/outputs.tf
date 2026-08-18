output "workload_name" {
  description = "The workload that was vended."
  value       = var.workload_name
}

output "workload_identity_client_ids" {
  description = "Vended identity client IDs keyed by role. Seed into the workload repo's GitHub environment variables."
  value       = module.workload.identity_client_ids
}

output "environment_client_ids" {
  description = "GitHub environment name -> client ID to set as AZURE_CLIENT_ID in that environment of the workload repo."
  value       = module.workload.environment_client_ids
}

output "workload_repo_slug" {
  description = "The workload repository as owner/repo, parsed from the subject prefix; identifies which repo to seed."
  value       = join("/", regex("^repo:([^@]+)@[0-9]+/([^@/]+)@[0-9]+$", var.workload.subject_prefix))
}
