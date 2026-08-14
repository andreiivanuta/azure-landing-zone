output "workload_identity_client_ids" {
  description = "Vended identity client IDs, keyed by workload then role. Seed into each workload repo's GitHub environment variables."
  value       = { for name, mod in module.workload : name => mod.identity_client_ids }
}
