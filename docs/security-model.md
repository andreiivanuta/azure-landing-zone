# Repository Structure and Security Model

## Trust boundaries

The project separates persistent control-plane resources from disposable AKS resources.

### Persistent bootstrap boundary

The minimal trust-anchor Bicep deployment will own:

- The bootstrap and disposable resource groups.
- The bootstrap user-assigned managed identity.
- Its exact GitHub OIDC federated credential and resource-group-scoped role assignments.

The bootstrap Terraform root will then own:

- The remote-state storage account and blob container.
- Plan, deployment, and cleanup identities and their federated identity credentials.
- Narrow Azure role assignments required by automation.
- Optional persistent audit and monitoring resources.

This split breaks the initial authentication and state-backend dependency cycle without local Terraform state. Routine AKS workflows must not be able to delete or modify this boundary. Bootstrap changes require a separate, explicitly approved process operated by a trusted human identity.

### Disposable AKS boundary

The AKS Terraform root will own:

- The ephemeral AKS cluster.
- Disposable networking and supporting resources.
- Resource tags that record ownership and expiration.

Apply, destroy, and TTL cleanup identities will be scoped only to the designated disposable resource group and the minimum remote-state data access they require.

## GitHub trust model

- Pull request workflows perform offline validation and scanning only. They receive no Azure OIDC token, environment secret, or repository write permission.
- Apply and destroy run only through manual dispatch from protected repository content.
- Apply and destroy use separate protected GitHub environments and exact OIDC subject claims.
- Scheduled cleanup uses its own OIDC subject and identity. It cannot access bootstrap resources and destroys resources only after validating expiration metadata.
- GitHub-hosted runners are used. Self-hosted runners are not permitted for this public repository.
- Every workflow declares explicit minimum `permissions` and pins external actions to full commit SHAs.

## Remote state requirements

The persistent Azure Storage account must use:

- Microsoft Entra ID authorization with narrowly scoped data-plane roles.
- HTTPS-only transport and TLS 1.2 or later.
- Public blob access disabled.
- Shared-key authorization disabled when supported by the selected backend flow.
- Blob versioning and blob/container soft delete.
- Separate state keys for bootstrap and AKS roots.
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