# rbac.tf
#
# Grants each listed identity the role needed to use this backend as a
# Terraform state store: read/write blobs in this storage account.
# Owner/Contributor on the storage account does NOT include this — Azure
# RBAC treats control-plane management (create/delete the account itself)
# and data-plane access (read/write the blobs inside it) as separate
# layers, even for the account's own owner. This role is what makes
# `use_azuread_auth = true` in backend.tf.example work — and, with shared
# key access disabled on the account (see main.tf), it is the only way in.
#
# Per-key isolation (ABAC): every entry in `consumers` gets the role with a
# role-assignment condition that only allows blob operations on its own
# state_key, so one consumer cannot read or overwrite another's state.
# `admin_principal_object_ids` get the role with no condition — that's
# the backend owner's break-glass path for recovering any key.
#
# To add a consumer: add an entry to `consumers` in terraform.tfvars and
# re-apply. To remove one: the CanNotDelete lock (locks.tf) blocks
# deleting role assignments, so revoking access needs the lock-off
# runbook in docs/disaster-recovery.md. Changing a key (condition) does
# not — conditions update in place.
#
# One resource for both kinds, keyed by object ID, so moving an identity
# between admin and consumer is an in-place update, not delete + create.

locals {
  # object_id => state_key, or null for an unconditional admin grant.
  blob_data_grants = merge(
    { for id in var.admin_principal_object_ids : id => null },
    merge([for c in values(var.consumers) : { for id in c.object_ids : id => c.state_key }]...),
  )

  blob_actions = "Microsoft.Storage/storageAccounts/blobServices/containers/blobs"
}

resource "azurerm_role_assignment" "consumer" {
  for_each = local.blob_data_grants

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.key

  # Two clauses, both must hold:
  #   1. Any read (except listing), write, create, delete, or rename is only
  #      allowed on the blob `<key>` or a workspace blob `<key>env:<name>`.
  #      (The azurerm backend stores workspaces as `<key>env:<name>`.)
  #   2. Listing is only allowed with a prefix of `<key>env:` — that's the
  #      exact list call the backend makes to discover workspaces during
  #      init. List operations carry no blob path, only the request prefix,
  #      so they need their own clause; an unprefixed list is denied.
  # Every action named here must be in the role, or Azure rejects the
  # condition (InvalidRoleAssignmentCondition).
  condition = each.value == null ? null : trimspace(<<-EOT
    (
     (
      !(ActionMatches{'${local.blob_actions}/read'} AND NOT SubOperationMatches{'Blob.List'})
      AND
      !(ActionMatches{'${local.blob_actions}/write'})
      AND
      !(ActionMatches{'${local.blob_actions}/add/action'})
      AND
      !(ActionMatches{'${local.blob_actions}/delete'})
      AND
      !(ActionMatches{'${local.blob_actions}/move/action'})
     )
     OR
     (
      @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals '${azurerm_storage_container.state.name}'
      AND
      (
       @Resource[${local.blob_actions}:path] StringEquals '${each.value}'
       OR
       @Resource[${local.blob_actions}:path] StringStartsWith '${each.value}env:'
      )
     )
    )
    AND
    (
     (
      !(ActionMatches{'${local.blob_actions}/read'} AND SubOperationMatches{'Blob.List'})
     )
     OR
     (
      @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals '${azurerm_storage_container.state.name}'
      AND
      @Request[${local.blob_actions}:prefix] StringStartsWith '${each.value}env:'
     )
    )
  EOT
  )
  condition_version = each.value == null ? null : "2.0"

  lifecycle {
    precondition {
      condition     = length(setintersection(toset([for id in var.admin_principal_object_ids : lower(id)]), toset(flatten([for c in values(var.consumers) : [for id in c.object_ids : lower(id)]])))) == 0
      error_message = "An identity can't be both an admin and a consumer — an unconditional admin grant would silently cancel its key restriction."
    }
  }
}

# --- CI identities -----------------------------------------------------
#
# CI needs ARM-level access too, not just blob data access — the blob role
# above lets it read/write state, but `terraform plan`/`apply` also has to
# read (and, for apply, write) the resource group, storage account, and
# container resources themselves.
#
# Deliberately two different roles, two different identities:
#   - plan (PR-triggered): "Reader" — no ARM write actions at all.
#   - apply (manual workflow_dispatch from main only): "Contributor",
#     scoped to just this resource group. Built-in Contributor explicitly
#     excludes Microsoft.Authorization/*/write and /delete, so it cannot
#     create or modify role assignments. That's an Azure-enforced
#     boundary, not a convention: even if the workflow's -target flags
#     were dropped, this identity cannot change who has access.
#
# Both also need the blob data role above to read/write this repo's own
# state — added as one `consumers` project with state_key
# "terraform-state-backend.tfstate" (backend.tf) and both CI object IDs.
# This file is applied locally by a human, never by CI.

resource "azurerm_role_assignment" "ci_plan_reader" {
  count = var.ci_plan_principal_object_id != null ? 1 : 0

  scope                = azurerm_resource_group.state.id
  role_definition_name = "Reader"
  principal_id         = var.ci_plan_principal_object_id
}

resource "azurerm_role_assignment" "ci_apply_contributor" {
  count = var.ci_apply_principal_object_id != null ? 1 : 0

  scope                = azurerm_resource_group.state.id
  role_definition_name = "Contributor"
  principal_id         = var.ci_apply_principal_object_id
}
