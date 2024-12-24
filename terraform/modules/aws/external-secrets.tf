# Generate IAM role and policy for external secrets if external secrets user is defined

data "aws_iam_user" "external_secret_user" {
  depends_on = [ data.aws_iam_users.iam_users ]
  count = var.external_secret_user_name != null && contains(data.aws_iam_users.iam_users.names, var.external_secret_user_name) ? 1 : 0
  user_name = var.external_secret_user_name
}

data "aws_iam_policy_document" "external_secrets_assume_role" {
  count = length(data.aws_iam_user.external_secret_user) > 0 ? 1 : 0
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_iam_user.external_secret_user[0].arn]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "external_secrets" {
  count = length(data.aws_iam_user.external_secret_user) > 0 ? 1 : 0
  name               = "external-secrets-${var.tags.project}-${var.tags.environment}"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume_role[0].json
}

data "aws_iam_policy_document" "external_secrets" {
  count = length(data.aws_iam_user.external_secret_user) > 0 ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
      "secretsmanager:ListSecrets"
    ]
    resources = ["arn:aws:secretsmanager:*:*:secret:external-secrets-${var.tags.project}-${var.tags.environment}-*"]
  }
}

resource "aws_iam_policy" "external_secrets" {
  count = length(data.aws_iam_user.external_secret_user) > 0 ? 1 : 0
  name        = "external-secrets-${var.tags.project}-${var.tags.environment}"
  description = "External secrets policy for ${var.tags.project} ${var.tags.environment}"
  policy      = data.aws_iam_policy_document.external_secrets[0].json
}

resource "aws_iam_role_policy_attachment" "external_secrets_attach" {
  count = length(data.aws_iam_user.external_secret_user) > 0 ? 1 : 0
  role       = aws_iam_role.external_secrets[0].name
  policy_arn = aws_iam_policy.external_secrets[0].arn
}
