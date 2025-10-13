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

  statement {
    sid = "TrustBitbucket"

    effect = "Allow"

    principals {
      type = "Federated"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${var.bitbucket_provider}"
      ]
    }

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    condition {
      test     = "StringLike"
      variable = "${var.bitbucket_provider}:sub"
      values = [
        "{bbf669a5-3875-4e8e-90b5-d480f855bac0}:*" # cloud-custodian repo
      ]
    }
  }
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.c7n.id
  policy_arn = data.aws_iam_policy.admin.arn
}

data "aws_iam_policy" "admin" {
  name = "AdministratorAccess"
}
