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

variable "log_analytics_workspace_name" {
  type        = string
  description = "Name of the Log Analytics workspace that receives blob audit logs (audit.tf)."
  default     = "log-tfstate-audit"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{2,61}[A-Za-z0-9]$", var.log_analytics_workspace_name))
    error_message = "log_analytics_workspace_name must be 4-63 characters: letters, numbers, and hyphens, starting and ending with a letter or number."
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

variable "admin_principal_object_ids" {
  type        = list(string)
  description = "Azure AD object IDs granted 'Storage Blob Data Contributor' on the whole state account with NO key condition. Break-glass only (the backend's owner, for disaster recovery of any key) — every other identity belongs in `consumers`."
  default     = []

  validation {
    condition     = alltrue([for id in var.admin_principal_object_ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))])
    error_message = "Each entry in admin_principal_object_ids must be a valid Azure AD object ID (GUID)."
  }
}

variable "consumers" {
  type = map(object({
    state_key  = string
    object_ids = list(string)
  }))
  description = "State consumers (one per consuming project), keyed by a friendly name. Every identity in object_ids gets 'Storage Blob Data Contributor' restricted by an ABAC condition to that project's state_key (plus its workspaces, `<state_key>env:<name>`). A project can have several identities (e.g. CI plan + apply). state_key must exactly match the `key` in the project's backend block."
  default     = {}

  validation {
    condition     = alltrue(flatten([for c in values(var.consumers) : [for id in c.object_ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))]]))
    error_message = "Each consumers[*].object_ids entry must be a valid Azure AD object ID (GUID)."
  }

  # Keys are interpolated into the ABAC condition string, so the character
  # set is deliberately narrow: no quotes, no ':' (reserved for the
  # workspace suffix), no leading '/' (ABAC paths exclude it).
  validation {
    condition     = alltrue([for c in values(var.consumers) : can(regex("^[A-Za-z0-9._-][A-Za-z0-9._/-]{0,254}$", c.state_key))])
    error_message = "Each consumers[*].state_key must be 1-255 characters of letters, digits, '.', '_', '-', '/', and must not start with '/'."
  }

  # A role assignment carries one condition, so one identity = one key.
  validation {
    condition     = length(distinct(flatten([for c in values(var.consumers) : [for id in c.object_ids : lower(id)]]))) == length(flatten([for c in values(var.consumers) : c.object_ids]))
    error_message = "Each identity can appear in consumers only once (one identity, one state key)."
  }

  validation {
    condition     = length(distinct([for c in values(var.consumers) : c.state_key])) == length(var.consumers)
    error_message = "Each consumers[*].state_key must be unique — two projects sharing a key would share (and clobber) the same state. Put both identities in one project's object_ids instead."
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
