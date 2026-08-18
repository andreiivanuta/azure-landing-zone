variable "workload_name" {
  description = "Short lowercase name of the workload being vended (matches its intake file, e.g. \"taks\"). Also used as the state key."
  type        = string
}

variable "workload" {
  description = "The single workload declaration, supplied via -var-file=workloads/<name>.tfvars. One workload = one state file. Only subject_prefix and resource_group_name are required: region defaults to the platform region, and identities default to the standard plan/deploy/cleanup archetype (override only if you need something different)."
  type = object({
    subject_prefix      = string
    resource_group_name = string
    location            = optional(string)
    location_code       = optional(string)
    identities = optional(map(object({
      resource_group_role = string
      state_role          = string
      environments        = list(string)
      })), {
      plan = {
        resource_group_role = "Reader"
        state_role          = "Storage Blob Data Reader"
        environments        = ["plan"]
      }
      deploy = {
        resource_group_role = "Contributor"
        state_role          = "Storage Blob Data Contributor"
        environments        = ["apply", "destroy"]
      }
      cleanup = {
        resource_group_role = "Contributor"
        state_role          = "Storage Blob Data Contributor"
        environments        = ["cleanup"]
      }
    })
  })
}

variable "state_storage_account_name" {
  description = "Name of the Bicep-provisioned Terraform state storage account (uniqueString-based; supplied by the pipeline from the Bicep output)."
  type        = string
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
