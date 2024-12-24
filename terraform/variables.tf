variable "workspace" {
  description = "The name of the workspace, this would ensure that the resources are created in the correct environment. It has to match the current selected terraform workspace"
  validation {
    condition     = var.workspace == terraform.workspace
    error_message = "[Error] You are trying to deploy '${var.workspace}' config while using '${terraform.workspace}' terraform workspace.\nPlease switch terraform workspace or variables config file.\nterraform workspace select ${var.workspace}"
  }
}

variable "pgp_key" {
  description = "value of the PGP key to encrypt the sensitive valueswit format keybase:username"
}

variable "iam_users_file" {
  default = "iam_users.json"
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

locals {
  # Ensure to at least have project and environment as tags
  tags = merge({
    project = "project"
    environment = terraform.workspace
  }, var.tags)

  iam_users_json = jsondecode(file(var.iam_users_file))

  db_users = lookup(local.iam_users_json, "users", [])
}
