#Requires -Modules Az.Accounts, Az.Websites

<#
.SYNOPSIS
    Checks all .NET Function Apps in a subscription and reports runtime version and hosting model.

.DESCRIPTION
    This script scans all Function Apps in a subscription and identifies:
    - .NET runtime version (e.g., v6.0, v8.0)
    - Hosting model: In-Process or Isolated
    - Functions Extension Version
    - App State and Location

.PARAMETER SubscriptionId
    Azure subscription ID to scan. If not provided, scans all accessible subscriptions.

.PARAMETER OutputFormat
    Output format: Table (default), CSV, or JSON

.PARAMETER ExportPath
    Path to export results (optional)

.EXAMPLE
    .\Get-DotNetFunctionApps.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012"

.EXAMPLE
    .\Get-DotNetFunctionApps.ps1 -OutputFormat CSV -ExportPath "C:\temp\dotnet-functions.csv"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Table", "CSV", "JSON")]
    [string]$OutputFormat = "Table",
    
    [Parameter(Mandatory=$false)]
    [string]$ExportPath
)

function Get-DotNetFunctionAppInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory=$true)]
        [string]$FunctionAppName
    )
    
    try {
        # Get Function App details
        $functionApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName
        
        if (-not $functionApp) {
            Write-Warning "Could not retrieve Function App: $FunctionAppName"
            return $null
        }
        
        # Get application settings
        $appSettings = @{}
        if ($functionApp.SiteConfig.AppSettings) {
            foreach ($setting in $functionApp.SiteConfig.AppSettings) {
                $appSettings[$setting.Name] = $setting.Value
            }
        }
        
        # Determine if this is a .NET Function App
        $workerRuntime = $appSettings["FUNCTIONS_WORKER_RUNTIME"]
        if ($workerRuntime -notin @("dotnet", "dotnet-isolated")) {
            # Check if it might be .NET based on other indicators
            $isLikelyDotNet = $false
            
            # Check LinuxFxVersion for .NET indicators
            if ($functionApp.SiteConfig.LinuxFxVersion -like "*dotnet*") {
                $isLikelyDotNet = $true
                $workerRuntime = "dotnet-isolated"  # Linux .NET apps are typically isolated
            }
            # Check NetFrameworkVersion for Windows .NET apps
            elseif ($functionApp.SiteConfig.NetFrameworkVersion -like "v*") {
                $isLikelyDotNet = $true
                $workerRuntime = if ($functionApp.SiteConfig.NetFrameworkVersion -like "v6*" -or 
                                    $functionApp.SiteConfig.NetFrameworkVersion -like "v7*" -or 
                                    $functionApp.SiteConfig.NetFrameworkVersion -like "v8*") { 
                    "dotnet-isolated" 
                } else { 
                    "dotnet" 
                }
            }
            
            # If not a .NET app, return null
            if (-not $isLikelyDotNet) {
                return $null
            }
        }
        
        # Determine hosting model
        $hostingModel = switch ($workerRuntime) {
            "dotnet" { "In-Process" }
            "dotnet-isolated" { "Isolated" }
            default { "Unknown" }
        }
        
        # Determine .NET runtime version
        $dotNetVersion = "Unknown"
        
        # Method 1: Check NetFrameworkVersion (most reliable for Windows)
        if ($functionApp.SiteConfig.NetFrameworkVersion) {
            $dotNetVersion = $functionApp.SiteConfig.NetFrameworkVersion
        }
        # Method 2: Check LinuxFxVersion for Linux apps
        elseif ($functionApp.SiteConfig.LinuxFxVersion -match "DOTNET\|(.+)") {
            $dotNetVersion = $matches[1]
        }
        # Method 3: Check app settings
        elseif ($appSettings["DOTNET_VERSION"]) {
            $dotNetVersion = $appSettings["DOTNET_VERSION"]
        }
        # Method 4: Infer from Functions Extension Version
        elseif ($appSettings["FUNCTIONS_EXTENSION_VERSION"]) {
            $functionsVersion = $appSettings["FUNCTIONS_EXTENSION_VERSION"]
            switch ($functionsVersion) {
                "~4" { 
                    $dotNetVersion = if ($hostingModel -eq "Isolated") { "v6.0+" } else { "v6.0" }
                }
                "~3" { $dotNetVersion = "v3.1" }
                "~2" { $dotNetVersion = "v2.1" }
                "~1" { $dotNetVersion = "v1.1" }
                default { $dotNetVersion = "Unknown ($functionsVersion)" }
            }
        }
        
        # Create result object
        $result = [PSCustomObject]@{
            SubscriptionId = $SubscriptionId
            SubscriptionName = (Get-AzSubscription -SubscriptionId $SubscriptionId).Name
            ResourceGroupName = $ResourceGroupName
            FunctionAppName = $FunctionAppName
            Location = $functionApp.Location
            State = $functionApp.State
            DotNetVersion = $dotNetVersion
            HostingModel = $hostingModel
            FunctionsExtensionVersion = if ($appSettings["FUNCTIONS_EXTENSION_VERSION"]) { $appSettings["FUNCTIONS_EXTENSION_VERSION"] } else { "Unknown" }
            WorkerRuntime = $workerRuntime
            Platform = if ($functionApp.SiteConfig.LinuxFxVersion) { "Linux" } else { "Windows" }
            AlwaysOn = $functionApp.SiteConfig.AlwaysOn
            Use32BitWorkerProcess = $functionApp.SiteConfig.Use32BitWorkerProcess
            LastModifiedTime = $functionApp.LastModifiedTimeUtc
        }
        
        return $result
    }
    catch {
        Write-Error "Error analyzing Function App '$FunctionAppName': $($_.Exception.Message)"
        return $null
    }
}

# Main script execution
try {
    Write-Host ".NET Function App Runtime Scanner" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    
    # Check if user is logged in to Azure
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not logged in to Azure. Please run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    
    # Get subscriptions to scan
    $subscriptions = @()
    if ($SubscriptionId) {
        $subscriptions = @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        Write-Host "Scanning specific subscription: $($subscriptions[0].Name)" -ForegroundColor Yellow
    } else {
        $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
        Write-Host "Scanning all accessible subscriptions ($($subscriptions.Count) found)" -ForegroundColor Yellow
    }
    
    $allResults = @()
    
    foreach ($subscription in $subscriptions) {
        Write-Host ""
        Write-Host "Processing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor White
        
        # Set subscription context
        Set-AzContext -SubscriptionId $subscription.Id | Out-Null
        
        # Get all resource groups
        $resourceGroups = Get-AzResourceGroup
        Write-Host "   Found $($resourceGroups.Count) resource group(s) to scan" -ForegroundColor Gray
        
        foreach ($rg in $resourceGroups) {
            try {
                Write-Host "      Scanning resource group: $($rg.ResourceGroupName)" -ForegroundColor Gray
                
                # Get Function Apps in this resource group
                $functionApps = Get-AzWebApp -ResourceGroupName $rg.ResourceGroupName | Where-Object { 
                    $_.Kind -like "*functionapp*" 
                }
                
                if ($functionApps.Count -eq 0) {
                    Write-Host "         No Function Apps found" -ForegroundColor DarkGray
                    continue
                }
                
                Write-Host "         Found $($functionApps.Count) Function App(s)" -ForegroundColor Gray
                
                foreach ($app in $functionApps) {
                    Write-Host "            Analyzing: $($app.Name)" -ForegroundColor White
                    
                    $config = Get-DotNetFunctionAppInfo -SubscriptionId $subscription.Id -ResourceGroupName $rg.ResourceGroupName -FunctionAppName $app.Name
                    if ($config) {
                        $allResults += $config
                    }
                }
            }
            catch {
                Write-Warning "Error scanning resource group '$($rg.ResourceGroupName)': $($_.Exception.Message)"
            }
        }
    }
    
    # Display results
    Write-Host ""
    Write-Host ".NET Function App Scanner Results" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    
    if ($allResults.Count -eq 0) {
        Write-Host "No .NET Function Apps found." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host ""
    Write-Host ".NET Function Apps Found: $($allResults.Count)" -ForegroundColor Green
    Write-Host ""
    
    # Summary statistics
    $hostingModelSummary = $allResults | Group-Object HostingModel
    Write-Host "Hosting Model Distribution:" -ForegroundColor Yellow
    foreach ($model in $hostingModelSummary) {
        Write-Host "   $($model.Name): $($model.Count) apps" -ForegroundColor White
    }
    
    $versionSummary = $allResults | Group-Object DotNetVersion
    Write-Host ""
    Write-Host ".NET Version Distribution:" -ForegroundColor Yellow
    foreach ($version in $versionSummary) {
        Write-Host "   $($version.Name): $($version.Count) apps" -ForegroundColor White
    }
    
    $platformSummary = $allResults | Group-Object Platform
    Write-Host ""
    Write-Host "Platform Distribution:" -ForegroundColor Yellow
    foreach ($platform in $platformSummary) {
        Write-Host "   $($platform.Name): $($platform.Count) apps" -ForegroundColor White
    }
    
    # Display detailed results
    Write-Host ""
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    Write-Host "================" -ForegroundColor Cyan
    Write-Host ""
    
    switch ($OutputFormat) {
        "Table" {
            $allResults | Format-Table -Property FunctionAppName, ResourceGroupName, DotNetVersion, HostingModel, Platform, FunctionsExtensionVersion, State, AlwaysOn -AutoSize
        }
        "CSV" {
            if ($ExportPath) {
                $allResults | Export-Csv -Path $ExportPath -NoTypeInformation
                Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
            } else {
                $allResults | ConvertTo-Csv -NoTypeInformation
            }
        }
        "JSON" {
            if ($ExportPath) {
                $allResults | ConvertTo-Json -Depth 3 | Out-File -FilePath $ExportPath -Encoding UTF8
                Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
            } else {
                $allResults | ConvertTo-Json -Depth 3
            }
        }
    }
    
    Write-Host ""
    Write-Host "Scan completed successfully!" -ForegroundColor Green
    
    # Return results for further processing if needed
    return $allResults
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}