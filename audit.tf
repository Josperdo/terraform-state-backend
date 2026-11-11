# audit.tf
#
# Blob audit logging: every read, write, and delete against the state
# container lands in a Log Analytics workspace, with the caller's Azure AD
# object ID. Answers "who read this project's state, and when?" — state
# files can hold secrets, and before this nothing recorded reads at all.
# It also fills a gap in lock info: its `Who` field is the local OS
# user@machine, not the Azure identity; the logs record the real caller.
#
# The diagnostic setting targets the *blob service*
# (<account id>/blobServices/default), not the storage account. The
# account-level setting only carries metrics — blob reads are only logged
# at the service level.
#
# Applied locally only, like rbac.tf and locks.tf: the CI apply identity is
# one of the principals being audited, so the pipeline shouldn't be the
# thing that manages its own audit trail. The CI workflow's -target scope
# leaves these resources out. The resource group's CanNotDelete lock
# (locks.tf) covers the workspace too.

resource "azurerm_log_analytics_workspace" "audit" {
  name                = var.log_analytics_workspace_name
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = var.tags

  sku = "PerGB2018"
  # Matches the 30-day soft delete window, and stays inside the retention
  # Log Analytics includes at no extra charge.
  retention_in_days = 30

  # Same rule as the storage account: no shared keys. Ingestion and queries
  # go through Azure AD only.
  local_authentication_enabled = false
}

resource "azurerm_monitor_diagnostic_setting" "blob_audit" {
  name                       = "blob-audit-to-log-analytics"
  target_resource_id         = "${azurerm_storage_account.state.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.audit.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}
