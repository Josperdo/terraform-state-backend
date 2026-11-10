# backend.tf
#
# This repo stores its own state remotely too, in a dedicated key inside
# the storage account it provisions. (The very first deploy has to run
# with local state, since the backend doesn't exist yet — see README
# "Deploying this backend".)
#
# Deliberately a PARTIAL backend config: resource_group_name,
# storage_account_name, and container_name are supplied at `terraform
# init` time rather than committed here:
#   - Locally: copy backend-config.hcl.example -> backend-config.hcl
#     (gitignored), fill in real values, then:
#       terraform init -backend-config=backend-config.hcl
#   - In CI: via -backend-config flags, with the storage account name
#     coming from a GitHub repo Variable (see
#     .github/workflows/terraform-ci.yml).
#
# `key` and `use_azuread_auth` are fixed for this repo, so they're
# committed directly.

terraform {
  backend "azurerm" {
    key              = "terraform-state-backend.tfstate"
    use_azuread_auth = true
  }
}
