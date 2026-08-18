# Operating & Onboarding Guide

How this platform is operated, and how a workload team gets a landing zone from it.
For architecture and design rationale see [implementation-plan.md](implementation-plan.md);
for the security model see [security-model.md](security-model.md).

## The model in one picture

The platform never deploys a workload. It establishes trust once, then **vends** each workload the
identities, federation, and scoped access it needs to deploy *itself*.

```text
0. Bicep trust anchor    local, once, by a trusted user   -> resource groups, platform identities, state storage
1. vending (PR + merge)  GitHub Actions (this repo)        -> each workload's identities (via the module)
2. workload repo apply   GitHub Actions (other repo)       -> the workload deploys itself
```

Step 0 is the only local step. Step 1 is this repository. Step 2 is the workload's own repository.

## Part A — Operating the platform

Order matters: the trust anchor lets Actions authenticate, and it also provisions the state
backend that `vending/` and every workload store state in.

### 0. Trust anchor (once, local)

A trusted user with `az login` runs `bootstrap-trust/deploy.ps1`. It deploys the Bicep trust anchor —
the management + identity resource groups, the platform identities (`admin`, `vending`, and the
read-only PR-plan identity) with their GitHub OIDC (OpenID Connect) federated credentials and scoped
roles, and the hardened Terraform state storage account — then seeds the GitHub environments and repo
values. This cannot run in CI (Continuous Integration), because before it exists there is no Azure
identity for Actions to use.

### 1. Shared state storage

The Terraform state backend — an Entra-ID-only storage account with a private `tfstate` container — is
provisioned by the Bicep trust anchor in step 0 (not a separate Terraform root), so there is no state
chicken-and-egg. Every workload stores its own state under its own key (`<name>.tfstate`).

### 2. `vending/` — workload identities

Runs in GitHub Actions. For each workload declared in its own registry file
`vending/workloads/<name>.tfvars`, it calls the `workload-identity` module to mint that workload's
identities, GitHub OIDC federation, and scoped RBAC (Role-Based Access Control) — each under its own
state key.

The registry drives three workflows automatically:

- **`vending-pr-plan.yml`** — a pull request into `main` posts a read-only preview to the PR:
  `terraform plan` for added/changed workloads, `terraform plan -destroy` for deleted ones. It runs as
  a **read-only** identity, so an untrusted PR can preview but never change anything.
- **`vending-apply.yml`** — merging a create/update change **pauses on the `vending` environment for a
  required reviewer**, then applies the exact reviewed plan.
- **`vending-destroy.yml`** — merging a deletion (offboard) pauses for a required reviewer, then
  destroys the exact reviewed plan.

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

Open a pull request adding your own registry file `vending/workloads/<name>.tfvars` (see
`vending/workloads/taks.tfvars.example` for a filled-in AKS example). Each workload is one file with
its own state key:

```hcl
workload = {
  subject_prefix      = "repo:<owner>@<ownerId>/<repo>@<repoId>"
  resource_group_name = "<your resource group>" # assigned by the platform
  location            = "swedencentral"
  location_code       = "swc"

  identities = {
    plan    = { resource_group_role = "Reader",      state_role = "Storage Blob Data Reader",      environments = ["<plan-env>"] }
    deploy  = { resource_group_role = "Contributor", state_role = "Storage Blob Data Contributor", environments = ["<apply-env>", "<destroy-env>"] }
    cleanup = { resource_group_role = "Contributor", state_role = "Storage Blob Data Contributor", environments = ["<cleanup-env>"] }
  }
}
```

Opening the PR posts a read-only `terraform plan` **preview** for review (the first gate). Merging then
**pauses the apply on the `vending` environment for a required reviewer** (the second gate) before it
runs. To offboard later, delete your file in a PR: the preview shows a `terraform plan -destroy`, and
merging runs the same gated destroy.

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
declaration (PR)  ->  preview + review + guardrails  ->  merge -> gated apply  ->  identities + federation + RBAC
                                                                        |
                        seed env vars/secret into the workload repo  <--+
                                                                        |
workload's apply job  ->  OIDC token  ->  matches the vended credential  ->  logs in  ->  deploys (fenced)
```
