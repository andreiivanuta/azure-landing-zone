targetScope = 'resourceGroup'

@description('Service principal object ID for the identity receiving these assignments.')
param principalId string

@description('Built-in role definition GUIDs to assign at this resource group scope.')
param roleDefinitionGuids array

@description('Human-readable prefix used in Azure role-assignment descriptions.')
param assignmentDescriptionPrefix string

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleDefinitionGuid in roleDefinitionGuids: {
  name: guid(resourceGroup().id, principalId, roleDefinitionGuid)
  properties: {
    description: '${assignmentDescriptionPrefix}: ${roleDefinitionGuid}'
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionGuid)
  }
}]
