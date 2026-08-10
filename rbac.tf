# rbac.tf
#
# Grants each listed identity the minimum role needed to use this backend
# as a Terraform state store: read/write blobs in this storage account,
# nothing else. Owner/Contributor on the storage account does NOT include
# this — Azure RBAC treats control-plane management (create/delete the
# account itself) and data-plane access (read/write the blobs inside it)
# as separate layers, even for the account's own owner. This role is what
# actually makes `use_azuread_auth = true` in backend.tf.example work,
# in place of a storage account access key.
#
# To add a new consumer (a person or a CI service principal): add their
# Azure AD object ID to consumer_principal_object_ids in terraform.tfvars
# and re-apply. To remove access, delete the entry and re-apply — no
# manual `az role assignment` commands needed either way.

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
# read (and, for apply, write) the actual azurerm_resource_group /
# azurerm_storage_account / azurerm_storage_container resources themselves.
#
# Deliberately two different roles, two different identities:
#   - plan (PR-triggered): "Reader" only — can never change anything, even
#     if the OIDC trust or workflow file were somehow compromised.
#   - apply (main-branch-only, behind a required-reviewer environment):
#     "Contributor", scoped to just this resource group. Built-in
#     Contributor explicitly excludes Microsoft.Authorization/*/write and
#     /delete — it cannot create or modify role assignments. That's not a
#     convention CI has to honor, it's an Azure-enforced boundary: even if
#     `-target` flags were ever dropped from the apply command, this
#     identity is structurally unable to touch rbac.tf's resources.
#
# Both also need the blob data role above to read/write this repo's own
# state — added via consumer_principal_object_ids in terraform.tfvars,
# same mechanism as any other consumer.

variable "ci_plan_principal_object_id" {
  type        = string
  description = "Azure AD object ID of the CI 'plan' service principal (PR-triggered, read-only). Null skips this assignment."
  default     = null
}

variable "ci_apply_principal_object_id" {
  type        = string
  description = "Azure AD object ID of the CI 'apply' service principal (main-branch-only, behind a manual-approval environment). Null skips this assignment."
  default     = null
}

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
