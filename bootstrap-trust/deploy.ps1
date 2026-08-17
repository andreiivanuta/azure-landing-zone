#!/usr/bin/env pwsh
# One-step platform bootstrap: deploys the Bicep trust anchor AND seeds the GitHub
# environments it produces (admin + vending). Bicep is only IaC, so this script does the
# surrounding automation.
#
# Prerequisites: run locally as the trusted human, already signed in with `az login` and
# `gh auth login`. Idempotent - safe to re-run. No secrets or IDs are hardcoded here;
# every value is read at runtime.
#
#   pwsh ./bootstrap-trust/deploy.ps1

[CmdletBinding()]
param(
  [string]$DeploymentName = 'alz-trust-anchor'
)

$ErrorActionPreference = 'Stop'

# --- Context ----------------------------------------------------------------
$repoRoot = Split-Path $PSScriptRoot -Parent
$repo     = gh repo view --json nameWithOwner --jq '.nameWithOwner'
$config   = Get-Content (Join-Path $repoRoot 'config/project.json') | ConvertFrom-Json
Write-Host "Repo=$repo  Region=$($config.location)"

# --- 1. Derive the exact OIDC subjects from GitHub --------------------------
# sub_claim_prefix already carries the immutable owner/repo IDs; append each environment.
$subjectPrefix  = gh api "repos/$repo/actions/oidc/customization/sub" --jq '.sub_claim_prefix'
$adminSubject   = "${subjectPrefix}:environment:admin"
$vendingSubject = "${subjectPrefix}:environment:vending"

# --- 2. Deploy the trust anchor (idempotent) --------------------------------
Write-Host 'Deploying trust anchor...'
az deployment sub create `
  --name $DeploymentName `
  --location $config.location `
  --template-file (Join-Path $repoRoot 'bootstrap-trust/main.bicep') `
  --parameters "adminOidcSubject=$adminSubject" `
  --parameters "vendingOidcSubject=$vendingSubject" `
  --output none

# --- 3. Read the outputs + account context (never printed) ------------------
$adminClientId   = az deployment sub show --name $DeploymentName --query properties.outputs.adminIdentityClientId.value -o tsv
$vendingClientId = az deployment sub show --name $DeploymentName --query properties.outputs.vendingIdentityClientId.value -o tsv
$stateSa         = az deployment sub show --name $DeploymentName --query properties.outputs.stateStorageAccountName.value -o tsv
$tenantId        = az account show --query tenantId -o tsv
$subId           = az account show --query id -o tsv

# --- 4. Helper: wire one GitHub environment (branch policy + login values) ---
function Set-PlatformEnvironment {
  param(
    [Parameter(Mandatory)][string]  $Name,
    [Parameter(Mandatory)][string]  $ClientId,
    [Parameter(Mandatory)][string[]]$Branches
  )
  # switch the environment to custom branch policies (not "all protected branches")
  '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' |
    gh api --method PUT "repos/$repo/environments/$Name" --input - --silent

  # add each allowed branch if it is not already present
  $existing = gh api "repos/$repo/environments/$Name/deployment-branch-policies" --jq '.branch_policies[].name'
  foreach ($branch in $Branches) {
    if (@($existing) -notcontains $branch) {
      ('{"name":"' + $branch + '"}') |
        gh api --method POST "repos/$repo/environments/$Name/deployment-branch-policies" --input - --silent
    }
  }

  # seed this environment's login values (identifiers as variables, subscription as a secret)
  gh variable set AZURE_CLIENT_ID       --env $Name --body $ClientId -R $repo
  gh variable set AZURE_TENANT_ID       --env $Name --body $tenantId -R $repo
  gh secret   set AZURE_SUBSCRIPTION_ID --env $Name --body $subId    -R $repo
  Write-Host "Wired environment '$Name' (branches: $($Branches -join ', '))."
}

# --- 5. Wire both platform environments -------------------------------------
# admin   = break-glass, reachable only from dev.
# vending = onboarding: dev previews (terraform plan), main applies (terraform apply).
Set-PlatformEnvironment -Name 'admin'   -ClientId $adminClientId   -Branches @('dev')
Set-PlatformEnvironment -Name 'vending' -ClientId $vendingClientId -Branches @('dev', 'main')

# --- 6. Shared repo-level value ---------------------------------------------
gh variable set STATE_STORAGE_ACCOUNT_NAME --body $stateSa -R $repo

Write-Host 'Done: trust anchor deployed and GitHub (admin + vending) wired.'
