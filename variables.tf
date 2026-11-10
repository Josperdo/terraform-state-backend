# variables.tf
#
# Input variables — the Terraform equivalent of Bicep's `param` block, but
# each declared as its own top-level `variable "name" {}` block instead of
# a single params section.

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group holding the Terraform state backend."

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,89}[a-zA-Z0-9_()-]$", var.resource_group_name))
    error_message = "resource_group_name must be 1-90 characters (letters, digits, '.', '_', '-', '(', ')') and must not end with a period."
  }
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

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9]|-[a-z0-9]){2,62}$", var.container_name))
    error_message = "container_name must be 3-63 characters: lowercase letters, numbers, and single hyphens, starting and ending with a letter or number."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource this repo creates."
  default = {
    managed_by = "terraform"
    purpose    = "terraform-remote-state"
  }
}

# --- Access (consumed by rbac.tf) --------------------------------------

variable "consumer_principal_object_ids" {
  type        = list(string)
  description = "Azure AD object IDs (users or service principals) granted 'Storage Blob Data Contributor' on the state storage account. Add one entry per person or CI identity that needs to read/write Terraform state here."
  default     = []

  validation {
    condition     = alltrue([for id in var.consumer_principal_object_ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))])
    error_message = "Each entry in consumer_principal_object_ids must be a valid Azure AD object ID (GUID)."
  }
}

variable "ci_plan_principal_object_id" {
  type        = string
  description = "Azure AD object ID of the CI 'plan' service principal (PR-triggered, Reader on the resource group). Null skips this assignment."
  default     = null

  validation {
    condition     = var.ci_plan_principal_object_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.ci_plan_principal_object_id))
    error_message = "ci_plan_principal_object_id must be null or a valid Azure AD object ID (GUID)."
  }
}

variable "ci_apply_principal_object_id" {
  type        = string
  description = "Azure AD object ID of the CI 'apply' service principal (manual workflow_dispatch only, Contributor on the resource group). Null skips this assignment."
  default     = null

  validation {
    condition     = var.ci_apply_principal_object_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.ci_apply_principal_object_id))
    error_message = "ci_apply_principal_object_id must be null or a valid Azure AD object ID (GUID)."
  }
}
