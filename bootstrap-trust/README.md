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
| Vending UAMI | `id-alz-vending-swc` (in management RG) | Bounded automation identity for the `vending` GitHub environment. |
| Federated credential per identity | `github-admin`, `github-vending` | Trusts only the exact GitHub OIDC subject for its environment. |
| Custom role `Landing Zone Vendor (alz)` | Subscription | The minimum set of actions the vending identity needs (see below). |
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

The custom role explicitly lists only:
`Microsoft.Resources/subscriptions/resourceGroups/{read,write,delete}`,
`Microsoft.ManagedIdentity/userAssignedIdentities/*`,
`Microsoft.Authorization/roleAssignments/{read,write,delete}`,
`Microsoft.Authorization/roleDefinitions/read`, and
`Microsoft.Storage/storageAccounts/read`.

Neither identity holds a subscription-wide Contributor or Owner assignment. There is
no client secret anywhere; every login is a short-lived OIDC token exchange.

## Deployment-time inputs

The two required parameters are the exact immutable GitHub OIDC subjects for the
`admin` and `vending` environments:

```text
adminOidcSubject    e.g. repo:<owner>@<ownerId>/azure-landing-zone@<repoId>:environment:admin
vendingOidcSubject  e.g. repo:<owner>@<ownerId>/azure-landing-zone@<repoId>:environment:vending
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

1. Derive both OIDC subjects via `gh api`.
2. Run `az deployment sub create` against this template.
3. Read the outputs (client IDs, SA name) without printing them.
4. Configure the `admin` (branches: `dev`) and `vending` (branches: `dev`, `main`)
   GitHub environments with `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` (variables) and
   `AZURE_SUBSCRIPTION_ID` (secret).
5. Set the repo-level `STATE_STORAGE_ACCOUNT_NAME` variable so CI knows the backend.

## Safe next checks

Before deploying, or when reviewing a change to this template:

```powershell
az bicep build --file ./bootstrap-trust/main.bicep                       # offline compile
az deployment sub validate --location swedencentral --template-file ...  # ARM validation
az deployment sub what-if  --location swedencentral --template-file ...  # preview diff
```

Only apply after reviewing the what-if.