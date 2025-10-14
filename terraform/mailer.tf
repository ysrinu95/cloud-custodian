# SQS Queue for Cloud Custodian mailer (enterprise feature)
resource "aws_sqs_queue" "custodian_mailer" {
  count = var.enable_enterprise_features ? 1 : 0

  name                      = "custodian-mailer-queue"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600 # 14 days (max retention period)
}

# SQS Queue policy for multi-account access (enterprise feature)
resource "aws_sqs_queue_policy" "custodian_mailer" {
  count = var.enable_enterprise_features ? 1 : 0

  queue_url = aws_sqs_queue.custodian_mailer[0].id
  policy    = data.aws_iam_policy_document.mailer_queue_policy[0].json
}

data "aws_iam_policy_document" "mailer_queue_policy" {
  count = var.enable_enterprise_features ? 1 : 0

  policy_id = "custodian-mailer-policy"

  statement {
    sid    = "AllowCloudCustodianSendMessage"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.custodian_execution.arn,
        aws_iam_role.custodian_lambda_execution.arn
      ]
    }

    actions = [
      "sqs:SendMessage"
    ]

    resources = [
      aws_sqs_queue.custodian_mailer[0].arn
    ]
  }
}

# SES Email Identity for notifications (enterprise feature)
resource "aws_ses_email_identity" "custodian_notifications" {
  count = var.enable_enterprise_features && var.notification_email != null ? 1 : 0

  email = var.notification_email
}

# Output for mailer queue URL
output "custodian_mailer_queue_url" {
  description = "SQS queue URL for Cloud Custodian mailer (enterprise feature)"
  value       = var.enable_enterprise_features ? aws_sqs_queue.custodian_mailer[0].url : null
}

# Output for SES email identity
output "custodian_notification_email" {
  description = "SES email identity for Cloud Custodian notifications"
  value       = var.enable_enterprise_features && var.notification_email != null ? aws_ses_email_identity.custodian_notifications[0].email : null
}