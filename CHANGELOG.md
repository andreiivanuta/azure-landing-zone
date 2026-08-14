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
