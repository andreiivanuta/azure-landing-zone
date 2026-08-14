variable "bootstrap_resource_group_name" {
  description = "Existing bootstrap resource group. Leave null to derive rg-<project_prefix>-bootstrap-<location_code>, matching the Bicep trust anchor. Set a value only to override the convention."
  type        = string
  default     = null
}

variable "tags" {
  description = "Base tags merged onto every resource this configuration creates."
  type        = map(string)
  default = {
    project     = "terraform-aks-sandbox"
    environment = "sandbox"
    managed_by  = "terraform"
  }
}
