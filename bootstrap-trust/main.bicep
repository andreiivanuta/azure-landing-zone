targetScope = 'subscription'

@description('Exact immutable GitHub Actions OIDC subject for the admin environment. Provide this at deployment time; do not commit it.')
@minLength(1)
param adminOidcSubject string

@description('Optional tags merged with the platform tags.')
param additionalTags object = {}

// Naming inputs come from the shared config so Bicep and Terraform stay in sync.
var config = loadJsonContent('../config/project.json')
var platformPrefix = config.platformPrefix
var locationCode = config.locationCode
var location = config.location

var managementResourceGroupName = 'rg-${platformPrefix}-management-${locationCode}'
var adminIdentityName = 'id-${platformPrefix}-admin-${locationCode}'

var contributorRoleDefinitionGuid = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var userAccessAdministratorRoleDefinitionGuid = '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'

var commonTags = union(additionalTags, {
  project: 'azure-landing-zone'
  layer: 'management'
  managed_by: 'bicep'
})

// The single resource group this repo's CI/CD manages. Workload resource groups are provisioned later, not here.
resource managementResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: managementResourceGroupName
  location: location
  tags: union(commonTags, {
    lifecycle: 'persistent'
    purpose: 'platform-management'
  })
}

// Admin identity: highest trust, used only by manual, protected workflows.
module adminIdentity 'modules/identity.bicep' = {
  name: 'admin-identity'
  scope: managementResourceGroup
  params: {
    identityName: adminIdentityName
    location: location
    credentialName: 'github-admin'
    oidcSubject: adminOidcSubject
    tags: union(commonTags, {
      lifecycle: 'persistent'
      purpose: 'github-admin-oidc'
    })
  }
}

// Admin may build and administer the platform foundation inside the management resource group.
module adminRoles 'modules/role-assignments.bicep' = {
  name: 'admin-rbac'
  scope: managementResourceGroup
  params: {
    assignmentDescriptionPrefix: 'GitHub admin access to the platform management resource group'
    principalId: adminIdentity.outputs.principalId
    roleDefinitionGuids: [
      contributorRoleDefinitionGuid
      userAccessAdministratorRoleDefinitionGuid
    ]
  }
}

@description('Client ID of the admin managed identity. Store only as a protected GitHub environment value after deployment.')
output adminIdentityClientId string = adminIdentity.outputs.clientId

@description('Name of the platform management resource group.')
output managementResourceGroupName string = managementResourceGroup.name
