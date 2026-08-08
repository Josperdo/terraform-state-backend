# variables.tf
#
# Input variables — the Terraform equivalent of Bicep's `param` block, but
# each declared as its own top-level `variable "name" {}` block instead of
# a single params section.

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group holding the Terraform state backend."
}

variable "location" {
  type        = string
  description = "Azure region for the state backend resources."
  default     = "eastus"
}

# Added in Phase 3:
#   - storage_account_name
#   - container_name
