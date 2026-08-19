# Repository Structure and Security Model

## Trust boundaries

The project separates persistent platform (control-plane) resources from the disposable workload resources they support.

### Persistent platform boundary (this repo)

The subscription-scope Bicep trust anchor (`bootstrap-trust/main.bicep`) owns:

- The management RG (Resource Group) `rg-alz-management-swc` and the identity RG `rg-alz-identity-swc`.
- The admin UAMI (User-Assigned Managed Identity) `id-alz-admin-swc` and its GitHub OIDC federated credential (`github-admin`).
- The vending **write** UAMI `id-alz-vending-swc` and its credential (`github-vending`), plus the read-only PR-plan UAMI `id-alz-vending-pr-swc` with two credentials (`github-vending-pr` for `:pull_request` and `github-vending-main-plan` for `:ref:refs/heads/main`).
- The custom roles `Landing Zone Vendor (alz)` (write, assigned to the vending identity) and `Landing Zone Vendor Reader (alz)` (read-only, assigned to the PR-plan identity), both at subscription scope.
- The shared Terraform state SA (Storage Account) inside the management RG, with Storage Blob Data Contributor granted to admin and vending, and Storage Blob Data Reader to the PR-plan identity.
- Admin's Contributor + UAA (User Access Administrator) role assignments, scoped only to the management RG.

The vending Terraform root (`vending/`) then owns, per workload:

- One workload RG (`rg-<workload>-swc`) created and destroyed with the workload.
- One UAMI per role (typically plan / deploy / cleanup), living in the identity RG so identities outlive the workload RG.
- One federated credential per (identity, environment) pair with an exact OIDC subject and no wildcards.
- Scoped RBAC (Role-Based Access Control) on the workload RG and on the state SA \u2014 nothing else.

This split breaks the initial authentication and state-backend dependency cycle without local Terraform state: Bicep needs no backend, and by the time Terraform runs, the state SA already exists. Routine workload workflows must not be able to modify anything in this platform boundary. Changes to the trust anchor require re-running `bootstrap-trust/deploy.ps1` locally as the trusted human.

### Workload boundary

The workload's Terraform root lives in the workload repository and owns the ephemeral cluster and its supporting resources.

The vended plan, deploy, and cleanup identities are granted access scoped only to the designated workload RG and the state SA. They never receive access to this platform boundary. The module's guardrails enforce this at plan time:

- control-plane roles limited to Reader or Contributor (never Owner or role-granting rights);
- state roles limited to Storage Blob Data Reader or Storage Blob Data Contributor;
- scope locked to the workload's own RG and the shared state SA;
- exact, wildcard-free OIDC subjects \u2014 one repository per credential;
- at least one environment per identity.

## GitHub trust model

- Pull-request previews run **read-only**: `vending-pr-plan` authenticates as the PR-plan identity (`id-alz-vending-pr-swc`), whose roles are read-only, and posts a `plan` preview comment (the review gate). It can read Azure and state but cannot create, update, or delete anything, and holds no write environment.
- Apply and destroy run on **merge to `main`** — the reviewed PR is the gate — under the `vending` environment and the write identity, with exact OIDC subject claims. They are also `workflow_dispatch`-able for re-run / recovery, and they **re-plan against current state** rather than replaying a saved plan, so no plan artifact is produced or exposed.
- Destroy has a **blast-radius gate**: it refuses to delete a workload RG that still contains resources unless explicitly forced, so a file-delete PR cannot recursively destroy live infrastructure.
- The vended `cleanup` identity exists for a workload's own scheduled time-to-live cleanup, executed from the workload repository — this platform repo runs no scheduled jobs.
- Workload repositories are seeded with their vended client IDs by a least-privilege GitHub App (`alz-vending-seeder`) that mints a repository-scoped token; it holds Variables/Secrets permission only, never repository administration. Client IDs are non-secret identifiers — the OIDC `:environment:<env>` subject is the real gate.
- GitHub-hosted runners are used. Self-hosted runners are not permitted for this public repository.
- Every workflow declares explicit minimum `permissions`. Pinning external actions to full commit SHAs is a tracked hardening item (actions are currently pinned to release tags).

## Remote state requirements

The persistent Azure Storage account must use:

- Microsoft Entra ID authorization with narrowly scoped data-plane roles.
- HTTPS-only transport and TLS 1.2 or later.
- Public blob access disabled.
- Shared-key authorization disabled when supported by the selected backend flow.
- Blob versioning and blob/container soft delete.
- Separate state keys for the bootstrap and workload roots.
- Restricted administrative access and auditable role assignments.

State and plan files are sensitive operational data. They must never be committed, printed to public logs, or uploaded as public workflow artifacts.

## Public data policy

Do not commit or print:

- Credentials, tokens, private keys, certificates, or connection strings.
- Terraform state, saved plans, crash logs, or provider caches.
- Kubeconfig, Kubernetes tokens, or cluster administrator material.
- Real tenant IDs, subscription IDs, object IDs, user principal names, or personal email addresses.
- Private resource names, IP addresses, customer data, or internal topology.

Use documented placeholders in examples. Store non-secret deployment configuration in GitHub environment or repository variables when disclosure is acceptable; otherwise use environment secrets only to reduce public log exposure. Secrets are not a substitute for OIDC.

## Planned validation gates

Pull requests will eventually require formatting, Terraform validation, linting, policy/security scanning, secret detection, and dependency review. Required checks will be added to the default-branch ruleset only after the corresponding workflows exist and have completed successfully once.