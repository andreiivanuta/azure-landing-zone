variable "workload_name" {
  description = "Short lowercase name of the workload being vended (matches its intake file, e.g. \"taks\"). Also used as the state key."
  type        = string
}

variable "workload" {
  description = "The single workload declaration, supplied via -var-file=workloads/<name>.tfvars. One workload = one state file."
  type = object({
    subject_prefix      = string
    resource_group_name = string
    location            = string
    location_code       = string
    identities = map(object({
      resource_group_role = string
      state_role          = string
      environments        = list(string)
    }))
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
