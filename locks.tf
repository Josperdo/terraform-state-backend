# locks.tf
#
# A CanNotDelete management lock on the resource group. Locks are
# inherited, so this also covers the storage account and container.
#
# Why both this and prevent_destroy (main.tf): prevent_destroy only stops
# *this* Terraform config. The lock is enforced by Azure Resource Manager
# itself, so it also blocks the portal, the CLI, the raw ARM API, and any
# other Terraform config. Deleting anything here first requires someone
# with lock permissions to remove the lock on purpose.
#
# CanNotDelete, not ReadOnly: updates are still allowed, so CI can keep
# applying setting changes. Blob reads and writes are data-plane
# operations and aren't affected by locks at all, so consumers can still
# write and delete their own state blobs.
#
# Applied locally only, like rbac.tf. Managing locks needs
# Microsoft.Authorization/locks/*, which the CI apply identity's built-in
# Contributor role doesn't include, and the CI workflow's -target scope
# leaves this resource out.

resource "azurerm_management_lock" "state" {
  name       = "do-not-delete-tfstate"
  scope      = azurerm_resource_group.state.id
  lock_level = "CanNotDelete"
  notes      = "Holds Terraform state for every consuming project. To delete anything here on purpose, follow docs/disaster-recovery.md."
}
