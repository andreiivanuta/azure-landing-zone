# Bootstrap Trust Anchor

This Bicep template establishes the first Azure trust relationship for GitHub Actions. It exists because an unauthenticated public GitHub workflow cannot safely create its own Azure identity or permissions.

This is the only project layer deployed by the already authenticated Azure user. It creates no client secret, Terraform state, Storage account, AKS cluster, or workload data.

## Why Bicep Is Used Here

Terraform needs an identity and a state backend before a GitHub Actions workflow can use Terraform. Azure Resource Manager records Bicep deployments itself, so this small initial deployment does not require Terraform state.

After it succeeds, the protected GitHub bootstrap workflow uses the new managed identity through OIDC and Terraform takes over the persistent project infrastructure.

## Resources Created

| Resource | Scope | Purpose |
|---|---|---|
| Bootstrap resource group | Subscription | Holds the state backend and CI identities created later by Terraform. |
| Disposable resource group | Subscription | Contains only short-lived AKS infrastructure. |
| Bootstrap user-assigned managed identity | Bootstrap resource group | The first Azure identity GitHub Actions may impersonate. |
| Federated identity credential | Bootstrap identity | Trusts only the exact GitHub `bootstrap` environment OIDC subject. |
| Four role assignments | Resource groups only | Give the bootstrap identity only the permissions needed to create later infrastructure and scoped role assignments. |

## Bootstrap Identity Permissions

| Scope | Role | Why it is needed |
|---|---|---|
| Bootstrap resource group | Contributor | Create the state Storage account and the three routine managed identities. |
| Bootstrap resource group | User Access Administrator | Assign data-plane state roles and OIDC-related permissions inside the bootstrap boundary. |
| Disposable resource group | Reader | Inspect the disposable boundary while configuring routine identities. |
| Disposable resource group | User Access Administrator | Assign the plan, deployment, and cleanup identities their narrow roles there. |

The bootstrap identity has no subscription-wide role and no `Owner` assignment. It cannot change permissions outside these two project resource groups.

## Deployment-Time Input

`bootstrapOidcSubject` is the exact immutable subject built from GitHub metadata and the `bootstrap` environment. It is supplied from the current PowerShell session when validating or deploying. It must never be placed in a committed parameter file.

The other parameters have safe defaults:

```text
location: swedencentral
projectPrefix: taks
```

## Safe Next Checks

The next steps are local Bicep compilation, Azure deployment validation, and an Azure `what-if` preview. None of those steps applies resources. Deployment happens only after the preview is reviewed and explicitly approved.