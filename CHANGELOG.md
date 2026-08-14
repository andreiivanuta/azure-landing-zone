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
