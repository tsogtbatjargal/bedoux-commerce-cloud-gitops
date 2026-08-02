locals {
  oidc_issuer_host = trimprefix(var.oidc_issuer_url, "https://")
  image_files      = fileset(var.image_source_directory, "*.svg")
}

# This bucket is deliberately session-scoped, not part of the persistent
# allowlist. force_destroy is safe here because every object is synthetic,
# version-controlled catalog artwork staged by the resources below.
resource "aws_s3_bucket" "this" {
  bucket_prefix = var.bucket_prefix
  force_destroy = true

  tags = merge(var.tags, {
    Name = "bedoux-product-images"
  })
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "product_image" {
  for_each = local.image_files

  bucket       = aws_s3_bucket.this.id
  key          = "products/${each.value}"
  source       = "${var.image_source_directory}/${each.value}"
  etag         = filemd5("${var.image_source_directory}/${each.value}")
  content_type = "image/svg+xml"
}

data "aws_iam_policy_document" "api_assume_role" {
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
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }
  }
}

resource "aws_iam_role" "api" {
  name               = "bedoux-product-images-role"
  assume_role_policy = data.aws_iam_policy_document.api_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "api_image_read" {
  statement {
    sid       = "ReadSyntheticProductImages"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/products/*"]
  }
}

resource "aws_iam_policy" "api_image_read" {
  name   = "bedoux-product-images-read-policy"
  policy = data.aws_iam_policy_document.api_image_read.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "api_image_read" {
  role       = aws_iam_role.api.name
  policy_arn = aws_iam_policy.api_image_read.arn
}
