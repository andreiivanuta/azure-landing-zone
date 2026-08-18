# azure-landing-zone

A learning-lab **platform landing zone**: the repository that establishes Azure
trust and **vends** governed access to workload repositories, so those workloads can deploy
through GitHub Actions using OIDC (OpenID Connect) — with no client secrets.

This repository does **not** deploy any workload — it only vends the trust, identities, and
scoped access that workload repositories consume to deploy themselves.

## What it provides

- **Trust anchor** — the first Azure identity + resource groups, so GitHub Actions can authenticate.
- **Shared state backend** — one Entra-ID-only storage account holding every workload's Terraform state.
- **Workload identity vending** — a guardrailed module that mints a workload's CI (Continuous
  Integration) identities, their GitHub OIDC federation, and least-privilege RBAC (Role-Based
  Access Control).

## Prerequisites

- **To onboard a workload:** an existing GitHub repository for your workload, and permission to
  open a PR (Pull Request) against this repo. That's it — everything else is defaulted.
- **To operate the platform** (the one-time trust anchor): `az`, `gh`, and Terraform installed
  locally, plus an Azure role that can create identities and assign roles.

## Quickstart — onboard a workload

You add **one file** in a PR; merging vends your identities automatically. Full detail is in the
[Operating & Onboarding Guide](docs/onboarding.md).

**1. Get your OIDC subject** — binds Azure trust to your exact repository:

```powershell
gh api repos/<owner>/<repo> --jq '"repo:\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"'
```

**2. Declare your workload** — add `vending/workloads/<name>.tfvars` (copy
[taks.tfvars.example](vending/workloads/taks.tfvars.example)):

```hcl
workload = {
  subject_prefix      = "repo:<owner>@<ownerId>/<repo>@<repoId>"
  resource_group_name = "<your resource group>"
}
```

**3. Open a PR** → a read-only `terraform plan` preview posts to the PR for review (the gate).

**4. Merge** → your identities, GitHub OIDC federation, and least-privilege RBAC are created
automatically (merge = deploy).

**5. Wire your repo (manual today)** → create the `plan` / `apply` / `destroy` / `cleanup`
environments in your workload repo and set `AZURE_CLIENT_ID` (from the apply run's output),
`AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`; then authenticate with `azure/login`. Automating
this handoff is a tracked next step.

To **offboard**, delete your file in a PR: the preview shows a `terraform plan -destroy`, and
merging runs it.

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
