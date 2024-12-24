variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "iam_users" {
  description = "An object that contains all the IAM users that should be created in the project"
  type        = any
  default     = []
}

variable "external_secret_user_name" {
  description = "The name of the external secrets user"
  type        = string
  default     = null
}

# variable "create_external_secrets_role" {
#   description = "A boolean value to determine if the external secrets role should be created"
#   type        = bool
#   default     = true
# }

variable "pgp_key" {
  description = "value of the PGP key to encrypt the sensitive values with format keybase:username"
}
