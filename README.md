# terraform-state-backend

A shared Azure remote-state backend for Terraform. This repo provisions one
resource group, one storage account, and one private blob container that
other Terraform projects point their `backend "azurerm" {}` block at,
instead of each project managing its own state storage. State stored here
gets automatic locking, blob versioning, and 30-day soft-delete recovery.

## What gets created

- A resource group
- A storage account — `TLS1_2` minimum, no public blob access at the
  account level, versioning + 30-day soft delete (blob and container) on
  by default
- A private blob container inside it, where every consuming project's
  state file lives as its own blob (one shared container, one blob per
  project — see "Key collisions" below)

See `main.tf` for the actual resource definitions.

## Prerequisites

- Terraform >= 1.6.0
- Azure CLI, logged in (`az login`), with rights to create a resource
  group + storage account — only needed if you're deploying this backend
  for the first time, not if you're just pointing another project at an
  already-deployed one
- To *consume* an already-deployed backend: your identity (local
  `az login` user, or CI's OIDC-federated identity) needs the **"Storage
  Blob Data Contributor"** Azure RBAC role on the storage account. See
  "Access model" below — this is not automatic, even for the account
  owner.

## Deploying this backend (one-time, per environment)

1. Copy `terraform.tfvars.example` → `terraform.tfvars` and fill in real
   values. `storage_account_name` must be globally unique across all of
   Azure — check with `az storage account check-name --name <name>`
   before committing to one.
2. `terraform init`
3. `terraform plan` — review what will be created
4. `terraform apply`
5. `terraform output` — these four values (resource group, storage
   account, container name, plus a key you choose per consumer) are what
   every consuming project needs.

This repo's own state stays **local** (gitignored) — it can't depend on
the backend it's in the middle of creating, so there's no remote-state
setup for this repo itself.

## Pointing another project's state here

1. In the consuming project's repo, copy this repo's `backend.tf.example`
   → `backend.tf`.
2. Fill in `resource_group_name` / `storage_account_name` /
   `container_name` using this repo's `terraform output` (run that from
   this repo's directory, not the consumer's).
3. Set a **unique `key`** — this is the blob name the project's state
   lives under inside the shared container. `use_azuread_auth = true` is
   already set in the example; leave it — see "Access model" below.
4. Make sure the identity that will run `terraform init`/`apply` there
   has been granted "Storage Blob Data Contributor" on the storage
   account (see below — currently a manual step, ask whoever manages
   this backend).
5. Run `terraform init`. Terraform detects the new backend config and
   offers to initialize it.

**Key collisions:** every consumer must pick a distinct `key`. Two
projects using the same key silently share — and can corrupt — one state
file. There's no automated collision check; naming it after the
consuming repo (e.g. `my-project.tfstate`) is the convention used in
`backend.tf.example`.

## Verifying it's working

From the consuming project, after `terraform init`:

```
terraform plan
```

If that completes without an auth error or "storage account not found,"
state is being read from the shared backend correctly. For a more
concrete check, apply something trivial and then confirm its blob shows
up:

```
az storage blob list \
  --account-name <storage_account_name> \
  --container-name <container_name> \
  --auth-mode login -o table
```

## State locking

The `azurerm` backend locks automatically via a blob lease — no separate
resource or setup needed. Verified 2026-08-10 against a real deployed
instance of this backend using a throwaway config with a 25-second
`time_sleep` resource to hold an apply open long enough to collide with a
second one:

1. `terraform apply` #1 starts, acquires the lock, begins its 25s wait.
2. `terraform apply` #2, run ~3s later against the same state key, fails
   immediately — the default `-lock-timeout` is `0s`, so it doesn't wait
   or retry, it just errors:

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
3. Apply #1 finishes and releases the lock. A follow-up `terraform plan`
   confirms it's fully released — no stale lease, clean state.

**If you hit a stuck lock** (e.g. a CI job got killed mid-apply and never
released it): confirm nothing is genuinely still running against that
key, then run `terraform force-unlock <LOCK_ID>` using the `ID` from the
error above. Don't force-unlock if there's any chance another apply is
still in flight — that's exactly how two applies end up racing on the
same state.

To wait instead of failing immediately (useful in CI, so a
slow-but-legitimate apply doesn't cause a spurious failure elsewhere),
pass `-lock-timeout=<duration>`, e.g. `-lock-timeout=5m`.

## Access model

- **No storage account keys, anywhere.** Every `backend.tf` uses
  `use_azuread_auth = true`. This means access is controlled by Azure AD
  RBAC, not a shared secret that has to be distributed and rotated.
- Consumers need the **"Storage Blob Data Contributor"** role, scoped to
  this storage account (not the whole subscription/resource group).
  Azure's built-in Owner/Contributor roles do **not** grant this
  automatically — RBAC control-plane roles and blob data-plane access are
  separate layers, even for the account's own owner.
- Granting that role today is a manual step (`az role assignment create`,
  or `az rest` against the ARM API directly if that command misbehaves —
  it has been seen to fail with a spurious `MissingSubscription` error).
  A more formal process (self-service, or a Terraform-managed role
  assignment per known consumer) is still open — treat the exact
  mechanism here as provisional.
- CI authenticates via **OIDC federation** — GitHub issues a short-lived,
  workflow-scoped token that Azure AD trusts via a federated credential
  on an app registration. No client secret is ever generated or stored
  in GitHub secrets.
- The container is private and the storage account blocks public blob
  access account-wide, independent of the container's own access
  setting — state must never be publicly readable.

## Known limitations

- CI currently runs `fmt`/`validate` only — no `terraform plan`/`apply`
  gate yet, so deploying changes to this backend itself is still manual.
- This repo's own state is local/manual — it can't bootstrap onto the
  backend it creates.
- Single region, LRS (locally redundant) replication — no geo-redundancy
  or multi-region failover.
- No automated check for `key` collisions between consumers — enforced
  by convention only.
