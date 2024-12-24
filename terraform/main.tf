module "aws" {
  source = "./modules/aws"
  providers = {
    aws = aws
  }

  tags = var.tags
  iam_users = local.db_users
  pgp_key = var.pgp_key
  external_secret_user_name = "${var.tags.project}_SecretManager"
}

# moved {
#   from = module.mongodb_atlas.mongodbatlas_custom_db_role.travelto-test-limited-collections
#   to = module.mongodb_atlas.mongodbatlas_custom_db_role.custom_db_role
# }

# output "roles" {
#   value = local.jsonroles
# }

output "users" {
  value = [ for user in module.aws.iam_users: user.arn ]
}

output "users_secret_access" {
  value = module.aws.iam_users_secret_access_key
  sensitive = true
}

output "external_secret_role" {
  value = module.aws.external_secret_role
}

output "tags" {
  value = local.tags
}
