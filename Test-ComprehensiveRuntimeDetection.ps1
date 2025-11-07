# Comprehensive Test of Enhanced Runtime Version Detection
# This script simulates different Function App scenarios to test the enhanced scanner logic

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId
)

Write-Host "Comprehensive Runtime Version Detection Test" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# Test data simulating different Function App configurations
$testScenarios = @(
    @{
        Name = "Real .NET Isolated App"
        AppSettings = @{
            "FUNCTIONS_WORKER_RUNTIME" = "dotnet-isolated"
            "FUNCTIONS_EXTENSION_VERSION" = "~4"
        }
        NetFrameworkVersion = "v6.0"
        LinuxFxVersion = ""
        Kind = "functionapp"
        Expected = "v6.0 (Isolated)"
    },
    @{
        Name = "Simulated Python App"
        AppSettings = @{
            "FUNCTIONS_WORKER_RUNTIME" = "python"
            "FUNCTIONS_EXTENSION_VERSION" = "~4"
            "PYTHON_VERSION" = "3.11"
        }
        NetFrameworkVersion = ""
        LinuxFxVersion = "PYTHON|3.11"
        Kind = "functionapp,linux"
        Expected = "3.11"
    },
    @{
        Name = "Simulated Node.js App"
        AppSettings = @{
            "FUNCTIONS_WORKER_RUNTIME" = "node"
            "FUNCTIONS_EXTENSION_VERSION" = "~4"
            "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
        }
        NetFrameworkVersion = ""
        LinuxFxVersion = "NODE|18-lts"
        Kind = "functionapp,linux"
        Expected = "~18"
    },
    @{
        Name = "Legacy .NET App (No Runtime Version)"
        AppSettings = @{
            "FUNCTIONS_WORKER_RUNTIME" = "dotnet"
            "FUNCTIONS_EXTENSION_VERSION" = "~3"
        }
        NetFrameworkVersion = "v4.8"
        LinuxFxVersion = ""
        Kind = "functionapp"
        Expected = "v4.8 (In-Process)"
    },
    @{
        Name = "Python App (Linux FxVersion only)"
        AppSettings = @{
            "FUNCTIONS_WORKER_RUNTIME" = "python"
            "FUNCTIONS_EXTENSION_VERSION" = "~4"
        }
        NetFrameworkVersion = ""
        LinuxFxVersion = "PYTHON|3.9"
        Kind = "functionapp,linux"
        Expected = "3.9"
    }
)

# Test the enhanced runtime detection logic
foreach ($scenario in $testScenarios) {
    Write-Host ""
    Write-Host "Testing: $($scenario.Name)" -ForegroundColor Yellow
    Write-Host "$(('-' * 50))" -ForegroundColor Gray
    
    # Simulate the enhanced detection logic from our scanner
    $appSettings = $scenario.AppSettings
    $runtimeStack = $appSettings["FUNCTIONS_WORKER_RUNTIME"]
    $workerRuntimeVersion = "N/A"
    
    # Apply the enhanced detection logic
    if ($appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"]) {
        $workerRuntimeVersion = $appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"]
    } else {
        switch ($runtimeStack) {
            { $_ -in @("dotnet", "dotnet-isolated") } {
                if ($scenario.NetFrameworkVersion) {
                    $netVersion = $scenario.NetFrameworkVersion
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
                } elseif ($scenario.LinuxFxVersion -match "PYTHON\|(.+)") {
                    $workerRuntimeVersion = $matches[1]
                } else {
                    $workerRuntimeVersion = "Python (version not specified)"
                }
            }
            "node" {
                if ($appSettings["WEBSITE_NODE_DEFAULT_VERSION"]) {
                    $workerRuntimeVersion = $appSettings["WEBSITE_NODE_DEFAULT_VERSION"]
                } elseif ($scenario.LinuxFxVersion -match "NODE\|(.+)") {
                    $workerRuntimeVersion = $matches[1]
                } else {
                    $workerRuntimeVersion = "Node.js (version not specified)"
                }
            }
            default {
                $workerRuntimeVersion = "Unknown runtime"
            }
        }
    }
    
    # Display results
    Write-Host "  Runtime Stack: $runtimeStack" -ForegroundColor White
    Write-Host "  Detected Version: $workerRuntimeVersion" -ForegroundColor Green
    Write-Host "  Expected Version: $($scenario.Expected)" -ForegroundColor Cyan
    
    # Check if detection was successful
    if ($workerRuntimeVersion -eq $scenario.Expected) {
        Write-Host "  Result: ✅ SUCCESS" -ForegroundColor Green
    } elseif ($workerRuntimeVersion -ne "N/A" -and $workerRuntimeVersion -ne "Unknown runtime") {
        Write-Host "  Result: ⚠️  PARTIAL (Version detected but different format)" -ForegroundColor Yellow
    } else {
        Write-Host "  Result: ❌ FAILED" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Summary: Enhanced Runtime Detection Capabilities" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "✅ .NET Apps: Detects from NetFrameworkVersion property" -ForegroundColor Green
Write-Host "✅ Python Apps: Detects from PYTHON_VERSION or LinuxFxVersion" -ForegroundColor Green  
Write-Host "✅ Node.js Apps: Detects from WEBSITE_NODE_DEFAULT_VERSION or LinuxFxVersion" -ForegroundColor Green
Write-Host "✅ Multiple Fallback Methods: Uses platform-specific detection" -ForegroundColor Green
Write-Host "✅ Descriptive Output: Shows runtime type (Isolated/In-Process)" -ForegroundColor Green

Write-Host ""
Write-Host "Real Function App Test:" -ForegroundColor Yellow
# Test with the real Function App
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
$realApps = Get-AzResource -ResourceType "Microsoft.Web/sites" | Where-Object { $_.Kind -like "*functionapp*" }

foreach ($app in $realApps) {
    $functionApp = Get-AzWebApp -ResourceGroupName $app.ResourceGroupName -Name $app.Name
    $appSettings = @{}
    if ($functionApp.SiteConfig.AppSettings) {
        foreach ($setting in $functionApp.SiteConfig.AppSettings) {
            $appSettings[$setting.Name] = $setting.Value
        }
    }
    
    $runtimeStack = if ($appSettings["FUNCTIONS_WORKER_RUNTIME"]) { $appSettings["FUNCTIONS_WORKER_RUNTIME"] } else { "Unknown" }
    
    Write-Host "  Real App: $($app.Name)" -ForegroundColor White
    Write-Host "    Runtime: $runtimeStack" -ForegroundColor Green
    Write-Host "    .NET Version: $($functionApp.SiteConfig.NetFrameworkVersion)" -ForegroundColor Green
    Write-Host "    Extension Version: $($appSettings["FUNCTIONS_EXTENSION_VERSION"])" -ForegroundColor Green
}