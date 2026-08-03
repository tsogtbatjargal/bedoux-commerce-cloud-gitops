locals {
  oidc_issuer_host = trimprefix(var.oidc_issuer_url, "https://")
}

resource "aws_secretsmanager_secret" "this" {
  name                    = var.secret_name
  description             = "Short-lived Bedoux learning-session database credential"
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name = var.secret_name
  })
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = var.secret_string
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"]
    }
  }
}

data "aws_iam_policy_document" "read_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.this.arn]
  }
}

resource "aws_iam_policy" "read_secret" {
  name        = var.policy_name
  description = "Read only the Bedoux learning-session database secret"
  policy      = data.aws_iam_policy_document.read_secret.json
  tags        = var.tags
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "read_secret" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.read_secret.arn
}
