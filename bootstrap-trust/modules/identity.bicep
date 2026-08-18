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

@description('Optional second federated credential name (e.g. a main-branch ref subject for merge-apply plans). Empty = none.')
param extraCredentialName string = ''

@description('Optional second exact OIDC subject for the same identity. Empty = none.')
param extraOidcSubject string = ''

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

// Optional second credential on the SAME identity (e.g. so a read-only identity trusts both :pull_request and
// :ref:refs/heads/main). Serialized after the first: Azure rejects parallel FIC writes on one identity.
resource extraFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = if (!empty(extraOidcSubject)) {
  parent: identity
  name: empty(extraCredentialName) ? 'extra' : extraCredentialName
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: 'https://token.actions.githubusercontent.com'
    subject: extraOidcSubject
  }
  dependsOn: [
    federatedCredential
  ]
}

output clientId string = identity.properties.clientId
output principalId string = identity.properties.principalId
