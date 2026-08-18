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
# PR previews carry the ":pull_request" subject (no environment), so the read-only plan identity trusts exactly that.
$prSubject      = "${subjectPrefix}:pull_request"
# The same read-only identity also plans during merge-apply, which runs on a push to main: ":ref:refs/heads/main".
$mainRefSubject = "${subjectPrefix}:ref:refs/heads/main"

# --- 2. Deploy the trust anchor (idempotent) --------------------------------
Write-Host 'Deploying trust anchor...'
az deployment sub create `
  --name $DeploymentName `
  --location $config.location `
  --template-file (Join-Path $repoRoot 'bootstrap-trust/main.bicep') `
  --parameters "adminOidcSubject=$adminSubject" `
  --parameters "vendingOidcSubject=$vendingSubject" `
  --parameters "pullRequestOidcSubject=$prSubject" `
  --parameters "mainRefOidcSubject=$mainRefSubject" `
  --output none

# --- 3. Read the outputs + account context (never printed) ------------------
$adminClientId   = az deployment sub show --name $DeploymentName --query properties.outputs.adminIdentityClientId.value -o tsv
$vendingClientId = az deployment sub show --name $DeploymentName --query properties.outputs.vendingIdentityClientId.value -o tsv
$planClientId    = az deployment sub show --name $DeploymentName --query properties.outputs.planIdentityClientId.value -o tsv
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

# --- 6. Shared repo-level values --------------------------------------------
gh variable set STATE_STORAGE_ACCOUNT_NAME --body $stateSa -R $repo
# PR-plan client id is a repo variable (not an environment): the pull_request job runs with NO environment,
# so it reads this at repo scope. A client id is a non-secret identifier.
gh variable set VENDING_PR_CLIENT_ID --body $planClientId -R $repo
# Tenant + subscription must also exist at repo scope for the environment-less PR job.
# They coexist with the per-environment copies (env value wins for env jobs; repo value is the PR job's fallback).
# Same sensitivity split as the environments: tenant is a variable, subscription is a secret.
gh variable set AZURE_TENANT_ID       --body $tenantId -R $repo
gh secret   set AZURE_SUBSCRIPTION_ID --body $subId    -R $repo

Write-Host 'Done: trust anchor deployed and GitHub (admin + vending) wired.'
