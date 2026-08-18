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
- **`vending-apply.yml`** — merging a create/update change re-plans it against current state and applies
  **automatically** (merge = deploy). The pull request preview is the gate; because it re-plans, the apply
  is safely re-runnable (and can be triggered manually to recover from a transient failure).
- **`vending-destroy.yml`** — merging a deletion (offboard) re-plans the destroy and runs it automatically.

### Operational notes & limitations

Because apply/destroy **re-plan** (they don't replay a frozen plan), they are safely re-runnable:

- **Recovery / manual re-run.** Both workflows have a **Run workflow** button (`workflow_dispatch`).
  `vending-apply` with an empty input **reconciles all** current workloads; with a workload name it
  re-applies + re-seeds just that one (use this to recover a half-seeded workload). `vending-destroy`
  takes a workload name and an optional `ref` (a commit/branch that still contains the intake file).
- **Rapid successive merges.** If several merges land while a run is in progress, GitHub keeps only the
  latest queued run, so an intermediate push's workload can be skipped. Recover by dispatching
  `vending-apply` with an empty input (reconcile all).
- **Renames.** Renaming `workloads/<old>.tfvars` to `<new>.tfvars` onboards `<new>` but does **not**
  offboard `<old>` (its state lives under the old key). Rename = offboard old + onboard new, in
  separate PRs.
- **Same-workload apply and destroy at once.** Adding and deleting the *same* workload in one change (or
  manually dispatching both together) can race the GitHub-side seed vs un-seed. Terraform's state lock
  still protects the Azure resources; just avoid doing both to one workload simultaneously.

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
`vending/workloads/taks.tfvars.example`). Each workload is one file with its own state key. In the
**minimal form you only supply the two facts the platform can't know for you**:

```hcl
workload = {
  subject_prefix      = "repo:<owner>@<ownerId>/<repo>@<repoId>"
  resource_group_name = "<your resource group>"
}
```

That's it — the region defaults to the platform region, and the identities default to the standard
**plan / deploy / cleanup** archetype:

| Identity | Control-plane role | State role | Federated environments |
|---|---|---|---|
| `plan` | Reader | Storage Blob Data Reader | `plan` |
| `deploy` | Contributor | Storage Blob Data Contributor | `apply`, `destroy` |
| `cleanup` | Contributor | Storage Blob Data Contributor | `cleanup` |

Override any of these only if your workload genuinely differs — add an explicit `location` /
`location_code`, or a full `identities = { ... }` block (the module's guardrails still apply).

Opening the PR posts a read-only `terraform plan` **preview** for review (the gate). Merging then re-plans
against current state and applies automatically (merge = deploy) — no second approval to remember, and the
apply is safely re-runnable.

### Offboarding (and why it's deliberately harder than onboarding)

Deleting your intake file in a PR offboards the workload — the preview shows a `terraform plan -destroy`,
and merging runs it. But destroying a landing zone is irreversible and, because vending owns the workload's
**resource group**, deleting it **recursively deletes everything the workload put inside it** (its AKS
cluster, disks, IPs …). So offboarding has extra guardrails:

- **Deletion protection (default ON).** Every workload is protected unless its file sets
  `deletion_protection = false`. A protected workload's offboard is **refused** by the destroy workflow, so
  a stray "delete the file" PR cannot tear down a live workload. To offboard on purpose, do it in **two
  steps**: (1) merge a PR setting `deletion_protection = false`, then (2) merge a PR deleting the file. A
  maintainer can also override once by running `vending-destroy` manually with `force = true`.
- **Blast-radius pre-flight** *(when enabled)* — the destroy refuses if the resource group still contains
  resources, i.e. the workload hasn't torn down its own infrastructure yet. Fail-safe: nothing is destroyed.
- **Owner surfaced** — set `owner` in your file and it appears on the RG tag and in the destroy preview, so
  a reviewer knows who to contact first.

### 4. What the guardrails allow

The module rejects, at plan time, anything outside policy:

- control-plane roles limited to `Reader` / `Contributor` (never `Owner` or role-granting);
- state roles limited to `Storage Blob Data Reader` / `Storage Blob Data Contributor`;
- access scoped only to your own resource group and the shared state account;
- OIDC subjects with no wildcards — one repository per credential;
- at least one environment per identity.

### 5. What you receive (seeded automatically on merge)

When your PR merges, vending seeds your workload repository automatically — no manual step:

- `AZURE_CLIENT_ID_PLAN`, `AZURE_CLIENT_ID_APPLY`, `AZURE_CLIENT_ID_DESTROY`,
  `AZURE_CLIENT_ID_CLEANUP` — **repo-level variables**, one per environment, each holding the
  (non-secret) client ID of the identity federated to that environment;
- `AZURE_TENANT_ID` and `STATE_STORAGE_ACCOUNT_NAME` — **repo-level variables**;
- `AZURE_SUBSCRIPTION_ID` — a **repo-level secret**.

These are **repo-level** (not environment-scoped) on purpose: it keeps the platform's seeder
least-privilege — it only needs permission to write variables/secrets, never to administer your
repository. Security is unchanged, because a client ID is not a secret; the real gate is the OIDC
federated-credential subject (`:environment:<env>`), which still requires your job to run in that
environment.

You also use the shared **state backend** (storage account + `tfstate` container), each workload
under its own state key.

### 6. Use them in your workflow

Run each job in the matching environment (so its OIDC subject matches the vended credential), and
read that environment's client-ID variable:

```yaml
jobs:
  apply:
    environment: apply            # OIDC subject becomes ...:environment:apply
    steps:
      - uses: azure/login@<sha>
        with:
          client-id:       ${{ vars.AZURE_CLIENT_ID_APPLY }}
          tenant-id:       ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

GitHub creates the `apply` environment on first reference. The rule is uniform: a job in
`environment: <env>` logs in with `${{ vars.AZURE_CLIENT_ID_<ENV> }}` (e.g. `plan` → `_PLAN`).
Only your repository, running in that environment, can assume that identity — with only the access
the guardrails allowed.

## End to end

```text
declaration (PR)  ->  preview + review + guardrails  ->  merge -> gated apply  ->  identities + federation + RBAC
                                                                        |
                    seed repo variables + secret in the workload repo (automatic)  <--+
                                                                        |
workload's apply job  ->  OIDC token  ->  matches the vended credential  ->  logs in  ->  deploys (fenced)
```
