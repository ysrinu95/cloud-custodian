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
    Lambda function to monitor low-risk public EC2 instances and set up enhanced monitoring.
    """
    try:
        logger.info(f"Processing monitoring setup for event: {json.dumps(event, default=str)}")
        
        # Extract instance information from the event
        instance_id = event.get('instanceId', '')
        account_id = event.get('accountId', '')
        region = event.get('region', '')
        risk_level = event.get('riskLevel', 'UNKNOWN')
        risk_score = event.get('riskScore', 0)
        risk_factors = event.get('riskFactors', [])
        
        if not instance_id:
            raise ValueError("Instance ID is required")
        
        # Initialize AWS clients
        ec2_client = boto3.client('ec2', region_name=region)
        cloudwatch_client = boto3.client('cloudwatch', region_name=region)
        logs_client = boto3.client('logs', region_name=region)
        
        current_timestamp = datetime.utcnow().isoformat()
        
        # 1. Enable detailed monitoring on the instance
        monitoring_result = enable_detailed_monitoring(ec2_client, instance_id)
        
        # 2. Create custom CloudWatch alarms
        alarm_results = create_monitoring_alarms(cloudwatch_client, instance_id, region)
        
        # 3. Set up log monitoring (if possible)
        log_monitoring_result = setup_log_monitoring(logs_client, instance_id)
        
        # 4. Update instance tags for monitoring
        monitoring_tags = [
            {
                'Key': 'custodian:monitoring-enabled',
                'Value': 'true'
            },
            {
                'Key': 'custodian:monitoring-timestamp',
                'Value': current_timestamp
            },
            {
                'Key': 'custodian:risk-monitoring',
                'Value': f"Level:{risk_level},Score:{risk_score}"
            },
            {
                'Key': 'custodian:monitoring-alarms',
                'Value': str(len(alarm_results.get('created_alarms', [])))
            },
            {
                'Key': 'custodian:workflow-status',
                'Value': 'MONITORING'
            },
            {
                'Key': 'custodian:next-review',
                'Value': get_next_review_date()
            }
        ]
        
        try:
            ec2_client.create_tags(Resources=[instance_id], Tags=monitoring_tags)
            tagging_success = True
        except Exception as e:
            logger.error(f"Failed to apply monitoring tags: {str(e)}")
            tagging_success = False
        
        # 5. Create monitoring dashboard entry
        dashboard_result = create_monitoring_dashboard_entry(
            cloudwatch_client, instance_id, region
        )
        
        # Create comprehensive audit log
        audit_log = {
            "event_type": "public_ec2_monitoring_setup",
            "timestamp": current_timestamp,
            "instance_id": instance_id,
            "account_id": account_id,
            "region": region,
            "risk_level": risk_level,
            "risk_score": risk_score,
            "monitoring_enabled": monitoring_result['success'],
            "alarms_created": len(alarm_results.get('created_alarms', [])),
            "log_monitoring": log_monitoring_result['success'],
            "tagging_success": tagging_success,
            "dashboard_updated": dashboard_result['success']
        }
        
        logger.info(f"Monitoring audit log: {json.dumps(audit_log)}")
        
        # Return result for Step Function
        return {
            "statusCode": 200,
            "instanceId": instance_id,
            "accountId": account_id,
            "region": region,
            "riskLevel": risk_level,
            "riskScore": risk_score,
            "monitoringEnabled": monitoring_result['success'],
            "alarmsCreated": alarm_results.get('created_alarms', []),
            "logMonitoring": log_monitoring_result['success'],
            "dashboardUpdated": dashboard_result['success'],
            "nextReviewDate": get_next_review_date(),
            "message": "Monitoring setup completed successfully",
            "timestamp": current_timestamp,
            "auditLog": audit_log
        }
        
    except Exception as e:
        logger.error(f"Error in monitoring function: {str(e)}")
        
        return {
            "statusCode": 500,
            "error": str(e),
            "instanceId": event.get('instanceId', 'Unknown'),
            "message": "Monitoring function failed",
            "timestamp": datetime.utcnow().isoformat()
        }

def enable_detailed_monitoring(ec2_client, instance_id: str) -> Dict[str, Any]:
    """
    Enable detailed monitoring on the EC2 instance.
    """
    try:
        response = ec2_client.monitor_instances(InstanceIds=[instance_id])
        
        if response['InstanceMonitorings']:
            monitoring_state = response['InstanceMonitorings'][0]['Monitoring']['State']
            logger.info(f"Detailed monitoring enabled for {instance_id}: {monitoring_state}")
            return {"success": True, "state": monitoring_state}
        else:
            return {"success": False, "error": "No monitoring response"}
            
    except Exception as e:
        logger.error(f"Failed to enable detailed monitoring: {str(e)}")
        return {"success": False, "error": str(e)}

def create_monitoring_alarms(cloudwatch_client, instance_id: str, region: str) -> Dict[str, Any]:
    """
    Create CloudWatch alarms for monitoring the public instance.
    """
    created_alarms = []
    failed_alarms = []
    
    # Define alarms to create
    alarms = [
        {
            'AlarmName': f'PublicEC2-HighCPU-{instance_id}',
            'AlarmDescription': f'High CPU utilization on public instance {instance_id}',
            'MetricName': 'CPUUtilization',
            'Namespace': 'AWS/EC2',
            'Statistic': 'Average',
            'Period': 300,
            'EvaluationPeriods': 2,
            'Threshold': 80.0,
            'ComparisonOperator': 'GreaterThanThreshold'
        },
        {
            'AlarmName': f'PublicEC2-HighNetworkIn-{instance_id}',
            'AlarmDescription': f'High network traffic inbound on public instance {instance_id}',
            'MetricName': 'NetworkIn',
            'Namespace': 'AWS/EC2',
            'Statistic': 'Sum',
            'Period': 300,
            'EvaluationPeriods': 2,
            'Threshold': 1000000000,  # 1GB in 5 minutes
            'ComparisonOperator': 'GreaterThanThreshold'
        },
        {
            'AlarmName': f'PublicEC2-HighNetworkOut-{instance_id}',
            'AlarmDescription': f'High network traffic outbound on public instance {instance_id}',
            'MetricName': 'NetworkOut',
            'Namespace': 'AWS/EC2',
            'Statistic': 'Sum',
            'Period': 300,
            'EvaluationPeriods': 2,
            'Threshold': 1000000000,  # 1GB in 5 minutes
            'ComparisonOperator': 'GreaterThanThreshold'
        },
        {
            'AlarmName': f'PublicEC2-StatusCheckFailed-{instance_id}',
            'AlarmDescription': f'Status check failed on public instance {instance_id}',
            'MetricName': 'StatusCheckFailed',
            'Namespace': 'AWS/EC2',
            'Statistic': 'Maximum',
            'Period': 60,
            'EvaluationPeriods': 1,
            'Threshold': 0,
            'ComparisonOperator': 'GreaterThanThreshold'
        }
    ]
    
    for alarm in alarms:
        try:
            cloudwatch_client.put_metric_alarm(
                AlarmName=alarm['AlarmName'],
                AlarmDescription=alarm['AlarmDescription'],
                ActionsEnabled=True,
                AlarmActions=[
                    f"arn:aws:sns:{region}:123456789012:cloud-custodian-security-alerts"
                ],
                MetricName=alarm['MetricName'],
                Namespace=alarm['Namespace'],
                Statistic=alarm['Statistic'],
                Dimensions=[
                    {
                        'Name': 'InstanceId',
                        'Value': instance_id
                    }
                ],
                Period=alarm['Period'],
                EvaluationPeriods=alarm['EvaluationPeriods'],
                Threshold=alarm['Threshold'],
                ComparisonOperator=alarm['ComparisonOperator'],
                Tags=[
                    {
                        'Key': 'CreatedBy',
                        'Value': 'cloud-custodian-stepfunction'
                    },
                    {
                        'Key': 'InstanceId',
                        'Value': instance_id
                    },
                    {
                        'Key': 'Purpose',
                        'Value': 'PublicInstanceMonitoring'
                    }
                ]
            )
            
            created_alarms.append(alarm['AlarmName'])
            logger.info(f"Created alarm: {alarm['AlarmName']}")
            
        except Exception as e:
            logger.error(f"Failed to create alarm {alarm['AlarmName']}: {str(e)}")
            failed_alarms.append({"alarm": alarm['AlarmName'], "error": str(e)})
    
    return {
        "created_alarms": created_alarms,
        "failed_alarms": failed_alarms,
        "total_attempted": len(alarms)
    }

def setup_log_monitoring(logs_client, instance_id: str) -> Dict[str, Any]:
    """
    Set up log monitoring for the instance (if CloudWatch agent is installed).
    """
    try:
        # Create log group for this instance if it doesn't exist
        log_group_name = f'/aws/ec2/public-instance-monitoring/{instance_id}'
        
        try:
            logs_client.create_log_group(
                logGroupName=log_group_name,
                tags={
                    'CreatedBy': 'cloud-custodian-stepfunction',
                    'InstanceId': instance_id,
                    'Purpose': 'PublicInstanceMonitoring'
                }
            )
            logger.info(f"Created log group: {log_group_name}")
            
        except logs_client.exceptions.ResourceAlreadyExistsException:
            logger.info(f"Log group already exists: {log_group_name}")
        
        # Set retention policy
        logs_client.put_retention_policy(
            logGroupName=log_group_name,
            retentionInDays=30
        )
        
        return {"success": True, "log_group": log_group_name}
        
    except Exception as e:
        logger.error(f"Failed to setup log monitoring: {str(e)}")
        return {"success": False, "error": str(e)}

def create_monitoring_dashboard_entry(cloudwatch_client, instance_id: str, region: str) -> Dict[str, Any]:
    """
    Create or update CloudWatch dashboard for public instance monitoring.
    """
    try:
        dashboard_name = "PublicEC2InstanceMonitoring"
        
        # Define dashboard widget for this instance
        widget_definition = {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/EC2", "CPUUtilization", "InstanceId", instance_id],
                    [".", "NetworkIn", ".", "."],
                    [".", "NetworkOut", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": region,
                "title": f"Public Instance Monitoring - {instance_id}",
                "view": "timeSeries"
            }
        }
        
        # Try to get existing dashboard
        try:
            response = cloudwatch_client.get_dashboard(DashboardName=dashboard_name)
            dashboard_body = json.loads(response['DashboardBody'])
            widgets = dashboard_body.get('widgets', [])
            
            # Check if widget for this instance already exists
            widget_exists = any(
                instance_id in str(widget.get('properties', {}).get('metrics', []))
                for widget in widgets
            )
            
            if not widget_exists:
                widgets.append(widget_definition)
                dashboard_body['widgets'] = widgets
                
                cloudwatch_client.put_dashboard(
                    DashboardName=dashboard_name,
                    DashboardBody=json.dumps(dashboard_body)
                )
                logger.info(f"Updated dashboard with widget for {instance_id}")
            else:
                logger.info(f"Widget for {instance_id} already exists in dashboard")
                
        except cloudwatch_client.exceptions.ResourceNotFound:
            # Create new dashboard
            dashboard_body = {
                "widgets": [widget_definition]
            }
            
            cloudwatch_client.put_dashboard(
                DashboardName=dashboard_name,
                DashboardBody=json.dumps(dashboard_body)
            )
            logger.info(f"Created new dashboard with widget for {instance_id}")
        
        return {"success": True, "dashboard": dashboard_name}
        
    except Exception as e:
        logger.error(f"Failed to create/update dashboard: {str(e)}")
        return {"success": False, "error": str(e)}

def get_next_review_date() -> str:
    """
    Calculate next review date (7 days from now).
    """
    from datetime import timedelta
    next_review = datetime.utcnow() + timedelta(days=7)
    return next_review.isoformat() + 'Z'