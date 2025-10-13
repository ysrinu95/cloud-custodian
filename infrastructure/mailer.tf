resource "aws_sqs_queue" "mailer" {
  for_each = toset(terraform.workspace == "shared-us-west-2" ? [terraform.workspace] : [])

  name                      = "custodian-mailer-queue"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600 # 14 days (max retention period)
}

resource "aws_sqs_queue_policy" "mailer" {
  for_each = toset(terraform.workspace == "shared-us-west-2" ? [terraform.workspace] : [])

  queue_url = aws_sqs_queue.mailer[terraform.workspace].id
  policy    = data.aws_iam_policy_document.mailer[terraform.workspace].json
}

data "aws_iam_policy_document" "mailer" {
  for_each = toset(terraform.workspace == "shared-us-west-2" ? [terraform.workspace] : [])

  policy_id = "mailer"

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
      "sqs:SendMessage"
    ]

    resources = [
      "${aws_sqs_queue.mailer[terraform.workspace].arn}"
    ]
  }
}

resource "aws_ses_email_identity" "cloudadmin" {
  for_each = toset(terraform.workspace == "shared-us-west-2" ? [terraform.workspace] : [])

  email = "CloudAdmin@greenstreet.com"
}
