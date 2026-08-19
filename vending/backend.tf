terraform {
  # Partial backend: details supplied at init via -backend-config. The vending root uses one
  # state key per workload: "<workload>-vending.tfstate" (distinct from the workload repo's own
  # "<workload>-infra.tfstate", so the platform's state can never collide with the workload's).
  backend "azurerm" {
    use_azuread_auth = true
  }
}
