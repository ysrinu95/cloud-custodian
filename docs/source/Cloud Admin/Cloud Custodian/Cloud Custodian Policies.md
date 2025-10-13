## Policies

File | Name | Description | Mode | Actions | Exceptions
--- | --- | --- | --- | --- | ---
account.yml | aws-account-root-user-login-detected | Notifies of any AWS root user console logins | cloudtrail | notify - Slack | N/A
account.yml | aws-phd-health-event-issue | Notifies of Personal Health Dashboard issues | periodic | notify - Slack | N/A
account.yml | aws-phd-health-event-scheduled-change | Notifies of Personal Health Dashboard scheduled changes | periodic | notify - Slack | N/A
account.yml | aws-phd-health-event-account-notification | Notifies of Personal Health Dashboard account notifications | periodic | notify - Slack | N/A
ec2.yml | aws-ec2-public-ips | Notifies of instances found with a public IP address | periodic | notify - Slack | N/A
ec2.yml | aws-security-group-unsafe-ports | Notifies of and remediates security group creation with unrestricted access over unsafe ports | cloudtrail | remove-permissions <br /> notify - Email | N/A
ecs.yml | aws-ecs-long-running-airflow-tasks | Notifies of and stops Airflow ECS tasks that have been running for more than 14 hours | periodic | stop task <br /> notify - Slack | resources tagged with `c7n-exception:long-running`
ecs.yml | aws-ecs-service-deployment-failures | Notifies of and stops ECS service deployments with more than 10 failed attempts | periodic | update desiredCount to 0 <br /> suspend scaling <br /> notify - Email | N/A
ecs.yml | aws-ecs-long-running-data-schema-tasks | Notifies of and stops Data Schema ECS tasks that have been running for more than 1 hour | periodic | stop task <br /> notify - Slack | resources tagged with `c7n-exception:long-running`
guardduty.yml | aws-guarduty-account-new-finding | Notifies of new account findings in GuardDuty | guard-duty | notify - Slack | N/A
guardduty.yml | aws-guarduty-iam-user-new-finding | Notifies of new IAM user findings in GuardDuty | guard-duty | notify - Slack | N/A
guardduty.yml | aws-guarduty-ec2-new-finding | Notifies of new EC2 findings in GuardDuty | guard-duty | notify - Slack | N/A
iam.yml | aws-iam-user-inactive-access-keys | Notifies of and disables IAM access keys found to be unused > 90 days | periodic | disables keys <br /> notify - Email | `data` squad users
iam.yml | aws-iam-policy-allow-all-report | Notifies of IAM policies which allow all permissions | periodic | notify - Email | resources tagged with `c7n-exception:iam-admin`
iam.yml | aws-iam-role-admin-access-report | Notifies of IAM roles with administrator permissions | periodic | notify - Email | resources tagged with `c7n-exception:iam-admin` <br /> AWS SSO `administrator` role
iam.yml | aws-iam-user-admin-access-report | Notifies of IAM users with administrator permissions | periodic | notify - Email | resources tagged with `c7n-exception:iam-admin`
iam.yml | aws-iam-group-admin-access-report | Notifies of IAM groups with administrator permissions | periodic | notify - Email | N/A
iam.yml | aws-iam-policy-allow-all-created | Notifies of IAM policy created which allows all permissions | cloudtrail | notify - Email | resources tagged with `c7n-exception:iam-admin`
iam.yml | aws-iam-role-admin-access-attached | Notifies of administrator policy being attached to IAM role | cloudtrail | notify - Email | resources tagged with `c7n-exception:iam-admin` <br /> AWS SSO `administrator` role <br /> `Mission` roles
iam.yml | aws-iam-user-admin-access-attached | Notifies of administrator policy being attached to IAM user | cloudtrail | notify - Email | resources tagged with `c7n-exception:iam-admin`
iam.yml | aws-iam-group-admin-access-attached | Notifies of administrator policy being attached to IAM group | cloudtrail | notify - Email | N/A
iam.yml | aws-iam-unused-roles-report | Notifies of IAM roles found to be unused | periodic | notify - Email | resources tagged with `c7n-exception:unused`
iam.yml | aws-iam-unused-policies-report | Notifies of IAM policies found to be unused | periodic | notify - Email | resources tagged with `c7n-exception:unused`
iam.yml | aws-iam-new-user-created | Notifies of new IAM user creation | cloudtrail | notify - Slack | N/A
lambda.yml | aws-lambda-deprecated-runtimes | Notifies of Lambda functions using deprecated runtimes | periodic | notify - Email | N/A
lambda.yml | aws-lambda-outdated-runtimes | Notifies of Lambda functions using oudated runtimes that will be deprecated soon | periodic | notify - Email | N/A
lambda.yml | aws-lambda-outdated-runtime-creation | Notifies when a Lambda function is created with an outdated runtime | cloudtrail | notify - Email | N/A
lambda.yml | aws-lambda-unused-functions | Notifies of Lambda functions appear to be unused | periodic | notify - Email | c7n `custodian` functions
s3.yml | aws-s3-no-encryption | Notifies of S3 buckets without encyrption enabled | periodic | notify - Slack | N/A
s3.yml | aws-s3-public-access | Notifies of S3 buckets that do not have public access fully restricted | periodic | notify - Slack | N/A
schedule.yml | aws-rds-schedule-stop | Stops RDS instances based on the c7n-schedule tag | periodic | stop <br /> notify - Slack | N/A
schedule.yml | aws-rds-schedule-start | Starts RDS instances based on the c7n-schedule tag | periodic | start <br /> notify - Slack | N/A
schedule.yml | aws-rds-cluster-schedule-stop | Stops RDS clusters based on the c7n-schedule tag | periodic | stop <br /> notify - Slack | N/A
schedule.yml | aws-rds-cluster-schedule-start | Starts RDS clusters based on the c7n-schedule tag | periodic | start <br /> notify - Slack | N/A
schedule.yml | aws-rds-schedule-stop | Stops EC2 instances based on the c7n-schedule tag | periodic | stop <br /> notify - Slack | N/A
schedule.yml | aws-rds-schedule-start | Starts EC2 instances based on the c7n-schedule tag | periodic | start <br /> notify - Slack | N/A
schedule.yml | aws-asg-schedule-stop | Suspends ASG based on the c7n-schedule tag | periodic | tag <br /> suspend <br /> notify - Slack | N/A
schedule.yml | aws-asg-schedule-start | Resumes ASG based on the c7n-schedule tag | periodic | untag <br /> resume <br /> notify - Slack | N/A
tagging.yml | aws-acm-auto-tag-user | Auto-tags ACM resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-ami-auto-tag-user | Auto-tags AMI resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-asg-auto-tag-user | Auto-tags ASG resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-api-auto-tag-user | Auto-tags API Gateway REST API resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-cfn-auto-tag-user | Auto-tags Cloud Formation resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-cloudtrail-auto-tag-user | Auto-tags CloudTrail resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-cloudfront-auto-tag-user | Auto-tags CloudFront resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-dynamodb-auto-tag-user | Auto-tags DynamoDB resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-ec2-auto-tag-user | Auto-tags EC2 resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-ecr-auto-tag-user | Auto-tags ECR resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-ecs-cluster-auto-tag-user | Auto-tags ECS cluster resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-ecs-service-auto-tag-user | Auto-tags ECS service resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-ecs-task-definition-auto-tag-user | Auto-tags ECS task definition resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-efs-auto-tag-user | Auto-tags EFS resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-elastic-ip-auto-tag-user | Auto-tags Elastic IP resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-eni-auto-tag-user | Auto-tags Elastic Network Interface resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-ebs-snapshot-auto-tag-user | Auto-tags EBS snapshot with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-elasticache-cluster-auto-tag-user | Auto-tags Elasticache cluster resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-elasticache-snapshot-auto-tag-user | Auto-tags Elasticache snapshot resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-elasticsearch-auto-tag-user | Auto-tags ElasticSearch resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-alb-auto-tag-user | Auto-tags ALB resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-igw-auto-tag-user | Auto-tags Internet Gateway resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-iam-role-auto-tag-user | Auto-tags IAM role resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-iam-policy-auto-tag-user | Auto-tags IAM policy resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-iam-user-auto-tag-user | Auto-tags IAM user resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-key-pair-auto-tag-user | Auto-tags key pair resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-kms-key-auto-tag-user | Auto-tags KMS key resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-lambda-auto-tag-user | Auto-tags Lambda resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-cloudwatch-log-group-auto-tag-user | Auto-tags CloudWatch log group resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-nat-gateway-auto-tag-user | Auto-tags NAT Gateway resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-nacl-auto-tag-user | Auto-tags Network ACL resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-peering-connection-auto-tag-user | Auto-tags VPC peering connection resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-rds-instance-auto-tag-user | Auto-tags RDS instance resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-rds-snapshot-auto-tag-user | Auto-tags RDS snapshot resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-rds-parameter-group-auto-tag-user | Auto-tags RDS parameter group resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-rds-subnet-group-auto-tag-user | Auto-tags RDS subnet group resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-route-table-auto-tag-user | Auto-tags VPC route-table resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-ssm-parameter-group-auto-tag-user | Auto-tags SSM parameter resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-secrets-manager-group-auto-tag-user | Auto-tags Secrets Manager resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-security-group-group-auto-tag-user | Auto-tags Security Group resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-s3-auto-tag-user | Auto-tags S3 resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-sns-auto-tag-user | Auto-tags SNS resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-sqs-auto-tag-user | Auto-tags SQS resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-subnet-auto-tag-user | Auto-tags VPC subnet resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-tgw-auto-tag-user | Auto-tags Transit Gateway resources with creator info | cloudtrail | auto-tag-user | N/A
tagging.yml | aws-vpc-auto-tag-user | Auto-tags VPC resources with creator info | cloudtrail | auto-tag-user | N/A
rds.yml | aws-rds-stop-public-db-instances | Notifies of and stops RDS DB instances launched as publicly accessible | cloudtrail | stop | N/A
rds.yml | aws-rds-engine-version-upgrade-available | Notifies of RDS instances with engine upgrades available | periodic | notify - Email | N/A
rds.yml | aws-rds-cluster-snapshot-old | Notifies of and deletes old RDS cluster manual snapshots | periodic | delete and notify - Email | resources tagged with `c7n-exception:retention`
rds.yml | aws-rds-snapshot-old | Notifies of and deletes old RDS instance manual snapshots | periodic | delete and notify - Email | resources tagged with `c7n-exception:retention`
cloudwatch.yml | aws-cloudwatch-stale-log-groups | Notifies of CloudWatch log groups found to be unused  | periodic | notify - Email | c7n `custodian` log groups <br /> resources tagged with `c7n-exception:unused` 
cloudwatch.yml | aws-cloudwatch-c7n-log-group-retention | Notifies and sets the log group retention for c7n log groups  | periodic | set retention <br /> notify - Emaill | N/A
cloudwatch.yml | aws-cloudwatch-log-group-retention | Notifies and sets the retention for log groups set to never expire  | periodic | set retention <br /> notify | N/A
lb.yml | app-elb-invalid-ciphers | Notifies on usage of outdated TLS protocols  | periodic | notify - Email | N/A
lb.yml | aws-elb-http-listeners-without-https | Notifies on LB HTTP listeners in use that do not redirect to HTTPS  | periodic | notify - Email | N/A
lb.yml | aws-elb-create-internet-facing-load-balancer | Notifies on creation of an internet-facing load balancer  | cloudtrail | notify - Slack | N/A

### Understanding This Table

* `File` column is file where the policy resides, under repo `cloud-custodian/c7n/policies`
* `Name` column is the policy name as defined in YAML; this is also seen in the deployed Lambda function name
* `Description` column is a readable description of what the policy does
* `Mode` column is the mode in which the policy gathers data; see [AWS Execution Modes](https://cloudcustodian.io/docs/aws/resources/aws-modes.html)
* `Actions` column lists the action(s) performed on the resources discovered by the policy; see [AWS Common Actions](https://cloudcustodian.io/docs/aws/resources/aws-common-actions.html); additionally, each AWS resource may support its own custom actions (ex: [EC2 actions](https://cloudcustodian.io/docs/aws/resources/ec2.html#actions))
* `Exceptions` column lists any exceptions to the policy

---

_This documentation is deployed via automation from the cloud-custodian repo - DO NOT EDIT THIS PAGE MANUALLY_