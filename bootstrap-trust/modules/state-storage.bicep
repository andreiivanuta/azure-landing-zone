targetScope = 'resourceGroup'

@description('Globally-unique name for the Terraform state storage account (3-24 lowercase alphanumerics).')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region for the storage account.')
param location string

@description('Tags applied to the storage account.')
param tags object

@description('Object IDs granted read/write on state (Storage Blob Data Contributor). Admin now; add the vending identity later.')
param stateContributorPrincipalIds array

@description('Object IDs granted read-only on state (Storage Blob Data Reader), e.g. the PR-plan identity.')
param stateReaderPrincipalIds array = []

@description('Name of the blob container that holds Terraform state.')
param stateContainerName string = 'tfstate'

// Storage Blob Data Contributor — data-plane read/write, needed because shared keys are disabled.
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
// Storage Blob Data Reader — data-plane read-only, for the PR-plan preview identity.
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

resource stateStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: stateStorage
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource tfstateContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: stateContainerName
  properties: {
    publicAccess: 'None'
  }
}

// One grant per principal, scoped to the account only (not the RG) so it stays as narrow as possible.
resource stateWriterRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principalId in stateContributorPrincipalIds: {
  scope: stateStorage
  name: guid(stateStorage.id, principalId, storageBlobDataContributorRoleId)
  properties: {
    description: 'Terraform state read/write (data plane) for platform CI identities'
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
  }
}]

// Read-only data-plane grants (Storage Blob Data Reader), scoped to the account only, for preview identities.
resource stateReaderRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principalId in stateReaderPrincipalIds: {
  scope: stateStorage
  name: guid(stateStorage.id, principalId, storageBlobDataReaderRoleId)
  properties: {
    description: 'Terraform state read-only (data plane) for the PR-plan preview identity'
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
  }
}]

output storageAccountName string = stateStorage.name
output storageAccountId string = stateStorage.id
output stateContainerName string = tfstateContainer.name
