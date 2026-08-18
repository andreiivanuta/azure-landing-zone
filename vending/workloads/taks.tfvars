# Workload intake: terraform-aks-sandbox (taks). Committed registry — no secrets.
# subject_prefix binds every vended federated credential to this exact repo (owner id + repo id).
# The module appends ":environment:<name>" per environment listed below.
# Re-onboarding via PR (2026-08-18): exercises the PR plan preview + gated apply cycle.
# Verify automated gated apply (2026-08-18): create flow end-to-end.

workload = {
  subject_prefix      = "repo:andreiivanuta@124058262/terraform-aks-sandbox@1331742868"
  resource_group_name = "rg-taks-sandbox-swc"
  location            = "swedencentral"
  location_code       = "swc"

  identities = {
    plan = {
      resource_group_role = "Reader"
      state_role          = "Storage Blob Data Reader"
      environments        = ["aks-plan"]
    }
    deploy = {
      resource_group_role = "Contributor"
      state_role          = "Storage Blob Data Contributor"
      environments        = ["aks-apply", "aks-destroy"]
    }
    cleanup = {
      resource_group_role = "Contributor"
      state_role          = "Storage Blob Data Contributor"
      environments        = ["ttl-cleanup"]
    }
  }
}
