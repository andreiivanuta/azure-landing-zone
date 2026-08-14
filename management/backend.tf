terraform {
  # Partial backend: resource_group_name, storage_account_name, container_name, and key
  # are supplied at init time via -backend-config so the account name (a subscription
  # hash) stays out of source control. First run uses a local backend to create the
  # account, then `init -migrate-state` moves this root's state here (key: management.tfstate).
  backend "azurerm" {
    use_azuread_auth = true
  }
}
