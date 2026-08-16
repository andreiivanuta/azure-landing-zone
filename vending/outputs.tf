output "workload_name" {
  description = "The workload that was vended."
  value       = var.workload_name
}

output "workload_identity_client_ids" {
  description = "Vended identity client IDs keyed by role. Seed into the workload repo's GitHub environment variables."
  value       = module.workload.identity_client_ids
}
