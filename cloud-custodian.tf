# SQS Queue to send Emails
resource "aws_sqs_queue" "mailer" {
  name                      = "aikyam-cloud-custodian-mailer-queue"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600 # 14 days (max retention period)
}

resource "aws_sqs_queue_policy" "mailer" {
  queue_url = aws_sqs_queue.mailer.id
  policy    = data.aws_iam_policy_document.mailer.json
}

data "aws_iam_policy_document" "mailer" {
  statement {
    sid    = "AllowOrgAccounts"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "sqs:SendMessage"
    ]

    resources = [
      aws_sqs_queue.mailer.arn
    ]
  }
}

resource "aws_ses_email_identity" "cloudadmin" {
  email = "srinivasula.yallala@optum.com"
}

resource "aws_s3_bucket" "logs" {
  bucket = "aikyam-s3-cloud-custodian-logs"
}

# Security - Object Ownership (ACLs disabled by default for better security)
resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Note: Public Access Block settings are managed at the organizational level
# via Service Control Policy (SCP), so this resource is not needed

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket_policy.json
}

data "aws_iam_policy_document" "logs_bucket_policy" {
  statement {
    sid    = "AllowCloudCustodianRole"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.c7n.arn
      ]
    }

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*"
    ]
  }

  statement {
    sid    = "AllowSSLRequestsOnly"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*"
    ]
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Maintenance
# keep 90 days worth of logs
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id = "prune"

    filter {}

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    status = "Enabled"
  }
}

resource "aws_iam_role" "c7n" {
  name               = "cloud-custodian"
  path               = "/devops/"
  description        = "Cloud Custodian policy runner"
  assume_role_policy = data.aws_iam_policy_document.c7n-trust.json

  tags = {
    "c7n-exception:iam-admin" = "",
    "c7n-exception:unused"    = ""
  }
}

data "aws_iam_policy_document" "c7n-trust" {
  statement {
    sid = "TrustLambda"

    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com"
      ]
    }

    actions = [
      "sts:AssumeRole"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.c7n.id
  policy_arn = data.aws_iam_policy.admin.arn
}

data "aws_iam_policy" "admin" {
  name = "AdministratorAccess"
}

output "custodian_role" {
  value       = aws_iam_role.c7n.arn
  description = "The Cloud Custodian IAM role ARN."
}
