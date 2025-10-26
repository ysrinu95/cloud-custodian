import json
import boto3
import logging
from datetime import datetime
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Lambda function to notify security team about public EC2 instances.
    Sends notifications via SNS and logs detailed information.
    """
    try:
        logger.info(f"Processing notification for event: {json.dumps(event, default=str)}")
        
        # Extract instance information from the event
        instance_id = event.get('instanceId', 'Unknown')
        account_id = event.get('accountId', 'Unknown')
        region = event.get('region', 'Unknown')
        public_ip = event.get('publicIp', 'None')
        instance_type = event.get('instanceType', 'Unknown')
        launch_time = event.get('launchTime', 'Unknown')
        discovered_by = event.get('discoveredBy', 'cloud-custodian')
        policy_name = event.get('policyName', 'Unknown')
        
        # Initialize AWS clients
        sns_client = boto3.client('sns', region_name=region)
        ec2_client = boto3.client('ec2', region_name=region)
        
        # Get additional instance details
        try:
            response = ec2_client.describe_instances(InstanceIds=[instance_id])
            instance_details = response['Reservations'][0]['Instances'][0]
            
            # Extract security group information
            security_groups = [sg['GroupId'] for sg in instance_details.get('SecurityGroups', [])]
            subnet_id = instance_details.get('SubnetId', 'Unknown')
            vpc_id = instance_details.get('VpcId', 'Unknown')
            tags = instance_details.get('Tags', [])
            
        except Exception as e:
            logger.warning(f"Could not fetch additional instance details: {str(e)}")
            security_groups = event.get('securityGroups', [])
            subnet_id = event.get('subnetId', 'Unknown')
            vpc_id = event.get('vpcId', 'Unknown')
            tags = event.get('tags', [])
        
        # Format tag information
        tag_info = ""
        if tags:
            tag_info = "\n".join([f"  - {tag.get('Key', 'Unknown')}: {tag.get('Value', 'Unknown')}" for tag in tags])
        else:
            tag_info = "  - No tags found"
        
        # Create notification message
        notification_message = f"""
🚨 SECURITY ALERT: Public EC2 Instance Detected

═══════════════════════════════════════════════════════════════════
INSTANCE DETAILS:
═══════════════════════════════════════════════════════════════════
Instance ID: {instance_id}
Public IP: {public_ip}
Instance Type: {instance_type}
Launch Time: {launch_time}
Account ID: {account_id}
Region: {region}
VPC ID: {vpc_id}
Subnet ID: {subnet_id}

SECURITY GROUPS:
{', '.join(security_groups) if security_groups else 'None'}

TAGS:
{tag_info}

DETECTION DETAILS:
═══════════════════════════════════════════════════════════════════
Discovered By: {discovered_by}
Policy Name: {policy_name}
Detection Time: {datetime.utcnow().isoformat()}Z
Severity: HIGH

AUTOMATED RESPONSE:
═══════════════════════════════════════════════════════════════════
A Step Function workflow has been initiated to:
1. ✅ Notify security team (CURRENT STEP)
2. 🏷️ Tag the instance for tracking
3. 🔍 Evaluate security risk level
4. ⚡ Take appropriate remediation action

NEXT STEPS:
═══════════════════════════════════════════════════════════════════
• The instance will be automatically tagged
• Risk assessment will determine remediation approach
• High-risk instances will be stopped immediately
• Medium-risk instances will await manual review
• Low-risk instances will be monitored

MANUAL REVIEW URL:
https://{region}.console.aws.amazon.com/ec2/v2/home?region={region}#InstanceDetails:instanceId={instance_id}

═══════════════════════════════════════════════════════════════════
This is an automated message from Cloud Custodian Step Function.
For questions, contact: security-team@company.com
"""
        
        # Send SNS notification
        sns_topic_arn = f"arn:aws:sns:{region}:{account_id}:cloud-custodian-security-alerts"
        
        try:
            sns_response = sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=notification_message,
                Subject=f"🚨 Public EC2 Instance Alert - {instance_id}",
                MessageAttributes={
                    'severity': {
                        'DataType': 'String',
                        'StringValue': 'HIGH'
                    },
                    'instance_id': {
                        'DataType': 'String',
                        'StringValue': instance_id
                    },
                    'account_id': {
                        'DataType': 'String',
                        'StringValue': account_id
                    },
                    'region': {
                        'DataType': 'String',
                        'StringValue': region
                    }
                }
            )
            
            logger.info(f"SNS notification sent successfully: {sns_response['MessageId']}")
            notification_success = True
            message_id = sns_response['MessageId']
            
        except Exception as e:
            logger.error(f"Failed to send SNS notification: {str(e)}")
            notification_success = False
            message_id = None
        
        # Log to CloudWatch for audit trail
        audit_log = {
            "event_type": "public_ec2_notification",
            "timestamp": datetime.utcnow().isoformat(),
            "instance_id": instance_id,
            "account_id": account_id,
            "region": region,
            "public_ip": public_ip,
            "security_groups": security_groups,
            "notification_sent": notification_success,
            "sns_message_id": message_id,
            "discovered_by": discovered_by,
            "policy_name": policy_name
        }
        
        logger.info(f"Audit log: {json.dumps(audit_log)}")
        
        # Return result for Step Function
        return {
            "statusCode": 200,
            "notificationSent": notification_success,
            "snsMessageId": message_id,
            "instanceId": instance_id,
            "accountId": account_id,
            "region": region,
            "publicIp": public_ip,
            "timestamp": datetime.utcnow().isoformat(),
            "message": "Notification sent successfully" if notification_success else "Notification failed",
            "auditLog": audit_log
        }
        
    except Exception as e:
        logger.error(f"Error in notification function: {str(e)}")
        
        return {
            "statusCode": 500,
            "error": str(e),
            "instanceId": event.get('instanceId', 'Unknown'),
            "message": "Notification function failed",
            "timestamp": datetime.utcnow().isoformat()
        }