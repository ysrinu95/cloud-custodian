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
    Lambda function to check manual review decision for medium-risk instances.
    """
    try:
        logger.info(f"Processing review check for event: {json.dumps(event, default=str)}")
        
        # Extract instance information from the event
        instance_id = event.get('instanceId', '')
        account_id = event.get('accountId', '')
        region = event.get('region', '')
        
        if not instance_id:
            raise ValueError("Instance ID is required")
        
        # Initialize AWS clients
        ec2_client = boto3.client('ec2', region_name=region)
        dynamodb = boto3.resource('dynamodb', region_name=region)
        
        current_timestamp = datetime.utcnow().isoformat()
        
        # Check for manual review decision in multiple places
        review_decision = check_review_decision(
            ec2_client, dynamodb, instance_id, account_id
        )
        
        # Log the review check
        audit_log = {
            "event_type": "manual_review_check",
            "timestamp": current_timestamp,
            "instance_id": instance_id,
            "account_id": account_id,
            "region": region,
            "review_decision": review_decision
        }
        
        logger.info(f"Review check audit log: {json.dumps(audit_log)}")
        
        # Return result for Step Function
        return {
            "statusCode": 200,
            "instanceId": instance_id,
            "accountId": account_id,
            "region": region,
            "action": review_decision['action'],
            "reviewer": review_decision.get('reviewer', 'SYSTEM'),
            "reviewTimestamp": review_decision.get('timestamp', current_timestamp),
            "reviewComment": review_decision.get('comment', ''),
            "reviewMethod": review_decision.get('method', 'TIMEOUT'),
            "message": f"Review decision: {review_decision['action']}",
            "timestamp": current_timestamp,
            "auditLog": audit_log
        }
        
    except Exception as e:
        logger.error(f"Error in review check function: {str(e)}")
        
        return {
            "statusCode": 500,
            "error": str(e),
            "instanceId": event.get('instanceId', 'Unknown'),
            "action": "STOP",  # Default to stop on error
            "message": "Review check function failed, defaulting to STOP",
            "timestamp": datetime.utcnow().isoformat()
        }

def check_review_decision(ec2_client, dynamodb, instance_id: str, account_id: str) -> Dict[str, Any]:
    """
    Check for manual review decision in multiple locations.
    """
    # 1. Check instance tags for review decision
    tag_decision = check_instance_tags(ec2_client, instance_id)
    if tag_decision['found']:
        return tag_decision
    
    # 2. Check DynamoDB table for review decisions
    db_decision = check_dynamodb_review(dynamodb, instance_id, account_id)
    if db_decision['found']:
        return db_decision
    
    # 3. Check for approval email responses (simulated)
    email_decision = check_email_responses(instance_id)
    if email_decision['found']:
        return email_decision
    
    # 4. Default action after timeout
    return {
        'action': 'STOP',
        'found': True,
        'method': 'TIMEOUT',
        'comment': 'No manual review decision received within timeout period',
        'timestamp': datetime.utcnow().isoformat(),
        'reviewer': 'SYSTEM_TIMEOUT'
    }

def check_instance_tags(ec2_client, instance_id: str) -> Dict[str, Any]:
    """
    Check instance tags for manual review decisions.
    """
    try:
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        
        tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
        
        # Look for review decision tags
        review_tags = [
            'custodian:manual-review-decision',
            'security:review-decision',
            'manual:review-action'
        ]
        
        for tag_key in review_tags:
            if tag_key in tags:
                decision_value = tags[tag_key].upper()
                
                # Parse the decision
                if decision_value in ['STOP', 'TERMINATE']:
                    action = 'STOP'
                elif decision_value in ['MONITOR', 'WATCH', 'OBSERVE']:
                    action = 'MONITOR'
                elif decision_value in ['APPROVE', 'ALLOW', 'WHITELIST']:
                    action = 'APPROVE'
                else:
                    continue  # Invalid decision, check next tag
                
                return {
                    'action': action,
                    'found': True,
                    'method': 'INSTANCE_TAG',
                    'comment': f'Decision found in tag {tag_key}: {decision_value}',
                    'timestamp': tags.get('custodian:review-timestamp', datetime.utcnow().isoformat()),
                    'reviewer': tags.get('custodian:reviewer', 'UNKNOWN')
                }
        
        return {'found': False}
        
    except Exception as e:
        logger.error(f"Error checking instance tags: {str(e)}")
        return {'found': False, 'error': str(e)}

def check_dynamodb_review(dynamodb, instance_id: str, account_id: str) -> Dict[str, Any]:
    """
    Check DynamoDB table for manual review decisions.
    """
    try:
        # Assume we have a DynamoDB table for review decisions
        table_name = 'cloud-custodian-review-decisions'
        
        try:
            table = dynamodb.Table(table_name)
            
            response = table.get_item(
                Key={
                    'instance_id': instance_id,
                    'account_id': account_id
                }
            )
            
            if 'Item' in response:
                item = response['Item']
                
                action = item.get('decision', '').upper()
                if action in ['STOP', 'MONITOR', 'APPROVE']:
                    return {
                        'action': action,
                        'found': True,
                        'method': 'DYNAMODB',
                        'comment': item.get('comment', ''),
                        'timestamp': item.get('timestamp', datetime.utcnow().isoformat()),
                        'reviewer': item.get('reviewer', 'UNKNOWN')
                    }
            
        except Exception as e:
            logger.warning(f"DynamoDB table {table_name} not accessible: {str(e)}")
        
        return {'found': False}
        
    except Exception as e:
        logger.error(f"Error checking DynamoDB: {str(e)}")
        return {'found': False, 'error': str(e)}

def check_email_responses(instance_id: str) -> Dict[str, Any]:
    """
    Check for email-based review responses (simulated).
    In a real implementation, this would check an email parsing service
    or integration with a ticketing system.
    """
    try:
        # This is a placeholder for email response checking
        # In practice, you might:
        # 1. Check SES received emails
        # 2. Query a ticketing system API
        # 3. Check a webhook endpoint for responses
        
        logger.info(f"Email response check for {instance_id} - not implemented")
        return {'found': False, 'method': 'EMAIL_NOT_IMPLEMENTED'}
        
    except Exception as e:
        logger.error(f"Error checking email responses: {str(e)}")
        return {'found': False, 'error': str(e)}