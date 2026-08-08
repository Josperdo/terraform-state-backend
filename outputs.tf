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
