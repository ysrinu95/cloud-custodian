#!/bin/bash

# Cloud Custodian EC2 Public Instance Demo
# This script creates public EC2 instances for Cloud Custodian to detect and manage

set -e

# Configuration
REGION="${AWS_REGION:-us-east-1}"
DEMO_PREFIX="custodian-ec2-demo"
DEMO_TAG_KEY="CustodianDemo"
DEMO_TAG_VALUE="EC2PublicInstanceTest"
MONITORING_DURATION="${MONITORING_DURATION:-15}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup_resources() {
    log_info "🧹 Cleaning up EC2 demo resources..."
    
    # Terminate demo EC2 instances
    local instances=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:$DEMO_TAG_KEY,Values=$DEMO_TAG_VALUE" "Name=instance-state-name,Values=running,pending" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$instances" && "$instances" != "None" ]]; then
        log_info "Terminating demo EC2 instances: $instances"
        aws ec2 terminate-instances --region "$REGION" --instance-ids $instances
        
        # Wait for termination
        log_info "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated --region "$REGION" --instance-ids $instances
    fi
    
    # Delete demo security groups
    local security_groups=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=tag:$DEMO_TAG_KEY,Values=$DEMO_TAG_VALUE" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$security_groups" && "$security_groups" != "None" ]]; then
        log_info "Deleting demo security groups: $security_groups"
        for sg in $security_groups; do
            aws ec2 delete-security-group --region "$REGION" --group-id "$sg" || true
        done
    fi
    
    # Delete demo key pairs
    local keypairs=$(aws ec2 describe-key-pairs \
        --region "$REGION" \
        --filters "Name=tag:$DEMO_TAG_KEY,Values=$DEMO_TAG_VALUE" \
        --query 'KeyPairs[].KeyName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$keypairs" && "$keypairs" != "None" ]]; then
        log_info "Deleting demo key pairs: $keypairs"
        for kp in $keypairs; do
            aws ec2 delete-key-pair --region "$REGION" --key-name "$kp" || true
        done
    fi
    
    log_success "EC2 demo cleanup completed"
}

create_public_ec2_instances() {
    log_info "🖥️ Creating public EC2 instances for Cloud Custodian detection..."
    
    # Get default VPC
    local vpc_id=$(aws ec2 describe-vpcs \
        --region "$REGION" \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [[ "$vpc_id" == "None" || -z "$vpc_id" ]]; then
        log_error "No default VPC found in region $REGION"
        return 1
    fi
    
    # Get public subnet
    local subnet_id=$(aws ec2 describe-subnets \
        --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=map-public-ip-on-launch,Values=true" \
        --query 'Subnets[0].SubnetId' \
        --output text)
    
    if [[ "$subnet_id" == "None" || -z "$subnet_id" ]]; then
        log_error "No public subnet found in default VPC"
        return 1
    fi
    
    # Create public security group
    log_info "Creating public security group..."
    local sg_id=$(aws ec2 create-security-group \
        --region "$REGION" \
        --group-name "$DEMO_PREFIX-public-sg" \
        --description "Public security group for EC2 demo" \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE},{Key=Name,Value=$DEMO_PREFIX-public-sg}]" \
        --query 'GroupId' \
        --output text)
    
    # Add public access rules
    log_warning "Adding public access rules (will trigger Cloud Custodian policies)..."
    
    # SSH access from internet
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0
    
    # HTTP access from internet
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0
    
    # HTTPS access from internet
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0
    
    # Get latest Amazon Linux 2 AMI
    local ami_id=$(aws ec2 describe-images \
        --region "$REGION" \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    log_info "Using AMI: $ami_id"
    
    # Create key pair
    local key_name="$DEMO_PREFIX-keypair"
    aws ec2 create-key-pair \
        --region "$REGION" \
        --key-name "$key_name" \
        --tag-specifications "ResourceType=key-pair,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE}]" \
        --query 'KeyMaterial' \
        --output text > "/tmp/$key_name.pem"
    
    chmod 600 "/tmp/$key_name.pem"
    
    # User data for web server
    cat > /tmp/user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

# Create a simple webpage
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Cloud Custodian EC2 Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f0f0f0; }
        .container { background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .warning { background-color: #fff3cd; padding: 15px; border-radius: 4px; border-left: 4px solid #ffc107; margin: 20px 0; }
        .info { background-color: #d1ecf1; padding: 15px; border-radius: 4px; border-left: 4px solid #17a2b8; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🖥️ Cloud Custodian EC2 Demo Instance</h1>
        <div class="warning">
            <strong>⚠️ Warning:</strong> This is a demo instance with public access!
        </div>
        <div class="info">
            <strong>ℹ️ Info:</strong> This instance was created to demonstrate Cloud Custodian's EC2 public instance detection and management capabilities.
        </div>
        <h2>Instance Details:</h2>
        <ul>
            <li><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></li>
            <li><strong>Public IP:</strong> <span id="public-ip">Loading...</span></li>
            <li><strong>Region:</strong> <span id="region">Loading...</span></li>
            <li><strong>Launch Time:</strong> <span id="launch-time">Loading...</span></li>
        </ul>
        
        <h2>Cloud Custodian Expected Actions:</h2>
        <ul>
            <li>🏷️ Tag instance with compliance status</li>
            <li>📧 Send notification to security team</li>
            <li>📊 Log to CloudWatch for monitoring</li>
            <li>🔄 Potentially stop/terminate if configured</li>
        </ul>
        
        <p><em>Generated at: $(date)</em></p>
    </div>
    
    <script>
        // Get instance metadata
        fetch('http://169.254.169.254/latest/meta-data/instance-id')
            .then(response => response.text())
            .then(data => document.getElementById('instance-id').textContent = data)
            .catch(() => document.getElementById('instance-id').textContent = 'Unable to fetch');
            
        fetch('http://169.254.169.254/latest/meta-data/public-ipv4')
            .then(response => response.text())
            .then(data => document.getElementById('public-ip').textContent = data)
            .catch(() => document.getElementById('public-ip').textContent = 'Unable to fetch');
            
        fetch('http://169.254.169.254/latest/meta-data/placement/region')
            .then(response => response.text())
            .then(data => document.getElementById('region').textContent = data)
            .catch(() => document.getElementById('region').textContent = 'Unable to fetch');
    </script>
</body>
</html>
HTML

# Log the startup
echo "$(date): Cloud Custodian demo web server started" >> /var/log/custodian-demo.log
EOF
    
    local instances=""
    
    # Create multiple instances for different scenarios
    log_info "Launching demo EC2 instances..."
    
    # Instance 1: Standard public instance
    local instance1=$(aws ec2 run-instances \
        --region "$REGION" \
        --image-id "$ami_id" \
        --count 1 \
        --instance-type t3.micro \
        --key-name "$key_name" \
        --security-group-ids "$sg_id" \
        --subnet-id "$subnet_id" \
        --associate-public-ip-address \
        --user-data file:///tmp/user-data.sh \
        --tag-specifications "ResourceType=instance,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE},{Key=Name,Value=$DEMO_PREFIX-public-web-server},{Key=Environment,Value=demo},{Key=Owner,Value=security-team}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    # Instance 2: Instance without proper tags (will trigger tagging policies)
    local instance2=$(aws ec2 run-instances \
        --region "$REGION" \
        --image-id "$ami_id" \
        --count 1 \
        --instance-type t3.micro \
        --key-name "$key_name" \
        --security-group-ids "$sg_id" \
        --subnet-id "$subnet_id" \
        --associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE},{Key=Name,Value=$DEMO_PREFIX-untagged-instance}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    # Instance 3: Instance with suspicious configuration
    local instance3=$(aws ec2 run-instances \
        --region "$REGION" \
        --image-id "$ami_id" \
        --count 1 \
        --instance-type t3.micro \
        --key-name "$key_name" \
        --security-group-ids "$sg_id" \
        --subnet-id "$subnet_id" \
        --associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE},{Key=Name,Value=$DEMO_PREFIX-suspicious-instance},{Key=Purpose,Value=testing},{Key=Department,Value=unknown}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    instances="$instance1,$instance2,$instance3"
    
    log_success "Created demo EC2 instances:"
    log_success "  • Public web server: $instance1"
    log_success "  • Untagged instance: $instance2"
    log_success "  • Suspicious instance: $instance3"
    
    # Wait for instances to be running
    log_info "Waiting for instances to be running..."
    aws ec2 wait instance-running --region "$REGION" --instance-ids $instance1 $instance2 $instance3
    
    # Get public IPs
    local public_ips=$(aws ec2 describe-instances \
        --region "$REGION" \
        --instance-ids $instance1 $instance2 $instance3 \
        --query 'Reservations[].Instances[].PublicIpAddress' \
        --output text)
    
    log_success "Instances are running with public IPs: $public_ips"
    
    # Clean up temporary files
    rm -f /tmp/user-data.sh /tmp/$key_name.pem
    
    echo "$instances,$sg_id,$public_ips"
}

monitor_custodian_actions() {
    local instances="$1"
    local duration="$2"
    
    log_info "📊 Monitoring Cloud Custodian actions for $duration minutes..."
    
    local end_time=$(($(date +%s) + duration * 60))
    local check_count=0
    
    while [[ $(date +%s) -lt $end_time ]]; do
        check_count=$((check_count + 1))
        
        log_info "Check #$check_count - Looking for Cloud Custodian actions..."
        
        # Check for new tags added by Cloud Custodian
        IFS=',' read -ra INSTANCE_ARRAY <<< "$instances"
        for instance in "${INSTANCE_ARRAY[@]}"; do
            local tags=$(aws ec2 describe-instances \
                --region "$REGION" \
                --instance-ids "$instance" \
                --query 'Reservations[0].Instances[0].Tags[?contains(Key, `custodian`) || contains(Key, `Custodian`)].{Key:Key,Value:Value}' \
                --output table 2>/dev/null || echo "")
            
            if [[ -n "$tags" && $(echo "$tags" | wc -l) -gt 3 ]]; then
                log_success "🏷️ Found Cloud Custodian tags on instance $instance!"
                echo "$tags"
                echo ""
            fi
        done
        
        # Check CloudWatch logs for Lambda function executions
        local lambda_logs=$(aws logs describe-log-groups \
            --region "$REGION" \
            --log-group-name-prefix "/aws/lambda/custodian" \
            --query 'logGroups[].logGroupName' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$lambda_logs" && "$lambda_logs" != "None" ]]; then
            log_info "Found Cloud Custodian Lambda logs: $(echo $lambda_logs | wc -w) functions"
            
            # Check recent log entries
            for log_group in $lambda_logs; do
                local recent_logs=$(aws logs filter-log-events \
                    --region "$REGION" \
                    --log-group-name "$log_group" \
                    --start-time "$(($(date +%s) - 300))000" \
                    --query 'events[0].message' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "$recent_logs" && "$recent_logs" != "None" ]]; then
                    log_success "📋 Recent activity in $log_group"
                fi
            done
        fi
        
        sleep 60
    done
}

generate_demo_report() {
    local instances="$1"
    local sg_id="$2"
    local public_ips="$3"
    
    log_info "📋 Generating EC2 Public Instance Demo Report..."
    
    cat << EOF

🖥️ EC2 Public Instance Demo Report
════════════════════════════════════════════════════════════════════════

📊 Demo Summary:
  • Region: $REGION
  • Demo Duration: $MONITORING_DURATION minutes
  • Instances Created: 3

🌐 Public Resources Created:
  • EC2 Instances: $instances
  • Security Group: $sg_id
  • Public IP Addresses: $public_ips

💻 Instance Details:
  • Public web server with HTTP/HTTPS access
  • Untagged instance (triggers tagging policies)
  • Suspicious instance with unknown department

⚠️ Expected Cloud Custodian Actions:
  • ec2-public-instances: Tag public instances
  • ec2-require-tags: Tag untagged instances
  • ec2-security-group-compliance: Review security groups
  • ec2-instance-lifecycle: Monitor instance states

🔍 Next Steps:
  1. Check AWS Lambda console for Cloud Custodian executions
  2. Review CloudWatch logs for policy actions
  3. Monitor instance tags for compliance updates
  4. Verify email notifications (if configured)

🌐 Test Web Access:
$(IFS=',' read -ra IP_ARRAY <<< "$public_ips"; for ip in "${IP_ARRAY[@]}"; do echo "  • http://$ip"; done)

🧹 Cleanup:
  Run: $0 --cleanup
  Or manually terminate instances: $instances

EOF
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

EC2 Public Instance Demo Script - Creates public EC2 instances for Cloud Custodian testing

OPTIONS:
    --region REGION         AWS region (default: us-east-1)
    --duration MINUTES      Monitoring duration in minutes (default: 15)
    --cleanup              Clean up demo resources and exit
    --help                 Show this help message

EXAMPLES:
    $0                           # Run full demo with defaults
    $0 --region us-west-2        # Run demo in us-west-2
    $0 --duration 30             # Monitor for 30 minutes
    $0 --cleanup                 # Clean up all demo resources

WARNING: This script creates real AWS resources that may incur costs.

EOF
}

main() {
    local cleanup_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                REGION="$2"
                shift 2
                ;;
            --duration)
                MONITORING_DURATION="$2"
                shift 2
                ;;
            --cleanup)
                cleanup_only=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    log_info "🖥️ Cloud Custodian EC2 Public Instance Demo"
    log_info "Region: $REGION"
    log_info "Monitoring Duration: $MONITORING_DURATION minutes"
    echo ""
    
    # Cleanup mode
    if [[ "$cleanup_only" == true ]]; then
        cleanup_resources
        log_success "🧹 Cleanup completed"
        exit 0
    fi
    
    # Trap to cleanup on exit
    trap cleanup_resources EXIT
    
    log_warning "⚠️ WARNING: This demo will create public EC2 instances!"
    log_warning "⚠️ These resources may incur AWS costs"
    log_info "Resources will be automatically cleaned up at the end"
    echo ""
    
    # Create public EC2 instances
    result=$(create_public_ec2_instances)
    IFS=',' read -r instances sg_id public_ips <<< "$result"
    
    # Monitor for Cloud Custodian actions
    monitor_custodian_actions "$instances" "$MONITORING_DURATION"
    
    # Generate report
    generate_demo_report "$instances" "$sg_id" "$public_ips"
    
    log_success "🎯 EC2 Public Instance Demo completed!"
    log_info "💡 Check the AWS EC2 console and Cloud Custodian logs for policy actions"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi