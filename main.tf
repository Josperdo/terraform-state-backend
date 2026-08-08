# main.tf
#
# Phase 2: resource group only. Storage account + container are added in
# Phase 3.

resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.location
}
