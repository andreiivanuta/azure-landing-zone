# Bootstrap Trust Anchor

The Bicep IaC that establishes the platform's first Azure trust relationship for
GitHub Actions. An unauthenticated GitHub workflow cannot safely create its own
Azure identity or role assignments, so this one deployment is run **once, locally**,
by a trusted user who is already signed in with `az login`.

It creates no client secret, no Terraform state, and no workload resources.

## Why Bicep, not Terraform

Terraform would need an identity and a remote state backend *before* it could run in
CI (Continuous Integration) — the exact chicken-and-egg problem this layer breaks.
ARM (Azure Resource Manager) records Bicep deployments itself, so this seed needs
no state backend at all. Everything else in the platform is Terraform, running in
GitHub Actions under the identities minted here.

## What it creates (subscription scope)

| Resource | Name / scope | Purpose |
|---|---|---|
| Management RG | `rg-alz-management-swc` | Persistent home for the platform's own resources (state SA and the platform identities). |
| Identity RG | `rg-alz-identity-swc` | Persistent home for the workload identities the vending pipeline mints (CAF identity archetype). |
| Admin UAMI | `id-alz-admin-swc` (in management RG) | Break-glass platform identity for the `admin` GitHub environment. |
| Vending UAMI | `id-alz-vending-swc` (in management RG) | Bounded **write** identity for the `vending` GitHub environment (apply / destroy). |
| Vending-PR UAMI | `id-alz-vending-pr-swc` (in management RG) | **Read-only** identity for pull-request plan previews (runs with no environment). |
| Federated credentials | `github-admin`, `github-vending`, `github-vending-pr` (`:pull_request`), `github-vending-main-plan` (`:ref:refs/heads/main`) | Each trusts only its exact GitHub OIDC subject. The read-only identity carries two so it can preview both on a PR and on merge. |
| Custom role `Landing Zone Vendor (alz)` | Subscription | The minimum **write** actions the vending identity needs (see below). |
| Custom role `Landing Zone Vendor Reader (alz)` | Subscription | The read-only counterpart, assigned to the PR-plan identity. |
| Terraform state SA | `st alz state <uniqueString>` (in management RG) | Shared, Entra-only, keyless backend for every Terraform root's state. |

The SA name is derived from `uniqueString(subscription().id)` so the deployment stays
idempotent without hard-coding any subscription-specific value.

## Identity permissions

| Identity | Where | Role | Why |
|---|---|---|---|
| Admin | Management RG | Contributor + UAA (User Access Administrator) | Build and administer the platform foundation; assign data-plane roles when needed. |
| Admin | State SA | Storage Blob Data Contributor | Read/write Terraform state (shared keys are disabled). |
| Vending | Subscription | `Landing Zone Vendor (alz)` (custom) | Create workload RGs, UAMIs + federated credentials, and role assignments — **no** Contributor, **no** Owner, no data-plane rights beyond state. |
| Vending | State SA | Storage Blob Data Contributor | Read/write its own state key (`<workload>.tfstate`). |
| Vending-PR | Subscription | `Landing Zone Vendor Reader (alz)` (custom) | Read-only preview only — no create / update / delete anywhere. |
| Vending-PR | State SA | Storage Blob Data Reader | Read state during `plan`; never writes. |

The vending Terraform root later also grants the vending **and** PR identities `Reader`
on each workload RG (not by this trust anchor), so the destroy pipeline can enumerate an
RG's live contents for its blast-radius check.

The custom role explicitly lists only:
`Microsoft.Resources/subscriptions/resourceGroups/{read,write,delete}`,
`Microsoft.ManagedIdentity/userAssignedIdentities/*`,
`Microsoft.Authorization/roleAssignments/{read,write,delete}`,
`Microsoft.Authorization/roleDefinitions/read`, and
`Microsoft.Storage/storageAccounts/read`.

The read-only `Landing Zone Vendor Reader (alz)` role lists only the `*/read` equivalents,
so the PR-plan identity can preview but never change anything.

No identity holds a subscription-wide Contributor or Owner assignment. There is no client
secret anywhere; every login is a short-lived OIDC token exchange.

## Deployment-time inputs

The required parameters are the exact immutable GitHub OIDC subjects for the platform
identities — the two environment subjects plus the two the read-only PR identity trusts:

```text
adminOidcSubject        …/azure-landing-zone@<repoId>:environment:admin
vendingOidcSubject      …/azure-landing-zone@<repoId>:environment:vending
pullRequestOidcSubject  …/azure-landing-zone@<repoId>:pull_request
mainRefOidcSubject      …/azure-landing-zone@<repoId>:ref:refs/heads/main
```

They are never committed. `deploy.ps1` derives them from `gh api` at deployment time,
so no identifier is hard-coded in source.

All naming is read from [`../config/project.json`](../config/project.json) via
`loadJsonContent`, keeping Bicep and Terraform in sync on `platformPrefix`,
`locationCode`, and `location`.

## How to run it

The whole flow is wrapped in `deploy.ps1`, which is idempotent and safe to re-run:

```powershell
pwsh ./bootstrap-trust/deploy.ps1
```

That script will:

1. Derive all four OIDC subjects via `gh api` (admin, vending, `:pull_request`, `:ref:refs/heads/main`).
2. Run `az deployment sub create` against this template.
3. Read the outputs (client IDs, SA name) without printing them.
4. Configure the `admin` and `vending` GitHub environments — **both restricted to `main`** —
   with `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` (variables) and `AZURE_SUBSCRIPTION_ID` (secret).
5. Set the repo-level values the environment-less PR-plan job needs:
   `STATE_STORAGE_ACCOUNT_NAME`, `VENDING_PR_CLIENT_ID` (the read-only client ID),
   `AZURE_TENANT_ID` (variable), and `AZURE_SUBSCRIPTION_ID` (secret).

> Seeding a **workload** repository with its vended credentials is a separate, automated
> step performed later by `vending-apply` via the seeder GitHub App — not by this script.
> See [../docs/architecture.md](../docs/architecture.md).

## Safe next checks

Before deploying, or when reviewing a change to this template:

```powershell
az bicep build --file ./bootstrap-trust/main.bicep                       # offline compile
az deployment sub validate --location swedencentral --template-file ...  # ARM validation
az deployment sub what-if  --location swedencentral --template-file ...  # preview diff
```

Only apply after reviewing the what-if.