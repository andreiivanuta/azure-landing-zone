targetScope = 'subscription'

@description('Azure region for the trust-anchor resource groups and bootstrap managed identity.')
@allowed([
  'swedencentral'
])
param location string = 'swedencentral'

@description('Short generic project prefix used to derive non-personal Azure resource names.')
@minLength(2)
@maxLength(20)
param projectPrefix string = 'taks'

@description('Exact immutable GitHub Actions OIDC subject for the bootstrap environment. Provide this at deployment time; do not commit it.')
@minLength(1)
param bootstrapOidcSubject string

@description('Optional tags merged with the required project tags.')
param additionalTags object = {}

var locationCode = 'swc'
var bootstrapResourceGroupName = 'rg-${projectPrefix}-bootstrap-${locationCode}'
var disposableResourceGroupName = 'rg-${projectPrefix}-sandbox-${locationCode}'
var bootstrapIdentityName = 'id-${projectPrefix}-bootstrap-${locationCode}'
var contributorRoleDefinitionGuid = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var readerRoleDefinitionGuid = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var userAccessAdministratorRoleDefinitionGuid = '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'
var commonTags = union(additionalTags, {
  project: 'terraform-aks-sandbox'
  environment: 'sandbox'
  managed_by: 'bicep'
})

resource bootstrapResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: bootstrapResourceGroupName
  location: location
  tags: union(commonTags, {
    lifecycle: 'persistent'
    purpose: 'terraform-state-and-ci'
  })
}

resource disposableResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: disposableResourceGroupName
  location: location
  tags: union(commonTags, {
    lifecycle: 'disposable'
    purpose: 'aks-sandbox'
  })
}

module bootstrapIdentity 'modules/bootstrap-identity.bicep' = {
  name: 'bootstrap-identity'
  scope: bootstrapResourceGroup
  params: {
    identityName: bootstrapIdentityName
    location: location
    oidcSubject: bootstrapOidcSubject
    tags: union(commonTags, {
      lifecycle: 'persistent'
      purpose: 'github-bootstrap-oidc'
    })
  }
}

module bootstrapRoles 'modules/role-assignments.bicep' = {
  name: 'bootstrap-rbac'
  scope: bootstrapResourceGroup
  params: {
    assignmentDescriptionPrefix: 'GitHub bootstrap access for persistent project resources'
    principalId: bootstrapIdentity.outputs.principalId
    roleDefinitionGuids: [
      contributorRoleDefinitionGuid
      userAccessAdministratorRoleDefinitionGuid
    ]
  }
}

module disposableRoles 'modules/role-assignments.bicep' = {
  name: 'disposable-rbac'
  scope: disposableResourceGroup
  params: {
    assignmentDescriptionPrefix: 'GitHub bootstrap access for disposable project resources'
    principalId: bootstrapIdentity.outputs.principalId
    roleDefinitionGuids: [
      readerRoleDefinitionGuid
      userAccessAdministratorRoleDefinitionGuid
    ]
  }
}

@description('Client ID for the bootstrap managed identity. Store it only as a protected GitHub environment secret after deployment.')
output bootstrapIdentityClientId string = bootstrapIdentity.outputs.clientId

@description('Name of the persistent bootstrap resource group.')
output bootstrapResourceGroupName string = bootstrapResourceGroup.name

@description('Name of the disposable AKS resource group.')
output disposableResourceGroupName string = disposableResourceGroup.name
