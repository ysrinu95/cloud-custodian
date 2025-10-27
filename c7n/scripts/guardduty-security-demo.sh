#!/bin/bash

# Cloud Custodian GuardDuty Security Demo
# This script creates real vulnerable resources that GuardDuty will detect
# WARNING: This creates actual AWS resources that may incur costs

set -e

# Configuration
REGION="${AWS_REGION:-us-east-1}"
DEMO_PREFIX="custodian-guardduty-demo"
DEMO_TAG_KEY="CustodianDemo"
DEMO_TAG_VALUE="GuardDutySecurityTest"
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
    log_info "🧹 Cleaning up demo resources..."
    
    # Terminate demo EC2 instances
    local instances=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:$DEMO_TAG_KEY,Values=$DEMO_TAG_VALUE" "Name=instance-state-name,Values=running,pending" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$instances" && "$instances" != "None" ]]; then
        log_info "Terminating demo EC2 instances: $instances"
        aws ec2 terminate-instances --region "$REGION" --instance-ids $instances || true
        
        # Wait for termination
        log_info "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated --region "$REGION" --instance-ids $instances || true
    fi
    
    # Delete demo security groups (except default)
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
    
    log_success "Resource cleanup completed"
}

check_guardduty_status() {
    log_info "🔍 Checking GuardDuty status..."
    
    # Check if GuardDuty is enabled
    local detector_id=$(aws guardduty list-detectors \
        --region "$REGION" \
        --query 'DetectorIds[0]' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$detector_id" == "None" || -z "$detector_id" ]]; then
        log_error "GuardDuty is not enabled in region $REGION"
        log_info "Enabling GuardDuty detector..."
        
        detector_id=$(aws guardduty create-detector \
            --region "$REGION" \
            --enable \
            --query 'DetectorId' \
            --output text)
        
        log_success "GuardDuty enabled with detector ID: $detector_id"
    else
        local status=$(aws guardduty get-detector \
            --region "$REGION" \
            --detector-id "$detector_id" \
            --query 'Status' \
            --output text)
        
        log_success "GuardDuty detector found: $detector_id (Status: $status)"
    fi
    
    echo "$detector_id"
}

create_vulnerable_ec2() {
    log_info "🖥️ Creating vulnerable EC2 instances for GuardDuty detection..."
    
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
    
    # Get a public subnet
    local subnet_id=$(aws ec2 describe-subnets \
        --region "$REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=map-public-ip-on-launch,Values=true" \
        --query 'Subnets[0].SubnetId' \
        --output text)
    
    if [[ "$subnet_id" == "None" || -z "$subnet_id" ]]; then
        log_error "No public subnet found in default VPC"
        return 1
    fi
    
    # Create overly permissive security group
    log_info "Creating vulnerable security group..."
    local sg_id=$(aws ec2 create-security-group \
        --region "$REGION" \
        --group-name "$DEMO_PREFIX-vulnerable-sg" \
        --description "Vulnerable security group for GuardDuty demo - OPEN TO INTERNET" \
        --vpc-id "$vpc_id" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE},{Key=Name,Value=$DEMO_PREFIX-vulnerable-sg}]" \
        --query 'GroupId' \
        --output text)
    
    # Add dangerous rules that GuardDuty will flag
    log_warning "Adding dangerous security group rules (GuardDuty will detect these)..."
    
    # SSH open to the world (0.0.0.0/0)
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 || true
    
    # RDP open to the world
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 3389 \
        --cidr 0.0.0.0/0 || true
    
    # HTTP/HTTPS open to the world
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 || true
    
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 || true
    
    # Database ports open to the world (very dangerous)
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 3306 \
        --cidr 0.0.0.0/0 || true  # MySQL
    
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 5432 \
        --cidr 0.0.0.0/0 || true  # PostgreSQL
    
    # Get latest Amazon Linux 2 AMI
    local ami_id=$(aws ec2 describe-images \
        --region "$REGION" \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    log_info "Using AMI: $ami_id"
    
    # Create key pair for demo
    local key_name="$DEMO_PREFIX-keypair"
    aws ec2 create-key-pair \
        --region "$REGION" \
        --key-name "$key_name" \
        --tag-specifications "ResourceType=key-pair,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE},{Key=Name,Value=$key_name}]" \
        --query 'KeyMaterial' \
        --output text > "/tmp/$key_name.pem" || true
    
    chmod 600 "/tmp/$key_name.pem" || true
    
    # User data script to create suspicious activity
    cat > /tmp/user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y netcat-openbsd nmap

# Create a suspicious process that GuardDuty might detect
# Note: These are for demo purposes and will be flagged by GuardDuty
echo "*/5 * * * * /usr/bin/nmap -sS -O 8.8.8.8 > /dev/null 2>&1" | crontab -

# Create suspicious network activity (port scanning simulation)
cat > /tmp/suspicious_activity.sh << 'INNER_EOF'
#!/bin/bash
while true; do
    # Simulate cryptocurrency mining DNS queries (GuardDuty detects this)
    nslookup pool.minergate.com 8.8.8.8 > /dev/null 2>&1 || true
    nslookup stratum.f2pool.com 8.8.8.8 > /dev/null 2>&1 || true
    
    # Simulate malware C&C communication patterns
    nc -z -w1 suspicious-domain.example.com 443 > /dev/null 2>&1 || true
    
    sleep 300  # Wait 5 minutes between suspicious activities
done
INNER_EOF

chmod +x /tmp/suspicious_activity.sh
nohup /tmp/suspicious_activity.sh > /dev/null 2>&1 &

# Log the startup
echo "$(date): GuardDuty demo instance started with suspicious activities" >> /var/log/guardduty-demo.log
EOF
    
    # Launch vulnerable instance
    log_info "Launching vulnerable EC2 instance..."
    local instance_id=$(aws ec2 run-instances \
        --region "$REGION" \
        --image-id "$ami_id" \
        --count 1 \
        --instance-type t3.micro \
        --key-name "$key_name" \
        --security-group-ids "$sg_id" \
        --subnet-id "$subnet_id" \
        --associate-public-ip-address \
        --user-data file:///tmp/user-data.sh \
        --tag-specifications "ResourceType=instance,Tags=[{Key=$DEMO_TAG_KEY,Value=$DEMO_TAG_VALUE},{Key=Name,Value=$DEMO_PREFIX-vulnerable-instance},{Key=Purpose,Value=SecurityTesting}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    log_success "Vulnerable EC2 instance created: $instance_id"
    
    # Wait for instance to be running
    log_info "Waiting for instance to be running..."
    aws ec2 wait instance-running --region "$REGION" --instance-ids "$instance_id"
    
    # Get public IP
    local public_ip=$(aws ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    log_success "Instance is running with public IP: $public_ip"
    
    # Clean up temporary files
    rm -f /tmp/user-data.sh /tmp/$key_name.pem
    
    echo "$instance_id,$public_ip,$sg_id"
}

simulate_suspicious_activities() {
    local instance_id="$1"
    local public_ip="$2"
    
    log_info "🚨 Simulating suspicious activities that GuardDuty will detect..."
    
    # These activities are designed to trigger GuardDuty findings
    log_warning "Starting activities that will trigger GuardDuty alerts..."
    
    # 1. Simulated cryptocurrency mining activity
    log_info "Simulating cryptocurrency mining DNS queries..."
    for domain in "pool.minergate.com" "stratum.f2pool.com" "pool.supportxmr.com"; do
        nslookup "$domain" 8.8.8.8 > /dev/null 2>&1 || true
        sleep 2
    done
    
    # 2. Simulated malware communication
    log_info "Simulating malware C&C communication patterns..."
    for port in 443 80 8080; do
        nc -z -w1 suspicious-domain.example.com "$port" > /dev/null 2>&1 || true
        sleep 1
    done
    
    # 3. Simulated port scanning from external (if possible)
    log_info "Simulating suspicious network scanning..."
    if command -v nmap >/dev/null 2>&1; then
        # Scan the instance itself to generate suspicious activity
        nmap -sS -p 22,80,443 "$public_ip" > /dev/null 2>&1 || true
    fi
    
    # 4. Generate suspicious API calls
    log_info "Simulating suspicious AWS API activity..."
    
    # Unusual API calls that GuardDuty might flag
    aws sts get-caller-identity --region "$REGION" > /dev/null 2>&1 || true
    aws iam list-users --region "$REGION" --max-items 1 > /dev/null 2>&1 || true
    aws ec2 describe-security-groups --region "$REGION" --max-items 1 > /dev/null 2>&1 || true
    
    log_success "Suspicious activities simulation completed"
}

monitor_guardduty_findings() {
    local detector_id="$1"
    local duration="$2"
    
    log_info "📊 Monitoring GuardDuty findings for $duration minutes..."
    log_info "GuardDuty typically takes 15-30 minutes to generate findings"
    
    local end_time=$(($(date +%s) + duration * 60))
    local check_count=0
    
    while [[ $(date +%s) -lt $end_time ]]; do
        check_count=$((check_count + 1))
        
        log_info "Check #$check_count - Looking for new findings..."
        
        # Get findings from last hour
        local findings=$(aws guardduty list-findings \
            --region "$REGION" \
            --detector-id "$detector_id" \
            --finding-criteria '{"updatedAt":{"gte":'$(($(date +%s) - 3600))'000}}' \
            --query 'FindingIds' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$findings" && "$findings" != "None" && "$findings" != "" ]]; then
            local finding_count=$(echo "$findings" | wc -w)
            log_success "🚨 Found $finding_count GuardDuty findings!"
            
            # Get details of the first few findings
            local first_few_findings=$(echo "$findings" | head -n 3)
            for finding_id in $first_few_findings; do
                log_info "📋 Finding Details:"
                aws guardduty get-findings \
                    --region "$REGION" \
                    --detector-id "$detector_id" \
                    --finding-ids "$finding_id" \
                    --query 'Findings[0].{Type:Type,Severity:Severity,Title:Title,Description:Description}' \
                    --output table 2>/dev/null || true
                echo ""
            done
            
            if [[ $finding_count -gt 3 ]]; then
                log_info "... and $((finding_count - 3)) more findings"
            fi
            
            break
        else
            log_info "No new findings yet... (GuardDuty needs time to analyze)"
        fi
        
        sleep 60  # Check every minute
    done
    
    if [[ $(date +%s) -ge $end_time ]]; then
        log_warning "Monitoring period ended. GuardDuty may still be analyzing..."
        log_info "💡 Check the AWS GuardDuty console for findings over the next hour"
    fi
}

generate_demo_report() {
    local detector_id="$1"
    local instance_id="$2"
    local public_ip="$3"
    local sg_id="$4"
    
    log_info "📋 Generating GuardDuty Security Demo Report..."
    
    cat << EOF

🛡️ GuardDuty Security Demo Report
════════════════════════════════════════════════════════════════════════

📊 Demo Summary:
  • Region: $REGION
  • GuardDuty Detector: $detector_id
  • Demo Instance: $instance_id
  • Public IP: $public_ip
  • Security Group: $sg_id
  • Duration: $MONITORING_DURATION minutes

🚨 Vulnerable Resources Created:
  • EC2 instance with overly permissive security group
  • Security group allowing SSH (22) from 0.0.0.0/0
  • Security group allowing RDP (3389) from 0.0.0.0/0
  • Security group allowing database ports (3306, 5432) from 0.0.0.0/0
  • Instance configured with suspicious network activities

⚠️ Expected GuardDuty Findings:
  • UnauthorizedAPICall:EC2/MaliciousIPCaller
  • CryptoCurrency:EC2/BitcoinTool.B!DNS
  • Trojan:EC2/DropPoint!DNS
  • Recon:EC2/PortProbeUnprotectedPort
  • Policy:IAMUser/RootCredentialUsage

🔍 Next Steps:
  1. Check AWS GuardDuty console for findings
  2. Review Cloud Custodian policies for automated response
  3. Monitor for 30-60 minutes for complete analysis

⚠️ Important Notes:
  • This demo creates real vulnerable resources
  • Resources are tagged for easy identification
  • Cleanup script will remove all demo resources
  • Some findings may take 15-30 minutes to appear

🧹 Cleanup:
  Run: $0 --cleanup
  Or manually delete resources with tag: $DEMO_TAG_KEY=$DEMO_TAG_VALUE

EOF
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

GuardDuty Security Demo Script - Creates vulnerable AWS resources for GuardDuty testing

OPTIONS:
    --region REGION         AWS region (default: us-east-1)
    --duration MINUTES      Monitoring duration in minutes (default: 15)
    --cleanup              Clean up demo resources and exit
    --check-only           Only check GuardDuty status
    --help                 Show this help message

EXAMPLES:
    $0                           # Run full demo with defaults
    $0 --region us-west-2        # Run demo in us-west-2
    $0 --duration 30             # Monitor for 30 minutes
    $0 --cleanup                 # Clean up all demo resources
    $0 --check-only              # Just check GuardDuty status

WARNING: This script creates real AWS resources that may incur costs.
All resources are tagged with $DEMO_TAG_KEY=$DEMO_TAG_VALUE for easy identification.

EOF
}

main() {
    local cleanup_only=false
    local check_only=false
    
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
            --check-only)
                check_only=true
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
    
    log_info "🛡️ Cloud Custodian GuardDuty Security Demo"
    log_info "Region: $REGION"
    log_info "Monitoring Duration: $MONITORING_DURATION minutes"
    echo ""
    
    # Cleanup mode
    if [[ "$cleanup_only" == true ]]; then
        cleanup_resources
        log_success "🧹 Cleanup completed"
        exit 0
    fi
    
    # Check GuardDuty status
    detector_id=$(check_guardduty_status)
    
    if [[ "$check_only" == true ]]; then
        log_success "✅ GuardDuty check completed"
        exit 0
    fi
    
    # Trap to cleanup on exit
    trap cleanup_resources EXIT
    
    log_warning "⚠️ WARNING: This demo will create real vulnerable AWS resources!"
    log_warning "⚠️ These resources may incur AWS costs and will be flagged by GuardDuty"
    log_info "Resources will be automatically cleaned up at the end"
    echo ""
    
    # Create vulnerable resources
    result=$(create_vulnerable_ec2)
    IFS=',' read -r instance_id public_ip sg_id <<< "$result"
    
    # Simulate suspicious activities
    simulate_suspicious_activities "$instance_id" "$public_ip"
    
    # Monitor for findings
    monitor_guardduty_findings "$detector_id" "$MONITORING_DURATION"
    
    # Generate report
    generate_demo_report "$detector_id" "$instance_id" "$public_ip" "$sg_id"
    
    log_success "🎯 GuardDuty Security Demo completed!"
    log_info "💡 Check the AWS GuardDuty console for findings over the next hour"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi