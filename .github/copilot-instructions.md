# Copilot instructions — azure-landing-zone

This is a **training repository**. The maintainer is actively learning Azure, Bicep,
Terraform, and Git, so favour clarity and teaching over brevity.

## Always expand acronyms

On the **first use in every reply**, write each acronym followed by its full name in
brackets. This is a deliberate learning aid — never skip it, even for "obvious" ones.

Examples:

- `OIDC (OpenID Connect)`
- `CI (Continuous Integration)` / `CD (Continuous Delivery)`
- `PR (Pull Request)`
- `RG (Resource Group)`
- `RBAC (Role-Based Access Control)`
- `UAA (User Access Administrator)`
- `IaC (Infrastructure as Code)`
- `SA (Storage Account)`
- `ARM (Azure Resource Manager)`
- `AKV (Azure Key Vault)`

## Work style

- Go **step by step**, one micro-step at a time. Propose a change, explain the *why*,
  and wait for approval before applying it. Never batch several changes into one leap.
- Briefly **teach the tooling** (Git, Bicep, Terraform, `gh`, `az`) as you use it —
  don't assume familiarity. Explain each command and its important flags before it runs.
- **Let me run the learning-critical commands myself.** For anything that teaches a core
  skill or changes real state — `git`, `gh`, `terraform`, `az`, Bicep deploys — hand me
  the exact command, explain what it does, and let me run it and paste the output back.
  You handle read-only file viewing and the code edits.
- I can always say **"you run it"** to hand a command back to you.
- After each command, **interpret the output together**: what it means, what changed,
  and what the next step is.

## Explaining changes

- Before editing any workflow, Terraform, or Bicep file, **show the snippet and the
  reasoning first** — name the file, the exact change, and why it's needed.
- Prefer small, reviewable diffs and focused commits. Use Conventional Commit prefixes
  (`feat`, `fix`, `docs`, `refactor`, `chore`) and briefly explain the prefix you chose.
- Keep a **visible checklist** of the current multi-step task so I can see where we are.

## Safety and verification

- Say whether a step is **read-only** (safe) or **mutating** (changes Git, GitHub, or
  Azure) before running it.
- Terraform: `fmt` and `validate` before pushing; `plan` before `apply`; never apply
  without reviewing the plan together.
- Bicep: `az bicep build`, then `what-if`, before any deploy.
- **Verify before extending**: prove a step works end-to-end before building on top of it.
