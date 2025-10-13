resource "aws_s3_bucket" "logs" {
  for_each = toset(terraform.workspace == "shared-us-west-2" ? [terraform.workspace] : [])

  bucket = "gs-s3-cloud-custodian-logs"
}

# Security
resource "aws_s3_bucket_acl" "logs" {
  for_each = toset(terraform.workspace == "shared-us-west-2" ? [terraform.workspace] : [])

  bucket = aws_s3_bucket.logs[terraform.workspace].id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "logs" {
  for_each = toset(terraform.workspace == "shared-us-west-2" ? [terraform.workspace] : [])

  bucket = aws_s3_bucket.logs[terraform.workspace].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "logs" {
  for_each = toset(terraform.workspace == "shared-us-west-2" ? [terraform.workspace] : [])

  bucket = aws_s3_bucket.logs[terraform.workspace].id
  policy = data.aws_iam_policy_document.logs_bucket_policy[terraform.workspace].json
}

data "aws_iam_policy_document" "logs_bucket_policy" {
  for_each = toset(terraform.workspace == "shared-us-west-2" ? [terraform.workspace] : [])

  statement {
    sid = "AllowOrgAccounts"

    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::472908028927:role/devops/cloud-custodian", # root
        "arn:aws:iam::140253569749:role/devops/cloud-custodian", # shared
        "arn:aws:iam::793362518373:role/devops/cloud-custodian", # development
        "arn:aws:iam::301712053745:role/devops/cloud-custodian", # staging
        "arn:aws:iam::101300729637:role/devops/cloud-custodian", # production
        "arn:aws:iam::605289256863:role/devops/cloud-custodian", # audit
        "arn:aws:iam::957617154769:role/devops/cloud-custodian", # log
      ]
    }

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]

    resources = [
      aws_s3_bucket.logs[terraform.workspace].arn,
      "${aws_s3_bucket.logs[terraform.workspace].arn}/*",
    ]
  }

  statement {
    sid    = "AllowSSLRequestsOnly"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.logs[terraform.workspace].arn,
      "${aws_s3_bucket.logs[terraform.workspace].arn}/*",
    ]
  }

  statement {
    sid    = "AllowMinimumTLS12Only"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.logs[terraform.workspace].arn,
      "${aws_s3_bucket.logs[terraform.workspace].arn}/*",
    ]
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  for_each = toset(terraform.workspace == "shared-us-west-2" ? [terraform.workspace] : [])

  bucket = aws_s3_bucket.logs[terraform.workspace].bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Maintenance
# keep 90 days worth of logs
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  for_each = toset(terraform.workspace == "shared-us-west-2" ? [terraform.workspace] : [])

  bucket = aws_s3_bucket.logs[terraform.workspace].id

  rule {
    id = "prune"

    filter {}

    expiration {
      days = 90
    }

    status = "Enabled"
  }
}
