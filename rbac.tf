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
# To add a consumer (a person or a CI service principal): add their Azure
# AD object ID to consumer_principal_object_ids in terraform.tfvars and
# re-apply. To remove access, delete the entry and re-apply.
#
# Known gap: this grants access to the whole storage account, i.e. every
# consumer's state blob, not just its own key. See README "Known
# limitations".

resource "azurerm_role_assignment" "consumer" {
  for_each = toset(var.consumer_principal_object_ids)

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
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
# state — added via consumer_principal_object_ids, same as any consumer.
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
