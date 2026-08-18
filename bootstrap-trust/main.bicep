targetScope = 'subscription'

@description('Exact immutable GitHub Actions OIDC subject for the admin environment. Provide this at deployment time; do not commit it.')
@minLength(1)
param adminOidcSubject string

@description('Exact immutable GitHub Actions OIDC subject for the vending environment. Provide this at deployment time; do not commit it.')
@minLength(1)
param vendingOidcSubject string

@description('Exact immutable GitHub Actions OIDC subject for pull-request plan previews (ends in :pull_request). Provide this at deployment time; do not commit it.')
@minLength(1)
param pullRequestOidcSubject string

@description('Exact immutable GitHub Actions OIDC subject for the main branch ref (ends in :ref:refs/heads/main). Lets the read-only identity also plan during merge-apply. Provide at deployment time; do not commit it.')
@minLength(1)
param mainRefOidcSubject string

@description('Optional tags merged with the platform tags.')
param additionalTags object = {}

// Naming inputs come from the shared config so Bicep and Terraform stay in sync.
var config = loadJsonContent('../config/project.json')
var platformPrefix = config.platformPrefix
var locationCode = config.locationCode
var location = config.location

var managementResourceGroupName = 'rg-${platformPrefix}-management-${locationCode}'
var identityResourceGroupName = 'rg-${platformPrefix}-identity-${locationCode}'
var adminIdentityName = 'id-${platformPrefix}-admin-${locationCode}'
var vendingIdentityName = 'id-${platformPrefix}-vending-${locationCode}'
var planIdentityName = 'id-${platformPrefix}-vending-pr-${locationCode}'
// Deterministic, globally-unique name; the subscription hash keeps the ID out of source.
var stateStorageAccountName = 'st${platformPrefix}state${uniqueString(subscription().id)}'

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

// Persistent home for the workload identities the vending pipeline mints (CAF identity archetype).
resource identityResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: identityResourceGroupName
  location: location
  tags: union(commonTags, {
    lifecycle: 'persistent'
    purpose: 'workload-identities'
    layer: 'identity'
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

// Vending identity: bounded automation that mints workload identities. Lives in management (platform automation);
// its permissions (custom role + state access) are granted in the steps below.
module vendingIdentity 'modules/identity.bicep' = {
  name: 'vending-identity'
  scope: managementResourceGroup
  params: {
    identityName: vendingIdentityName
    location: location
    credentialName: 'github-vending'
    oidcSubject: vendingOidcSubject
    tags: union(commonTags, {
      lifecycle: 'persistent'
      purpose: 'github-vending-oidc'
    })
  }
}

// Custom role: exactly what vending needs to mint a workload landing zone - and nothing more.
resource landingZoneVendorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, 'landing-zone-vendor')
  properties: {
    roleName: 'Landing Zone Vendor (${platformPrefix})'
    description: 'Vend workload landing zones: create resource groups, user-assigned identities + federated credentials, and role assignments. No Contributor/Owner.'
    type: 'CustomRole'
    assignableScopes: [
      subscription().id
    ]
    permissions: [
      {
        actions: [
          'Microsoft.Resources/subscriptions/resourceGroups/read'
          'Microsoft.Resources/subscriptions/resourceGroups/write'
          'Microsoft.Resources/subscriptions/resourceGroups/delete'
          'Microsoft.ManagedIdentity/userAssignedIdentities/*'
          'Microsoft.Authorization/roleAssignments/read'
          'Microsoft.Authorization/roleAssignments/write'
          'Microsoft.Authorization/roleAssignments/delete'
          'Microsoft.Authorization/roleDefinitions/read'
          'Microsoft.Storage/storageAccounts/read'
        ]
      }
    ]
  }
}

// Grant the vending identity that custom role at subscription scope, so it can vend into any workload RG.
resource vendingRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, vendingIdentityName, landingZoneVendorRole.id)
  properties: {
    roleDefinitionId: landingZoneVendorRole.id
    principalId: vendingIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    description: 'Vending identity may create workload RGs, identities, and role assignments (Landing Zone Vendor custom role).'
  }
}

// PR-plan identity: LOWEST trust. Read-only preview (terraform plan) for untrusted pull requests.
module planIdentity 'modules/identity.bicep' = {
  name: 'plan-identity'
  scope: managementResourceGroup
  params: {
    identityName: planIdentityName
    location: location
    credentialName: 'github-vending-pr'
    oidcSubject: pullRequestOidcSubject
    extraCredentialName: 'github-vending-main-plan'
    extraOidcSubject: mainRefOidcSubject
    tags: union(commonTags, {
      lifecycle: 'persistent'
      purpose: 'github-pr-plan-oidc'
    })
  }
}

// Custom read-only role: exactly the read verbs `terraform plan` needs to refresh vended resources - and nothing more.
resource landingZoneVendorReaderRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, 'landing-zone-vendor-reader')
  properties: {
    roleName: 'Landing Zone Vendor Reader (${platformPrefix})'
    description: 'Read-only preview of vended landing zones: read RGs, user-assigned identities + federated credentials, role assignments/definitions, and state storage metadata. No writes.'
    type: 'CustomRole'
    assignableScopes: [
      subscription().id
    ]
    permissions: [
      {
        actions: [
          'Microsoft.Resources/subscriptions/resourceGroups/read'
          'Microsoft.ManagedIdentity/userAssignedIdentities/read'
          'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/read'
          'Microsoft.Authorization/roleAssignments/read'
          'Microsoft.Authorization/roleDefinitions/read'
          'Microsoft.Storage/storageAccounts/read'
        ]
      }
    ]
  }
}

// Grant the read-only role at subscription scope so plan can refresh resources in any (dynamically-named) workload RG.
resource planRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, planIdentityName, landingZoneVendorReaderRole.id)
  properties: {
    roleDefinitionId: landingZoneVendorReaderRole.id
    principalId: planIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    description: 'PR-plan identity may read (preview) vended landing-zone resources (Landing Zone Vendor Reader custom role).'
  }
}

// Terraform state backend: one shared, keyless storage account for every root's state.
module stateStorage 'modules/state-storage.bicep' = {
  name: 'state-storage'
  scope: managementResourceGroup
  params: {
    storageAccountName: stateStorageAccountName
    location: location
    tags: union(commonTags, {
      lifecycle: 'persistent'
      purpose: 'terraform-state'
    })
    stateContributorPrincipalIds: [
      adminIdentity.outputs.principalId
      vendingIdentity.outputs.principalId
    ]
    stateReaderPrincipalIds: [
      planIdentity.outputs.principalId
    ]
  }
}

@description('Client ID of the admin managed identity. Store only as a protected GitHub environment value after deployment.')
output adminIdentityClientId string = adminIdentity.outputs.clientId

@description('Client ID of the vending managed identity. Store as the vending environment value after deployment.')
output vendingIdentityClientId string = vendingIdentity.outputs.clientId

@description('Client ID of the PR-plan (read-only) managed identity. Store as a repo-level variable for pull_request plan jobs.')
output planIdentityClientId string = planIdentity.outputs.clientId

@description('Name of the platform management resource group.')
output managementResourceGroupName string = managementResourceGroup.name

@description('Name of the resource group that holds vended workload identities.')
output identityResourceGroupName string = identityResourceGroup.name

@description('Terraform state storage account name (for backend -backend-config).')
output stateStorageAccountName string = stateStorage.outputs.storageAccountName

@description('Blob container holding Terraform state.')
output stateContainerName string = stateStorage.outputs.stateContainerName
