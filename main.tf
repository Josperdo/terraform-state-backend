# main.tf
#
# Every resource here carries `prevent_destroy`: this storage account holds
# state for *every* consuming project, so an accidental `terraform destroy`
# (or a refactor that renames a resource address) would be catastrophic.
# Terraform refuses to plan a destroy of these resources at all — removing
# that guard has to be a deliberate, reviewed code change first.

resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_account" "state" {
  # Deliberate checkov exceptions — each is a trade-off, not an oversight:
  #checkov:skip=CKV_AZURE_59:Public network endpoint is required for GitHub-hosted runners (dynamic IPs). Access is still Azure AD RBAC-only with shared keys disabled. See README "Known limitations".
  #checkov:skip=CKV2_AZURE_33:Private endpoint needs self-hosted runners in a VNet — out of scope for this backend. See README "Known limitations".
  #checkov:skip=CKV2_AZURE_1:Data is encrypted at rest with Microsoft-managed keys; customer-managed keys add a Key Vault dependency with no threat-model benefit at this scale.
  #checkov:skip=CKV_AZURE_33:Queue service is unused — this account only stores blobs.

  name                = var.storage_account_name
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = var.tags

  account_tier = "Standard"
  # Geo-redundant with a readable secondary region. State files are tiny
  # (kilobytes), so the cost over LRS is negligible — real protection
  # against a full regional outage for close to free.
  account_replication_type   = "RAGRS"
  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true # provider default, stated explicitly so tests/ can assert on it

  # Disables storage account access keys (and SAS tokens signed with them)
  # entirely. Every consumer already uses Azure AD auth
  # (use_azuread_auth = true), but that's a client-side choice — while
  # keys stay enabled, anyone holding Contributor on this account (which
  # includes listKeys) can bypass RBAC and read or write every project's
  # state. Turning keys off makes Azure AD RBAC the only way in.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

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

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "state" {
  #checkov:skip=CKV2_AZURE_21:Blob reads ARE logged — via a diagnostic setting on the blob service (audit.tf). This check only recognizes the legacy azurerm_log_analytics_storage_insights resource, which needs a storage account key; keys are disabled on this account.

  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}
