# Operating & Onboarding Guide

How this platform is operated, and how a workload team gets a landing zone from it.
For architecture and design rationale see [implementation-plan.md](implementation-plan.md);
for the security model see [security-model.md](security-model.md).

## The model in one picture

The platform never deploys a workload. It establishes trust once, then **vends** each workload the
identities, federation, and scoped access it needs to deploy *itself*.

```text
0. Bicep trust anchor    local, once, by a trusted user   -> first identity + resource groups
1. management/  apply    GitHub Actions (this repo)        -> shared state storage
2. vending/  apply       GitHub Actions (this repo)        -> each workload's identities (via the module)
3. workload repo apply   GitHub Actions (other repo)       -> the workload deploys itself
```

Step 0 is the only manual step. Steps 1–2 are this repository. Step 3 is the workload's own repository.

## Part A — Operating the platform

Order matters: the trust anchor lets Actions authenticate, and `management/` creates the state
backend that `vending/` and every workload store state in.

### 0. Trust anchor (once, local)

A trusted user with `az login` deploys `bootstrap-trust/main.bicep`. It creates the two resource
groups, the bootstrap/management identity, its GitHub OIDC federated credential (for this repo's
`bootstrap` environment), and its scoped roles. This cannot run in CI, because before it exists
there is no Azure identity for Actions to use.

### 1. `management/` — shared state storage

Runs in GitHub Actions as the bootstrap identity. Creates the Entra-ID-only storage account and the
private `tfstate` container that hold every root's state. Run **rarely** — only when the shared
platform changes. State key: `management.tfstate`.

### 2. `vending/` — workload identities

Runs in GitHub Actions as the bootstrap identity. For every workload declared in
`vending/workloads.auto.tfvars`, it calls the `workload-identity` module to mint that workload's
identities, GitHub OIDC federation, and scoped RBAC. State key: `vending.tfstate`.

Triggered by the registry itself: a pull request runs `terraform plan` (preview); merging to the
default branch (or a manual dispatch) runs `terraform apply` in a protected environment.

## Part B — Onboarding a workload

You are a workload team that wants a landing zone. Here is the full path.

### 1. Prerequisite

Your workload repository must already exist (it needs a GitHub repository ID).

### 2. Get your OIDC subject

Your subject binds Azure trust to your exact repository. Retrieve it from GitHub:

```powershell
gh api repos/<owner>/<repo> --jq '"repo:\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"'
```

Example output: `repo:<owner>@<ownerId>/<repo>@<repoId>`. The numeric IDs are immutable, so a
renamed or recreated repository cannot inherit the old trust.

### 3. Submit your declaration

Open a pull request adding your block to `vending/workloads.auto.tfvars` (see
`vending/workloads.auto.tfvars.example` for a filled-in AKS example):

```hcl
workloads = {
  <name> = {
    subject_prefix      = "repo:<owner>@<ownerId>/<repo>@<repoId>"
    resource_group_name = "<your resource group>" # assigned by the platform

    identities = {
      plan    = { resource_group_role = "Reader",      state_role = "Storage Blob Data Reader",      environments = ["<plan-env>"] }
      deploy  = { resource_group_role = "Contributor", state_role = "Storage Blob Data Contributor", environments = ["<apply-env>", "<destroy-env>"] }
      cleanup = { resource_group_role = "Contributor", state_role = "Storage Blob Data Contributor", environments = ["<cleanup-env>"] }
    }
  }
}
```

The platform team reviews the pull request (the governance gate). Merging triggers the vending apply.

### 4. What the guardrails allow

The module rejects, at plan time, anything outside policy:

- control-plane roles limited to `Reader` / `Contributor` (never `Owner` or role-granting);
- state roles limited to `Storage Blob Data Reader` / `Storage Blob Data Contributor`;
- access scoped only to your own resource group and the shared state account;
- OIDC subjects with no wildcards — one repository per credential;
- at least one environment per identity.

### 5. What you receive

After vending, the platform seeds your repository's environments with:

- `AZURE_CLIENT_ID` — a **variable**, per environment, holding the client ID of the identity
  federated to that environment (plan / deploy / cleanup differ);
- `AZURE_TENANT_ID` — a **variable**;
- `AZURE_SUBSCRIPTION_ID` — a **secret**.

You also receive your **state backend** coordinates (storage account and container) so your
Terraform can use it — each workload under its own state key.

### 6. Use them in your workflow

```yaml
- uses: azure/login@<sha>
  with:
    client-id:       ${{ vars.AZURE_CLIENT_ID }}
    tenant-id:       ${{ vars.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

The job's environment selects which identity you get, and the OIDC subject must match the credential
the platform vended — so only your repository, in that environment, can assume that identity, with
only the access the guardrails allowed.

## End to end

```text
declaration (PR)  ->  review + guardrails  ->  vending apply  ->  identities + federation + RBAC
                                                                        |
                        seed env vars/secret into the workload repo  <--+
                                                                        |
workload's apply job  ->  OIDC token  ->  matches the vended credential  ->  logs in  ->  deploys (fenced)
```
