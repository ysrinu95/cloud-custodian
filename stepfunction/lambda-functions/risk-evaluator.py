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
    Lambda function to evaluate security risk level of public EC2 instances.
    """
    try:
        logger.info(f"Processing risk evaluation for event: {json.dumps(event, default=str)}")
        
        # Extract instance information from the event
        instance_id = event.get('instanceId', '')
        account_id = event.get('accountId', '')
        region = event.get('region', '')
        public_ip = event.get('publicIp', 'Unknown')
        instance_type = event.get('instanceType', 'Unknown')
        security_groups = event.get('securityGroups', [])
        
        # Get security analysis from previous step if available
        security_analysis = event.get('taggingResult', {}).get('securityAnalysis', {})
        
        if not instance_id:
            raise ValueError("Instance ID is required")
        
        # Initialize AWS clients
        ec2_client = boto3.client('ec2', region_name=region)
        
        # Perform comprehensive risk evaluation
        risk_evaluation = perform_risk_assessment(
            ec2_client, instance_id, instance_type, public_ip, 
            security_groups, security_analysis
        )
        
        # Get current timestamp
        current_timestamp = datetime.utcnow().isoformat()
        
        # Log risk evaluation for audit trail
        audit_log = {
            "event_type": "public_ec2_risk_evaluation",
            "timestamp": current_timestamp,
            "instance_id": instance_id,
            "account_id": account_id,
            "region": region,
            "public_ip": public_ip,
            "instance_type": instance_type,
            "risk_evaluation": risk_evaluation
        }
        
        logger.info(f"Risk evaluation audit log: {json.dumps(audit_log)}")
        
        # Return result for Step Function
        return {
            "statusCode": 200,
            "instanceId": instance_id,
            "accountId": account_id,
            "region": region,
            "publicIp": public_ip,
            "riskLevel": risk_evaluation['risk_level'],
            "riskScore": risk_evaluation['total_risk_score'],
            "riskFactors": risk_evaluation['risk_factors'],
            "recommendations": risk_evaluation['recommendations'],
            "immediateAction": risk_evaluation['immediate_action'],
            "timestamp": current_timestamp,
            "message": "Risk evaluation completed successfully",
            "auditLog": audit_log
        }
        
    except Exception as e:
        logger.error(f"Error in risk evaluation function: {str(e)}")
        
        return {
            "statusCode": 500,
            "error": str(e),
            "instanceId": event.get('instanceId', 'Unknown'),
            "riskLevel": "HIGH",  # Default to high risk on error
            "message": "Risk evaluation function failed",
            "timestamp": datetime.utcnow().isoformat()
        }

def perform_risk_assessment(ec2_client, instance_id: str, instance_type: str, 
                          public_ip: str, security_groups: list, 
                          security_analysis: Dict[str, Any]) -> Dict[str, Any]:
    """
    Perform comprehensive risk assessment of the public EC2 instance.
    """
    risk_factors = []
    risk_score = 0
    recommendations = []
    
    try:
        # Get detailed instance information
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        
        # 1. Check instance type risk
        instance_risk = assess_instance_type_risk(instance_type)
        risk_factors.extend(instance_risk['factors'])
        risk_score += instance_risk['score']
        recommendations.extend(instance_risk['recommendations'])
        
        # 2. Check security group configuration
        if security_analysis and 'risk_factors' in security_analysis:
            sg_risk_factors = security_analysis['risk_factors']
            sg_risk_score = security_analysis.get('total_risk_score', 0)
            
            risk_factors.extend(sg_risk_factors)
            risk_score += sg_risk_score
            
            if sg_risk_score > 30:
                recommendations.append("Immediately review and restrict security group rules")
            elif sg_risk_score > 10:
                recommendations.append("Review security group configuration for potential restrictions")
        
        # 3. Check for critical ports exposure
        critical_ports_risk = assess_critical_ports_exposure(ec2_client, instance_id)
        risk_factors.extend(critical_ports_risk['factors'])
        risk_score += critical_ports_risk['score']
        recommendations.extend(critical_ports_risk['recommendations'])
        
        # 4. Check instance metadata and configuration
        metadata_risk = assess_instance_metadata(instance)
        risk_factors.extend(metadata_risk['factors'])
        risk_score += metadata_risk['score']
        recommendations.extend(metadata_risk['recommendations'])
        
        # 5. Check for compliance tags and approvals
        compliance_risk = assess_compliance_status(instance)
        risk_factors.extend(compliance_risk['factors'])
        risk_score += compliance_risk['score']
        recommendations.extend(compliance_risk['recommendations'])
        
        # 6. Geographic and network location risk
        location_risk = assess_location_risk(instance)
        risk_factors.extend(location_risk['factors'])
        risk_score += location_risk['score']
        recommendations.extend(location_risk['recommendations'])
        
    except Exception as e:
        logger.error(f"Error during detailed risk assessment: {str(e)}")
        risk_factors.append(f"Error retrieving instance details: {str(e)}")
        risk_score += 25  # Add risk for inability to assess
        recommendations.append("Manual investigation required due to API errors")
    
    # Determine overall risk level
    risk_level = determine_risk_level(risk_score)
    immediate_action = determine_immediate_action(risk_level, risk_factors)
    
    return {
        "risk_level": risk_level,
        "total_risk_score": risk_score,
        "risk_factors": risk_factors,
        "recommendations": recommendations,
        "immediate_action": immediate_action,
        "assessment_timestamp": datetime.utcnow().isoformat()
    }

def assess_instance_type_risk(instance_type: str) -> Dict[str, Any]:
    """
    Assess risk based on instance type and capabilities.
    """
    factors = []
    score = 0
    recommendations = []
    
    # High-performance instances are higher risk when public
    if any(prefix in instance_type for prefix in ['p3', 'p4', 'x1', 'r5']):
        factors.append(f"High-performance instance type ({instance_type}) exposed publicly")
        score += 15
        recommendations.append("Consider using private subnets for high-performance workloads")
    
    # GPU instances
    if any(prefix in instance_type for prefix in ['p2', 'p3', 'p4', 'g3', 'g4']):
        factors.append(f"GPU instance ({instance_type}) with public access")
        score += 10
        recommendations.append("GPU instances should typically be in private networks")
    
    # Large instances
    if any(size in instance_type for size in ['xlarge', '2xlarge', '4xlarge']):
        factors.append(f"Large instance size ({instance_type}) exposed publicly")
        score += 8
        recommendations.append("Large instances represent higher value targets")
    
    return {
        "factors": factors,
        "score": score,
        "recommendations": recommendations
    }

def assess_critical_ports_exposure(ec2_client, instance_id: str) -> Dict[str, Any]:
    """
    Check for exposure of critical ports and services.
    """
    factors = []
    score = 0
    recommendations = []
    
    critical_ports = {
        22: ("SSH", 25),
        3389: ("RDP", 25),
        23: ("Telnet", 30),
        21: ("FTP", 20),
        135: ("RPC", 15),
        445: ("SMB", 20),
        1433: ("SQL Server", 20),
        3306: ("MySQL", 15),
        5432: ("PostgreSQL", 15),
        6379: ("Redis", 15),
        27017: ("MongoDB", 15)
    }
    
    try:
        # This would require more detailed network analysis
        # For now, we'll base this on security group analysis
        factors.append("Critical ports exposure assessment requires security group analysis")
        recommendations.append("Review all open ports and restrict to necessary services only")
        
    except Exception as e:
        logger.warning(f"Could not assess port exposure: {str(e)}")
    
    return {
        "factors": factors,
        "score": score,
        "recommendations": recommendations
    }

def assess_instance_metadata(instance: Dict[str, Any]) -> Dict[str, Any]:
    """
    Assess risk based on instance metadata and configuration.
    """
    factors = []
    score = 0
    recommendations = []
    
    # Check for public DNS name
    if instance.get('PublicDnsName'):
        factors.append("Instance has public DNS name")
        score += 5
    
    # Check launch time (recently launched instances might be test/temporary)
    launch_time = instance.get('LaunchTime')
    if launch_time:
        from datetime import timezone
        now = datetime.now(timezone.utc)
        launch_datetime = launch_time if isinstance(launch_time, datetime) else datetime.fromisoformat(launch_time.replace('Z', '+00:00'))
        
        hours_since_launch = (now - launch_datetime).total_seconds() / 3600
        
        if hours_since_launch < 2:
            factors.append("Instance launched very recently (< 2 hours)")
            score += 10
            recommendations.append("Verify if this is a legitimate launch or potential security incident")
        elif hours_since_launch < 24:
            factors.append("Instance launched recently (< 24 hours)")
            score += 5
            recommendations.append("Confirm instance purpose and necessity of public access")
    
    # Check for instance profile/IAM role
    if not instance.get('IamInstanceProfile'):
        factors.append("No IAM instance profile attached")
        score += 10
        recommendations.append("Attach appropriate IAM role with minimal permissions")
    
    # Check monitoring state
    monitoring = instance.get('Monitoring', {})
    if monitoring.get('State') != 'enabled':
        factors.append("Detailed monitoring not enabled")
        score += 5
        recommendations.append("Enable detailed monitoring for better security visibility")
    
    return {
        "factors": factors,
        "score": score,
        "recommendations": recommendations
    }

def assess_compliance_status(instance: Dict[str, Any]) -> Dict[str, Any]:
    """
    Check for compliance-related tags and approvals.
    """
    factors = []
    score = 0
    recommendations = []
    
    tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
    
    # Check for approval tags
    approval_tags = ['custodian:approved', 'security:approved', 'public-access:approved']
    has_approval = any(tag in tags for tag in approval_tags)
    
    if not has_approval:
        factors.append("No security approval tags found")
        score += 15
        recommendations.append("Add appropriate approval tags if public access is legitimate")
    
    # Check for owner information
    owner_tags = ['Owner', 'owner', 'responsible-party', 'contact']
    has_owner = any(tag in tags for tag in owner_tags)
    
    if not has_owner:
        factors.append("No owner/contact information in tags")
        score += 10
        recommendations.append("Add owner/contact tags for accountability")
    
    # Check for environment tags
    env_tags = ['Environment', 'environment', 'env', 'stage']
    environment = None
    for tag in env_tags:
        if tag in tags:
            environment = tags[tag].lower()
            break
    
    if environment in ['prod', 'production']:
        factors.append("Production instance with public access")
        score += 20
        recommendations.append("Production instances should rarely have public access")
    elif environment in ['dev', 'development', 'test', 'staging']:
        factors.append("Development/test instance with public access")
        score += 5
        recommendations.append("Consider if public access is necessary for dev/test environments")
    elif not environment:
        factors.append("No environment tag specified")
        score += 8
        recommendations.append("Add environment tags for proper classification")
    
    return {
        "factors": factors,
        "score": score,
        "recommendations": recommendations
    }

def assess_location_risk(instance: Dict[str, Any]) -> Dict[str, Any]:
    """
    Assess risk based on network location and availability zone.
    """
    factors = []
    score = 0
    recommendations = []
    
    # Check subnet type (would need additional VPC analysis)
    subnet_id = instance.get('SubnetId')
    if subnet_id:
        factors.append(f"Instance in subnet {subnet_id}")
        recommendations.append("Verify subnet is intended for public instances")
    
    # Check availability zone for geographic considerations
    az = instance.get('Placement', {}).get('AvailabilityZone')
    if az:
        factors.append(f"Instance in availability zone {az}")
    
    return {
        "factors": factors,
        "score": score,
        "recommendations": recommendations
    }

def determine_risk_level(risk_score: int) -> str:
    """
    Determine overall risk level based on total risk score.
    """
    if risk_score >= 60:
        return "HIGH"
    elif risk_score >= 30:
        return "MEDIUM"
    else:
        return "LOW"

def determine_immediate_action(risk_level: str, risk_factors: list) -> str:
    """
    Determine what immediate action should be taken.
    """
    if risk_level == "HIGH":
        return "STOP_INSTANCE"
    elif risk_level == "MEDIUM":
        if any("SSH" in factor or "RDP" in factor for factor in risk_factors):
            return "IMMEDIATE_REVIEW"
        else:
            return "SCHEDULED_REVIEW"
    else:
        return "MONITOR"