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
    Lambda function to verify that EC2 instance was successfully stopped.
    """
    try:
        logger.info(f"Processing verification for event: {json.dumps(event, default=str)}")
        
        # Extract instance information from the event
        instance_id = event.get('instanceId', '')
        account_id = event.get('accountId', '')
        region = event.get('region', '')
        expected_state = 'stopped'  # We expect the instance to be stopped
        
        # Get stop result from previous step
        stop_result = event.get('stopResult', {})
        stop_success = stop_result.get('stopSuccess', False)
        
        if not instance_id:
            raise ValueError("Instance ID is required")
        
        # Initialize EC2 client
        ec2_client = boto3.client('ec2', region_name=region)
        
        current_timestamp = datetime.utcnow().isoformat()
        
        # Verify instance state
        verification_result = verify_instance_state(
            ec2_client, instance_id, expected_state
        )
        
        # Check if stop was actually successful
        overall_success = (
            stop_success and 
            verification_result['current_state'] in ['stopped', 'stopping']
        )
        
        # Update verification tags
        verification_tags = [
            {
                'Key': 'custodian:verification-timestamp',
                'Value': current_timestamp
            },
            {
                'Key': 'custodian:verification-result',
                'Value': 'SUCCESS' if overall_success else 'FAILED'
            },
            {
                'Key': 'custodian:verified-state',
                'Value': verification_result['current_state']
            },
            {
                'Key': 'custodian:workflow-status',
                'Value': 'VERIFIED_STOPPED' if overall_success else 'VERIFICATION_FAILED'
            }
        ]
        
        try:
            ec2_client.create_tags(Resources=[instance_id], Tags=verification_tags)
            tagging_success = True
        except Exception as e:
            logger.error(f"Failed to apply verification tags: {str(e)}")
            tagging_success = False
        
        # Additional security verification
        security_verification = perform_security_verification(
            ec2_client, instance_id
        )
        
        # Create comprehensive audit log
        audit_log = {
            "event_type": "public_ec2_stop_verification",
            "timestamp": current_timestamp,
            "instance_id": instance_id,
            "account_id": account_id,
            "region": region,
            "stop_success": stop_success,
            "verification_success": overall_success,
            "current_state": verification_result['current_state'],
            "expected_state": expected_state,
            "state_change_time": verification_result.get('state_change_time'),
            "security_verification": security_verification,
            "tagging_success": tagging_success
        }
        
        logger.info(f"Verification audit log: {json.dumps(audit_log)}")
        
        # Return result for Step Function
        return {
            "statusCode": 200 if overall_success else 500,
            "instanceId": instance_id,
            "accountId": account_id,
            "region": region,
            "verificationSuccess": overall_success,
            "currentState": verification_result['current_state'],
            "expectedState": expected_state,
            "stateChangeTime": verification_result.get('state_change_time'),
            "securityVerification": security_verification,
            "message": "Instance stop verified successfully" if overall_success else "Stop verification failed",
            "timestamp": current_timestamp,
            "auditLog": audit_log
        }
        
    except Exception as e:
        logger.error(f"Error in verification function: {str(e)}")
        
        return {
            "statusCode": 500,
            "error": str(e),
            "instanceId": event.get('instanceId', 'Unknown'),
            "verificationSuccess": False,
            "message": "Verification function failed",
            "timestamp": datetime.utcnow().isoformat()
        }

def verify_instance_state(ec2_client, instance_id: str, expected_state: str) -> Dict[str, Any]:
    """
    Verify the current state of the EC2 instance.
    """
    try:
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        
        current_state = instance['State']['Name']
        state_reason = instance['State']['Reason']
        state_transition_time = instance.get('StateTransitionReason', '')
        
        # Get state change time if available
        state_change_time = None
        if 'StateTransitionTime' in instance:
            state_change_time = instance['StateTransitionTime'].isoformat()
        
        logger.info(f"Instance {instance_id} current state: {current_state} (reason: {state_reason})")
        
        return {
            "current_state": current_state,
            "expected_state": expected_state,
            "state_matches": current_state == expected_state,
            "state_reason": state_reason,
            "state_transition_reason": state_transition_time,
            "state_change_time": state_change_time,
            "verification_success": current_state in ['stopped', 'stopping']
        }
        
    except Exception as e:
        logger.error(f"Failed to verify instance state: {str(e)}")
        return {
            "current_state": "UNKNOWN",
            "expected_state": expected_state,
            "state_matches": False,
            "error": str(e),
            "verification_success": False
        }

def perform_security_verification(ec2_client, instance_id: str) -> Dict[str, Any]:
    """
    Perform additional security verification to ensure the instance is no longer a threat.
    """
    verification_results = {}
    
    try:
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        
        # 1. Verify no public IP
        public_ip = instance.get('PublicIpAddress')
        verification_results['public_ip_removed'] = public_ip is None
        verification_results['public_ip'] = public_ip
        
        # 2. Verify no public DNS
        public_dns = instance.get('PublicDnsName')
        verification_results['public_dns_removed'] = not public_dns
        verification_results['public_dns'] = public_dns
        
        # 3. Check network interfaces
        network_interfaces = instance.get('NetworkInterfaces', [])
        public_interfaces = []
        
        for ni in network_interfaces:
            if ni.get('Association', {}).get('PublicIp'):
                public_interfaces.append({
                    'interface_id': ni.get('NetworkInterfaceId'),
                    'public_ip': ni.get('Association', {}).get('PublicIp')
                })
        
        verification_results['public_interfaces_count'] = len(public_interfaces)
        verification_results['public_interfaces'] = public_interfaces
        verification_results['all_interfaces_private'] = len(public_interfaces) == 0
        
        # 4. Overall security status
        is_secure = (
            verification_results['public_ip_removed'] and
            verification_results['public_dns_removed'] and
            verification_results['all_interfaces_private']
        )
        
        verification_results['security_status'] = 'SECURE' if is_secure else 'POTENTIAL_RISK'
        verification_results['overall_secure'] = is_secure
        
        logger.info(f"Security verification for {instance_id}: {verification_results['security_status']}")
        
    except Exception as e:
        logger.error(f"Security verification failed: {str(e)}")
        verification_results = {
            "error": str(e),
            "security_status": "VERIFICATION_FAILED",
            "overall_secure": False
        }
    
    return verification_results