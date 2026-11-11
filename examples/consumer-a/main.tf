# Minimal consuming project: the smallest config that keeps its state in
# this backend. Copy the terraform {} block into a real project, change
# `key`, and get that key granted via `consumers` in this repo's tfvars.
#
# Deploys nothing to Azure: terraform_data is a built-in resource that only
# exists in state. consumer-a and consumer-b were used to prove per-key
# isolation (each denied on the other's key) — see README "What's been
# verified".
#
# Init (PowerShell: quote each whole flag):
#   terraform init "-backend-config=storage_account_name=<name>" "-backend-config=container_name=<container>"

terraform {
  required_version = ">= 1.7.0"

  backend "azurerm" {
    key              = "consumer-a.tfstate"
    use_azuread_auth = true
    # storage_account_name + container_name are supplied at init time
    # (-backend-config), same partial-config pattern as this repo's backend.tf.
  }
}

resource "terraform_data" "marker" {
  input = "consumer-a"
}
