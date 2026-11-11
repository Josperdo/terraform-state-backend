# outputs.tf
#
# The Terraform equivalent of Bicep's `output` block. These are the exact
# values a consuming repo needs to fill in backend.tf.example.

output "resource_group_name" {
  value       = azurerm_resource_group.state.name
  description = "Name of the resource group holding the Terraform state backend."
}

output "storage_account_name" {
  value       = azurerm_storage_account.state.name
  description = "Name of the storage account holding Terraform state files."
}

output "container_name" {
  value       = azurerm_storage_container.state.name
  description = "Name of the blob container holding Terraform state files."
}

output "consumer_role_assignments" {
  value       = { for object_id, ra in azurerm_role_assignment.consumer : object_id => ra.id }
  description = "Blob data role assignment IDs (admins and key-scoped consumers), keyed by Azure AD object ID. Useful for confirming who currently has access without a separate az query."
}
