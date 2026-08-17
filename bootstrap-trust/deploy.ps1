#!/usr/bin/env pwsh
# One-step platform bootstrap: deploys the Bicep trust anchor AND seeds the GitHub values
# it produces. Bicep is only IaC, so this script does the surrounding automation.
#
# Prerequisites: run locally as the trusted human, already signed in with `az login` and
# `gh auth login`. Idempotent - safe to re-run. No secrets or IDs are hardcoded here;
# every value is read at runtime.
#
#   pwsh ./bootstrap-trust/deploy.ps1

[CmdletBinding()]
param(
  [string]$EnvironmentName = 'admin',
  [string]$DeploymentName  = 'alz-trust-anchor'
)

$ErrorActionPreference = 'Stop'

# --- Context ----------------------------------------------------------------
$repoRoot = Split-Path $PSScriptRoot -Parent
$repo     = gh repo view --json nameWithOwner --jq '.nameWithOwner'
$config   = Get-Content (Join-Path $repoRoot 'config/project.json') | ConvertFrom-Json
Write-Host "Repo=$repo  Region=$($config.location)  Environment=$EnvironmentName"

# --- 1. Derive the exact OIDC subject from GitHub ---------------------------
# sub_claim_prefix already carries the immutable owner/repo IDs; append the environment.
$subjectPrefix = gh api "repos/$repo/actions/oidc/customization/sub" --jq '.sub_claim_prefix'
$adminSubject  = "${subjectPrefix}:environment:${EnvironmentName}"
Write-Host "OIDC subject: $adminSubject"

# --- 2. Deploy the trust anchor (idempotent) --------------------------------
Write-Host 'Deploying trust anchor...'
az deployment sub create `
  --name $DeploymentName `
  --location $config.location `
  --template-file (Join-Path $repoRoot 'bootstrap-trust/main.bicep') `
  --parameters "adminOidcSubject=$adminSubject" `
  --output none

# --- 3. Read the outputs + account context (never printed) ------------------
$clientId = az deployment sub show --name $DeploymentName --query properties.outputs.adminIdentityClientId.value -o tsv
$stateSa  = az deployment sub show --name $DeploymentName --query properties.outputs.stateStorageAccountName.value -o tsv
$tenantId = az account show --query tenantId -o tsv
$subId    = az account show --query id -o tsv

# --- 4. Ensure the GitHub environment + dev-only branch policy --------------
'{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' |
  gh api --method PUT "repos/$repo/environments/$EnvironmentName" --input - --silent

$branches = gh api "repos/$repo/environments/$EnvironmentName/deployment-branch-policies" --jq '.branch_policies[].name'
if (@($branches) -notcontains 'dev') {
  '{"name":"dev"}' | gh api --method POST "repos/$repo/environments/$EnvironmentName/deployment-branch-policies" --input - --silent
}

# --- 5. Seed GitHub (identifiers as variables, subscription as a secret) -----
gh variable set AZURE_CLIENT_ID            --env $EnvironmentName --body $clientId -R $repo
gh variable set AZURE_TENANT_ID            --env $EnvironmentName --body $tenantId -R $repo
gh secret   set AZURE_SUBSCRIPTION_ID      --env $EnvironmentName --body $subId    -R $repo
gh variable set STATE_STORAGE_ACCOUNT_NAME --body $stateSa -R $repo

Write-Host 'Done: trust anchor deployed and GitHub wired.'
