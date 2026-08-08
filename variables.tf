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

variable "storage_account_name" {
  type        = string
  description = "Globally-unique storage account name (Azure requirement — must be unique across all of Azure, not just this subscription)."

  # Terraform's `validation` block is the equivalent of Bicep's
  # @minLength/@maxLength decorators, but expressed as an arbitrary
  # condition + custom error message rather than fixed decorators.
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 characters, lowercase letters and numbers only (Azure storage account naming rules)."
  }
}

variable "container_name" {
  type        = string
  description = "Name of the blob container that holds Terraform state files."
  default     = "tfstate"
}
