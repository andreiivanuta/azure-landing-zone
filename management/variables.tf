variable "management_resource_group_name" {
  description = "Existing platform management resource group. Leave null to derive rg-<platformPrefix>-management-<locationCode>, matching the Bicep trust anchor. Set only to override the convention."
  type        = string
  default     = null
}

variable "tags" {
  description = "Base tags merged onto the shared platform resources this root creates."
  type        = map(string)
  default = {
    project    = "azure-landing-zone"
    layer      = "management"
    managed_by = "terraform"
  }
}
