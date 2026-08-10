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
