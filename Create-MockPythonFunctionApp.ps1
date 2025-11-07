# Create a Mock Python Function App for Testing Scanner
# This script creates a web app with Python Function App-like settings to test the scanner

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$AppName
)

try {
    Write-Host "Creating Mock Python Function App for Scanner Testing" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    
    # Set context
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    
    # Create a basic web app that we can configure to look like a Python Function App
    Write-Host "Creating base web app..." -ForegroundColor Yellow
    $webApp = New-AzWebApp -ResourceGroupName $ResourceGroupName -Name $AppName -Location "Canada Central" -AppServicePlan "testruidongldurable_groupplan"
    
    if (-not $webApp) {
        # Create app service plan first
        Write-Host "Creating app service plan..." -ForegroundColor Yellow
        New-AzAppServicePlan -ResourceGroupName $ResourceGroupName -Name "testruidongldurable_groupplan" -Location "Canada Central" -Tier "Free" -NumberofWorkers 1 -WorkerSize "Small"
        
        # Try creating web app again
        $webApp = New-AzWebApp -ResourceGroupName $ResourceGroupName -Name $AppName -Location "Canada Central" -AppServicePlan "testruidongldurable_groupplan"
    }
    
    # Configure app settings to mimic a Python Function App
    Write-Host "Configuring Python Function App settings..." -ForegroundColor Green
    
    $appSettings = @{
        "FUNCTIONS_WORKER_RUNTIME" = "python"
        "FUNCTIONS_EXTENSION_VERSION" = "~4"
        "PYTHON_VERSION" = "3.11"
        "WEBSITE_NODE_DEFAULT_VERSION" = ""
        "FUNCTIONS_WORKER_RUNTIME_VERSION" = "3.11"
        "WEBSITE_RUN_FROM_PACKAGE" = "1"
        "SCM_DO_BUILD_DURING_DEPLOYMENT" = "1"
    }
    
    # Update app settings
    Set-AzWebApp -ResourceGroupName $ResourceGroupName -Name $AppName -AppSettings $appSettings
    
    # Update site config to mimic Linux Python Function App
    $webApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $AppName
    $webApp.SiteConfig.LinuxFxVersion = "PYTHON|3.11"
    $webApp.Kind = "functionapp,linux"
    
    # Try to update the configuration
    try {
        Set-AzWebApp -WebApp $webApp
    } catch {
        Write-Warning "Could not update some configuration: $($_.Exception.Message)"
    }
    
    Write-Host ""
    Write-Host "Mock Python Function App Created!" -ForegroundColor Green
    Write-Host "=================================" -ForegroundColor Green
    Write-Host "App Name: $AppName" -ForegroundColor White
    Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
    Write-Host "Expected Scanner Results:" -ForegroundColor Yellow
    Write-Host "  RuntimeStack: python" -ForegroundColor White
    Write-Host "  FunctionsWorkerRuntimeVersion: 3.11" -ForegroundColor White
    Write-Host "  FunctionsExtensionVersion: ~4" -ForegroundColor White
    
    return $webApp
    
} catch {
    Write-Error "Failed to create mock Python Function App: $($_.Exception.Message)"
}