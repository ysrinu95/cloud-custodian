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
    Lambda function to stop public EC2 instances based on risk assessment.
    """
    try:
        logger.info(f"Processing instance stop for event: {json.dumps(event, default=str)}")
        
        # Extract instance information from the event
        instance_id = event.get('instanceId', '')
        account_id = event.get('accountId', '')
        region = event.get('region', '')
        risk_level = event.get('riskLevel', 'UNKNOWN')
        risk_score = event.get('riskScore', 0)
        risk_factors = event.get('riskFactors', [])
        
        if not instance_id:
            raise ValueError("Instance ID is required")
        
        # Initialize EC2 client
        ec2_client = boto3.client('ec2', region_name=region)
        
        # Get current instance state first
        try:
            response = ec2_client.describe_instances(InstanceIds=[instance_id])
            instance = response['Reservations'][0]['Instances'][0]
            current_state = instance['State']['Name']
            
            logger.info(f"Current instance state: {current_state}")
            
        except Exception as e:
            logger.error(f"Failed to get instance state: {str(e)}")
            return {
                "statusCode": 500,
                "error": f"Failed to get instance state: {str(e)}",
                "instanceId": instance_id,
                "stopSuccess": False,
                "message": "Could not retrieve instance state",
                "timestamp": datetime.utcnow().isoformat()
            }
        
        # Check if instance is already stopped or stopping
        if current_state in ['stopped', 'stopping']:
            logger.info(f"Instance {instance_id} is already in state: {current_state}")
            return {
                "statusCode": 200,
                "instanceId": instance_id,
                "accountId": account_id,
                "region": region,
                "stopSuccess": True,
                "previousState": current_state,
                "newState": current_state,
                "riskLevel": risk_level,
                "message": f"Instance already in {current_state} state",
                "timestamp": datetime.utcnow().isoformat()
            }
        
        # Check for stop protection
        stop_protection_enabled = check_stop_protection(ec2_client, instance_id)
        
        if stop_protection_enabled:
            logger.warning(f"Instance {instance_id} has stop protection enabled")
            
            # Try to disable stop protection for high-risk instances
            if risk_level == "HIGH" and risk_score >= 70:
                try:
                    logger.info("Attempting to disable stop protection for high-risk instance")
                    ec2_client.modify_instance_attribute(
                        InstanceId=instance_id,
                        DisableApiStop={'Value': False}
                    )
                    logger.info("Stop protection disabled successfully")
                    stop_protection_enabled = False
                    
                except Exception as e:
                    logger.error(f"Failed to disable stop protection: {str(e)}")
                    return {
                        "statusCode": 400,
                        "error": f"Stop protection enabled and could not be disabled: {str(e)}",
                        "instanceId": instance_id,
                        "stopSuccess": False,
                        "stopProtectionEnabled": True,
                        "message": "Manual intervention required to disable stop protection",
                        "timestamp": datetime.utcnow().isoformat()
                    }
            else:
                return {
                    "statusCode": 400,
                    "error": "Instance has stop protection enabled",
                    "instanceId": instance_id,
                    "stopSuccess": False,
                    "stopProtectionEnabled": True,
                    "message": "Cannot stop instance with protection enabled",
                    "timestamp": datetime.utcnow().isoformat()
                }
        
        # Add final warning tags before stopping
        warning_tags = [
            {
                'Key': 'custodian:stop-reason',
                'Value': f"Public access violation - Risk Level: {risk_level}"
            },
            {
                'Key': 'custodian:stop-timestamp',
                'Value': datetime.utcnow().isoformat()
            },
            {
                'Key': 'custodian:automated-stop',
                'Value': 'true'
            },
            {
                'Key': 'custodian:risk-score',
                'Value': str(risk_score)
            },
            {
                'Key': 'custodian:workflow-status',
                'Value': 'STOPPING'
            }
        ]
        
        try:
            ec2_client.create_tags(Resources=[instance_id], Tags=warning_tags)
            logger.info("Applied stop warning tags successfully")
        except Exception as e:
            logger.warning(f"Failed to apply warning tags: {str(e)}")
        
        # Attempt to stop the instance
        try:
            logger.info(f"Attempting to stop instance {instance_id}")
            
            stop_response = ec2_client.stop_instances(
                InstanceIds=[instance_id],
                Force=False  # Graceful stop first
            )
            
            stopping_instances = stop_response.get('StoppingInstances', [])
            if stopping_instances:
                new_state = stopping_instances[0]['CurrentState']['Name']
                previous_state = stopping_instances[0]['PreviousState']['Name']
                
                logger.info(f"Instance {instance_id} stop initiated: {previous_state} -> {new_state}")
                stop_success = True
                
            else:
                logger.error("No stopping instances returned in response")
                stop_success = False
                new_state = current_state
                previous_state = current_state
            
        except Exception as e:
            logger.error(f"Failed to stop instance {instance_id}: {str(e)}")
            
            # For critical instances, try force stop
            if risk_level == "HIGH" and risk_score >= 80:
                try:
                    logger.info("Attempting force stop for critical risk instance")
                    stop_response = ec2_client.stop_instances(
                        InstanceIds=[instance_id],
                        Force=True
                    )
                    
                    stopping_instances = stop_response.get('StoppingInstances', [])
                    if stopping_instances:
                        new_state = stopping_instances[0]['CurrentState']['Name']
                        previous_state = stopping_instances[0]['PreviousState']['Name']
                        logger.info(f"Force stop successful: {previous_state} -> {new_state}")
                        stop_success = True
                    else:
                        stop_success = False
                        new_state = current_state
                        previous_state = current_state
                        
                except Exception as force_error:
                    logger.error(f"Force stop also failed: {str(force_error)}")
                    stop_success = False
                    new_state = current_state
                    previous_state = current_state
            else:
                stop_success = False
                new_state = current_state
                previous_state = current_state
        
        # Create audit log
        current_timestamp = datetime.utcnow().isoformat()
        
        audit_log = {
            "event_type": "public_ec2_stop",
            "timestamp": current_timestamp,
            "instance_id": instance_id,
            "account_id": account_id,
            "region": region,
            "risk_level": risk_level,
            "risk_score": risk_score,
            "risk_factors": risk_factors,
            "stop_success": stop_success,
            "previous_state": previous_state,
            "new_state": new_state,
            "stop_protection_enabled": stop_protection_enabled
        }
        
        logger.info(f"Stop audit log: {json.dumps(audit_log)}")
        
        # Update workflow status tag
        try:
            status_tag = [
                {
                    'Key': 'custodian:workflow-status',
                    'Value': 'STOPPED' if stop_success else 'STOP_FAILED'
                }
            ]
            ec2_client.create_tags(Resources=[instance_id], Tags=status_tag)
        except Exception as e:
            logger.warning(f"Failed to update workflow status tag: {str(e)}")
        
        # Return result for Step Function
        return {
            "statusCode": 200 if stop_success else 500,
            "instanceId": instance_id,
            "accountId": account_id,
            "region": region,
            "stopSuccess": stop_success,
            "previousState": previous_state,
            "newState": new_state,
            "riskLevel": risk_level,
            "riskScore": risk_score,
            "stopProtectionEnabled": stop_protection_enabled,
            "message": "Instance stopped successfully" if stop_success else "Failed to stop instance",
            "timestamp": current_timestamp,
            "auditLog": audit_log
        }
        
    except Exception as e:
        logger.error(f"Error in stop function: {str(e)}")
        
        return {
            "statusCode": 500,
            "error": str(e),
            "instanceId": event.get('instanceId', 'Unknown'),
            "stopSuccess": False,
            "message": "Stop function failed",
            "timestamp": datetime.utcnow().isoformat()
        }

def check_stop_protection(ec2_client, instance_id: str) -> bool:
    """
    Check if the instance has stop protection enabled.
    """
    try:
        response = ec2_client.describe_instance_attribute(
            InstanceId=instance_id,
            Attribute='disableApiStop'
        )
        
        return response.get('DisableApiStop', {}).get('Value', False)
        
    except Exception as e:
        logger.warning(f"Could not check stop protection status: {str(e)}")
        return False  # Assume no protection if we can't check