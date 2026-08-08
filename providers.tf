# providers.tf
#
# Terraform requires two things before any azurerm_* resource can be used —
# this is the biggest structural difference from Bicep, where "Azure" is
# just the implicit deployment target and none of this exists:
#
#   1. A `terraform {}` block declaring which provider(s) this config needs
#      and which version(s) are acceptable. This is Terraform's dependency
#      declaration — think of it like a package.json "engines" field, but
#      for the plugin that knows how to talk to Azure's API.
#
#   2. A `provider "azurerm" {}` block that actually configures that
#      provider. Bicep never asks for this because `az deployment` already
#      knows it's talking to Azure via your `az login` session. Terraform's
#      provider model is deliberately generic (same mechanism plugs in AWS,
#      GCP, Cloudflare, etc.), so it needs to be told explicitly.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The `features {}` block is required by the azurerm provider even when
# left empty — it's the extension point for provider-specific behavior
# (e.g. how deletes interact with soft-deleted resources). We'll come back
# to this in Phase 3 when the storage account's soft delete setting is
# in play.
provider "azurerm" {
  features {}
}
