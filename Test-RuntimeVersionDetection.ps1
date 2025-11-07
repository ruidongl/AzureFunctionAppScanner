# Minimal test script to verify the enhanced runtime version detection
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId
)

try {
    Write-Host "Testing Enhanced Runtime Version Detection" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    
    # Get Function Apps directly
    $functionApps = Get-AzResource -ResourceType "Microsoft.Web/sites" | Where-Object { $_.Kind -like "*functionapp*" }
    
    Write-Host "Found $($functionApps.Count) Function App(s)" -ForegroundColor Green
    
    foreach ($app in $functionApps) {
        Write-Host ""
        Write-Host "Analyzing: $($app.Name)" -ForegroundColor Yellow
        
        # Get detailed info
        $functionApp = Get-AzWebApp -ResourceGroupName $app.ResourceGroupName -Name $app.Name
        
        # Convert app settings
        $appSettings = @{}
        if ($functionApp.SiteConfig.AppSettings) {
            foreach ($setting in $functionApp.SiteConfig.AppSettings) {
                $appSettings[$setting.Name] = $setting.Value
            }
        }
        
        # Get runtime stack
        $runtimeStack = if ($appSettings["FUNCTIONS_WORKER_RUNTIME"]) { $appSettings["FUNCTIONS_WORKER_RUNTIME"] } else { "Unknown" }
        
        # Enhanced version detection
        $workerRuntimeVersion = "N/A"
        if ($appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"]) {
            $workerRuntimeVersion = $appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"]
        } else {
            switch ($runtimeStack) {
                { $_ -in @("dotnet", "dotnet-isolated") } {
                    if ($functionApp.SiteConfig.NetFrameworkVersion) {
                        $netVersion = $functionApp.SiteConfig.NetFrameworkVersion
                        if ($runtimeStack -eq "dotnet-isolated") {
                            $workerRuntimeVersion = "$netVersion (Isolated)"
                        } else {
                            $workerRuntimeVersion = "$netVersion (In-Process)"
                        }
                    } else {
                        $workerRuntimeVersion = ".NET (version unknown)"
                    }
                }
                "python" {
                    if ($appSettings["PYTHON_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["PYTHON_VERSION"]
                    } else {
                        $workerRuntimeVersion = "Python (version not specified)"
                    }
                }
                "node" {
                    if ($appSettings["WEBSITE_NODE_DEFAULT_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["WEBSITE_NODE_DEFAULT_VERSION"]
                    } else {
                        $workerRuntimeVersion = "Node.js (version not specified)"
                    }
                }
                default {
                    $workerRuntimeVersion = "Unknown runtime"
                }
            }
        }
        
        Write-Host "  Runtime Stack: $runtimeStack" -ForegroundColor White
        Write-Host "  Worker Runtime Version: $workerRuntimeVersion" -ForegroundColor Green
        Write-Host "  .NET Framework Version: $($functionApp.SiteConfig.NetFrameworkVersion)" -ForegroundColor White
        Write-Host "  Functions Extension Version: $($appSettings["FUNCTIONS_EXTENSION_VERSION"])" -ForegroundColor White
    }
    
} catch {
    Write-Error "Error: $($_.Exception.Message)"
}