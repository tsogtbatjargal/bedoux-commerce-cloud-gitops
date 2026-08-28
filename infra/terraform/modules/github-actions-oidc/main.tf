locals {
  oidc_issuer_host = trimprefix(var.oidc_issuer_url, "https://")
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "this" {
  url            = var.oidc_issuer_url
  client_id_list = ["sts.amazonaws.com"]
  tags           = var.tags
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = [var.github_oidc_subject]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "bedoux-github-actions-role"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = 3600
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

data "aws_iam_policy_document" "deployment" {
  statement {
    sid       = "GetEcrAuthorizationToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushBedouxImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = var.ecr_repository_arns
  }

  statement {
    sid       = "DescribeLearningCluster"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"]
  }

  statement {
    sid = "VerifyCanaryAlbReconciliation"
    actions = [
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetHealth",
    ]
    # ELBv2 Describe APIs do not support resource-level permissions. These are
    # read-only and are used only after Kubernetes maps the two named Services
    # to their controller-owned target-group ARNs.
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deployment" {
  name   = "bedoux-github-actions-policy"
  policy = data.aws_iam_policy_document.deployment.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "deployment" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.deployment.arn
}
