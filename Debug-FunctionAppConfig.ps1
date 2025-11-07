# Debug script to examine Function App configuration details
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$FunctionAppName
)

try {
    Write-Host "Debug: Function App Configuration Analysis" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    
    # Set context
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    
    # Get Function App details
    $functionApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction Stop
    
    Write-Host "Basic Information:" -ForegroundColor Yellow
    Write-Host "  Name: $($functionApp.Name)"
    Write-Host "  Kind: $($functionApp.Kind)"
    Write-Host "  State: $($functionApp.State)"
    Write-Host "  NetFrameworkVersion: $($functionApp.SiteConfig.NetFrameworkVersion)"
    Write-Host "  LinuxFxVersion: $($functionApp.SiteConfig.LinuxFxVersion)"
    
    # Convert app settings
    $appSettings = @{}
    if ($functionApp.SiteConfig.AppSettings) {
        foreach ($setting in $functionApp.SiteConfig.AppSettings) {
            $appSettings[$setting.Name] = $setting.Value
        }
    }
    
    Write-Host ""
    Write-Host "Key App Settings:" -ForegroundColor Yellow
    $keySettings = @(
        "FUNCTIONS_WORKER_RUNTIME",
        "FUNCTIONS_WORKER_RUNTIME_VERSION", 
        "FUNCTIONS_EXTENSION_VERSION",
        "PYTHON_VERSION",
        "WEBSITE_NODE_DEFAULT_VERSION",
        "NODE_VERSION",
        "DOTNET_VERSION",
        "JAVA_VERSION",
        "POWERSHELL_VERSION",
        "FUNCTIONS_INPROC_SCOPE_ALIAS"
    )
    
    foreach ($setting in $keySettings) {
        if ($appSettings.ContainsKey($setting)) {
            Write-Host "  $setting = $($appSettings[$setting])" -ForegroundColor Green
        } else {
            Write-Host "  $setting = [NOT SET]" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "All App Settings Count: $($appSettings.Count)" -ForegroundColor Yellow
    Write-Host "First 10 App Settings:" -ForegroundColor Yellow
    $appSettings.GetEnumerator() | Select-Object -First 10 | ForEach-Object {
        Write-Host "  $($_.Key) = $($_.Value)"
    }
    
} catch {
    Write-Error "Error: $($_.Exception.Message)"
}