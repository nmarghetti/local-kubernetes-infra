# https://github.com/terraform-aws-modules/terraform-aws-iam/tree/v5.48.0/modules/iam-user
# https://github.com/terraform-aws-modules/terraform-aws-iam/tree/v5.48.0/examples/iam-user
module "iam_users" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"
  version = "5.48.0"

  for_each                      = { for user in var.iam_users : user.name => user }
  tags                          = var.tags
  name                          = each.value.name
  create_iam_access_key         = each.value.create_iam_access_key
  create_iam_user_login_profile = each.value.create_iam_user_login_profile
  create_user                   = true
  pgp_key                       = var.pgp_key
}

data "aws_iam_users" "iam_users" {
  depends_on = [ module.iam_users ]
}

# module "external_secrets_role" {
#   source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
#   version = "5.48.0"

#   count = var.create_external_secrets_role ? 1 : 0

#   tags = var.tags

#   role_name                                          = "external-secrets-${var.tags.project}-${var.tags.environment}"
#   create_role                                        = true
#   attach_external_secrets_policy                     = true
#   external_secrets_secrets_manager_create_permission = true
#   external_secrets_ssm_parameter_arns                = ["arn:aws:ssm:*:*:none"]
#   external_secrets_secrets_manager_arns              = ["arn:aws:secretsmanager:*:*:secret:external-secrets-${var.tags.project}-${var.tags.environment}-*"]
#   external_secrets_kms_key_arns                      = ["arn:aws:kms:*:*:none"]

# }

