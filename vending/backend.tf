terraform {
  # Partial backend: details supplied at init via -backend-config (key: vending.tfstate).
  backend "azurerm" {
    use_azuread_auth = true
  }
}
