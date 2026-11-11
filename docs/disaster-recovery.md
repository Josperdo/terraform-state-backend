# Disaster recovery: the backend itself is destroyed

This covers losing the storage account or the whole resource group. It's
the one scenario that the backend's own protections (versioning and soft
delete) don't cover, because those protect blobs and containers, not the
account. Everything here is run by a human: CI deliberately has no
standing permission to recreate the resource group.

**Prevention comes first.** Two layers stand in the way of an accidental
delete:

- `prevent_destroy` on every resource: Terraform refuses to plan a
  destroy at all.
- A `CanNotDelete` management lock on the resource group
  ([locks.tf](../locks.tf)): Azure itself rejects deletes from the
  portal, CLI, API, or any other tool with a `ScopeLocked` error.
  Updates still work, and blob reads and writes aren't affected. It also
  blocks deleting role assignments; see
  [Revoking a consumer's access](#revoking-a-consumers-access).

## Deleting something here on purpose

Both guards have to be lifted deliberately, by a human with Owner (or
User Access Administrator) rights:

1. Remove `prevent_destroy` from the resource in question (a reviewed
   PR), or delete outside Terraform.
2. Remove the lock: `az lock delete --name do-not-delete-tfstate --resource-group <rg>`
3. Make the change.
4. Put the lock back with a local `terraform apply`. Terraform sees the
   lock missing and recreates it.

## Revoking a consumer's access

The lock also blocks deleting **role assignments** on the storage
account, so removing a consumer from `consumers` (or an admin from
`admin_principal_object_ids`) fails with `ScopeLocked` (HTTP 409) until
the lock is lifted. Granting access or changing a consumer's `state_key`
is an in-place update and doesn't need any of this.

Run locally, from the repo root, as the backend owner:

1. Remove the entry from `terraform.tfvars`, then `terraform plan`.
   Expect `1 to destroy` per removed identity and nothing else.
2. `az lock delete --name do-not-delete-tfstate --resource-group <rg>`
3. `terraform apply -target="azurerm_role_assignment.consumer"`. Expect
   only the role assignment destroys.
4. `terraform apply`. Expect `1 to add`: the lock coming back.
5. `terraform plan`. Expect `No changes`.

**Why step 3 is targeted:** with the lock gone, a plain `apply` would
delete the assignment *and* recreate the lock in the same run. Nothing
orders those two, so the lock can come back first and the delete fails
with 409 again. Do steps 2–4 back to back: the resource group is
unprotected in between.

**If you're also deleting the identity** (e.g. an app registration),
revoke first. Deleting the identity first leaves an orphaned assignment
that shows up as "Identity not found" and still needs the lock lifted to
remove. A revoked identity can take a few minutes to lose access while
Azure's caches catch up.

## 1. Try to recover the account first

A deleted storage account can sometimes be restored, which brings back
every consumer's state intact. Recovery is possible within a limited
window if no account with the same name has been created since. Check
right away, before redeploying anything:

- Azure portal → Storage accounts → **Restore** (or open a support request)

If that works, stop here. Nothing below is needed.

## 2. Redeploy the backend

This repo's own state lived in the deleted account, so `terraform init`
against [backend.tf](../backend.tf) will fail. Rebuild from scratch with
local state, the same way as the first deploy:

1. With subscription-level rights (Owner, or Contributor plus User
   Access Administrator; not either CI identity), make sure
   `terraform.tfvars` has the previous values: the same
   `storage_account_name`, `admin_principal_object_ids`, `consumers`, and
   `ci_*_principal_object_id`.
2. `mv backend.tf backend.tf.bootstrap`
3. `terraform init -reconfigure`, then `terraform apply`. This recreates
   the resources *and* every role assignment, since a new account starts
   with none.
4. Restore and migrate:
   ```sh
   mv backend.tf.bootstrap backend.tf
   terraform init -migrate-state -backend-config=backend-config.hcl
   ```

The CI app registrations, federated credentials, and GitHub secrets live
outside the storage account, so they survive. Nothing in GitHub needs
changing.

## 3. Consuming projects

Their state is gone unless step 1 succeeded. For each consuming project,
either:

- restore its last known state file if one exists elsewhere, or
- re-run `terraform init`, then `terraform import` every resource that
  project manages (or use `import {}` blocks, Terraform 1.5+, to generate
  them).

This is why prevention matters more than recovery here.
