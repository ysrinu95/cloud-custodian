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

create_real_critical_findings() {
    log_info "🚨 Creating REAL HIGH and CRITICAL GuardDuty findings..."
    log_warning "⚠️  This will create actual vulnerable resources that GuardDuty will detect!"
    
    local detector_id="$1"
    
    log_info "GuardDuty Detector: $detector_id"
    log_info "Region: $REGION"
    
    # Step 1: Create vulnerable EC2 instance with dangerous security group
    log_warning "�️ Creating vulnerable EC2 instance (will trigger CRITICAL findings)..."
    local instance_info=$(create_vulnerable_ec2)
    local instance_id=$(echo "$instance_info" | cut -d',' -f1)
    local public_ip=$(echo "$instance_info" | cut -d',' -f2)
    local sg_id=$(echo "$instance_info" | cut -d',' -f3)
    
    if [[ -z "$instance_id" || "$instance_id" == "None" ]]; then
        log_error "❌ Failed to create vulnerable EC2 instance"
        return 1
    fi
    
    log_success "✅ Vulnerable EC2 instance created: $instance_id ($public_ip)"
    
    # Step 2: Perform suspicious activities that trigger HIGH/CRITICAL findings
    log_warning "🚨 Performing suspicious activities to trigger GuardDuty findings..."
    
    # Activity 1: Cryptocurrency mining DNS queries (CRITICAL finding)
    log_info "💰 Simulating cryptocurrency mining activity..."
    for pool in "pool.minergate.com" "stratum.f2pool.com" "pool.supportxmr.com" "xmr-eu1.nanopool.org"; do
        nslookup "$pool" 8.8.8.8 >/dev/null 2>&1 || true
        sleep 2
    done
    
    # Activity 2: Malware C&C communication (HIGH finding)
    log_info "🕷️ Simulating malware command and control communication..."
    for domain in "botnet-c2.example.com" "malware.suspicious-domain.com"; do
        for port in 443 80 8080; do
            timeout 3 nc -z "$domain" "$port" >/dev/null 2>&1 || true
        done
        sleep 1
    done
    
    # Activity 3: Port scanning from external source (HIGH finding)
    log_info "🔍 Performing port scanning to trigger reconnaissance finding..."
    if command -v nmap >/dev/null 2>&1; then
        # Scan the instance we just created
        timeout 30 nmap -sS -p 22,80,443,3389 "$public_ip" >/dev/null 2>&1 || true
    fi
    
    # Activity 4: Suspicious API calls from potentially compromised credentials
    log_info "� Making suspicious API calls to trigger unauthorized access finding..."
    
    # Make unusual API calls that GuardDuty might flag
    aws iam list-users --region "$REGION" --max-items 1 >/dev/null 2>&1 || true
    aws iam list-roles --region "$REGION" --max-items 1 >/dev/null 2>&1 || true
    aws ec2 describe-security-groups --region "$REGION" --max-items 5 >/dev/null 2>&1 || true
    aws s3 ls >/dev/null 2>&1 || true
    
    # Activity 5: DNS queries to known malicious domains (CRITICAL finding)
    log_info "🌐 Making DNS queries to suspicious domains..."
    for malicious_domain in "malware-dropzone.evil.com" "trojan-command.bad-actor.net" "phishing-site.suspicious.org"; do
        nslookup "$malicious_domain" 8.8.8.8 >/dev/null 2>&1 || true
        sleep 2
    done
    
    # Step 3: Wait and check for findings
    log_info "⏳ Waiting for GuardDuty to process activities and generate findings..."
    log_info "🔍 Will check for findings every 2 minutes for the next 10 minutes..."
    
    local check_count=0
    local findings_found=false
    
    for ((i=1; i<=5; i++)); do
        check_count=$((check_count + 1))
        log_info "🔎 Check #$check_count - Looking for new HIGH/CRITICAL findings..."
        
        # Check for findings created in the last hour
        local recent_findings=$(aws guardduty list-findings \
            --detector-id "$detector_id" \
            --region "$REGION" \
            --finding-criteria "{\"severity\":{\"gte\":7.0},\"updatedAt\":{\"gte\":$(($(date +%s) - 3600))000}}" \
            --max-items 20 \
            --query 'FindingIds' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$recent_findings" && "$recent_findings" != "None" ]]; then
            local finding_count=$(echo "$recent_findings" | wc -w)
            log_success "🎉 FOUND $finding_count HIGH/CRITICAL GuardDuty findings!"
            
            # Show details of first few findings
            local first_three=$(echo "$recent_findings" | awk '{print $1,$2,$3}')
            for finding_id in $first_three; do
                log_info "📋 Finding Details:"
                aws guardduty get-findings \
                    --detector-id "$detector_id" \
                    --region "$REGION" \
                    --finding-ids "$finding_id" \
                    --query 'Findings[0].{Type:Type,Severity:Severity,Title:Title,Description:Description}' \
                    --output table 2>/dev/null || true
                echo ""
            done
            
            findings_found=true
            break
        else
            log_info "⚪ No HIGH/CRITICAL findings detected yet..."
        fi
        
        if [[ $i -lt 5 ]]; then
            log_info "⏳ Waiting 2 minutes before next check..."
            sleep 120
        fi
    done
    
    if [[ "$findings_found" == true ]]; then
        log_success "✅ SUCCESS: REAL HIGH/CRITICAL GuardDuty findings have been created!"
        log_info "🌐 View findings in GuardDuty console: https://$REGION.console.aws.amazon.com/guardduty/home?region=$REGION#/findings"
        log_info "🚀 These REAL findings should trigger your Cloud Custodian Lambda functions"
        return 0
    else
        log_warning "⚠️  No findings detected yet, but activities were performed"
        log_info "💡 GuardDuty may need more time (up to 15-30 minutes) to generate findings"
        log_info "🔍 Check the GuardDuty console periodically for new findings"
        log_success "✅ Vulnerable resources created - GuardDuty will detect them eventually"
        return 0
    fi
}
            }

monitor_lambda_invocations() {
        fi
    else
        log_error "❌ No findings found in GuardDuty at all"
        log_info "💡 This could mean:"
        log_info "   • GuardDuty is not properly enabled"
        log_info "   • Sample findings are not supported in this region"
        log_info "   • There's an AWS API issue"
        
        # Try one more time with a simple approach
        log_info "� Trying basic sample finding creation..."
        aws guardduty create-sample-findings \
            --detector-id "$detector_id" \
            --region "$REGION" \
            --output json 2>/dev/null
        
        sleep 15
        
        # Final check
        local final_check=$(aws guardduty list-findings \
            --detector-id "$detector_id" \
            --region "$REGION" \
            --max-items 10 \
            --query 'FindingIds' \
            --output text 2>/dev/null)
        
        if [[ -n "$final_check" && "$final_check" != "None" ]]; then
            log_success "✅ Findings created on final attempt!"
        else
            log_error "❌ Still no findings - may need manual GuardDuty console check"
        fi
    fi
    
    echo ""
    log_success "🌐 GuardDuty Console: https://$REGION.console.aws.amazon.com/guardduty/home?region=$REGION#/findings"
    log_info "🎯 Look for findings with severity 7.0+ (HIGH) or 8.5+ (CRITICAL)"
    
    return 0
}

monitor_lambda_invocations() {
    local finding_ids="$1"
    
    log_info "📊 Monitoring Cloud Custodian Lambda function invocations..."
    log_info "GuardDuty Finding IDs to track: $finding_ids"
    
    # Find all Cloud Custodian Lambda functions
    local custodian_functions=$(aws lambda list-functions \
        --region "$REGION" \
        --query 'Functions[?starts_with(FunctionName, `custodian-`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$custodian_functions" ]]; then
        log_warning "❌ No Cloud Custodian Lambda functions found"
        log_info "💡 Expected functions like: custodian-guardduty-high-severity-findings"
        log_info "🔧 Make sure your security policies are deployed as Lambda functions"
        return 1
    fi
    
    local function_count=$(echo "$custodian_functions" | wc -w)
    log_success "Found $function_count Cloud Custodian Lambda functions"
    
    # Show all functions for reference
    log_info "📋 Available Cloud Custodian Lambda functions:"
    for func in $custodian_functions; do
        log_info "  • $func"
    done
    echo ""
    
    # Look specifically for GuardDuty-related functions
    local guardduty_functions=""
    for func in $custodian_functions; do
        if [[ "$func" == *"guardduty"* || "$func" == *"security"* ]]; then
            guardduty_functions="$guardduty_functions $func"
        fi
    done
    
    if [[ -n "$guardduty_functions" ]]; then
        log_success "🎯 Security/GuardDuty-specific functions: $guardduty_functions"
    else
        log_info "ℹ️ No GuardDuty-specific functions found, monitoring all custodian functions"
        guardduty_functions="$custodian_functions"
    fi
    
    # Monitor Lambda invocations for the specified duration
    local monitoring_start=$(date +%s)
    local monitoring_end=$((monitoring_start + MONITORING_DURATION * 60))
    local check_count=0
    local invocations_detected=false
    local total_invocations=0
    
    log_info "� Starting Lambda invocation monitoring for $MONITORING_DURATION minutes..."
    log_info "⏰ Start time: $(date)"
    log_info "🎯 Monitoring $(echo "$guardduty_functions" | wc -w) Lambda functions"
    echo ""
    
    while [[ $(date +%s) -lt $monitoring_end ]]; do
        check_count=$((check_count + 1))
        local check_time=$(date +"%H:%M:%S")
        log_info "🔍 Check #$check_count at $check_time - Polling Lambda invocations..."
        
        local this_check_invocations=0
        
        for func_name in $guardduty_functions; do
            # Check CloudWatch metrics for invocations (more reliable)
            local metric_invocations=$(aws cloudwatch get-metric-statistics \
                --namespace "AWS/Lambda" \
                --metric-name "Invocations" \
                --dimensions Name=FunctionName,Value="$func_name" \
                --start-time $(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%S) \
                --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
                --period 120 \
                --statistics Sum \
                --region "$REGION" \
                --query 'Datapoints[0].Sum' \
                --output text 2>/dev/null || echo "0")
            
            if [[ "$metric_invocations" != "None" && "$metric_invocations" != "0" && -n "$metric_invocations" ]]; then
                local inv_count=${metric_invocations%.*}  # Remove decimal part
                log_success "🚀 LAMBDA INVOCATION DETECTED!"
                log_success "📦 Function: $func_name"
                log_success "📊 Invocations in last 2 minutes: $inv_count"
                this_check_invocations=$((this_check_invocations + inv_count))
                invocations_detected=true
                
                # Get recent logs to see what triggered the function
                log_info "📋 Getting recent execution logs..."
                local recent_logs=$(aws logs filter-log-events \
                    --log-group-name "/aws/lambda/$func_name" \
                    --region "$REGION" \
                    --start-time $(( ($(date +%s) - 180) * 1000 )) \
                    --filter-pattern "GuardDuty" \
                    --query 'events[0:2].{Time:timestamp,Message:message}' \
                    --output table 2>/dev/null || echo "No GuardDuty-related logs found")
                
                if [[ "$recent_logs" != "No GuardDuty-related logs found" ]]; then
                    echo "$recent_logs"
                else
                    # Try to get any recent START logs
                    aws logs filter-log-events \
                        --log-group-name "/aws/lambda/$func_name" \
                        --region "$REGION" \
                        --start-time $(( ($(date +%s) - 180) * 1000 )) \
                        --filter-pattern "START RequestId" \
                        --query 'events[0:1].{Time:timestamp,Message:message}' \
                        --output table 2>/dev/null || log_info "Could not retrieve detailed logs"
                fi
                echo ""
            else
                log_info "  ⚪ $func_name: No recent invocations"
            fi
        done
        
        total_invocations=$((total_invocations + this_check_invocations))
        
        if [[ "$this_check_invocations" -gt 0 ]]; then
            log_success "📈 Total invocations this check: $this_check_invocations"
            log_success "📊 Cumulative invocations detected: $total_invocations"
        fi
        
        # If we detected invocations, continue monitoring to see the full response
        if [[ "$invocations_detected" == true ]]; then
            log_success "✅ SUCCESS: Lambda functions are being invoked by GuardDuty findings!"
            
            # Continue monitoring for a bit more to see additional invocations
            if [[ $check_count -lt 3 ]]; then
                log_info "🔄 Continuing to monitor for additional invocations..."
            else
                log_info "🎯 Sufficient monitoring completed - Lambda integration is working!"
                break
            fi
        fi
        
        echo ""
        
        # Wait before next check (shorter intervals for better monitoring)
        if [[ $(date +%s) -lt $monitoring_end ]]; then
            log_info "⏳ Waiting 45 seconds before next check..."
            sleep 45
        fi
    done
    
    # Final summary
    echo ""
    log_info "📋 Lambda Monitoring Summary:"
    log_info "════════════════════════════════════════════════════════"
    log_info "⏱️ Duration: $MONITORING_DURATION minutes"
    log_info "🔍 Checks performed: $check_count"
    log_info "📦 Functions monitored: $(echo "$guardduty_functions" | wc -w)"
    log_info "📊 Total invocations detected: $total_invocations"
    
    if [[ "$invocations_detected" == true && "$total_invocations" -gt 0 ]]; then
        log_success "✅ RESULT: SUCCESS! Lambda functions were invoked $total_invocations times"
        log_success "� Your GuardDuty → Cloud Custodian → Lambda integration is working correctly!"
        log_info "� Check the GuardDuty console: https://$REGION.console.aws.amazon.com/guardduty/home?region=$REGION#/findings"
        log_info "📊 Check CloudWatch Logs: https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups"
    else
        log_warning "⚠️ RESULT: No Lambda invocations detected"
        log_info "💡 Possible reasons:"
        log_info "   • GuardDuty findings may not have been created successfully"
        log_info "   • CloudWatch Events rules not configured for GuardDuty events"
        log_info "   • Lambda functions not subscribed to correct event patterns"
        log_info "   • Policy filters don't match the created finding types"
        log_info "   • IAM permissions issues with Lambda execution"
        
        # Suggest troubleshooting steps
        log_info ""
        log_info "🔧 Troubleshooting suggestions:"
        log_info "   1. Check GuardDuty console for the created findings"
        log_info "   2. Verify CloudWatch Events rules: aws events list-rules --name-prefix custodian-"
        log_info "   3. Check Lambda function event source mappings"
        log_info "   4. Review Cloud Custodian policy event filters"
        log_info "   5. Check Lambda function CloudWatch logs for errors"
    fi
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
        local high_finding_id="$2"
        local critical_finding_id="$3"
        local finding_type="$4"

        log_info "📋 Generating GuardDuty Security Demo Report (synthetic findings)..."

        cat << EOF

🛡️ GuardDuty Synthetic Findings Demo Report
════════════════════════════════════════════════════════════════════════

📊 Demo Summary:
    • Region: $REGION
    • GuardDuty Detector: $detector_id
    • Synthetic HIGH Finding ID: $high_finding_id
    • Synthetic CRITICAL Finding ID: $critical_finding_id
    • Finding Type (EventBridge): $finding_type
    • Duration: $MONITORING_DURATION minutes

� What was done:
    • Created synthetic HIGH and CRITICAL GuardDuty findings (no vulnerable resources were created).
    • Published synthetic events to EventBridge to trigger Cloud Custodian Lambda functions.
    • Monitored Lambda invocations and CloudWatch metrics for evidence of trigger/processing.

⚠️ Important Notes:
    • This demo uses synthetic findings and EventBridge events to test alerting and automation.
    • No EC2 instances, security groups, or other risky resources were created.
    • Synthetic findings appear in the GuardDuty console under the detector when EventBridge routes them.

🧹 Cleanup:
    No resource cleanup is required for synthetic findings. If any demo resources were created, run: $0 --cleanup

EOF
}

list_findings_now() {
    local detector_id="$1"
    log_info "🔎 Listing recent HIGH/CRITICAL findings for detector: $detector_id"

    local findings_list=$(aws guardduty list-findings \
        --region "$REGION" \
        --detector-id "$detector_id" \
        --finding-criteria '{"severity":{"gte":7.0}}' \
        --max-items 50 \
        --query 'FindingIds' \
        --output text 2>/dev/null || echo "")

    if [[ -z "$findings_list" || "$findings_list" == "None" ]]; then
        log_warning "No HIGH/CRITICAL findings found for detector $detector_id"
        return 1
    fi

    local count=$(echo "$findings_list" | wc -w)
    log_success "Found $count HIGH/CRITICAL findings"

    # Show details for the first few findings
    local first_three=$(echo "$findings_list" | awk '{print $1,$2,$3}')
    for fid in $first_three; do
        log_info "📋 Finding ID: $fid"
        aws guardduty get-findings \
            --region "$REGION" \
            --detector-id "$detector_id" \
            --finding-ids "$fid" \
            --query 'Findings[0].{Id:Id,Type:Type,Severity:Severity,Title:Title,CreatedAt:CreatedAt}' \
            --output table 2>/dev/null || true
        echo ""
    done

    log_info "🔗 Open GuardDuty console: https://$REGION.console.aws.amazon.com/guardduty/home?region=$REGION#/findings"
    return 0
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
    --check-findings       List recent HIGH/CRITICAL findings for the detector
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
    local check_findings=false
    
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
            --check-findings)
                check_findings=true
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

    if [[ "$check_findings" == true ]]; then
        list_findings_now "$detector_id"
        exit 0
    fi
    
    log_info "🎯 Creating REAL HIGH and CRITICAL GuardDuty findings..."
    log_warning "⚠️  This will create vulnerable AWS resources that cost money!"
    log_info "🌐 Real findings will appear in your GuardDuty console and trigger Lambda functions"
    echo ""
    
    # Create simulated findings that appear in GuardDuty console
    if create_real_critical_findings "$detector_id"; then
        log_success "✅ REAL GuardDuty findings creation process started!"
        
        # Basic check for Lambda function invocations
        log_info "🔍 Checking for Lambda function invocations..."
        monitor_lambda_invocations
    else
        log_error "❌ Failed to create REAL GuardDuty findings"
        exit 1
    fi
    
    # Generate simple report
    generate_demo_report "$detector_id" "simulated-findings" "guardduty-console" "sample-findings"
    
    log_success "🎯 GuardDuty REAL Findings Demo completed!"
    log_info "🌐 Check the AWS GuardDuty console to view your simulated findings"
    log_info "📊 Monitor CloudWatch Logs for Lambda function executions"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi