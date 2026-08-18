# azure-landing-zone

A learning-lab **platform landing zone**: the repository that establishes Azure
trust and **vends** governed access to workload repositories, so those workloads can deploy
through GitHub Actions using OIDC (OpenID Connect) — with no client secrets.

This repository does **not** deploy any workload. The first workload (an ephemeral AKS
cluster) lives in a separate repository (`terraform-aks-sandbox`) and only *consumes* what
this platform provides.

## What it provides

- **Trust anchor** — the first Azure identity + resource groups, so GitHub Actions can authenticate.
- **Shared state backend** — one Entra-ID-only storage account holding every workload's Terraform state.
- **Workload identity vending** — a guardrailed module that mints a workload's CI (Continuous
  Integration) identities, their GitHub OIDC federation, and least-privilege RBAC (Role-Based
  Access Control).

## Layout

```text
bootstrap-trust/         Bicep trust anchor + shared state storage — run ONCE, locally
modules/
  workload-identity/     Terraform module — vends one workload's identities (guardrailed)
vending/                 Terraform — consumes the module to vend each declared workload
  workloads/             one <name>.tfvars per workload (the registry)
.github/workflows/       vending PR-plan / apply / destroy (GitHub Actions)
config/project.json      shared naming (platform prefix, region)
docs/                    onboarding guide, implementation plan, security model
```

## Operating model

One manual step, then everything through GitHub Actions:

1. **Local, once (you):** deploy the Bicep trust anchor → creates the platform identities, resource
   groups, and the shared Terraform state storage. This is the only manual step, because an empty
   repo has no Azure identity yet.
2. **GitHub Actions (this repo):** a PR (Pull Request) adding/editing a `vending/workloads/<name>.tfvars`
   posts a read-only plan; merging vends that workload's identities through the module (merge = deploy).
3. **GitHub Actions (workload repo):** the workload deploys itself using the vended identities and
   the shared state backend.

**To operate this repo or onboard a workload, start with the [Operating & Onboarding Guide](docs/onboarding.md)** —
it walks through the trust anchor and the vending workflows, and how a workload team gets its OIDC
subject, submits a declaration, and receives its identities.

## Guardrails

The vending module enforces, at plan time:

- roles limited to Reader / Contributor (control plane) and Storage Blob Data Reader/Contributor
  (state) — never Owner or role-granting rights;
- scope locked to the workload's own resource group + the shared state account;
- exact, wildcard-free OIDC subjects — one repository per credential.

## Security

No secrets, Terraform state, or real identifiers are committed. Storage is Entra-ID-only
(shared keys disabled). See [SECURITY.md](SECURITY.md) and [docs/security-model.md](docs/security-model.md).

## Status

Learning sandbox. See [docs/implementation-plan.md](docs/implementation-plan.md) for the current
checkpoint and plan.
