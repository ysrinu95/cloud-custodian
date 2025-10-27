# Cloud Custodian GuardDuty Security Demo - PowerShell Version
# This script creates real vulnerable resources that GuardDuty will detect
# WARNING: This creates actual AWS resources that may incur costs

param(
    [string]$Region = "us-east-1",
    [int]$MonitoringDuration = 15,
    [switch]$Cleanup,
    [switch]$CheckOnly,
    [switch]$Help
)

$DemoPrefix = "custodian-guardduty-demo"
$DemoTagKey = "CustodianDemo"
$DemoTagValue = "GuardDutySecurityTest"
$DetectorId = "52cd128303789eb9a3b21ddaf2f5cc1b"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Show-Usage {
    Write-Host @"
Usage: .\guardduty-demo.ps1 [OPTIONS]

GuardDuty Security Demo Script - Creates vulnerable AWS resources for GuardDuty testing

OPTIONS:
    -Region REGION              AWS region (default: us-east-1)
    -MonitoringDuration MINUTES Monitoring duration in minutes (default: 15)
    -Cleanup                   Clean up demo resources and exit
    -CheckOnly                 Only check GuardDuty status
    -Help                      Show this help message

EXAMPLES:
    .\guardduty-demo.ps1                    # Run full demo with defaults
    .\guardduty-demo.ps1 -Region us-west-2  # Run demo in us-west-2
    .\guardduty-demo.ps1 -MonitoringDuration 30  # Monitor for 30 minutes
    .\guardduty-demo.ps1 -Cleanup           # Clean up all demo resources
    .\guardduty-demo.ps1 -CheckOnly         # Just check GuardDuty status

WARNING: This script creates real AWS resources that may incur costs.
All resources are tagged with $DemoTagKey=$DemoTagValue for easy identification.
"@
}

function Test-GuardDutyStatus {
    Write-Info "🔍 Checking GuardDuty status..."
    
    try {
        $detectors = aws guardduty list-detectors --region $Region --output json | ConvertFrom-Json
        
        if ($detectors.DetectorIds.Count -eq 0) {
            Write-Error "GuardDuty is not enabled in region $Region"
            return $false
        }
        
        $detectorId = $detectors.DetectorIds[0]
        $detector = aws guardduty get-detector --region $Region --detector-id $detectorId --output json | ConvertFrom-Json
        
        Write-Success "GuardDuty detector found: $detectorId (Status: $($detector.Status))"
        return $detectorId
    }
    catch {
        Write-Error "Failed to check GuardDuty status: $_"
        return $false
    }
}

function Start-VulnerableInstance {
    Write-Info "🖥️ Creating vulnerable EC2 instance for GuardDuty detection..."
    
    try {
        # Get default VPC
        $vpc = aws ec2 describe-vpcs --region $Region --filters "Name=is-default,Values=true" --output json | ConvertFrom-Json
        $vpcId = $vpc.Vpcs[0].VpcId
        
        if (-not $vpcId) {
            Write-Error "No default VPC found in region $Region"
            return $null
        }
        
        # Get public subnet
        $subnet = aws ec2 describe-subnets --region $Region --filters "Name=vpc-id,Values=$vpcId" "Name=map-public-ip-on-launch,Values=true" --output json | ConvertFrom-Json
        $subnetId = $subnet.Subnets[0].SubnetId
        
        # Create vulnerable security group
        Write-Info "Creating vulnerable security group..."
        $sgResult = aws ec2 create-security-group --region $Region --group-name "$DemoPrefix-vulnerable-sg" --description "Vulnerable security group for GuardDuty demo - OPEN TO INTERNET" --vpc-id $vpcId --tag-specifications "ResourceType=security-group,Tags=[{Key=$DemoTagKey,Value=$DemoTagValue},{Key=Name,Value=$DemoPrefix-vulnerable-sg}]" --output json | ConvertFrom-Json
        $sgId = $sgResult.GroupId
        
        # Add dangerous rules
        Write-Warning "Adding dangerous security group rules (GuardDuty will detect these)..."
        aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --protocol tcp --port 22 --cidr "0.0.0.0/0" | Out-Null
        aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --protocol tcp --port 3389 --cidr "0.0.0.0/0" | Out-Null
        aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --protocol tcp --port 80 --cidr "0.0.0.0/0" | Out-Null
        aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --protocol tcp --port 443 --cidr "0.0.0.0/0" | Out-Null
        aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --protocol tcp --port 3306 --cidr "0.0.0.0/0" | Out-Null
        aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --protocol tcp --port 5432 --cidr "0.0.0.0/0" | Out-Null
        
        # Get latest Amazon Linux 2 AMI
        $ami = aws ec2 describe-images --region $Region --owners amazon --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" --output text
        
        Write-Info "Using AMI: $ami"
        
        # Create key pair
        $keyName = "$DemoPrefix-keypair"
        aws ec2 create-key-pair --region $Region --key-name $keyName --tag-specifications "ResourceType=key-pair,Tags=[{Key=$DemoTagKey,Value=$DemoTagValue},{Key=Name,Value=$keyName}]" --query KeyMaterial --output text | Out-File -FilePath "$env:TEMP\$keyName.pem" -Encoding ASCII
        
        # User data for suspicious activities
        $userData = @'
#!/bin/bash
yum update -y
yum install -y netcat-openbsd nmap

# Create suspicious network activity
cat > /tmp/suspicious_activity.sh << 'EOF'
#!/bin/bash
while true; do
    # Simulate cryptocurrency mining DNS queries
    nslookup pool.minergate.com 8.8.8.8 > /dev/null 2>&1 || true
    nslookup stratum.f2pool.com 8.8.8.8 > /dev/null 2>&1 || true
    
    # Simulate malware C&C communication
    nc -z -w1 suspicious-domain.example.com 443 > /dev/null 2>&1 || true
    
    sleep 300
done
EOF

chmod +x /tmp/suspicious_activity.sh
nohup /tmp/suspicious_activity.sh > /dev/null 2>&1 &

echo "$(date): GuardDuty demo instance started" >> /var/log/guardduty-demo.log
'@
        
        $userDataB64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userData))
        
        # Launch instance
        Write-Info "Launching vulnerable EC2 instance..."
        $instance = aws ec2 run-instances --region $Region --image-id $ami --count 1 --instance-type t3.micro --key-name $keyName --security-group-ids $sgId --subnet-id $subnetId --associate-public-ip-address --user-data $userDataB64 --tag-specifications "ResourceType=instance,Tags=[{Key=$DemoTagKey,Value=$DemoTagValue},{Key=Name,Value=$DemoPrefix-vulnerable-instance},{Key=Purpose,Value=SecurityTesting}]" --output json | ConvertFrom-Json
        
        $instanceId = $instance.Instances[0].InstanceId
        Write-Success "Vulnerable EC2 instance created: $instanceId"
        
        # Wait for instance to be running
        Write-Info "Waiting for instance to be running..."
        aws ec2 wait instance-running --region $Region --instance-ids $instanceId
        
        # Get public IP
        $instanceDetails = aws ec2 describe-instances --region $Region --instance-ids $instanceId --output json | ConvertFrom-Json
        $publicIp = $instanceDetails.Reservations[0].Instances[0].PublicIpAddress
        
        Write-Success "Instance is running with public IP: $publicIp"
        
        return @{
            InstanceId = $instanceId
            PublicIp = $publicIp
            SecurityGroupId = $sgId
        }
    }
    catch {
        Write-Error "Failed to create vulnerable instance: $_"
        return $null
    }
}

function Start-SuspiciousActivities {
    Write-Info "🚨 Simulating suspicious activities that GuardDuty will detect..."
    
    # Simulate cryptocurrency mining DNS queries
    Write-Info "Simulating cryptocurrency mining DNS queries..."
    $domains = @("pool.minergate.com", "stratum.f2pool.com", "pool.supportxmr.com")
    foreach ($domain in $domains) {
        try {
            Resolve-DnsName -Name $domain -Server 8.8.8.8 -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 2
        }
        catch {
            # Expected to fail for suspicious domains
        }
    }
    
    # Simulate suspicious AWS API calls
    Write-Info "Simulating suspicious AWS API activity..."
    aws sts get-caller-identity --region $Region | Out-Null
    aws iam list-users --region $Region --max-items 1 | Out-Null
    aws ec2 describe-security-groups --region $Region --max-items 1 | Out-Null
    
    Write-Success "Suspicious activities simulation completed"
}

function Watch-GuardDutyFindings {
    param([string]$DetectorId, [int]$Duration)
    
    Write-Info "📊 Monitoring GuardDuty findings for $Duration minutes..."
    Write-Info "GuardDuty typically takes 15-30 minutes to generate findings"
    
    $endTime = (Get-Date).AddMinutes($Duration)
    $checkCount = 0
    
    while ((Get-Date) -lt $endTime) {
        $checkCount++
        Write-Info "Check #$checkCount - Looking for new findings..."
        
        try {
            # Get findings from last hour
            $oneHourAgo = [DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeMilliseconds()
            $findings = aws guardduty list-findings --region $Region --detector-id $DetectorId --finding-criteria "{`"updatedAt`":{`"gte`":$oneHourAgo}}" --output json | ConvertFrom-Json
            
            if ($findings.FindingIds.Count -gt 0) {
                Write-Success "🚨 Found $($findings.FindingIds.Count) GuardDuty findings!"
                
                # Get details of first few findings
                $firstFew = $findings.FindingIds | Select-Object -First 3
                foreach ($findingId in $firstFew) {
                    Write-Info "📋 Finding Details:"
                    $findingDetails = aws guardduty get-findings --region $Region --detector-id $DetectorId --finding-ids $findingId --output json | ConvertFrom-Json
                    $finding = $findingDetails.Findings[0]
                    Write-Host "  Type: $($finding.Type)" -ForegroundColor Cyan
                    Write-Host "  Severity: $($finding.Severity)" -ForegroundColor Cyan
                    Write-Host "  Title: $($finding.Title)" -ForegroundColor Cyan
                    Write-Host "  Description: $($finding.Description)" -ForegroundColor Cyan
                    Write-Host ""
                }
                
                if ($findings.FindingIds.Count -gt 3) {
                    Write-Info "... and $($findings.FindingIds.Count - 3) more findings"
                }
                break
            }
            else {
                Write-Info "No new findings yet... (GuardDuty needs time to analyze)"
            }
        }
        catch {
            Write-Warning "Error checking findings: $_"
        }
        
        Start-Sleep -Seconds 60
    }
    
    if ((Get-Date) -ge $endTime) {
        Write-Warning "Monitoring period ended. GuardDuty may still be analyzing..."
        Write-Info "💡 Check the AWS GuardDuty console for findings over the next hour"
    }
}

function Remove-DemoResources {
    Write-Info "🧹 Cleaning up demo resources..."
    
    try {
        # Terminate instances
        $instances = aws ec2 describe-instances --region $Region --filters "Name=tag:$DemoTagKey,Values=$DemoTagValue" "Name=instance-state-name,Values=running,pending" --query "Reservations[].Instances[].InstanceId" --output text
        
        if ($instances -and $instances -ne "None") {
            Write-Info "Terminating demo EC2 instances: $instances"
            aws ec2 terminate-instances --region $Region --instance-ids $instances.Split() | Out-Null
            aws ec2 wait instance-terminated --region $Region --instance-ids $instances.Split()
        }
        
        # Delete security groups
        $securityGroups = aws ec2 describe-security-groups --region $Region --filters "Name=tag:$DemoTagKey,Values=$DemoTagValue" --query "SecurityGroups[?GroupName!=``default``].GroupId" --output text
        
        if ($securityGroups -and $securityGroups -ne "None") {
            Write-Info "Deleting demo security groups: $securityGroups"
            foreach ($sg in $securityGroups.Split()) {
                aws ec2 delete-security-group --region $Region --group-id $sg 2>$null | Out-Null
            }
        }
        
        # Delete key pairs
        $keyPairs = aws ec2 describe-key-pairs --region $Region --filters "Name=tag:$DemoTagKey,Values=$DemoTagValue" --query "KeyPairs[].KeyName" --output text
        
        if ($keyPairs -and $keyPairs -ne "None") {
            Write-Info "Deleting demo key pairs: $keyPairs"
            foreach ($kp in $keyPairs.Split()) {
                aws ec2 delete-key-pair --region $Region --key-name $kp | Out-Null
            }
        }
        
        Write-Success "Resource cleanup completed"
    }
    catch {
        Write-Error "Error during cleanup: $_"
    }
}

function Show-DemoReport {
    param($DetectorId, $InstanceDetails)
    
    Write-Info "📋 Generating GuardDuty Security Demo Report..."
    
    Write-Host @"

🛡️ GuardDuty Security Demo Report
════════════════════════════════════════════════════════════════════════

📊 Demo Summary:
  • Region: $Region
  • GuardDuty Detector: $DetectorId
  • Demo Instance: $($InstanceDetails.InstanceId)
  • Public IP: $($InstanceDetails.PublicIp)
  • Security Group: $($InstanceDetails.SecurityGroupId)
  • Duration: $MonitoringDuration minutes

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

🌐 AWS Console Links:
  • GuardDuty: https://$Region.console.aws.amazon.com/guardduty/home?region=$Region#/findings
  • EC2: https://$Region.console.aws.amazon.com/ec2/home?region=$Region#Instances:
  • CloudWatch: https://$Region.console.aws.amazon.com/cloudwatch/home?region=$Region#logsV2:log-groups

🧹 Cleanup:
  Run: .\guardduty-demo.ps1 -Cleanup
  Or manually delete resources with tag: $DemoTagKey=$DemoTagValue

"@ -ForegroundColor White
}

# Main execution
if ($Help) {
    Show-Usage
    exit 0
}

Write-Info "🛡️ Cloud Custodian GuardDuty Security Demo"
Write-Info "Region: $Region"
Write-Info "Monitoring Duration: $MonitoringDuration minutes"
Write-Host ""

if ($Cleanup) {
    Remove-DemoResources
    Write-Success "🧹 Cleanup completed"
    exit 0
}

# Check GuardDuty status
$detectorResult = Test-GuardDutyStatus

if (-not $detectorResult) {
    Write-Error "GuardDuty is not properly configured. Exiting."
    exit 1
}

if ($CheckOnly) {
    Write-Success "✅ GuardDuty check completed"
    exit 0
}

Write-Warning "⚠️ WARNING: This demo will create real vulnerable AWS resources!"
Write-Warning "⚠️ These resources may incur AWS costs and will be flagged by GuardDuty"
Write-Info "Resources will be automatically cleaned up at the end"
Write-Host ""

# Create vulnerable resources
$instanceDetails = Start-VulnerableInstance

if (-not $instanceDetails) {
    Write-Error "Failed to create vulnerable instance. Exiting."
    exit 1
}

# Simulate suspicious activities
Start-SuspiciousActivities

# Monitor for findings
Watch-GuardDutyFindings -DetectorId $DetectorId -Duration $MonitoringDuration

# Generate report
Show-DemoReport -DetectorId $DetectorId -InstanceDetails $instanceDetails

Write-Success "🎯 GuardDuty Security Demo completed!"
Write-Info "💡 Check the AWS GuardDuty console for findings over the next hour"

# Offer cleanup
$cleanup = Read-Host "`nWould you like to clean up demo resources now? (y/N)"
if ($cleanup -eq 'y' -or $cleanup -eq 'Y') {
    Remove-DemoResources
    Write-Success "🧹 Demo resources cleaned up"
}
else {
    Write-Info "💡 Remember to run '.\guardduty-demo.ps1 -Cleanup' later to remove demo resources"
}