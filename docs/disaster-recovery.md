# Disaster recovery: the backend itself is destroyed

This covers losing the storage account or the whole resource group. It's
the one scenario that the backend's own protections (versioning and soft
delete) don't cover, because those protect blobs and containers, not the
account. Everything here is run by a human: CI deliberately has no
standing permission to recreate the resource group.

**Prevention comes first.** Every resource has `prevent_destroy`, so
Terraform refuses to destroy them. A `CanNotDelete` management lock (on
the [Roadmap](../README.md#roadmap)) would block deletion from the portal
and CLI as well.

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
   `storage_account_name`, `consumer_principal_object_ids`, and
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
