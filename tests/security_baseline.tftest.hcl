# tests/security_baseline.tftest.hcl
#
# Guards the settings this backend's security model depends on. Uses a
# mocked azurerm provider, so it runs offline in CI with no Azure
# credentials — it asserts on what the configuration *declares*, not on
# live Azure state (that's what `plan` in CI is for).
#
# Run locally:  terraform init -backend=false && terraform test

mock_provider "azurerm" {}

variables {
  resource_group_name  = "rg-tfstate-test"
  storage_account_name = "sttfstatetest001"
}

run "storage_account_is_locked_down" {
  command = plan

  assert {
    condition     = azurerm_storage_account.state.shared_access_key_enabled == false
    error_message = "Shared key access must stay disabled — Azure AD RBAC is the only supported auth path."
  }

  assert {
    condition     = azurerm_storage_account.state.default_to_oauth_authentication == true
    error_message = "Storage account must default to OAuth (Azure AD) authentication."
  }

  assert {
    condition     = azurerm_storage_account.state.allow_nested_items_to_be_public == false
    error_message = "Public blob access must stay disabled at the account level."
  }

  assert {
    condition     = azurerm_storage_account.state.min_tls_version == "TLS1_2"
    error_message = "Minimum TLS version must be TLS1_2."
  }

  assert {
    condition     = azurerm_storage_account.state.https_traffic_only_enabled == true
    error_message = "HTTPS-only traffic must stay enabled."
  }
}

run "state_is_recoverable" {
  command = plan

  assert {
    condition     = azurerm_storage_account.state.blob_properties[0].versioning_enabled == true
    error_message = "Blob versioning must stay enabled — it's the recovery path for a bad apply."
  }

  assert {
    condition     = azurerm_storage_account.state.blob_properties[0].delete_retention_policy[0].days >= 7
    error_message = "Blob soft delete retention must be at least 7 days."
  }

  assert {
    condition     = azurerm_storage_account.state.blob_properties[0].container_delete_retention_policy[0].days >= 7
    error_message = "Container soft delete retention must be at least 7 days."
  }

  assert {
    condition     = startswith(azurerm_storage_account.state.account_replication_type, "RAGRS") || azurerm_storage_account.state.account_replication_type == "GRS" || endswith(azurerm_storage_account.state.account_replication_type, "GZRS")
    error_message = "State storage must be geo-redundant."
  }
}

run "container_is_private" {
  command = plan

  assert {
    condition     = azurerm_storage_container.state.container_access_type == "private"
    error_message = "The state container must be private."
  }
}

run "no_rbac_without_inputs" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.consumer) == 0 && length(azurerm_role_assignment.ci_plan_reader) == 0 && length(azurerm_role_assignment.ci_apply_contributor) == 0
    error_message = "No role assignments should be created unless principals are explicitly provided."
  }
}

run "rejects_invalid_storage_account_name" {
  command = plan

  variables {
    storage_account_name = "Invalid_Name!"
  }

  expect_failures = [var.storage_account_name]
}

run "rejects_invalid_principal_id" {
  command = plan

  variables {
    consumer_principal_object_ids = ["not-a-guid"]
  }

  expect_failures = [var.consumer_principal_object_ids]
}
