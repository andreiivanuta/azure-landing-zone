# Security Policy

## Reporting a vulnerability

Use this repository's GitHub private vulnerability reporting feature. Do not open a public issue for a suspected vulnerability, exposed credential, personal information, or sensitive Azure identifier.

Do not include live credentials, access tokens, Terraform state, plans, kubeconfig, or customer data in a report. Revoke exposed credentials before sharing sanitized evidence.

## Credential exposure response

If a credential or sensitive file is committed, pushed, logged, or uploaded:

1. Revoke or rotate the credential immediately at its issuing service.
2. Disable affected access and review recent authentication and audit activity.
3. Delete any public workflow log or artifact containing the value.
4. Remove the material from the current branch and, when necessary, rewrite Git history.
5. Treat forks, clones, caches, and external archives as potentially retaining the original content.
6. Document the incident and add a preventive control or detection rule.

Deleting a value from Git history does not make it trustworthy again. Rotation or revocation is mandatory.

## Supported versions

This is a learning sandbox rather than a versioned software product. Security fixes apply only to the default branch.
