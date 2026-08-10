# backend.tf
#
# This repo now manages its own state remotely too — in a dedicated key
# inside the very storage account it provisions. Previously this repo's
# own state stayed local because it couldn't depend on a backend that
# didn't exist yet; now that the backend is deployed and proven working
# (Phases 4/5), that bootstrap step is done.
#
# Deliberately a PARTIAL backend config: resource_group_name,
# storage_account_name, and container_name are NOT hardcoded here, per
# this project's own rule against committing real resource/network
# identifiers into tracked files. They're supplied at `terraform init`
# time instead:
#   - Locally: copy backend-config.hcl.example -> backend-config.hcl
#     (gitignored, same pattern as terraform.tfvars), fill in real
#     values from `terraform output`, then:
#       terraform init -backend-config=backend-config.hcl
#   - In CI: via -backend-config flags — resource_group_name/
#     container_name are stable enough to live directly in the workflow,
#     storage_account_name comes from a GitHub repo Variable (non-secret,
#     same treatment as this repo's AZURE_SUBSCRIPTION_ID — see
#     .github/workflows/terraform-ci.yml)
#
# `key` and `use_azuread_auth` aren't real-identifier concerns (a
# filename this repo chose, and a fixed auth-mode flag), so they're safe
# to commit directly.

terraform {
  backend "azurerm" {
    key              = "terraform-state-backend.tfstate"
    use_azuread_auth = true
  }
}
