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

variable "consumer_principal_object_ids" {
  type        = list(string)
  description = "Azure AD object IDs (users or service principals) granted 'Storage Blob Data Contributor' on the state storage account — least privilege, scoped to just this storage account, not the resource group or subscription. Add one entry per person or CI identity that needs to read/write Terraform state here."
  default     = []

  validation {
    condition     = alltrue([for id in var.consumer_principal_object_ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))])
    error_message = "Each entry in consumer_principal_object_ids must be a valid Azure AD object ID (GUID)."
  }
}
