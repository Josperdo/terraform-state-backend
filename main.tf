# main.tf

resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "state" {
  name                = var.storage_account_name
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_tier = "Standard"
  # Geo-redundant + readable secondary region. State files here are tiny
  # (kilobytes), so the cost delta over LRS is negligible — this is
  # meaningful protection against a full East US regional outage for
  # close to free. Was LRS through Phase 3; upgraded once the backend
  # was actually in daily use (see ROADMAP.md "Open items").
  account_replication_type = "RAGRS"
  min_tls_version          = "TLS1_2"

  # Blocks anonymous/public read access to blobs in this account, full
  # stop — independent of any per-container access-type setting below.
  # State files must never be publicly readable.
  allow_nested_items_to_be_public = false

  blob_properties {
    # Keeps prior blob versions on every overwrite. If state gets
    # corrupted by a bad apply, you restore the previous version instead
    # of losing it outright.
    versioning_enabled = true

    # Soft delete: a deleted blob is recoverable for N days instead of
    # being gone immediately. Covers accidental `terraform state rm` /
    # container deletion, not just bad overwrites.
    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
}

resource "azurerm_storage_container" "state" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}
