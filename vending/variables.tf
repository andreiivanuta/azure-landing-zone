variable "workloads" {
  description = "Workloads to vend, keyed by workload name. Each entry is a declaration passed to the workload-identity module. Real values live in a gitignored workloads.auto.tfvars (the manual intake form)."
  type = map(object({
    subject_prefix      = string
    resource_group_name = string
    identities = map(object({
      resource_group_role = string
      state_role          = string
      environments        = list(string)
    }))
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to the identities vended by this root."
  type        = map(string)
  default = {
    project    = "azure-landing-zone"
    layer      = "vending"
    managed_by = "terraform"
  }
}
