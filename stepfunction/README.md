# Cloud Custodian Step Function Integration

This project demonstrates a comprehensive solution for detecting and automatically remediating public EC2 instances using AWS Step Functions and Cloud Custodian.

## 🏗️ Architecture Overview

The solution consists of:

1. **Cloud Custodian Policies** - Detect public EC2 instances in real-time
2. **AWS Step Functions** - Orchestrate the remediation workflow
3. **Lambda Functions** - Handle specific remediation tasks
4. **Supporting Infrastructure** - SNS, DynamoDB, CloudWatch, IAM roles

## 📁 Project Structure

```
cloud-custodian/
├── policies/
│   └── ec2-public-stepfunction.yml          # Cloud Custodian policies
├── stepfunction/
│   ├── ec2-public-remediation-statemachine.json   # Step Function definition
│   └── lambda-functions/                    # Lambda function source code
│       ├── notifier.py                      # Send security notifications
│       ├── tagger.py                        # Tag instances for tracking
│       ├── risk-evaluator.py                # Evaluate security risk level
│       ├── stopper.py                       # Stop high-risk instances
│       ├── monitor.py                       # Set up monitoring for low-risk
│       ├── verifier.py                      # Verify instance stop success
│       ├── review-checker.py                # Check manual review decisions
│       └── approver.py                      # Document approved instances
└── c7n/scripts/
    ├── deploy-stepfunction-demo.sh          # Deploy all resources
    ├── cleanup-stepfunction-demo.sh         # Clean up all resources
    └── test-stepfunction-demo.sh             # Test the complete workflow
```

## 🔄 Workflow Description

When a public EC2 instance is detected:

1. **Notification** - Security team is alerted via SNS
2. **Tagging** - Instance is tagged with compliance information
3. **Risk Evaluation** - Security risk level is assessed
4. **Decision Branch** - Based on risk level:
   - **HIGH RISK** → Instance is stopped immediately
   - **MEDIUM RISK** → Manual review (30-minute wait)
   - **LOW RISK** → Enhanced monitoring is enabled
5. **Verification** - Success/failure is verified and documented

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- Python 3.8+ installed
- Cloud Custodian installed (`pip install c7n`)
- `jq` and `zip` utilities installed
- Bash shell (Linux/macOS/WSL)

### 1. Deploy the Solution

```bash
# Make scripts executable
chmod +x c7n/scripts/*.sh

# Deploy all resources (takes 5-10 minutes)
./c7n/scripts/deploy-stepfunction-demo.sh us-west-2
```

### 2. Test the Solution

```bash
# Run basic testing
./c7n/scripts/test-stepfunction-demo.sh us-west-2

# Run comprehensive testing
./c7n/scripts/test-stepfunction-demo.sh us-west-2 $(aws sts get-caller-identity --query Account --output text) comprehensive
```

### 3. Clean Up Resources

```bash
# Remove all created resources
./c7n/scripts/cleanup-stepfunction-demo.sh us-west-2 --force
```

## 📋 Detailed Component Description

### Cloud Custodian Policies

**ec2-public-instances-stepfunction-remediation**
- **Mode**: CloudTrail (real-time)
- **Triggers**: RunInstances, ModifyInstanceAttribute, SecurityGroup changes
- **Filters**: Running instances with public IPs or permissive security groups
- **Action**: Invoke Step Function with instance details

**ec2-public-instances-periodic-check**
- **Mode**: Periodic (every 6 hours)
- **Purpose**: Catch instances missed by real-time monitoring
- **Filter**: Excludes recently processed instances

### Lambda Functions

| Function | Purpose | Risk Actions |
|----------|---------|--------------|
| **Notifier** | Send SNS alerts to security team | All risk levels |
| **Tagger** | Apply compliance and tracking tags | All risk levels |
| **Risk Evaluator** | Assess security risk (HIGH/MEDIUM/LOW) | All risk levels |
| **Stopper** | Stop instances immediately | HIGH risk only |
| **Monitor** | Set up CloudWatch alarms and monitoring | LOW risk only |
| **Review Checker** | Check for manual review decisions | MEDIUM risk only |
| **Approver** | Document approved instances | Manual approval |
| **Verifier** | Verify stop actions were successful | After stopping |

### Step Function State Machine

The state machine implements a sophisticated decision tree:

```
Start → Notify → Tag → Risk Evaluation → Decision
                                        ├─ HIGH → Stop → Verify → Complete
                                        ├─ MEDIUM → Wait → Review Decision
                                        │                 ├─ STOP → Stop
                                        │                 ├─ MONITOR → Monitor
                                        │                 └─ APPROVE → Approve
                                        └─ LOW → Monitor → Complete
```

## 🔧 Configuration Options

### Risk Assessment Criteria

**HIGH RISK** (Automatic Stop):
- SSH (22) or RDP (3389) open to 0.0.0.0/0
- All traffic (protocol -1) open to public
- High-performance instance types (p3, p4, x1, r5)
- Risk score ≥ 60

**MEDIUM RISK** (Manual Review):
- HTTP/HTTPS open to public with other security concerns
- Missing owner/approval tags
- Production environment instances
- Risk score 30-59

**LOW RISK** (Monitor Only):
- Limited public access with proper tags
- Development/test environments
- Risk score < 30

### Customization

**Environment Variables** (in deployment script):
```bash
# Modify these in deploy-stepfunction-demo.sh
AWS_REGION="us-west-2"
LAMBDA_TIMEOUT=300
LAMBDA_MEMORY=512
STEP_FUNCTION_NAME="EC2PublicInstanceRemediation"
```

**Risk Scoring** (in risk-evaluator.py):
```python
# Adjust risk factors and scores
CRITICAL_PORTS = {
    22: ("SSH", 25),      # SSH access
    3389: ("RDP", 25),    # RDP access
    1433: ("SQL Server", 20)  # Database access
}
```

## 📊 Monitoring and Logging

### CloudWatch Dashboards
- Public instance monitoring dashboard
- Step Function execution metrics
- Lambda function performance

### Log Groups
- `/aws/lambda/EC2-PublicInstance-*` - Lambda function logs
- `/aws/stepfunctions/EC2PublicInstanceRemediation` - Step Function logs
- `/aws/ec2/public-instance-monitoring/*` - Instance monitoring logs

### Alarms
- High CPU utilization on public instances
- Excessive network traffic
- Status check failures
- Step Function execution failures

## 🔐 Security Considerations

### IAM Permissions
- **Principle of Least Privilege** - Each Lambda has minimal required permissions
- **Role Separation** - Different roles for Step Functions and Lambda execution
- **Cross-Service Access** - Secure communication between services

### Data Protection
- **Sensitive Information** - Instance metadata is handled securely
- **Audit Trails** - All actions are logged for compliance
- **Tag Sanitization** - User input in tags is limited and sanitized

### Network Security
- **Public Access Detection** - Multiple methods to identify public exposure
- **Security Group Analysis** - Comprehensive rule evaluation
- **Risk Scoring** - Multi-factor risk assessment

## 🛠️ Troubleshooting

### Common Issues

**Step Function Not Triggering**
```bash
# Check Cloud Custodian policy deployment
custodian validate policies/ec2-public-stepfunction.yml

# Verify CloudTrail is enabled
aws cloudtrail describe-trails --region us-west-2
```

**Lambda Function Errors**
```bash
# Check function logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/EC2-PublicInstance-Notifier \
  --start-time 1680000000000

# Test function directly
aws lambda invoke \
  --function-name EC2-PublicInstance-Notifier \
  --payload '{"instanceId":"i-1234567890abcdef0"}' \
  response.json
```

**Permissions Issues**
```bash
# Verify IAM role exists and has policies
aws iam get-role --role-name cloud-custodian-stepfunction-role
aws iam list-attached-role-policies --role-name cloud-custodian-stepfunction-role
```

### Debug Mode

Enable detailed logging by setting environment variables:
```bash
export DEBUG=1
export VERBOSE_LOGGING=true
./c7n/scripts/deploy-stepfunction-demo.sh
```

## 📈 Performance and Scaling

### Throughput
- **Concurrent Executions**: Up to 1000 Step Function executions
- **Lambda Scaling**: Auto-scales based on demand
- **CloudTrail Processing**: Near real-time (1-5 minutes)

### Cost Optimization
- **Lambda**: Pay per execution, optimized memory allocation
- **Step Functions**: Pay per state transition
- **DynamoDB**: On-demand billing mode
- **CloudWatch**: 30-day log retention

## 🧪 Testing Scenarios

### Basic Test
```bash
./c7n/scripts/test-stepfunction-demo.sh us-west-2 $(aws sts get-caller-identity --query Account --output text) basic
```
- Creates 1 public instance
- Verifies Step Function triggers
- Checks basic workflow completion

### Comprehensive Test
```bash
./c7n/scripts/test-stepfunction-demo.sh us-west-2 $(aws sts get-caller-identity --query Account --output text) comprehensive
```
- Creates instances with different risk levels
- Tests all workflow branches
- Verifies risk assessment logic

### Stress Test
```bash
./c7n/scripts/test-stepfunction-demo.sh us-west-2 $(aws sts get-caller-identity --query Account --output text) stress
```
- Creates 5 concurrent instances
- Tests parallel processing
- Validates system scalability

## 🔄 Integration with Existing Systems

### SIEM Integration
```python
# Example: Forward notifications to Splunk
def forward_to_siem(event_data):
    splunk_hec_url = "https://your-splunk.com:8088/services/collector"
    headers = {"Authorization": "Splunk your-hec-token"}
    requests.post(splunk_hec_url, json=event_data, headers=headers)
```

### Ticketing System Integration
```python
# Example: Create ServiceNow ticket for manual review
def create_servicenow_ticket(instance_details):
    servicenow_api = "https://your-instance.service-now.com/api/now/table/incident"
    auth = ("username", "password")
    ticket_data = {
        "short_description": f"Public EC2 Instance: {instance_details['instanceId']}",
        "description": f"Instance requires manual review: {instance_details}",
        "urgency": "2",
        "impact": "2"
    }
    requests.post(servicenow_api, json=ticket_data, auth=auth)
```

## 📚 Additional Resources

### AWS Documentation
- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [Amazon CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/)

### Cloud Custodian Documentation
- [Cloud Custodian Documentation](https://cloudcustodian.io/)
- [EC2 Resource Documentation](https://cloudcustodian.io/docs/aws/resources/ec2.html)
- [Policy Language Reference](https://cloudcustodian.io/docs/aws/policy/index.html)

### Best Practices
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Security Best Practices](https://aws.amazon.com/security/security-learning/)
- [Cost Optimization](https://aws.amazon.com/aws-cost-management/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

For questions or issues:
- Create an issue in this repository
- Contact the security team at security-team@company.com
- Review AWS documentation for service-specific issues

---

**⚠️ Important Note**: This solution creates real AWS resources that may incur charges. Always clean up resources after testing using the provided cleanup script.