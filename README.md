# terraform-state-backend

[![Terraform CI](https://github.com/Josperdo/terraform-state-backend/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/Josperdo/terraform-state-backend/actions/workflows/terraform-ci.yml)
[![License: MIT](https://img.shields.io/github/license/Josperdo/terraform-state-backend)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/Josperdo/terraform-state-backend)](https://github.com/Josperdo/terraform-state-backend/commits/main)

A shared, hardened Azure remote-state backend for Terraform. This repo
provisions one resource group, one storage account, and one private blob
container that other Terraform projects use as their `backend "azurerm"`.
Each consumer gets automatic state locking, versioned recovery, and
access controlled entirely by Azure AD RBAC: storage account keys are
disabled, and CI authenticates with OIDC rather than stored secrets.

## Architecture

```mermaid
flowchart LR
  subgraph Azure["Azure — rg-tfstate-backend"]
    SA["Storage account<br/>RA-GRS · TLS 1.2 · shared keys off<br/>versioning · 30-day soft delete"]
    C["Container: tfstate (private)"]
    SA --> C
    C --> B1["project-a.tfstate"]
    C --> B2["project-b.tfstate"]
    C --> B3["terraform-state-backend.tfstate<br/>(this repo's own state)"]
  end

  Dev["Backend owner<br/>(az login)"] -- "Azure AD · Blob Data Contributor<br/>break-glass, all keys" --> C
  Consumers["Consuming projects<br/>(people or CI)"] -- "Blob Data Contributor<br/>ABAC: own key only" --> C
```

```mermaid
flowchart LR
  PR["Pull request"] --> V["validate<br/>fmt · validate · terraform test · checkov<br/>(no Azure credentials)"]
  V --> P["plan<br/>OIDC: Reader on RG<br/>plan → job summary"]
  M["Merge to main"] -.-> D["Manual dispatch<br/>(Actions → Run workflow)"]
  D --> A["apply<br/>OIDC: Contributor on RG<br/>cannot modify RBAC"]
```

## Design decisions

| Decision | Why |
| --- | --- |
| One storage account and container shared by all consumers, separated by blob `key` | Keeps the backend simple; one place to harden, monitor, and recover |
| Shared key access **disabled**; every consumer uses `use_azuread_auth = true` | No long-lived shared secret to distribute or rotate, and nothing that bypasses RBAC |
| Blob versioning + 30-day soft delete (blobs and containers) | Recovers from a bad `apply` or an accidental `terraform state rm` with no separate backup system |
| RA-GRS replication | State files are kilobytes; geo-redundancy costs almost nothing |
| `prevent_destroy` on every resource **and** a `CanNotDelete` lock on the resource group | `prevent_destroy` only stops this Terraform config; the lock is enforced by Azure itself, so it also blocks the portal, CLI, and API. One accidental delete here would take every consumer's state with it |
| OIDC federation for CI, with **separate plan and apply identities** | No client secrets. A PR can only ever reach a Reader identity; writes need a manual dispatch from `main` |
| Apply identity is Contributor (excludes `Microsoft.Authorization/*/write`) | CI is structurally unable to change who has access; `rbac.tf` is applied by a human |
| Per-key **ABAC conditions** on every consumer's role assignment; one unconditional admin | A shared account no longer means shared access: each identity can only touch its own state key. The owner keeps break-glass access to every key for recovery |
| Partial backend config for this repo's own state | Real resource names come from `-backend-config` at init time, not tracked files |

## What's been verified (against real Azure, not just on paper)

- **Locking:** two concurrent `apply`s against the same key. The second failed
  immediately with `Error acquiring the state lock` / `state blob is already
  locked`, and the lease released cleanly afterward (see [State locking](#state-locking)).
- **Least privilege:** a zero-role service principal was **denied**
  (`AuthorizationPermissionMismatch`), granted access through `rbac.tf`,
  confirmed able to read *and* write, then revoked and deleted.
- **CI end to end:** real PRs through `validate` → `plan` with the
  read-only identity, then manual `apply` dispatches. One was a no-op; one
  changed real infrastructure (LRS → RA-GRS), confirmed independently with
  `az storage account show`.
- **A bug only least privilege could find:** without
  `storage_use_azuread = true`, the azurerm provider silently calls
  `listKeys` for some storage reads. That worked under elevated local
  credentials and failed under the Reader-only CI identity, which is how
  it was found. The fix is in [providers.tf](providers.tf).
- **Delete lock:** created a throwaway container in the locked resource
  group and tried to delete it through the ARM API. Azure refused with
  `ScopeLocked`. Then ran the [deliberate-deletion runbook](docs/disaster-recovery.md#deleting-something-here-on-purpose)
  end to end: removed the lock, deleted the container (it went into
  30-day soft delete as designed), and a local `terraform apply` detected
  the missing lock and recreated it.
- **Per-key isolation (ABAC):** two throwaway consumers (the
  [examples/](examples/)), each with its own service principal and key.
  Each could init, apply, and list workspaces on its own key. Each was
  **denied** on the other's key with `AuthorizationPermissionMismatch`,
  for reads (`state pull`) and for the lock lease (`plan`), and the
  target blob was untouched. Locking still worked under the condition (a
  held lease blocked even the unrestricted admin), and the CI identities,
  now key-scoped too, kept passing `plan`.
- **Revoking under the delete lock:** removing a consumer from `consumers`
  failed with `ScopeLocked` (409), because the lock also blocks deleting
  role assignments. The [revoke runbook](docs/disaster-recovery.md#revoking-a-consumers-access)
  worked end to end, and the revoked identity was then denied even on its
  own key.

On every PR, CI also runs `terraform test` ([tests/](tests/)) to assert
the security baseline (keys off, no public access, TLS 1.2, versioning,
soft delete, private container) and a checkov scan. Every checkov
exception is justified inline in [main.tf](main.tf).

## Repository layout

| File | Purpose |
| --- | --- |
| [main.tf](main.tf) | Resource group, storage account, container |
| [rbac.tf](rbac.tf) | Role assignments for consumers and the two CI identities (applied locally only) |
| [locks.tf](locks.tf) | `CanNotDelete` lock on the resource group (applied locally only) |
| [variables.tf](variables.tf) / [outputs.tf](outputs.tf) | Inputs (with validation) and the values consumers need |
| [providers.tf](providers.tf) / [backend.tf](backend.tf) | Provider config; this repo's own remote state (partial config) |
| [backend.tf.example](backend.tf.example) | Template for consuming projects |
| [examples/](examples/) | Minimal consuming projects (partial backend config, deploy nothing); used to prove per-key isolation |
| [tests/](tests/) | `terraform test` suite with a mocked provider, so it needs no Azure credentials |
| [.github/workflows/terraform-ci.yml](.github/workflows/terraform-ci.yml) | validate / plan / apply pipeline |
| [docs/disaster-recovery.md](docs/disaster-recovery.md) | Runbook for losing the backend itself |

## Usage

### Prerequisites

- Terraform >= 1.7
- Azure CLI, logged in (`az login`)
- To deploy the backend: rights to create a resource group and storage
  account, and to assign roles (e.g. Owner or User Access Administrator) on it
- To *consume* an existing backend: the **Storage Blob Data Contributor**
  role on the storage account (see [Access model](#access-model))

### Deploying this backend (first time)

This repo stores its own state in the backend it creates, so the first
deploy has to run with local state and then migrate:

1. `cp terraform.tfvars.example terraform.tfvars` and fill in real
   values. `storage_account_name` must be globally unique
   (`az storage account check-name --name <name>`). Put your own object
   ID (`az ad signed-in-user show --query id -o tsv`) in
   `admin_principal_object_ids`. Owner on the subscription does
   **not** include blob data access.
2. Temporarily disable the remote backend so Terraform uses local state:
   `mv backend.tf backend.tf.bootstrap`
3. `terraform init`, `terraform plan`, `terraform apply`
4. Restore the backend and migrate the local state into it:
   ```sh
   mv backend.tf.bootstrap backend.tf
   cp backend-config.hcl.example backend-config.hcl   # fill in from `terraform output`
   terraform init -migrate-state -backend-config=backend-config.hcl
   ```
   New role assignments can take a few minutes to propagate. If the
   migration gets a 403, wait and retry.
5. After confirming `terraform plan` shows no changes, delete the local
   `terraform.tfstate*` files.

On a machine where the backend already exists, skip to
`terraform init -backend-config=backend-config.hcl`.

### Pointing another project's state here

1. Copy [backend.tf.example](backend.tf.example) into the consuming repo
   as `backend.tf`.
2. Fill in `resource_group_name` / `storage_account_name` /
   `container_name` from this repo's `terraform output`.
3. Choose a **unique `key`**, such as the repo name (`my-project.tfstate`).
   Keep `use_azuread_auth = true`.
4. Make sure the identity running Terraform there is listed in
   `consumers` in this repo, under a `state_key` that **exactly matches**
   the `key` from step 3, and that this repo has been re-applied. Access
   is limited to that key, so a mismatch shows up as a 403.
5. `terraform init`, then `terraform plan` to confirm. An auth error or
   "storage account not found" means steps 2–4 need another look.

For a working minimal consumer, see [examples/consumer-a](examples/consumer-a/main.tf):
it keeps only `key` and `use_azuread_auth` in the file and passes the
rest at init time:

```sh
terraform init "-backend-config=storage_account_name=<storage_account_name>" "-backend-config=container_name=<container_name>"
```

(Quote each whole flag in PowerShell, or it splits the value at the `.`.)

To see what's stored:

```sh
az storage blob list --account-name <storage_account_name> \
  --container-name <container_name> --auth-mode login -o table
```

## Access model

- **No storage account keys.** Shared key access is disabled on the
  account, so Azure AD RBAC is the only way to read or write state, for
  people and for CI.
- Consumers need **Storage Blob Data Contributor** on the storage
  account. Owner/Contributor do **not** include it, because control-plane
  and data-plane permissions are separate layers in Azure.
- Access is managed in [rbac.tf](rbac.tf): add a project to `consumers`
  (its `state_key` plus the object IDs allowed to use it) and
  `terraform apply` locally. Each identity is limited to its own key by an
  ABAC condition; only `admin_principal_object_ids` (break-glass) can
  reach every key. CI never applies `rbac.tf`.
- The condition allows reads, writes, and deletes only on the blob
  `<key>` and its workspaces (`<key>env:<name>`), and allows listing only
  with the prefix `<key>env:`, which is exactly what the backend does
  during `init`. A project can list several identities (e.g. a CI plan
  and apply identity) under one key; one identity can belong to only one
  project.
- **Granting or re-keying access** is an in-place change and works with
  the delete lock on. **Revoking access** deletes a role assignment,
  which the lock blocks. Follow the
  [revoke runbook](docs/disaster-recovery.md#revoking-a-consumers-access).
- CI uses **OIDC federation**. GitHub issues a short-lived,
  workflow-scoped token that Azure AD trusts through a federated
  credential, and no client secret exists anywhere.

## CI/CD

Every PR to `main` runs **validate** (fmt, validate, `terraform test`,
checkov; no cloud credentials) and **plan** (read-only identity, plan
posted to the job summary). There's deliberately no paths filter: both
are required checks, and a filtered-out workflow never reports them, so
docs-only PRs would be unmergeable. `plan` is skipped for fork and
Dependabot PRs, which don't get secrets.

Applying is deliberately manual. After merging, go to **Actions → Terraform
CI → Run workflow** on `main`. The apply job plans to a file, records that
plan in the job summary, and applies exactly that file, using a
Contributor identity scoped to this resource group. Both jobs `-target`
only the three backend resources. Role assignments and the delete lock
stay local and manual, by policy and by permission: Contributor can't
manage either.

There are two human gates before anything writes to Azure: someone has
to dispatch the run, and the `production` environment then pauses the
`apply` job until a required reviewer approves it (**Review deployments**
on the run page). The environment only accepts deployments from `main`.

## State locking

The `azurerm` backend locks state automatically with a blob lease; no
extra resource is needed. This was tested with a 25-second `time_sleep`
holding one apply open while a second ran against the same key:

```
Error: Error acquiring the state lock

Error message: state blob is already locked
Lock Info:
  ID:        5d16c90e-bcd4-e0f7-5129-044159ee985c
  Path:      tfstate/<key>.tfstate
  Operation: OperationTypeApply
  Who:       <user>@<machine>
  Version:   1.14.6
  Created:   2026-08-10 20:33:06 UTC
```

The default `-lock-timeout` is `0s`, so the second run fails immediately.
Pass `-lock-timeout=5m` to wait instead (CI does this). **Stuck lock**
(e.g. a job killed mid-apply): confirm nothing is still running against
that key, then run `terraform force-unlock <LOCK_ID>`. Never force-unlock
while another apply might still be in flight.

## Known limitations

- **Revoking access needs the delete lock lifted.** The `CanNotDelete`
  lock blocks deleting role assignments too, so removing a consumer is a
  short manual procedure (see the
  [revoke runbook](docs/disaster-recovery.md#revoking-a-consumers-access))
  rather than a one-line tfvars change. Granting access isn't affected.
- **Admins bypass the per-key boundary by design.** Anyone in
  `admin_principal_object_ids` can read and write every key. Keep that
  list to the backend's owner.
- **Public network endpoint.** GitHub-hosted runners have dynamic IPs, so
  the account isn't behind a firewall or private endpoint. Access still
  requires an Azure AD identity with an explicit role assignment.
- **Recreating the resource group needs a human.** The CI apply identity
  is scoped to the resource group, so it can't recreate the group if it's
  deleted. That's deliberate: CI gets no standing subscription-level
  access. See [docs/disaster-recovery.md](docs/disaster-recovery.md).

## Roadmap

- [x] Per-consumer ABAC conditions: each principal can only access its own state key ([rbac.tf](rbac.tf))
- [x] `CanNotDelete` management lock on the resource group ([locks.tf](locks.tf))
- [ ] Blob read audit logging (diagnostic settings → Log Analytics)

## License

[MIT](LICENSE)
