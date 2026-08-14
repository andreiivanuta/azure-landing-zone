provider "azurerm" {
  features {}

  # The RG-scoped bootstrap identity cannot register providers at subscription scope,
  # and the ones we use (Storage, ManagedIdentity) are already registered.
  resource_provider_registrations = "none"

  # Credentials and target subscription come from the environment, never from code:
  #   local dev : az login (Azure CLI) + ARM_SUBSCRIPTION_ID
  #   CI        : GitHub OIDC via ARM_USE_OIDC + ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID
}
