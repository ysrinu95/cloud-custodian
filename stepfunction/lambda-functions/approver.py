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
    Lambda function to approve and document approved public EC2 instances.
    """
    try:
        logger.info(f"Processing approval for event: {json.dumps(event, default=str)}")
        
        # Extract instance information from the event
        instance_id = event.get('instanceId', '')
        account_id = event.get('accountId', '')
        region = event.get('region', '')
        reviewer = event.get('reviewDecision', {}).get('reviewer', 'UNKNOWN')
        review_comment = event.get('reviewDecision', {}).get('comment', '')
        
        if not instance_id:
            raise ValueError("Instance ID is required")
        
        # Initialize AWS clients
        ec2_client = boto3.client('ec2', region_name=region)
        dynamodb = boto3.resource('dynamodb', region_name=region)
        
        current_timestamp = datetime.utcnow().isoformat()
        
        # 1. Apply approval tags to the instance
        approval_result = apply_approval_tags(
            ec2_client, instance_id, reviewer, review_comment, current_timestamp
        )
        
        # 2. Document the approval in DynamoDB
        documentation_result = document_approval(
            dynamodb, instance_id, account_id, region, reviewer, 
            review_comment, current_timestamp
        )
        
        # 3. Create approval record for audit trail
        audit_record = create_approval_audit_record(
            instance_id, account_id, region, reviewer, review_comment, current_timestamp
        )
        
        # 4. Schedule periodic reviews
        review_schedule = schedule_periodic_review(
            ec2_client, instance_id, current_timestamp
        )
        
        # Create comprehensive audit log
        audit_log = {
            "event_type": "public_ec2_approval",
            "timestamp": current_timestamp,
            "instance_id": instance_id,
            "account_id": account_id,
            "region": region,
            "reviewer": reviewer,
            "review_comment": review_comment,
            "approval_tags_applied": approval_result['success'],
            "documentation_success": documentation_result['success'],
            "review_scheduled": review_schedule['success']
        }
        
        logger.info(f"Approval audit log: {json.dumps(audit_log)}")
        
        # Return result for Step Function
        return {
            "statusCode": 200,
            "instanceId": instance_id,
            "accountId": account_id,
            "region": region,
            "approvalSuccess": approval_result['success'] and documentation_result['success'],
            "reviewer": reviewer,
            "reviewComment": review_comment,
            "approvalTimestamp": current_timestamp,
            "nextReviewDate": review_schedule.get('next_review_date'),
            "approvalTags": approval_result.get('applied_tags', []),
            "message": "Instance approved and documented successfully",
            "timestamp": current_timestamp,
            "auditLog": audit_log
        }
        
    except Exception as e:
        logger.error(f"Error in approval function: {str(e)}")
        
        return {
            "statusCode": 500,
            "error": str(e),
            "instanceId": event.get('instanceId', 'Unknown'),
            "approvalSuccess": False,
            "message": "Approval function failed",
            "timestamp": datetime.utcnow().isoformat()
        }

def apply_approval_tags(ec2_client, instance_id: str, reviewer: str, 
                       comment: str, timestamp: str) -> Dict[str, Any]:
    """
    Apply approval tags to the EC2 instance.
    """
    try:
        approval_tags = [
            {
                'Key': 'custodian:approved',
                'Value': 'true'
            },
            {
                'Key': 'custodian:approval-timestamp',
                'Value': timestamp
            },
            {
                'Key': 'custodian:approved-by',
                'Value': reviewer
            },
            {
                'Key': 'custodian:approval-comment',
                'Value': comment[:255]  # Limit comment length for tag value
            },
            {
                'Key': 'custodian:public-access-approved',
                'Value': 'true'
            },
            {
                'Key': 'custodian:compliance-status',
                'Value': 'APPROVED'
            },
            {
                'Key': 'custodian:workflow-status',
                'Value': 'APPROVED'
            },
            {
                'Key': 'custodian:next-review',
                'Value': get_next_review_date(90)  # Review in 90 days
            },
            {
                'Key': 'custodian:approval-valid-until',
                'Value': get_next_review_date(365)  # Approval valid for 1 year
            },
            {
                'Key': 'security:reviewed',
                'Value': 'true'
            }
        ]
        
        ec2_client.create_tags(Resources=[instance_id], Tags=approval_tags)
        
        logger.info(f"Applied {len(approval_tags)} approval tags to {instance_id}")
        
        return {
            "success": True,
            "applied_tags": approval_tags,
            "tags_count": len(approval_tags)
        }
        
    except Exception as e:
        logger.error(f"Failed to apply approval tags: {str(e)}")
        return {"success": False, "error": str(e)}

def document_approval(dynamodb, instance_id: str, account_id: str, region: str,
                     reviewer: str, comment: str, timestamp: str) -> Dict[str, Any]:
    """
    Document the approval in DynamoDB for audit and tracking.
    """
    try:
        table_name = 'cloud-custodian-approvals'
        
        try:
            table = dynamodb.Table(table_name)
            
            # Create approval record
            approval_record = {
                'instance_id': instance_id,
                'account_id': account_id,
                'region': region,
                'approval_timestamp': timestamp,
                'reviewer': reviewer,
                'comment': comment,
                'approval_status': 'APPROVED',
                'approval_type': 'PUBLIC_ACCESS',
                'valid_until': get_next_review_date(365),
                'next_review_date': get_next_review_date(90),
                'created_by': 'cloud-custodian-stepfunction',
                'ttl': int((datetime.utcnow().timestamp() + (365 * 24 * 3600)))  # 1 year TTL
            }
            
            table.put_item(Item=approval_record)
            
            logger.info(f"Documented approval for {instance_id} in DynamoDB")
            
            return {
                "success": True,
                "table_name": table_name,
                "record_id": f"{instance_id}#{account_id}"
            }
            
        except Exception as e:
            logger.warning(f"DynamoDB table {table_name} not accessible: {str(e)}")
            # Continue without DynamoDB documentation
            return {"success": False, "error": str(e), "skipped": True}
        
    except Exception as e:
        logger.error(f"Error documenting approval: {str(e)}")
        return {"success": False, "error": str(e)}

def create_approval_audit_record(instance_id: str, account_id: str, region: str,
                               reviewer: str, comment: str, timestamp: str) -> Dict[str, Any]:
    """
    Create detailed audit record for the approval.
    """
    return {
        "audit_type": "public_ec2_approval",
        "instance_id": instance_id,
        "account_id": account_id,
        "region": region,
        "approval_details": {
            "reviewer": reviewer,
            "comment": comment,
            "timestamp": timestamp,
            "approval_method": "manual_review",
            "approval_duration": "365_days",
            "review_frequency": "90_days"
        },
        "compliance_details": {
            "policy_name": "public-ec2-instance-management",
            "approval_required": True,
            "approval_obtained": True,
            "documentation_complete": True
        },
        "audit_timestamp": timestamp
    }

def schedule_periodic_review(ec2_client, instance_id: str, timestamp: str) -> Dict[str, Any]:
    """
    Schedule periodic review for the approved instance.
    """
    try:
        # Calculate next review date (90 days)
        next_review_date = get_next_review_date(90)
        
        # Apply scheduling tags
        schedule_tags = [
            {
                'Key': 'custodian:review-frequency',
                'Value': '90-days'
            },
            {
                'Key': 'custodian:next-review-date',
                'Value': next_review_date
            },
            {
                'Key': 'custodian:auto-review-enabled',
                'Value': 'true'
            }
        ]
        
        ec2_client.create_tags(Resources=[instance_id], Tags=schedule_tags)
        
        logger.info(f"Scheduled periodic review for {instance_id}: {next_review_date}")
        
        return {
            "success": True,
            "next_review_date": next_review_date,
            "review_frequency": "90-days"
        }
        
    except Exception as e:
        logger.error(f"Failed to schedule periodic review: {str(e)}")
        return {"success": False, "error": str(e)}

def get_next_review_date(days: int) -> str:
    """
    Calculate next review date.
    """
    from datetime import timedelta
    next_date = datetime.utcnow() + timedelta(days=days)
    return next_date.isoformat() + 'Z'