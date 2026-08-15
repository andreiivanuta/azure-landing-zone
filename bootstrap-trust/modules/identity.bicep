targetScope = 'resourceGroup'

@description('Name for the user-assigned managed identity.')
param identityName string

@description('Azure region for the managed identity.')
param location string

@description('Tags applied to the managed identity.')
param tags object

@description('Name for the GitHub federated credential (e.g. github-admin).')
param credentialName string

@description('Exact immutable GitHub Actions OIDC subject.')
param oidcSubject string

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: identityName
  location: location
  tags: tags
}

resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  parent: identity
  name: credentialName
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: 'https://token.actions.githubusercontent.com'
    subject: oidcSubject
  }
}

output clientId string = identity.properties.clientId
output principalId string = identity.properties.principalId
