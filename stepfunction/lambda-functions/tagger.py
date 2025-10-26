import json
import boto3
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Lambda function to tag public EC2 instances with compliance and tracking information.
    """
    try:
        logger.info(f"Processing tagging for event: {json.dumps(event, default=str)}")
        
        # Extract instance information from the event
        instance_id = event.get('instanceId', '')
        account_id = event.get('accountId', '')
        region = event.get('region', '')
        discovered_by = event.get('discoveredBy', 'cloud-custodian')
        policy_name = event.get('policyName', 'unknown')
        public_ip = event.get('publicIp', 'Unknown')
        
        if not instance_id:
            raise ValueError("Instance ID is required")
        
        # Initialize EC2 client
        ec2_client = boto3.client('ec2', region_name=region)
        
        # Get current timestamp
        current_timestamp = datetime.utcnow().isoformat()
        
        # Define tags to apply
        compliance_tags = [
            {
                'Key': 'custodian:public-instance-detected',
                'Value': 'true'
            },
            {
                'Key': 'custodian:detection-timestamp',
                'Value': current_timestamp
            },
            {
                'Key': 'custodian:detected-by',
                'Value': discovered_by
            },
            {
                'Key': 'custodian:policy-name',
                'Value': policy_name
            },
            {
                'Key': 'custodian:stepfunction-processed',
                'Value': current_timestamp
            },
            {
                'Key': 'custodian:public-ip',
                'Value': public_ip
            },
            {
                'Key': 'custodian:compliance-status',
                'Value': 'NON_COMPLIANT'
            },
            {
                'Key': 'custodian:remediation-required',
                'Value': 'true'
            },
            {
                'Key': 'custodian:risk-category',
                'Value': 'PUBLIC_ACCESS'
            },
            {
                'Key': 'custodian:workflow-status',
                'Value': 'IN_PROGRESS'
            }
        ]
        
        # Get existing tags to preserve important ones
        try:
            response = ec2_client.describe_instances(InstanceIds=[instance_id])
            instance = response['Reservations'][0]['Instances'][0]
            existing_tags = instance.get('Tags', [])
            
            # Check for owner and project tags to preserve
            important_tags = ['Owner', 'Project', 'Environment', 'Name', 'Purpose']
            preserved_tags = []
            
            for tag in existing_tags:
                if tag['Key'] in important_tags:
                    preserved_tags.append(tag)
            
            logger.info(f"Preserving {len(preserved_tags)} important existing tags")
            
        except Exception as e:
            logger.warning(f"Could not retrieve existing tags: {str(e)}")
            preserved_tags = []
        
        # Combine compliance tags with preserved tags
        all_tags = compliance_tags + preserved_tags
        
        # Apply tags to the instance
        try:
            ec2_client.create_tags(
                Resources=[instance_id],
                Tags=all_tags
            )
            
            logger.info(f"Successfully applied {len(all_tags)} tags to instance {instance_id}")
            tagging_success = True
            applied_tags = all_tags
            
        except Exception as e:
            logger.error(f"Failed to apply tags to instance {instance_id}: {str(e)}")
            tagging_success = False
            applied_tags = []
        
        # Get security group analysis
        security_analysis = analyze_security_groups(ec2_client, instance_id)
        
        # Log tagging activity for audit trail
        audit_log = {
            "event_type": "public_ec2_tagging",
            "timestamp": current_timestamp,
            "instance_id": instance_id,
            "account_id": account_id,
            "region": region,
            "tagging_success": tagging_success,
            "tags_applied": len(applied_tags),
            "compliance_tags": len(compliance_tags),
            "preserved_tags": len(preserved_tags),
            "security_analysis": security_analysis,
            "discovered_by": discovered_by,
            "policy_name": policy_name
        }
        
        logger.info(f"Tagging audit log: {json.dumps(audit_log)}")
        
        # Return result for Step Function
        return {
            "statusCode": 200,
            "taggingSuccess": tagging_success,
            "instanceId": instance_id,
            "accountId": account_id,
            "region": region,
            "publicIp": public_ip,
            "appliedTags": applied_tags,
            "securityAnalysis": security_analysis,
            "timestamp": current_timestamp,
            "message": "Instance tagged successfully" if tagging_success else "Tagging failed",
            "auditLog": audit_log
        }
        
    except Exception as e:
        logger.error(f"Error in tagging function: {str(e)}")
        
        return {
            "statusCode": 500,
            "error": str(e),
            "instanceId": event.get('instanceId', 'Unknown'),
            "message": "Tagging function failed",
            "timestamp": datetime.utcnow().isoformat()
        }

def analyze_security_groups(ec2_client, instance_id: str) -> Dict[str, Any]:
    """
    Analyze security groups associated with the instance to assess risk.
    """
    try:
        # Get instance details
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        
        security_groups = instance.get('SecurityGroups', [])
        security_group_ids = [sg['GroupId'] for sg in security_groups]
        
        if not security_group_ids:
            return {"analysis": "No security groups found", "risk_score": 0}
        
        # Analyze each security group
        sg_response = ec2_client.describe_security_groups(GroupIds=security_group_ids)
        
        risk_factors = []
        total_risk_score = 0
        
        for sg in sg_response['SecurityGroups']:
            sg_analysis = analyze_single_security_group(sg)
            risk_factors.extend(sg_analysis['risk_factors'])
            total_risk_score += sg_analysis['risk_score']
        
        return {
            "security_groups_count": len(security_group_ids),
            "security_groups": security_group_ids,
            "risk_factors": risk_factors,
            "total_risk_score": total_risk_score,
            "risk_level": get_risk_level(total_risk_score),
            "analysis_timestamp": datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error analyzing security groups: {str(e)}")
        return {"error": str(e), "risk_score": 100}  # Assume high risk on error

def analyze_single_security_group(security_group: Dict[str, Any]) -> Dict[str, Any]:
    """
    Analyze a single security group for security risks.
    """
    risk_factors = []
    risk_score = 0
    
    group_id = security_group.get('GroupId', 'Unknown')
    group_name = security_group.get('GroupName', 'Unknown')
    
    # Check inbound rules
    for rule in security_group.get('IpPermissions', []):
        protocol = rule.get('IpProtocol', 'Unknown')
        from_port = rule.get('FromPort')
        to_port = rule.get('ToPort')
        
        # Check for 0.0.0.0/0 access
        for ip_range in rule.get('IpRanges', []):
            cidr = ip_range.get('CidrIp', '')
            if cidr == '0.0.0.0/0':
                if protocol == '-1':  # All traffic
                    risk_factors.append(f"SG {group_id}: All traffic allowed from 0.0.0.0/0")
                    risk_score += 50
                elif from_port == 22 or to_port == 22:  # SSH
                    risk_factors.append(f"SG {group_id}: SSH (22) open to 0.0.0.0/0")
                    risk_score += 30
                elif from_port == 3389 or to_port == 3389:  # RDP
                    risk_factors.append(f"SG {group_id}: RDP (3389) open to 0.0.0.0/0")
                    risk_score += 30
                elif from_port == 80 or to_port == 80:  # HTTP
                    risk_factors.append(f"SG {group_id}: HTTP (80) open to 0.0.0.0/0")
                    risk_score += 10
                elif from_port == 443 or to_port == 443:  # HTTPS
                    risk_factors.append(f"SG {group_id}: HTTPS (443) open to 0.0.0.0/0")
                    risk_score += 5
                else:
                    risk_factors.append(f"SG {group_id}: Port {from_port}-{to_port} open to 0.0.0.0/0")
                    risk_score += 15
    
    return {
        "group_id": group_id,
        "group_name": group_name,
        "risk_factors": risk_factors,
        "risk_score": risk_score
    }

def get_risk_level(risk_score: int) -> str:
    """
    Determine risk level based on total risk score.
    """
    if risk_score >= 50:
        return "HIGH"
    elif risk_score >= 20:
        return "MEDIUM"
    else:
        return "LOW"