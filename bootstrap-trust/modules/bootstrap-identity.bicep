targetScope = 'resourceGroup'

@description('Name for the user-assigned managed identity.')
param identityName string

@description('Azure region for the managed identity.')
param location string

@description('Tags applied to the managed identity.')
param tags object

@description('Exact immutable GitHub Actions OIDC subject for the bootstrap environment.')
param oidcSubject string

resource bootstrapIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: identityName
  location: location
  tags: tags
}

resource bootstrapFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  parent: bootstrapIdentity
  name: 'github-bootstrap'
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: 'https://token.actions.githubusercontent.com'
    subject: oidcSubject
  }
}

output clientId string = bootstrapIdentity.properties.clientId
output principalId string = bootstrapIdentity.properties.principalId
