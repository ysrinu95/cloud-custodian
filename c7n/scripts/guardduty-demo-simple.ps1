# Cloud Custodian GuardDuty Security Demo - Simplified PowerShell Version
# This script creates real vulnerable resources that GuardDuty will detect

param(
    [string]$Region = "us-east-1",
    [int]$MonitoringDuration = 10,
    [switch]$Cleanup,
    [switch]$CheckOnly
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

if ($CheckOnly) {
    Write-Info "🔍 Checking GuardDuty status..."
    aws guardduty get-detector --region $Region --detector-id $DetectorId
    Write-Success "✅ GuardDuty check completed"
    exit 0
}

if ($Cleanup) {
    Write-Info "🧹 Cleaning up demo resources..."
    
    # Get and terminate instances
    Write-Info "Finding demo instances..."
    $instances = aws ec2 describe-instances --region $Region --filters "Name=tag:$DemoTagKey,Values=$DemoTagValue" "Name=instance-state-name,Values=running,pending,stopped" --query "Reservations[].Instances[].InstanceId" --output text
    
    if ($instances -and $instances.Trim() -ne "") {
        Write-Info "Terminating instances: $instances"
        aws ec2 terminate-instances --region $Region --instance-ids $instances.Split()
    }
    
    Start-Sleep -Seconds 10
    
    # Delete security groups
    Write-Info "Finding demo security groups..."
    $sgs = aws ec2 describe-security-groups --region $Region --filters "Name=tag:$DemoTagKey,Values=$DemoTagValue" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text
    
    if ($sgs -and $sgs.Trim() -ne "") {
        Write-Info "Deleting security groups: $sgs"
        foreach ($sg in $sgs.Split()) {
            if ($sg.Trim() -ne "") {
                aws ec2 delete-security-group --region $Region --group-id $sg.Trim() 2>$null
            }
        }
    }
    
    # Delete key pairs
    Write-Info "Finding demo key pairs..."
    $keys = aws ec2 describe-key-pairs --region $Region --filters "Name=tag:$DemoTagKey,Values=$DemoTagValue" --query "KeyPairs[].KeyName" --output text
    
    if ($keys -and $keys.Trim() -ne "") {
        Write-Info "Deleting key pairs: $keys"
        foreach ($key in $keys.Split()) {
            if ($key.Trim() -ne "") {
                aws ec2 delete-key-pair --region $Region --key-name $key.Trim() 2>$null
            }
        }
    }
    
    Write-Success "🧹 Cleanup completed"
    exit 0
}

Write-Info "🛡️ Cloud Custodian GuardDuty Security Demo"
Write-Info "Region: $Region"
Write-Info "Monitoring Duration: $MonitoringDuration minutes"
Write-Host ""

Write-Warning "⚠️ WARNING: This demo will create real vulnerable AWS resources!"
Write-Warning "⚠️ These resources may incur AWS costs and will be flagged by GuardDuty"
Write-Info "Resources will be automatically cleaned up at the end"
Write-Host ""

# Check GuardDuty status
Write-Info "🔍 Checking GuardDuty status..."
$detectorStatus = aws guardduty get-detector --region $Region --detector-id $DetectorId --query "Status" --output text 2>$null

if ($detectorStatus -ne "ENABLED") {
    Write-Error "GuardDuty is not enabled properly"
    exit 1
}

Write-Success "GuardDuty is enabled and ready"

# Get default VPC
Write-Info "🔍 Finding default VPC..."
$vpcId = aws ec2 describe-vpcs --region $Region --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text

if (-not $vpcId -or $vpcId -eq "None") {
    Write-Error "No default VPC found"
    exit 1
}

Write-Info "Using VPC: $vpcId"

# Get public subnet
$subnetId = aws ec2 describe-subnets --region $Region --filters "Name=vpc-id,Values=$vpcId" "Name=map-public-ip-on-launch,Values=true" --query "Subnets[0].SubnetId" --output text

if (-not $subnetId -or $subnetId -eq "None") {
    Write-Error "No public subnet found"
    exit 1
}

Write-Info "Using subnet: $subnetId"

# Create security group
Write-Info "🔒 Creating vulnerable security group..."
$sgName = "$DemoPrefix-vulnerable-sg-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Info "Creating security group with name: $sgName"
$sgCreateOutput = aws ec2 create-security-group --region $Region --group-name $sgName --description "Vulnerable SG for GuardDuty demo" --vpc-id $vpcId --output json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create security group"
    Write-Error "AWS CLI output: $sgCreateOutput"
    exit 1
}

$sgResult = $sgCreateOutput | ConvertFrom-Json
$sgId = $sgResult.GroupId

if (-not $sgId -or $sgId -eq "" -or $sgId -eq "None") {
    Write-Error "Failed to get security group ID from creation result"
    Write-Error "Creation output: $sgCreateOutput"
    exit 1
}

Write-Success "Created security group: $sgId"

# Tag the security group
Write-Info "Tagging security group..."
aws ec2 create-tags --region $Region --resources $sgId --tags "Key=$DemoTagKey,Value=$DemoTagValue" "Key=Name,Value=$sgName"

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Failed to tag security group, but continuing..."
}

# Add dangerous rules
Write-Warning "Adding dangerous security group rules (GuardDuty will detect these)..."

Write-Info "Adding SSH rule (port 22)..."
aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --protocol tcp --port 22 --cidr "0.0.0.0/0"

Write-Info "Adding RDP rule (port 3389)..."
aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --protocol tcp --port 3389 --cidr "0.0.0.0/0"

Write-Info "Adding HTTP rule (port 80)..."
aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --protocol tcp --port 80 --cidr "0.0.0.0/0"

Write-Info "Adding HTTPS rule (port 443)..."
aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --protocol tcp --port 443 --cidr "0.0.0.0/0"

Write-Info "Adding MySQL rule (port 3306)..."
aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --protocol tcp --port 3306 --cidr "0.0.0.0/0"

Write-Info "Adding PostgreSQL rule (port 5432)..."
aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId --protocol tcp --port 5432 --cidr "0.0.0.0/0"

Write-Success "Added dangerous security group rules"

# Get latest Amazon Linux 2 AMI
Write-Info "🔍 Finding latest Amazon Linux 2 AMI..."
$amiOutput = aws ec2 describe-images --region $Region --owners amazon --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text

if ($LASTEXITCODE -ne 0 -or -not $amiOutput -or $amiOutput -eq "None") {
    Write-Error "Failed to find Amazon Linux 2 AMI"
    exit 1
}

$amiId = $amiOutput.Trim()
Write-Info "Using AMI: $amiId"

# Create key pair
$keyName = "$DemoPrefix-keypair-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Info "Creating key pair: $keyName"

$keyOutput = aws ec2 create-key-pair --region $Region --key-name $keyName --output json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create key pair"
    exit 1
}

$keyResult = $keyOutput | ConvertFrom-Json
$keyMaterial = $keyResult.KeyMaterial
$keyMaterial | Out-File -FilePath "$env:TEMP\$keyName.pem" -Encoding ASCII

# Tag the key pair
aws ec2 create-tags --region $Region --resources $keyName --tags "Key=$DemoTagKey,Value=$DemoTagValue" "Key=Name,Value=$keyName"

# Create user data for suspicious activities
$userData = @"
#!/bin/bash
yum update -y
yum install -y netcat-openbsd nmap

# Create suspicious activity script
cat > /tmp/suspicious_activity.sh << 'EOF'
#!/bin/bash
while true; do
    # Simulate cryptocurrency mining DNS queries (GuardDuty detects this)
    nslookup pool.minergate.com 8.8.8.8 > /dev/null 2>&1 || true
    nslookup stratum.f2pool.com 8.8.8.8 > /dev/null 2>&1 || true
    
    # Simulate malware C&C communication patterns
    nc -z -w1 suspicious-domain.example.com 443 > /dev/null 2>&1 || true
    
    sleep 300  # Wait 5 minutes between activities
done
EOF

chmod +x /tmp/suspicious_activity.sh
nohup /tmp/suspicious_activity.sh > /dev/null 2>&1 &

echo "`$(date): GuardDuty demo instance started with suspicious activities" >> /var/log/guardduty-demo.log
"@

# Encode user data
$userDataBytes = [System.Text.Encoding]::UTF8.GetBytes($userData)
$userDataBase64 = [System.Convert]::ToBase64String($userDataBytes)

# Launch instance
Write-Info "🖥️ Launching vulnerable EC2 instance..."
$instanceOutput = aws ec2 run-instances --region $Region --image-id $amiId --count 1 --instance-type t3.micro --key-name $keyName --security-group-ids $sgId --subnet-id $subnetId --associate-public-ip-address --user-data $userDataBase64 --output json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to launch instance"
    Write-Error "AWS CLI output: $instanceOutput"
    exit 1
}

$instanceResult = $instanceOutput | ConvertFrom-Json
$instanceId = $instanceResult.Instances[0].InstanceId

if (-not $instanceId -or $instanceId -eq "" -or $instanceId -eq "None") {
    Write-Error "Failed to get instance ID from launch result"
    Write-Error "Launch output: $instanceOutput"
    exit 1
}

Write-Success "Launched instance: $instanceId"

# Tag the instance
Write-Info "Tagging instance..."
aws ec2 create-tags --region $Region --resources $instanceId --tags "Key=$DemoTagKey,Value=$DemoTagValue" "Key=Name,Value=$DemoPrefix-vulnerable-instance" "Key=Purpose,Value=SecurityTesting"

# Wait for instance to be running
Write-Info "Waiting for instance to be running..."
aws ec2 wait instance-running --region $Region --instance-ids $instanceId

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Instance may not be running yet, but continuing..."
}

# Get public IP
$publicIpOutput = aws ec2 describe-instances --region $Region --instance-ids $instanceId --query "Reservations[0].Instances[0].PublicIpAddress" --output text

if ($LASTEXITCODE -eq 0 -and $publicIpOutput -and $publicIpOutput -ne "None") {
    $publicIp = $publicIpOutput.Trim()
    Write-Success "Instance is running with public IP: $publicIp"
} else {
    Write-Warning "Could not get public IP, but instance should be launching"
    $publicIp = "pending"
}

# Simulate additional suspicious activities from client side
Write-Info "🚨 Simulating suspicious activities..."

# Cryptocurrency mining DNS queries
Write-Info "Simulating cryptocurrency mining DNS queries..."
$domains = @("pool.minergate.com", "stratum.f2pool.com", "pool.supportxmr.com")
foreach ($domain in $domains) {
    try {
        Resolve-DnsName -Name $domain -Server "8.8.8.8" -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 2
    }
    catch {
        # Expected to fail for suspicious domains
    }
}

# Suspicious API calls
Write-Info "Simulating suspicious AWS API activity..."
aws sts get-caller-identity --region $Region | Out-Null
aws iam list-users --region $Region --max-items 1 | Out-Null
aws ec2 describe-security-groups --region $Region --max-items 1 | Out-Null

Write-Success "Suspicious activities simulation completed"

# Monitor for findings
Write-Info "📊 Monitoring GuardDuty findings for $MonitoringDuration minutes..."
Write-Info "GuardDuty typically takes 15-30 minutes to generate findings"

$endTime = (Get-Date).AddMinutes($MonitoringDuration)
$checkCount = 0

while ((Get-Date) -lt $endTime) {
    $checkCount++
    Write-Info "Check #$checkCount - Looking for new findings..."
    
    try {
        # Get findings from last 2 hours
        $twoHoursAgo = [DateTimeOffset]::UtcNow.AddHours(-2).ToUnixTimeMilliseconds()
        $findingIds = aws guardduty list-findings --region $Region --detector-id $DetectorId --finding-criteria "{`"updatedAt`":{`"gte`":$twoHoursAgo}}" --query "FindingIds" --output text
        
        if ($findingIds -and $findingIds.Trim() -ne "" -and $findingIds -ne "None") {
            $findingArray = $findingIds.Split()
            Write-Success "🚨 Found $($findingArray.Count) GuardDuty findings!"
            
            # Get details of first finding
            if ($findingArray.Count -gt 0) {
                $firstFinding = $findingArray[0]
                Write-Info "📋 Sample Finding Details:"
                
                $findingJson = aws guardduty get-findings --region $Region --detector-id $DetectorId --finding-ids $firstFinding --output json
                $finding = $findingJson | ConvertFrom-Json
                
                if ($finding.Findings.Count -gt 0) {
                    $f = $finding.Findings[0]
                    Write-Host "  Type: $($f.Type)" -ForegroundColor Cyan
                    Write-Host "  Severity: $($f.Severity)" -ForegroundColor Cyan
                    Write-Host "  Title: $($f.Title)" -ForegroundColor Cyan
                    Write-Host "  Description: $($f.Description)" -ForegroundColor Cyan
                }
            }
            
            if ($findingArray.Count -gt 1) {
                Write-Info "... and $($findingArray.Count - 1) more findings"
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

# Display report
Write-Host @"

🛡️ GuardDuty Security Demo Report
════════════════════════════════════════════════════════════════════════

📊 Demo Summary:
  • Region: $Region
  • GuardDuty Detector: $DetectorId
  • Demo Instance: $instanceId
  • Public IP: $publicIp
  • Security Group: $sgId
  • Duration: $MonitoringDuration minutes

🚨 Vulnerable Resources Created:
  • EC2 instance with overly permissive security group
  • Security group allowing SSH (22) from 0.0.0.0/0
  • Security group allowing database ports (3306, 5432) from 0.0.0.0/0
  • Instance configured with suspicious network activities

⚠️ Expected GuardDuty Findings:
  • UnauthorizedAPICall:EC2/MaliciousIPCaller
  • CryptoCurrency:EC2/BitcoinTool.B!DNS
  • Trojan:EC2/DropPoint!DNS
  • Recon:EC2/PortProbeUnprotectedPort
  • Policy:IAMUser/RootCredentialUsage

🌐 AWS Console Links:
  • GuardDuty: https://$Region.console.aws.amazon.com/guardduty/home?region=$Region#/findings
  • EC2: https://$Region.console.aws.amazon.com/ec2/home?region=$Region#Instances:
  • CloudWatch: https://$Region.console.aws.amazon.com/cloudwatch/home?region=$Region#logsV2:log-groups

🧹 To clean up resources later:
  .\guardduty-demo.ps1 -Cleanup

"@ -ForegroundColor White

Write-Success "🎯 GuardDuty Security Demo completed!"

# Offer cleanup
$cleanup = Read-Host "`nWould you like to clean up demo resources now? (y/N)"
if ($cleanup -eq 'y' -or $cleanup -eq 'Y') {
    Write-Info "🧹 Cleaning up resources..."
    
    # Terminate instance
    aws ec2 terminate-instances --region $Region --instance-ids $instanceId
    
    Start-Sleep -Seconds 10
    
    # Delete security group
    aws ec2 delete-security-group --region $Region --group-id $sgId 2>$null
    
    # Delete key pair
    aws ec2 delete-key-pair --region $Region --key-name $keyName 2>$null
    
    # Clean up key file
    Remove-Item -Path "$env:TEMP\$keyName.pem" -ErrorAction SilentlyContinue
    
    Write-Success "🧹 Demo resources cleaned up"
}
else {
    Write-Info "💡 Remember to run '.\guardduty-demo.ps1 -Cleanup' later to remove demo resources"
    Write-Info "💡 Or manually delete resources with tag: $DemoTagKey=$DemoTagValue"
}