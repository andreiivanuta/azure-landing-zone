provider "azurerm" {
  features {}

  # The RG-scoped management identity cannot register providers at subscription scope,
  # and the ones we use (ManagedIdentity, Authorization, Storage) are already registered.
  resource_provider_registrations = "none"

  # Shared keys are disabled on the state account, so data-plane calls use Entra ID.
  storage_use_azuread = true

  # Credentials and target subscription come from the environment, never from code:
  #   local dev : az login (Azure CLI) + ARM_SUBSCRIPTION_ID
  #   CI        : GitHub OIDC via ARM_USE_OIDC + ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID
}
