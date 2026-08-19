# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This is a learning sandbox rather than a versioned product, so entries are grouped
under `Unreleased` and tracked by date instead of semantic-version tags.

## [Unreleased]

### Added

- **Documentation consolidation** — added [docs/architecture.md](docs/architecture.md) as the
  single authoritative design doc: a component catalog (trust anchor, vending module, vending
  root, workflows, seeder App), the two-repository trust and identity model, the OIDC subject
  model (including the read-only PR-plan identity), the shared state backend, the convergent
  vending lifecycle (PR preview → merge re-plan apply + GitHub App seeding; offboard → blast-radius
  gate → destroy + un-seed), and a distilled design-decision log. Diagrams are provided both as
  inline Mermaid and as editable draw.io sources under [docs/diagrams/](docs/diagrams/)
  (`architecture.drawio`, `vending-lifecycle.drawio`).
  artifact (keyed by workload + PR head SHA). On merge, `vending-apply.yml` / `vending-destroy.yml` correlate
  the merge commit to its PR, download that exact artifact, and `terraform apply tf.plan` — so what deploys is
  byte-for-byte the plan that was reviewed. If state moved since the plan was saved, Terraform refuses (stale
  plan) and fails safe. Terraform is pinned to one version across all workflows so saved plans stay applyable.
- **Single-trunk model**: `main` is now the default and only long-lived branch. The `dev` integration
  branch is retired (nothing triggered from it; it only drifted). Work happens on short-lived branches
  merged via pull request. The `admin` and `vending` environment branch policies (and `deploy.ps1`) now
  target `main`, so break-glass and vending both run from the single trunk.
- **Vending intake defaults (less boilerplate)**: in `vending/`, a workload's `identities` now defaults to
  the standard **plan / deploy / cleanup** archetype and its region defaults to the platform region, so a
  new workload file needs only `subject_prefix` + `resource_group_name`. Everything stays overridable, and
  the module guardrails still apply. Updated `taks.tfvars.example` and `docs/onboarding.md` to the minimal form.
- **Branch protection on `main`**: require a pull request before merging (no direct pushes), so every
  workload change flows through the read-only plan preview. Solo-friendly (0 required approvals).
- Baseline commit of the platform (landing zone) foundation:
  - Repository hygiene: `.editorconfig`, `.gitattributes`, `.gitignore`.
  - `SECURITY.md` — vulnerability reporting and credential-exposure response policy.
  - `bootstrap-trust/` — subscription-scope Bicep trust anchor (resource groups,
    bootstrap managed identity, GitHub OIDC federated credential, and
    resource-group-scoped role assignments) with `modules/` and `README.md`.
  - `bootstrap/` — foundation Terraform through the hardened Terraform state storage
    account (`versions.tf`, `providers.tf`, `variables.tf`, `main.tf`, `.terraform.lock.hcl`).
  - `config/project.json` — shared naming configuration consumed by Bicep and Terraform.
  - `docs/implementation-plan.md`, `docs/security-model.md` — design and security model.
- `bootstrap-trust/modules/identity.bicep` — generic, reusable managed-identity + GitHub
  OIDC (OpenID Connect) federated-credential module (parameterised `credentialName`), replacing
  the single-purpose `bootstrap-identity.bicep`.
- `bootstrap-trust/modules/state-storage.bicep` — hardened, keyless (Entra-only) Terraform
  state backend: a storage account (`Standard_LRS`, shared keys disabled, no public blob, TLS 1.2)
  with blob versioning + 7-day soft-delete, a private `tfstate` container, and a list-based
  Storage Blob Data Contributor grant (admin now, vending identity later).
- `.github/copilot-instructions.md` — repository Copilot instructions (always expand acronyms;
  step-by-step, teaching-oriented working style).
- `vending/workloads/taks.tfvars.example` — per-workload intake template for the new
  one-file-per-workload registry (`vending/workloads/<name>.tfvars`, committed via a `.gitignore` exception).
- `.github/workflows/oidc-smoke-test.yml` — manual diagnostic that verifies GitHub Actions can
  authenticate to Azure via OIDC (OpenID Connect) as the admin identity **and** reach the Terraform
  state backend (`terraform init` via `ARM_USE_OIDC`), with no stored secret.
- `bootstrap-trust/deploy.ps1` — one-step local bootstrap: deploys the Bicep trust anchor and seeds
  the GitHub values it produces (admin-environment `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` variables,
  `AZURE_SUBSCRIPTION_ID` secret, and the repo `STATE_STORAGE_ACCOUNT_NAME` variable). Idempotent; no IDs hardcoded.
- **Read-only PR-plan identity** in the Bicep trust anchor: `id-alz-vending-pr-swc` with a custom
  `Landing Zone Vendor Reader (alz)` role (read-only RG / UAMI / federated-credential / role-assignment /
  role-definition / storage-account verbs at subscription scope) and Storage Blob Data Reader on the state
  account. Two federated credentials on this one identity — `github-vending-pr` (subject `:pull_request`)
  and `github-vending-main-plan` (subject `:ref:refs/heads/main`) — so untrusted pull-request previews and
  the merge-time plan both run read-only. `deploy.ps1` seeds the repo variable `VENDING_PR_CLIENT_ID` and
  publishes `AZURE_TENANT_ID` (variable) + `AZURE_SUBSCRIPTION_ID` (secret) at repo scope for the
  environment-less plan jobs.
- **Automated vending lifecycle** (three workflows) replacing the manual v1 pipeline:
  - `.github/workflows/vending-pr-plan.yml` — on a pull request into `main`, a read-only preview posted
    back to the PR: `terraform plan` for added/changed `vending/workloads/*.tfvars`, `terraform plan -destroy`
    for deleted ones. Runs as the read-only PR identity; fork PRs are excluded.
  - `.github/workflows/vending-apply.yml` — on merge to `main`, plan the changed workloads read-only, then
    apply the exact saved plan automatically (create/update). The pull request is the gate (merge = deploy).
  - `.github/workflows/vending-destroy.yml` — on merge that deletes a workload's intake file, plan its
    destroy (checking out the pre-merge commit), then destroy the exact saved plan automatically (offboard).
- The repository was made **public** so branch protection and workflows are unrestricted; the gate is the
  pull request review + read-only plan preview (its no-secrets OIDC design keeps this safe). The `vending`
  environment supplies the write identity's OIDC subject but carries no required reviewer, so a merge deploys
  without a separate, forgettable approval step.

### Changed

- **Refreshed the docs to the current convergent design.** `bootstrap-trust/README.md` now documents
  the read-only PR-plan identity (`id-alz-vending-pr-swc`), the `Landing Zone Vendor Reader (alz)`
  custom role, its two federated credentials (`:pull_request` + `:ref:refs/heads/main`), and the
  `main`-only environment branch policies (the stale `dev` references are gone). `docs/security-model.md`
  now reflects that PR previews run read-only under an OIDC identity, that apply/destroy run on merge
  (with `workflow_dispatch` recovery) and re-plan instead of replaying a saved plan, the destroy
  blast-radius gate, and least-privilege workload-repo seeding via the GitHub App. `README.md` gained a
  Documentation section pointing at the new architecture doc.
- Scoped the repository to **platform authority only** (the landing-zone foundation): removed
  workload/AKS deployment content from `docs/implementation-plan.md` and `docs/security-model.md`.
  The AKS cluster deploys from the workload repository, using the identities and state this platform vends.
- Reframed the plan to the CAF landing-zone model (platform archetypes; `alz` platform prefix,
  `taks` reserved for the workload) and confirmed the CI/CD-first operating model.
- Restructured the platform Terraform into a modular vending design: `management/` (shared state
  storage), `modules/workload-identity/` (guardrailed vending module), and `vending/` (per-workload
  consumer); removed the monolithic `bootstrap/` root.
- Added `README.md` describing the repository, its layout, and operating model.
- Added `docs/onboarding.md` (operating + workload onboarding guide), linked from the README.
- Reworked the Bicep trust anchor (`bootstrap-trust/main.bicep`) to a **minimal admin-only** form:
  it now creates only the management RG (resource group) and one admin identity `id-alz-admin-swc`
  with a GitHub OIDC (OpenID Connect) federated credential and Contributor + UAA (User Access
  Administrator) scoped to that RG. Dropped the workload sandbox RG and workload-prefix; naming is
  read from `config/project.json` via `loadJsonContent`. Deployed and verified via `az deployment sub create`.
- Moved the Terraform state backend from the `management/` Terraform root **into the Bicep seed**
  (`bootstrap-trust/`): `main.bicep` now provisions the hardened state storage account (name via
  `uniqueString(subscription().id)`) and outputs it for `-backend-config`. This removes the state
  chicken-and-egg (Bicep needs no backend) and stops Terraform from owning its own state store.
  Deployed and verified.
- Removed the now-redundant `management/` Terraform root (the state backend lives in Bicep).
- Reworked `vending/` from a `workloads` **map** (one shared state) to a **single per-workload**
  model (`var.workload` + `var.workload_name`, module called once): each workload gets its own state
  file via `-backend-config="key=<name>.tfstate"`, isolating blast radius per workload. The state
  account name is now supplied as a variable (from the Bicep output) rather than recomputed, and the
  per-workload declarations live in a committed registry `vending/workloads/<name>.tfvars`.
- Made a vended identity's **region per-workload**: each workload declares its own `location` /
  `location_code`; `config/project.json` is now used only for the platform management resource group.
- Extended the Bicep trust anchor (`bootstrap-trust/main.bicep`) to provision the **bounded vending
  identity** and its least-privilege authority: a new identity resource group `rg-alz-identity-swc`
  (holds all vended workload identities), the `id-alz-vending-swc` managed identity with a
  `github-vending` OIDC (OpenID Connect) federated credential, a **custom role**
  `Landing Zone Vendor (alz)` (create/read/delete resource groups, manage user-assigned identities +
  federated credentials, read/write/delete role assignments, read role definitions and storage
  accounts — no Contributor/Owner) assigned to the vending identity at subscription scope, and a
  Storage Blob Data Contributor grant on the state account. Adds outputs `vendingIdentityClientId`
  and `identityResourceGroupName`. Verified via what-if + `az deployment sub create`.
- Reworked `bootstrap-trust/deploy.ps1` to seed **both** platform environments in a single run: it now
  derives the admin and vending OIDC (OpenID Connect) subjects, passes both to the deployment, and wires
  each environment's branch policy and login values through a shared `Set-PlatformEnvironment` helper —
  `admin` reachable from `dev` only (break-glass), `vending` from `dev` + `main` (dev previews a
  `terraform plan`, main runs `terraform apply`).
- `.github/workflows/vending.yml` — first vending pipeline (v1): manual `workflow_dispatch` `plan` for
  one workload, running under the bounded `vending` GitHub environment (not `admin`), with OIDC-only
  Azure auth. PR-plan / merge-apply and a changed-workload matrix are the next iteration.
- `vending/`: the workload RG is now **created and destroyed by vending itself** (was a `data` source
  that assumed a pre-existing RG). Onboarding a workload no longer requires a manual RG create.
- `modules/workload-identity` + `vending/`: vended UAMIs (User-Assigned Managed Identities) now land in
  the dedicated identity RG `rg-alz-identity-swc` instead of the management RG. Renamed the module
  input `management_resource_group_name` → `identity_resource_group_name` to match.
- Refreshed `bootstrap-trust/README.md`, `docs/implementation-plan.md`, and `docs/security-model.md`
  to describe the current admin + vending + identity-RG + custom-role design (they still described the
  earlier single-`bootstrap`-environment model).

### Fixed

- `modules/workload-identity`: replaced the deprecated `parent_id` + `resource_group_name` arguments on
  `azurerm_federated_identity_credential` with the single `user_assigned_identity_id` (required by azurerm v5).
- `vending/main.tf`: corrected the shared-config lookup from `local.config.prefix` to
  `local.config.platformPrefix` (the key in `config/project.json` is `platformPrefix`, so the previous
  form would have failed `terraform plan`).
- `.github/workflows/vending.yml`: supply the required `state_storage_account_name` variable to Terraform
  via `TF_VAR_state_storage_account_name` in the job `env` (sourced from the `STATE_STORAGE_ACCOUNT_NAME`
  repo variable). The `plan` step previously passed it only to `-backend-config`, so `terraform plan
  -input=false` would have failed with "No value for required variable".

### Removed

- `docs/implementation-plan.md` — the obsolete build journal (phases, checkpoints, resume protocol).
  Its durable design content was distilled into [docs/architecture.md](docs/architecture.md) and
  refreshed to the current design; the build history remains in git.
- `.github/workflows/vending.yml` — the manual `workflow_dispatch` plan/apply/destroy pipeline, superseded
  by the automated PR-preview + gated apply/destroy lifecycle above. (Retained in git history for break-glass.)
- `.github/workflows/oidc-smoke-test.yml` — the one-off OIDC (OpenID Connect) + state-backend diagnostic;
  its checks were verified end-to-end and are now exercised by the vending workflows themselves.
