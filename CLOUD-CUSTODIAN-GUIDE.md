# Cloud Custodian - AWS Security Automation Framework

## Table of Contents
1. [Overview](#overview)
2. [Architecture & Design](#architecture--design)
3. [Features & Capabilities](#features--capabilities)
4. [Runtime Execution Logic](#runtime-execution-logic)
5. [AWS Security Service Policies](#aws-security-service-policies)
6. [Deployment & Operations](#deployment--operations)
7. [Monitoring & Troubleshooting](#monitoring--troubleshooting)

---

## Overview

Cloud Custodian is an open-source rules engine for cloud security, compliance, and governance. It enables policy-as-code for managing AWS resources through automated enforcement and remediation.

### Aikyam Security Objectives

**Mission**: Implement a comprehensive, automated security response framework for cloud infrastructure that minimizes human intervention and reduces mean time to remediation (MTTR).

#### Core Objectives

1. **Framework for Auto-Response to Cloud Security Events**
   - Real-time detection and response to security threats via EventBridge integration
   - Event-driven architecture that responds to GuardDuty, Security Hub, Config, and Macie findings
   - Automated policy enforcement across all AWS accounts and regions
   - Zero-touch remediation for known security patterns
   - Continuous monitoring and validation of security posture

2. **Automatic Remediation (Enabled by Default)**
   - **High/Critical Findings**: Immediate automated remediation without human approval
     - Isolate compromised EC2 instances to quarantine security groups
     - Revoke IAM credentials for compromised users
     - Remove dangerous security group rules (0.0.0.0/0 exposure)
     - Disable non-compliant resources
   - **Medium Findings**: Automated remediation with notification
     - Apply missing encryption to S3 buckets and EBS volumes
     - Enable CloudTrail logging on non-compliant accounts
     - Remediate IAM policy violations
   - **Low Findings**: Alert and schedule remediation
     - Tag resources for compliance tracking
     - Generate compliance reports for manual review

3. **Trigger Automatic Incident Response Runbooks**
   - **Critical Security Incidents** (Severity >= 9.0):
     - **Ransomware Attacks**: Immediate isolation, snapshot creation, forensic data collection
     - **Data Exfiltration**: Block outbound traffic, disable IAM credentials, alert SOC
     - **Cryptocurrency Mining**: Terminate instances, analyze attack vectors, update WAF rules
     - **Root Credential Usage**: Disable access keys, rotate credentials, notify CISO
   
   - **High Security Breaches** (Severity >= 7.0):
     - **Unauthorized Access**: Revoke sessions, enable MFA enforcement, audit access logs
     - **Security Group Violations**: Remove dangerous rules, restore to baseline configuration
     - **IAM Policy Violations**: Revert to least-privilege policies, notify security team
   
   - **Automated Runbook Execution** (via Step Functions):
     - Create ServiceNow/Jira incident tickets automatically
     - Initiate forensic investigation workflows
     - Trigger compliance audit processes
     - Update security dashboards and SIEM platforms
     - Generate executive security reports

#### Implementation Strategy

| Severity | Response Time | Automation Level | Human Intervention |
|----------|---------------|------------------|--------------------|
| **CRITICAL** (9.0-10.0) | < 1 minute | 100% Automated | Post-incident review only |
| **HIGH** (7.0-8.9) | < 5 minutes | 95% Automated | Approval for destructive actions |
| **MEDIUM** (4.0-6.9) | < 15 minutes | 80% Automated | Review before remediation |
| **LOW** (0.1-3.9) | < 1 hour | 50% Automated | Manual remediation preferred |

### Key Benefits
- **Policy as Code**: Define security and compliance rules in YAML
- **Event-Driven**: Respond to AWS events in real-time via EventBridge/CloudWatch Events
- **Serverless**: Runs as AWS Lambda functions with no infrastructure to manage
- **Multi-Account**: Supports AWS Organizations for centralized governance
- **Extensible**: Rich filter and action library with custom extensions
- **Integrated Alerting**: Native support for Teams, PagerDuty, Email, and SNS notifications

### Core Components
```
┌─────────────────────────────────────────────────────────────┐
│                     Cloud Custodian Stack                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │   Policies   │───▶│  c7n Engine  │───▶│   Actions    │ │
│  │   (YAML)     │    │              │    │ (Remediate)  │ │
│  └──────────────┘    └──────────────┘    └──────────────┘ │
│         │                    │                    │         │
│         │                    │                    │         │
│  ┌──────▼──────┐    ┌────────▼────────┐  ┌───────▼──────┐ │
│  │   Schema    │    │    Filters      │  │ Notifications│ │
│  │ Validation  │    │ (Resource Query)│  │(Teams/Email) │ │
│  └─────────────┘    └─────────────────┘  └──────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
         │                       │                      │
         ▼                       ▼                      ▼
┌──────────────┐        ┌──────────────┐      ┌──────────────┐
│ EventBridge  │        │  AWS Lambda  │      │  CloudWatch  │
│   Events     │        │  Functions   │      │     Logs     │
└──────────────┘        └──────────────┘      └──────────────┘
```

---

## Architecture & Design

### 1. Policy Structure

Cloud Custodian policies follow a consistent YAML schema:

```yaml
policies:
  - name: policy-name                    # Unique identifier
    resource: aws.resource-type          # AWS resource type
    description: |                       # Policy description
      What this policy does
    
    mode:                                # Execution mode
      type: cloudtrail | periodic | guard-duty | config-rule
      role: arn:aws:iam::account:role/name
      events:                            # Event filters (for cloudtrail mode)
        - source: service.amazonaws.com
          event: EventName
      schedule: "rate(1 day)"            # Schedule (for periodic mode)
    
    filters:                             # Resource selection criteria
      - type: filter-type
        key: attribute
        op: eq | ne | gt | gte | lt | lte | in | not-in
        value: value
    
    actions:                             # Remediation actions
      - type: action-type
        parameter: value
```

### 2. Execution Modes

Cloud Custodian supports multiple execution modes:

#### a) **CloudTrail Mode** (Event-Driven)
Responds to real-time AWS API calls via EventBridge.

```yaml
mode:
  type: cloudtrail
  role: arn:aws:iam::{account_id}:role/cloud-custodian
  events:
    - source: ec2.amazonaws.com
      event: RunInstances
      ids: "responseElements.instancesSet.items[].instanceId"
```

**Execution Flow:**
```
AWS API Call → CloudTrail → EventBridge → Lambda → Policy Evaluation → Action
```

#### b) **Periodic Mode** (Scheduled)
Runs on a schedule using CloudWatch Events cron/rate expressions.

```yaml
mode:
  type: periodic
  schedule: "rate(24 hours)"
  role: arn:aws:iam::{account_id}:role/cloud-custodian
```

**Execution Flow:**
```
CloudWatch Event (Schedule) → Lambda → Query All Resources → Filter → Action
```

#### c) **GuardDuty Mode** (Security Findings)
Responds to GuardDuty security findings via EventBridge.

```yaml
mode:
  type: guard-duty
  role: arn:aws:iam::{account_id}:role/cloud-custodian
```

**Execution Flow:**
```
GuardDuty Finding → EventBridge → Lambda → Policy Filter → Action
```

#### d) **Security Hub Mode** (CSPM Findings)
Responds to AWS Security Hub findings via CloudTrail events.

```yaml
mode:
  type: cloudtrail
  events:
    - source: aws.securityhub
      event: BatchImportFindings
      ids: "detail.findings[].Id"
  role: arn:aws:iam::{account_id}:role/cloud-custodian
```

**Execution Flow:**
```
Security Hub Finding → CloudTrail → EventBridge → Lambda → Policy Filter → Action
```

**Key Features:**
- Aggregates findings from multiple services (GuardDuty, Inspector, Macie, Config, IAM Access Analyzer)
- Supports compliance standards (AWS Foundational Security Best Practices, CIS Benchmarks)
- Real-time response to BatchImportFindings events
- Filter by severity labels (CRITICAL, HIGH, MEDIUM, LOW)
- Update finding workflow status with `post-finding` action

**Example Policy:**
```yaml
policies:
  - name: securityhub-critical-findings
    resource: aws.securityhub-finding
    mode:
      type: cloudtrail
      events:
        - source: aws.securityhub
          event: BatchImportFindings
          ids: "detail.findings[].Id"
    filters:
      - type: value
        key: Severity.Label
        op: in
        value: ["CRITICAL", "HIGH"]
      - type: value
        key: RecordState
        value: ACTIVE
    actions:
      - type: post-finding
        compliance_status: FAILED
        severity_label: HIGH
      - type: notify
        to: security-team@company.com
```

#### e) **Config Rule Mode** (Compliance)
Integrates with AWS Config for compliance evaluation.

```yaml
mode:
  type: config-rule
  role: arn:aws:iam::{account_id}:role/cloud-custodian
```

**Detailed Step-by-Step Process (Security Hub Example):**

```
┌─────────────────────────────────────────────────────────────┐
│  1. Security Hub Aggregates Finding                         │
│     • Source: AWS Foundational Security Best Practices      │
│     • Control: EC2.19 - Security groups should not allow    │
│       unrestricted access to ports with high risk           │
│     • Severity Label: HIGH                                  │
│     • Resource: sg-1234567890abcdef0                        │
│     • Compliance Status: FAILED                             │
│     • Violation: RDP (port 3389) open to 0.0.0.0/0          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  2. Security Hub Imports Finding (CloudTrail Event)         │
│     {                                                        │
│       "source": "aws.securityhub",                          │
│       "detail-type": "Security Hub Findings - Imported",    │
│       "detail": {                                           │
│         "findings": [{                                      │
│           "SchemaVersion": "2018-10-08",                    │
│           "Id": "arn:aws:securityhub:...",                  │
│           "ProductArn": "arn:aws:securityhub:...:fsbp",     │
│           "GeneratorId": "aws-foundational-security-...",   │
│           "AwsAccountId": "172327596604",                   │
│           "Types": [                                        │
│             "Software and Configuration Checks/AWS Security │
│              Best Practices"                                │
│           ],                                                │
│           "Severity": {                                     │
│             "Label": "HIGH",                                │
│             "Normalized": 70                                │
│           },                                                │
│           "Title": "EC2.19 Security groups should not...",  │
│           "Resources": [{                                   │
│             "Type": "AwsEc2SecurityGroup",                  │
│             "Id": "arn:aws:ec2:...:security-group/sg-...",  │
│             "Details": {                                    │
│               "AwsEc2SecurityGroup": {                      │
│                 "GroupId": "sg-1234567890abcdef0",          │
│                 "IpPermissions": [{                         │
│                   "FromPort": 3389,                         │
│                   "ToPort": 3389,                           │
│                   "IpRanges": [{"CidrIp": "0.0.0.0/0"}]     │
│                 }]                                          │
│               }                                             │
│             }                                               │
│           }],                                               │
│           "Compliance": {                                   │
│             "Status": "FAILED"                              │
│           },                                                │
│           "RecordState": "ACTIVE"                           │
│         }]                                                  │
│       }                                                     │
│     }                                                       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  3. EventBridge Rule Evaluation                             │
│     Rule Name: custodian-securityhub-critical-findings      │
│     Event Pattern:                                          │
│     {                                                       │
│       "source": ["aws.securityhub"],                       │
│       "detail-type": ["Security Hub Findings - Imported"], │
│       "detail": {                                          │
│         "findings": {                                      │
│           "Severity": {                                    │
│             "Label": ["CRITICAL", "HIGH"]                  │
│           },                                               │
│           "RecordState": ["ACTIVE"]                        │
│         }                                                  │
│       }                                                    │
│     }                                                      │
│     ✅ Pattern Match! → Trigger Lambda                     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  4. Lambda Function Invoked                                 │
│     Function: custodian-securityhub-critical-findings       │
│     • Receives Security Hub BatchImportFindings event       │
│     • Loads Cloud Custodian policy from embedded config     │
│     • Initializes AWS session and runtime environment       │
│     • Extracts resource IDs from findings array             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  5. Policy Filter Evaluation                                │
│     Filter 1: Severity Label Check                          │
│       - type: value                                         │
│         key: Severity.Label                                 │
│         op: in                                              │
│         value: ["CRITICAL", "HIGH"]                         │
│       ✅ HIGH → MATCH                                       │
│                                                             │
│     Filter 2: Record State Check                            │
│       - type: value                                         │
│         key: RecordState                                    │
│         value: ACTIVE                                       │
│       ✅ ACTIVE → PASS                                      │
│                                                             │
│     Filter 3: Compliance Status Check                       │
│       - type: value                                         │
│         key: Compliance.Status                              │
│         value: FAILED                                       │
│       ✅ FAILED → PASS                                      │
│                                                             │
│     All filters passed → Execute actions                    │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  6. Actions Executed Sequentially                           │
│     Action 1: Remediate Security Group                      │
│       • Query security group sg-1234567890abcdef0           │
│       • Remove dangerous ingress rules (0.0.0.0/0)          │
│       • Keep rules with specific CIDR ranges                │
│       • Log original rules to S3 for audit                  │
│                                                             │
│     Action 2: Update Security Hub Finding                   │
│       • type: post-finding                                  │
│       • Set Workflow.Status = RESOLVED                      │
│       • Add Note: "Remediated by Cloud Custodian"           │
│       • Update Compliance.Status = PASSED                   │
│                                                             │
│     Action 3: Tag Resource for Compliance Tracking          │
│       • SecurityHubFinding: EC2.19                          │
│       • Severity: HIGH                                      │
│       • RemediatedAt: 2025-10-28T10:00:00Z                  │
│       • Status: Remediated                                  │
│       • ComplianceFramework: AWS-FSBP                       │
│                                                             │
│     Action 4: Trigger Step Functions Workflow               │
│       • invoke-sfn: compliance-remediation-workflow         │
│       • Update compliance dashboard                         │
│       • Generate audit trail for compliance team            │
│       • Create ServiceNow change ticket                     │
│                                                             │
│     Action 5: Send Multi-Channel Notifications              │
│       • Teams message to #security-compliance channel       │
│       • Email to compliance-team@company.com                │
│       • PagerDuty incident (if critical severity)           │
│       • SNS message for SIEM integration                    │
└─────────────────────────────────────────────────────────────┘
```

**Event Pattern Matching:**
The EventBridge rule uses a pattern that pre-filters events before Lambda invocation:
- ✅ **Reduces Lambda invocations** (only HIGH/CRITICAL findings)
- ✅ **Lowers costs** (fewer function executions)
- ✅ **Faster response** (no unnecessary filter evaluation in Lambda)

**Why This Flow is Efficient:**
1. **Real-time**: GuardDuty → EventBridge is near-instantaneous
2. **Serverless**: No infrastructure to manage, auto-scales
3. **Cost-effective**: Pay only for Lambda executions that matter
4. **Reliable**: EventBridge guarantees at-least-once delivery
5. **Auditable**: Complete event trail in CloudWatch Logs

**Similar Flow for Security Hub:**
Security Hub uses the same EventBridge-based architecture but triggers on `BatchImportFindings` CloudTrail events:
```
Security Hub Finding → CloudTrail (BatchImportFindings) → EventBridge → Lambda → Policy Evaluation → Action
```

Security Hub aggregates findings from multiple AWS security services:
- **GuardDuty**: Threat detection findings
- **Inspector**: Vulnerability assessments
- **Macie**: Sensitive data discovery
- **Config**: Compliance rule violations
- **IAM Access Analyzer**: Resource access findings
- **Firewall Manager**: Security policy violations

This allows a single Cloud Custodian policy to respond to findings from all these services.

#### f) **Config Rule Mode** (Compliance)
Integrates with AWS Config for compliance evaluation.

```yaml
mode:
  type: config-rule
  role: arn:aws:iam::{account_id}:role/cloud-custodian
```

### 3. Resource Query & Filtering

Cloud Custodian uses a powerful filtering system:

#### Filter Types

| Filter Type | Description | Example |
|------------|-------------|---------|
| `value` | Compare attribute values | `key: State.Name, value: running` |
| `age` | Resource age | `type: age, days: 90, op: gt` |
| `tag` | Tag presence/value | `tag:Environment, value: production` |
| `security-group` | Security group rules | `type: ingress, Cidr: 0.0.0.0/0` |
| `event` | Event attribute (event mode) | `detail.severity, op: gte, value: 7.0` |
| `metrics` | CloudWatch metrics | `type: metrics, name: CPUUtilization` |

#### Filter Operators

- **Comparison**: `eq`, `ne`, `gt`, `gte`, `lt`, `lte`
- **Membership**: `in`, `not-in`, `contains`, `absent`, `present`
- **Pattern**: `regex`, `glob`
- **Logical**: `and`, `or`, `not`

### 4. Action System

Actions define what happens to resources that match filters:

#### Common Actions

| Action | Description | Use Case |
|--------|-------------|----------|
| `notify` | Send notifications | Alert via Teams/PagerDuty/Email/SNS |
| `tag` | Add/modify tags | Mark resources for tracking |
| `remove-tag` | Remove tags | Cleanup |
| `stop` | Stop instances | Cost savings |
| `terminate` | Delete resources | Cleanup |
| `snapshot` | Create backup | Before deletion |
| `modify-security-groups` | Update SG rules | Remove dangerous rules |
| `invoke-lambda` | Call custom Lambda | Custom logic |
| `invoke-sfn` | Trigger Step Functions | Complex workflows & orchestration |
| `put-metric` | Publish CloudWatch metric | Monitoring |

---

## Runtime Execution Logic

### 1. Lambda Function Lifecycle

```python
# Simplified execution flow
def handler(event, context):
    # 1. Load Policy
    policy = load_policy_from_config()
    
    # 2. Initialize Session
    session = get_aws_session(role_arn)
    
    # 3. Parse Event (if event-driven)
    if is_event_mode():
        resources = parse_event_resources(event)
    else:
        # 4. Query Resources
        resources = query_aws_resources(policy.resource_type)
    
    # 5. Apply Filters
    matched_resources = []
    for resource in resources:
        if policy.evaluate_filters(resource):
            matched_resources.append(resource)
    
    # 6. Execute Actions
    for action in policy.actions:
        action.process(matched_resources)
    
    # 7. Generate Report
    return {
        'resources_evaluated': len(resources),
        'resources_matched': len(matched_resources),
        'actions_taken': len(policy.actions)
    }
```

### 2. Event Processing

#### GuardDuty Event Structure
```json
{
  "version": "0",
  "id": "finding-id",
  "detail-type": "GuardDuty Finding",
  "source": "aws.guardduty",
  "account": "123456789012",
  "time": "2025-10-27T10:00:00Z",
  "region": "us-east-1",
  "detail": {
    "schemaVersion": "2.0",
    "accountId": "123456789012",
    "region": "us-east-1",
    "id": "finding-id",
    "arn": "arn:aws:guardduty:region:account:detector/id/finding/id",
    "type": "UnauthorizedAccess:EC2/SSHBruteForce",
    "severity": 8.0,
    "title": "SSH brute force attack detected",
    "description": "EC2 instance targeted by SSH brute force",
    "resource": {
      "resourceType": "Instance",
      "instanceDetails": {
        "instanceId": "i-1234567890abcdef0"
      }
    }
  }
}
```

### 3. Resource Resolution

Cloud Custodian resolves resources from events using JMESPath:

```yaml
mode:
  type: cloudtrail
  events:
    - event: RunInstances
      ids: "responseElements.instancesSet.items[].instanceId"
    - event: CreateSecurityGroup
      ids: "responseElements.groupId"
```

### 4. Error Handling & Retries

- **Lambda Retries**: Automatic retry on transient failures (up to 2 retries)
- **DLQ Support**: Failed events sent to Dead Letter Queue for manual review
- **CloudWatch Logs**: All execution details logged for debugging
- **Metrics**: Custom CloudWatch metrics for monitoring

---

## AWS Security Service Policies

### 1. GuardDuty Integration

#### Policy: High Severity Findings

```yaml
policies:
  - name: guardduty-high-severity-findings
    resource: ec2
    description: |
      Responds to GuardDuty HIGH and CRITICAL severity findings
      Automatically isolates compromised EC2 instances
    
    mode:
      type: guard-duty
      role: arn:aws:iam::{account_id}:role/cloud-custodian
    
    filters:
      # Filter by finding severity
      - type: event
        key: detail.severity
        op: gte
        value: 7.0  # HIGH (7.0-8.9) and CRITICAL (9.0-10.0)
      
      # Filter by finding type (optional)
      - type: event
        key: detail.type
        op: in
        value:
          - UnauthorizedAccess:EC2/SSHBruteForce
          - CryptoCurrency:EC2/BitcoinTool.B!DNS
          - Trojan:EC2/*
          - Backdoor:EC2/*
    
    actions:
      # 1. Isolate instance - remove from existing security groups
      - type: modify-security-groups
        isolation-group: sg-quarantine-id
        add-groups: 
          - sg-forensics-access
        remove-groups: matched
      
      # 2. Create snapshot for forensics
      - type: snapshot
        copy-tags:
          - Name
          - Environment
      
      # 3. Tag for tracking
      - type: tag
        tags:
          GuardDutyFinding: "{detail[type]}"
          Severity: "{detail[severity]}"
          QuarantinedAt: "{now}"
          Status: "Quarantined"
      
      # 4. Notify security team
      - type: notify
        template: guardduty-finding
        priority_header: "1"
        subject: "GuardDuty HIGH/CRITICAL Finding - Action Taken"
        to:
          - security-team@company.com
        transport:
          type: sns
          topic: arn:aws:sns:region:account:security-alerts
```

#### Notification Configuration Options

Cloud Custodian supports multiple notification channels:

##### Option 1: Microsoft Teams Webhook

```yaml
actions:
  - type: notify
    template: default
    subject: "GuardDuty HIGH/CRITICAL Finding - {account} {region}"
    to:
      - https://outlook.office.com/webhook/YOUR-WEBHOOK-URL
    transport:
      type: webhook
      webhook_url: https://outlook.office.com/webhook/YOUR-WEBHOOK-URL
    violation_desc: |
      GuardDuty detected HIGH/CRITICAL severity finding
    action_desc: |
      Affected resource has been quarantined for investigation
```

**Teams Webhook Payload:**
```python
{
  "@type": "MessageCard",
  "@context": "http://schema.org/extensions",
  "themeColor": "FF0000",
  "summary": "GuardDuty HIGH/CRITICAL Finding",
  "sections": [{
    "activityTitle": "Cloud Custodian Alert",
    "activitySubtitle": "GuardDuty Finding Detected",
    "facts": [
      {"name": "Severity", "value": "{detail[severity]}"},
      {"name": "Finding Type", "value": "{detail[type]}"},
      {"name": "Resource", "value": "{detail[resource][instanceDetails][instanceId]}"},
      {"name": "Account", "value": "{account}"},
      {"name": "Region", "value": "{region}"}
    ],
    "markdown": true
  }]
}
```

##### Option 2: PagerDuty Integration

```yaml
actions:
  - type: notify
    template: default
    subject: "GuardDuty HIGH/CRITICAL Finding"
    priority_header: "high"
    to:
      - pagerduty://INTEGRATION_KEY
    transport:
      type: pagerduty
      integration_key: YOUR_PAGERDUTY_INTEGRATION_KEY
      api_key: YOUR_PAGERDUTY_API_KEY
    violation_desc: |
      GuardDuty Finding: {detail[type]}
      Severity: {detail[severity]}
      Resource: {detail[resource][instanceDetails][instanceId]}
```

**PagerDuty Event Payload:**
```yaml
actions:
  - type: notify
    transport:
      type: pagerduty
      integration_key: YOUR_INTEGRATION_KEY
    pagerduty_event:
      event_action: trigger
      severity: critical
      source: cloud-custodian
      summary: "GuardDuty {detail[type]} - Severity {detail[severity]}"
      custom_details:
        finding_id: "{detail[id]}"
        finding_type: "{detail[type]}"
        severity: "{detail[severity]}"
        resource_id: "{detail[resource][instanceDetails][instanceId]}"
        account: "{account}"
        region: "{region}"
```

##### Option 3: Email Notifications (via SES)

```yaml
actions:
  - type: notify
    template: default
    subject: "[CRITICAL] GuardDuty Finding - {detail[type]}"
    to:
      - security-team@company.com
      - soc-team@company.com
    cc:
      - compliance@company.com
    transport:
      type: ses
      from: cloud-custodian@company.com
      region: us-east-1
```

##### Option 4: SNS Topic (for Multi-Channel Fanout)

```yaml
actions:
  - type: notify
    template: default
    subject: "GuardDuty Finding Alert"
    to:
      - arn:aws:sns:us-east-1:123456789012:security-alerts
    transport:
      type: sns
      topic: arn:aws:sns:us-east-1:123456789012:security-alerts
```

**SNS Topic Subscribers:**
- Email subscriptions
- Lambda functions for Teams/PagerDuty webhooks
- SMS notifications
- SQS queues for event processing
```

#### GuardDuty Finding Types & Severity

| Finding Type | Severity | Description | Recommended Action |
|--------------|----------|-------------|-------------------|
| `CryptoCurrency:EC2/*` | CRITICAL (9.0+) | Cryptocurrency mining | Isolate + Investigate |
| `Trojan:EC2/*` | CRITICAL (9.0+) | Trojan malware detected | Isolate + Terminate |
| `Backdoor:EC2/*` | HIGH (8.0+) | C&C communication | Isolate + Investigate |
| `UnauthorizedAccess:EC2/SSHBruteForce` | HIGH (8.0) | SSH brute force | Block IP + Monitor |
| `Recon:EC2/PortProbe*` | MEDIUM-HIGH (5.0-8.0) | Port scanning | Monitor + Investigate |

### 2. AWS Security Hub Integration

```yaml
policies:
  - name: securityhub-critical-findings
    resource: account
    description: |
      Responds to Security Hub critical findings
      Aggregates findings from GuardDuty, Inspector, Macie, etc.
    
    mode:
      type: cloudtrail
      events:
        - source: securityhub.amazonaws.com
          event: BatchImportFindings
          ids: "requestParameters.findings[].Id"
      role: arn:aws:iam::{account_id}:role/cloud-custodian
    
    filters:
      - type: event
        key: detail.findings[].Severity.Label
        op: in
        value: ["CRITICAL", "HIGH"]
      
      - type: event
        key: detail.findings[].Compliance.Status
        value: FAILED
    
    actions:
      - type: invoke-lambda
        function: arn:aws:lambda:region:account:function:remediate-finding
      
      - type: notify
        template: security-hub-finding
        to:
          - compliance-team@company.com
```

### 3. IAM Access Analyzer

```yaml
policies:
  - name: iam-access-analyzer-findings
    resource: iam-role
    description: |
      Responds to IAM Access Analyzer findings
      Remediates overly permissive IAM roles
    
    mode:
      type: cloudtrail
      events:
        - source: access-analyzer.amazonaws.com
          event: CreateFinding
      role: arn:aws:iam::{account_id}:role/cloud-custodian
    
    filters:
      - type: event
        key: detail.finding.status
        value: ACTIVE
      
      - type: event
        key: detail.finding.resourceType
        value: AWS::IAM::Role
    
    actions:
      - type: tag
        tags:
          AccessAnalyzerFinding: "Active"
          ReviewRequired: "true"
      
      - type: notify
        template: access-analyzer-finding
        to:
          - iam-admin@company.com
```

### 4. AWS Config Compliance

```yaml
policies:
  - name: config-non-compliant-resources
    resource: ec2
    description: |
      Responds to AWS Config compliance changes
      Remediates non-compliant EC2 instances
    
    mode:
      type: config-rule
      role: arn:aws:iam::{account_id}:role/cloud-custodian
    
    filters:
      - type: config-compliance
        eval: non-compliant
        rules:
          - required-tags
          - encrypted-volumes
    
    actions:
      - type: stop
      
      - type: notify
        template: config-compliance
        to:
          - operations@company.com
```

### 5. Macie Data Discovery

```yaml
policies:
  - name: macie-sensitive-data-findings
    resource: s3
    description: |
      Responds to Macie sensitive data findings
      Encrypts buckets and restricts access
    
    mode:
      type: cloudtrail
      events:
        - source: macie.amazonaws.com
          event: CreateFinding
      role: arn:aws:iam::{account_id}:role/cloud-custodian
    
    filters:
      - type: event
        key: detail.finding.severity
        op: in
        value: ["HIGH", "CRITICAL"]
      
      - type: event
        key: detail.finding.category
        value: CLASSIFICATION
    
    actions:
      - type: encrypt-s3-bucket
        crypto: AES256
      
      - type: set-bucket-policy
        policy:
          Statement:
            - Effect: Deny
              Principal: "*"
              Action: "s3:GetObject"
              Resource: "arn:aws:s3:::{bucket}/*"
              Condition:
                Bool:
                  "aws:SecureTransport": "false"
      
      - type: notify
        template: macie-finding
        to:
          - data-protection@company.com
```

---

## Notification Templates & Integration

### 1. Microsoft Teams Integration

#### Setup Teams Webhook
1. Go to your Teams channel → Connectors → Incoming Webhook
2. Create webhook and copy URL
3. Use webhook URL in Cloud Custodian policy

#### Teams Notification Example

```yaml
policies:
  - name: guardduty-teams-notification
    resource: ec2
    mode:
      type: guard-duty
      role: arn:aws:iam::{account_id}:role/cloud-custodian
    
    filters:
      - type: event
        key: detail.severity
        op: gte
        value: 7.0
    
    actions:
      - type: notify
        template: teams-alert
        to:
          - https://outlook.office.com/webhook/YOUR-WEBHOOK-URL
        transport:
          type: webhook
          webhook_url: https://outlook.office.com/webhook/YOUR-WEBHOOK-URL
          headers:
            Content-Type: application/json
        body: |
          {
            "@type": "MessageCard",
            "@context": "https://schema.org/extensions",
            "themeColor": "FF0000",
            "summary": "GuardDuty Security Alert",
            "sections": [{
              "activityTitle": "🚨 GuardDuty HIGH/CRITICAL Finding",
              "activitySubtitle": "Automated Response Triggered",
              "facts": [
                {"name": "Finding Type", "value": "{{ event.detail.type }}"},
                {"name": "Severity", "value": "{{ event.detail.severity }}"},
                {"name": "Instance ID", "value": "{{ event.detail.resource.instanceDetails.instanceId }}"},
                {"name": "Account", "value": "{{ account }}"},
                {"name": "Region", "value": "{{ region }}"},
                {"name": "Timestamp", "value": "{{ event.time }}"}
              ],
              "markdown": true
            }],
            "potentialAction": [{
              "@type": "OpenUri",
              "name": "View in GuardDuty Console",
              "targets": [{
                "os": "default",
                "uri": "https://{{ region }}.console.aws.amazon.com/guardduty/home?region={{ region }}#/findings"
              }]
            }]
          }
```

### 2. PagerDuty Integration

#### Setup PagerDuty
1. Create PagerDuty service integration (Events API v2)
2. Copy Integration Key
3. Optionally create API key for advanced features

#### PagerDuty Alert Example

```yaml
policies:
  - name: guardduty-pagerduty-alert
    resource: ec2
    mode:
      type: guard-duty
      role: arn:aws:iam::{account_id}:role/cloud-custodian
    
    filters:
      - type: event
        key: detail.severity
        op: gte
        value: 8.5  # CRITICAL only
    
    actions:
      - type: notify
        template: pagerduty-incident
        to:
          - pagerduty://INTEGRATION_KEY
        transport:
          type: pagerduty
          integration_key: YOUR_INTEGRATION_KEY
        pagerduty_payload:
          routing_key: YOUR_INTEGRATION_KEY
          event_action: trigger
          payload:
            summary: "CRITICAL GuardDuty Finding: {{ event.detail.type }}"
            severity: critical
            source: cloud-custodian
            component: guardduty
            group: security
            class: threat-detection
            custom_details:
              finding_id: "{{ event.detail.id }}"
              finding_type: "{{ event.detail.type }}"
              severity_score: "{{ event.detail.severity }}"
              instance_id: "{{ event.detail.resource.instanceDetails.instanceId }}"
              account_id: "{{ account }}"
              region: "{{ region }}"
              detection_time: "{{ event.detail.service.eventFirstSeen }}"
              description: "{{ event.detail.description }}"
          images:
            - src: https://example.com/custodian-logo.png
              alt: Cloud Custodian
          links:
            - href: "https://{{ region }}.console.aws.amazon.com/guardduty/home?region={{ region }}#/findings?search=id%3D{{ event.detail.id }}"
              text: View in GuardDuty Console
```

#### PagerDuty Auto-Resolve Example

```yaml
policies:
  - name: guardduty-pagerduty-resolve
    resource: ec2
    mode:
      type: cloudtrail
      events:
        - source: guardduty.amazonaws.com
          event: ArchiveFinding
    
    actions:
      - type: notify
        transport:
          type: pagerduty
          integration_key: YOUR_INTEGRATION_KEY
        pagerduty_payload:
          routing_key: YOUR_INTEGRATION_KEY
          event_action: resolve
          dedup_key: "guardduty-{{ event.detail.id }}"
```

### 3. Email Notifications (AWS SES)

```yaml
policies:
  - name: guardduty-email-notification
    resource: ec2
    mode:
      type: guard-duty
      role: arn:aws:iam::{account_id}:role/cloud-custodian
    
    filters:
      - type: event
        key: detail.severity
        op: gte
        value: 7.0
    
    actions:
      - type: notify
        template: guardduty-email
        template_format: html
        subject: "[{{ event.detail.severity }}] GuardDuty Finding - {{ event.detail.type }}"
        to:
          - security-team@company.com
          - soc-alerts@company.com
        cc:
          - compliance@company.com
        transport:
          type: ses
          from: cloud-custodian-alerts@company.com
          region: us-east-1
```

**Email Template (guardduty-email.html):**
```html
<html>
<head>
  <style>
    .alert { background-color: #ff0000; color: white; padding: 10px; }
    .details { background-color: #f5f5f5; padding: 15px; margin: 10px 0; }
    .fact { margin: 5px 0; }
  </style>
</head>
<body>
  <div class="alert">
    <h2>🚨 GuardDuty Security Alert</h2>
  </div>
  
  <div class="details">
    <h3>Finding Details</h3>
    <div class="fact"><strong>Finding Type:</strong> {{ event.detail.type }}</div>
    <div class="fact"><strong>Severity:</strong> {{ event.detail.severity }}</div>
    <div class="fact"><strong>Title:</strong> {{ event.detail.title }}</div>
    <div class="fact"><strong>Description:</strong> {{ event.detail.description }}</div>
    
    <h3>Resource Information</h3>
    <div class="fact"><strong>Instance ID:</strong> {{ event.detail.resource.instanceDetails.instanceId }}</div>
    <div class="fact"><strong>Instance Type:</strong> {{ event.detail.resource.instanceDetails.instanceType }}</div>
    
    <h3>Account & Location</h3>
    <div class="fact"><strong>Account:</strong> {{ account }}</div>
    <div class="fact"><strong>Region:</strong> {{ region }}</div>
    <div class="fact"><strong>Detection Time:</strong> {{ event.detail.service.eventFirstSeen }}</div>
    
    <h3>Actions Taken</h3>
    <ul>
      <li>Instance isolated to quarantine security group</li>
      <li>Forensic snapshot created</li>
      <li>Resource tagged for investigation</li>
    </ul>
    
    <p>
      <a href="https://{{ region }}.console.aws.amazon.com/guardduty/home?region={{ region }}#/findings">
        View in GuardDuty Console
      </a>
    </p>
  </div>
</body>
</html>
```

### 4. Multi-Channel Notification Strategy

```yaml
policies:
  - name: guardduty-multi-channel-alerts
    resource: ec2
    mode:
      type: guard-duty
      role: arn:aws:iam::{account_id}:role/cloud-custodian
    
    filters:
      - type: event
        key: detail.severity
        op: gte
        value: 7.0
    
    actions:
      # 1. Immediate PagerDuty alert for CRITICAL findings
      - type: notify
        transport:
          type: pagerduty
          integration_key: YOUR_INTEGRATION_KEY
        priority_header: high
        filters:
          - type: event
            key: detail.severity
            op: gte
            value: 9.0
      
      # 2. Teams notification for all HIGH+ findings
      - type: notify
        transport:
          type: webhook
          webhook_url: https://outlook.office.com/webhook/YOUR-WEBHOOK-URL
      
      # 3. Email digest for compliance team
      - type: notify
        transport:
          type: ses
          from: custodian@company.com
        to:
          - compliance@company.com
      
      # 4. SNS topic for downstream processing
      - type: notify
        transport:
          type: sns
          topic: arn:aws:sns:us-east-1:123456789012:security-events
```

### 5. Notification Template Variables

Available variables in notification templates:

| Variable | Description | Example |
|----------|-------------|---------|
| `{{ account }}` | AWS Account ID | `123456789012` |
| `{{ region }}` | AWS Region | `us-east-1` |
| `{{ event.detail.* }}` | GuardDuty finding details | `{{ event.detail.type }}` |
| `{{ event.time }}` | Event timestamp | `2025-10-27T10:00:00Z` |
| `{{ policy.name }}` | Cloud Custodian policy name | `guardduty-high-severity` |
| `{{ resources }}` | Affected resources | List of resource IDs |
| `{{ action_date }}` | Action execution time | `2025-10-27 10:05:00` |

---

## Deployment & Operations

### 1. Deployment Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Repository                         │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  policies/                                             │ │
│  │  ├── guardduty.yml                                     │ │
│  │  ├── securityhub.yml                                   │ │
│  │  ├── ec2.yml                                           │ │
│  │  └── iam.yml                                           │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
        ┌─────────────────────────┐
        │   GitHub Actions CI/CD   │
        │  .github/workflows/      │
        │  cloud-custodian-        │
        │  policies.yml            │
        └────────────┬─────────────┘
                     │
                     ▼
        ┌────────────────────────────┐
        │  custodian run --validate  │
        │  custodian run -s output/  │
        └────────────┬───────────────┘
                     │
                     ▼
        ┌────────────────────────────────────┐
        │      AWS Lambda Functions          │
        │  ┌──────────────────────────────┐  │
        │  │ custodian-guardduty-findings │  │
        │  │ custodian-ec2-public-ips     │  │
        │  │ custodian-sg-remediation     │  │
        │  └──────────────────────────────┘  │
        └────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────────┐
        │   EventBridge Rules         │
        │  ┌──────────────────────┐   │
        │  │ GuardDuty Finding    │   │
        │  │ CloudTrail Events    │   │
        │  │ Scheduled Rules      │   │
        │  └──────────────────────┘   │
        └────────────────────────────┘
```

### 2. CI/CD Pipeline

```yaml
# .github/workflows/cloud-custodian-policies.yml
name: Cloud Custodian Policies

on:
  push:
    branches: [main]
    paths:
      - 'policies/**'
  pull_request:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Validate Policies
        run: |
          custodian validate policies/*.yml
      
      - name: Schema Check
        run: |
          custodian schema --validate policies/*.yml
  
  deploy:
    needs: validate
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Deploy to Lambda
        run: |
          custodian run \
            -s output/ \
            --region us-east-1 \
            policies/*.yml
```

### 3. Multi-Account Deployment

```bash
# Using c7n-org for AWS Organizations
c7n-org run \
  -c accounts.yml \
  -s output/ \
  -u policies/*.yml \
  --region us-east-1
```

**accounts.yml:**
```yaml
accounts:
  - account_id: '111111111111'
    name: production
    role: arn:aws:iam::111111111111:role/CloudCustodian
    tags:
      - environment:prod
  
  - account_id: '222222222222'
    name: staging
    role: arn:aws:iam::222222222222:role/CloudCustodian
    tags:
      - environment:staging
```

---

## Monitoring & Troubleshooting

### 1. CloudWatch Dashboards

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Invocations", {"stat": "Sum"}],
          [".", "Errors", {"stat": "Sum"}],
          [".", "Duration", {"stat": "Average"}]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "Cloud Custodian Lambda Metrics"
      }
    }
  ]
}
```

### 2. Log Queries

```bash
# Find GuardDuty finding processing
aws logs filter-log-events \
  --log-group-name /aws/lambda/custodian-guardduty-findings \
  --filter-pattern "GuardDuty Finding" \
  --start-time $(date -d '1 hour ago' +%s)000

# Find policy errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/custodian-* \
  --filter-pattern "ERROR" \
  --start-time $(date -d '24 hours ago' +%s)000
```

### 3. Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Lambda not triggered | EventBridge pattern mismatch | Verify event pattern matches AWS service events |
| Permission errors | Missing IAM permissions | Add required permissions to Lambda execution role |
| Resource not found | Event delay or filter issue | Add retries or adjust filters |
| Timeout | Too many resources | Reduce batch size or increase timeout |

### 4. Testing

```bash
# Dry-run mode (no actions taken)
custodian run \
  --dryrun \
  -s output/ \
  policies/guardduty.yml

# Test specific policy
custodian run \
  --policy guardduty-high-severity-findings \
  -s output/ \
  policies/guardduty.yml

# Validate policy syntax
custodian validate policies/guardduty.yml
```

---

## Best Practices

### 1. Policy Design
- ✅ Use descriptive policy names
- ✅ Add detailed descriptions
- ✅ Test with `--dryrun` before deploying
- ✅ Use tags for resource tracking
- ✅ Implement proper error handling

### 2. Security
- ✅ Use least-privilege IAM roles
- ✅ Encrypt sensitive data in transit and at rest
- ✅ Enable CloudTrail logging
- ✅ Review policies in pull requests
- ✅ Regular security audits

### 3. Operations
- ✅ Monitor Lambda invocations and errors
- ✅ Set up CloudWatch alarms
- ✅ Use Dead Letter Queues for failed events
- ✅ Regular policy reviews and updates
- ✅ Document policy changes

---

## Additional Resources

- **Official Documentation**: https://cloudcustodian.io/docs/
- **GitHub Repository**: https://github.com/cloud-custodian/cloud-custodian
- **AWS GuardDuty**: https://docs.aws.amazon.com/guardduty/
- **AWS Security Hub**: https://docs.aws.amazon.com/securityhub/
- **EventBridge Patterns**: https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns.html

---

**Last Updated**: October 2025  
**Version**: 1.0  
**Maintained By**: DevOps/Security Team
