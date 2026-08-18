# The interface a workload declares to be vended a landing-zone identity set.
# This module is workload-agnostic: every workload-specific fact is an input here,
# and the guardrails below cap what any workload can ask for.

variable "workload_name" {
  description = "Short lowercase name of the workload (used to name its identities), e.g. \"taks\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.workload_name))
    error_message = "workload_name must be 2-12 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region for the workload's identities."
  type        = string
}

variable "location_code" {
  description = "Short region code used in resource names, e.g. \"swc\"."
  type        = string
}

variable "identity_resource_group_name" {
  description = "Persistent platform identity resource group where the vended identities are created, so they outlive the disposable workload."
  type        = string
}

variable "workload_resource_group_id" {
  description = "Resource ID of the workload's own resource group. The ONLY control-plane scope these identities may receive."
  type        = string
}

variable "state_storage_account_id" {
  description = "Resource ID of the shared Terraform state storage account. The ONLY data-plane scope these identities may receive."
  type        = string
}

variable "subject_prefix" {
  description = "Immutable OIDC subject prefix identifying the workload's repository, e.g. \"repo:<owner>@<ownerId>/<repo>@<repoId>\". The module appends the per-environment suffix."
  type        = string

  # GUARDRAIL: no wildcards — every credential must bind to one exact repository.
  validation {
    condition     = !can(regex("[*]", var.subject_prefix))
    error_message = "subject_prefix must not contain wildcards; each credential binds to one exact repository."
  }
}

variable "identities" {
  description = "Identities the workload requests. Key = identity name (e.g. plan/deploy/cleanup); each declares its roles and the environments it federates from."
  type = map(object({
    resource_group_role = string
    state_role          = string
    environments        = list(string)
  }))

  # GUARDRAIL: control-plane role must come from the platform's allowlist.
  validation {
    condition = alltrue([
      for name, spec in var.identities : contains(["Reader", "Contributor"], spec.resource_group_role)
    ])
    error_message = "resource_group_role must be one of: Reader, Contributor. Owner and other privileged roles are not vendable."
  }

  # GUARDRAIL: data-plane (state) role must come from the platform's allowlist.
  validation {
    condition = alltrue([
      for name, spec in var.identities : contains(["Storage Blob Data Reader", "Storage Blob Data Contributor"], spec.state_role)
    ])
    error_message = "state_role must be one of: Storage Blob Data Reader, Storage Blob Data Contributor."
  }

  # GUARDRAIL: every identity must federate at least one environment.
  validation {
    condition = alltrue([
      for name, spec in var.identities : length(spec.environments) > 0
    ])
    error_message = "each identity must declare at least one environment to federate."
  }
}

variable "issuer" {
  description = "OIDC issuer. Defaults to GitHub Actions; override to federate another CI provider later."
  type        = string
  default     = "https://token.actions.githubusercontent.com"
}

variable "audience" {
  description = "OIDC audience for the token exchange."
  type        = string
  default     = "api://AzureADTokenExchange"
}

variable "tags" {
  description = "Tags applied to the identities this module creates."
  type        = map(string)
  default     = {}
}

variable "platform_reader_principal_ids" {
  description = "Principal (object) IDs of platform identities (the vending write + PR-plan read identities) that receive read-only Reader on the workload RG, so the pipeline can enumerate the RG's live contents for the destroy blast-radius check and the offboard preview. Defaults to none."
  type        = list(string)
  default     = []
}
