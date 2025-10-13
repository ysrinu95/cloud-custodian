output "custodian_role" {
  value       = aws_iam_role.c7n.arn
  description = "The Cloud Custodian IAM role ARN."
}

output "mailer_queue" {
  value       = { for k, v in aws_sqs_queue.mailer : "url" => v.url }
  description = "The Cloud Custodian SQS mailer queue URL."
}
