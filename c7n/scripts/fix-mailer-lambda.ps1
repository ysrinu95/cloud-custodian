# PowerShell script to fix c7n-mailer Lambda PyJWT dependency
param(
    [string]$LambdaFunctionName = "cloud-custodian-mailer",
    [string]$Region = "us-west-2"
)

Write-Host "🔧 Post-deployment fix for c7n-mailer Lambda..." -ForegroundColor Cyan

# Create a temporary directory
$tempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
Write-Host "📁 Using temporary directory: $tempDir" -ForegroundColor Yellow

try {
    # Check if Lambda function exists
    Write-Host "🔍 Checking if Lambda function exists..." -ForegroundColor Yellow
    $functionInfo = aws lambda get-function --function-name $LambdaFunctionName --region $Region 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Lambda function '$LambdaFunctionName' not found in region '$Region'" -ForegroundColor Red
        Write-Host "💡 Please deploy the mailer first using: ./scripts/deploy-mailer.sh" -ForegroundColor Yellow
        exit 1
    }

    # Get the Lambda function download URL
    Write-Host "⬇️ Getting Lambda function download URL..." -ForegroundColor Yellow
    $downloadUrl = aws lambda get-function --function-name $LambdaFunctionName --region $Region --query 'Code.Location' --output text
    
    if ([string]::IsNullOrEmpty($downloadUrl)) {
        Write-Host "❌ Failed to get Lambda function download URL" -ForegroundColor Red
        exit 1
    }

    # Download the current Lambda function
    Write-Host "⬇️ Downloading current Lambda function..." -ForegroundColor Yellow
    $zipPath = Join-Path $tempDir "function.zip"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath

    # Extract the function
    Write-Host "📦 Extracting Lambda function..." -ForegroundColor Yellow
    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

    # Change to temp directory
    Push-Location $tempDir

    # Install PyJWT and other missing dependencies using pip
    Write-Host "📦 Installing missing dependencies..." -ForegroundColor Yellow
    pip install --target . PyJWT>=2.0.0 cryptography>=3.0.0 requests>=2.25.0 --quiet

    # Verify PyJWT is installed
    Write-Host "🔍 Verifying PyJWT installation..." -ForegroundColor Yellow
    $env:PYTHONPATH = $tempDir
    python -c "import jwt; print(f'✅ PyJWT {jwt.__version__} installed')" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ PyJWT successfully installed in Lambda package" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Could not verify PyJWT installation" -ForegroundColor Yellow
    }

    # Remove the original zip file before repackaging
    Remove-Item $zipPath -Force

    # Repackage the function
    Write-Host "📦 Repackaging Lambda function..." -ForegroundColor Yellow
    $updatedZipPath = Join-Path $tempDir "function-updated.zip"
    
    # Get all files and folders in the current directory
    $items = Get-ChildItem -Path $tempDir -Exclude "function-updated.zip"
    Compress-Archive -Path $items -DestinationPath $updatedZipPath -Force

    # Update the Lambda function
    Write-Host "⬆️ Updating Lambda function..." -ForegroundColor Yellow
    aws lambda update-function-code --function-name $LambdaFunctionName --region $Region --zip-file "fileb://$updatedZipPath"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Lambda function updated successfully" -ForegroundColor Green
        
        # Test the function
        Write-Host "🧪 Testing Lambda function..." -ForegroundColor Yellow
        $testPayload = '{}'
        $responseFile = Join-Path $tempDir "response.json"
        aws lambda invoke --function-name $LambdaFunctionName --region $Region --payload $testPayload $responseFile
        
        if (Test-Path $responseFile) {
            $response = Get-Content $responseFile
            Write-Host "📋 Lambda response: $response" -ForegroundColor Gray
        }
    } else {
        Write-Host "❌ Failed to update Lambda function" -ForegroundColor Red
    }

} catch {
    Write-Host "❌ Error during Lambda fix: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    # Return to original directory
    Pop-Location

    # Cleanup
    Write-Host "🧹 Cleaning up temporary directory..." -ForegroundColor Yellow
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "✅ Post-deployment fix complete" -ForegroundColor Green