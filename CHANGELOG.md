# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This is a learning sandbox rather than a versioned product, so entries are grouped
under `Unreleased` and tracked by date instead of semantic-version tags.

## [Unreleased]

### Added
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
  authenticate to Azure via OIDC (OpenID Connect) as the admin identity, with no stored secret.

### Changed

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

### Fixed

- `modules/workload-identity`: replaced the deprecated `parent_id` + `resource_group_name` arguments on
  `azurerm_federated_identity_credential` with the single `user_assigned_identity_id` (required by azurerm v5).
