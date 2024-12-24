output "iam_users" {
  value = tomap({
    for user in module.iam_users : user.iam_user_name => {
      id                = user.iam_user_unique_id
      arn               = user.iam_user_arn
      access_key        = user.iam_access_key_id
      policy_arns       = user.policy_arns
    }
  })
  description = "users"
}

output "iam_users_secret_access_key" {
  sensitive = true
  value = tomap({
    for user in module.iam_users : user.iam_user_name => {
      secret_access_key = user.keybase_secret_key_pgp_message
    }
  })
  description = "users secret access key"
}

output "external_secret_role" {
  value = try(resource.aws_iam_role.external_secrets[0].arn, null)
  description = "external secret role"
}
