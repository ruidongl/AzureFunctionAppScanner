# Requires Az.Accounts module (relaxed requirements for compatibility)
# Optional: Az.Functions, Az.Resources (will use alternatives if not available)

<#
.SYNOPSIS
    Finds all Azure Function App bundle versions across subscriptions.

.DESCRIPTION
    This script scans Azure subscriptions for Function Apps and retrieves:
    - Function App name and resource group
    - Runtime stack and version
    - Extension bundle version
    - Host.json configuration
    - App settings related to extensions

.PARAMETER SubscriptionId
    Specific subscription ID to scan. If not provided, scans all accessible subscriptions.

.PARAMETER ResourceGroupName
    Specific resource group to scan. If not provided, scans all resource groups.

.PARAMETER OutputFormat
    Output format: Table, List, CSV, or JSON. Default is Table.

.PARAMETER ExportPath
    Path to export results. If provided, results will be saved to file.

.EXAMPLE
    .\Get-AzureFunctionAppBundleVersions.ps1
    
.EXAMPLE
    .\Get-AzureFunctionAppBundleVersions.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -OutputFormat CSV -ExportPath "C:\Reports\FunctionApps.csv"

.EXAMPLE
    .\Get-AzureFunctionAppBundleVersions.ps1 -ResourceGroupName "MyResourceGroup" -OutputFormat JSON
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Table", "List", "CSV", "JSON")]
    [string]$OutputFormat = "Table",
    
    [Parameter(Mandatory = $false)]
    [string]$ExportPath
)

# Function to get Function App configuration (with fallback methods)
function Get-FunctionAppConfig {
    param(
        [string]$ResourceGroupName,
        [string]$FunctionAppName,
        [string]$SubscriptionId
    )
    
    try {
        Write-Verbose "Getting configuration for Function App: $FunctionAppName"
        
        # Try Az.Functions module first, fallback to Az.Websites
        $functionApp = $null
        $appSettings = @{}
        
        try {
            # Try Az.Functions cmdlet
            $functionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction Stop
            $appSettings = $functionApp.ApplicationSetting
        }
        catch {
            Write-Verbose "Az.Functions not available, using Az.Websites fallback"
            # Fallback to Az.Websites
            $functionApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction Stop
            
            # Convert app settings format
            if ($functionApp.SiteConfig.AppSettings) {
                foreach ($setting in $functionApp.SiteConfig.AppSettings) {
                    $appSettings[$setting.Name] = $setting.Value
                }
            }
        }
        
        # Initialize result object
        $result = [PSCustomObject]@{
            SubscriptionId = $SubscriptionId
            SubscriptionName = (Get-AzSubscription -SubscriptionId $SubscriptionId).Name
            ResourceGroupName = $ResourceGroupName
            FunctionAppName = $FunctionAppName
            Location = $functionApp.Location
            RuntimeStack = if ($functionApp.Runtime) { $functionApp.Runtime } else { "Unknown" }
            RuntimeVersion = if ($functionApp.RuntimeVersion) { $functionApp.RuntimeVersion } elseif ($functionApp.SiteConfig.NetFrameworkVersion) { $functionApp.SiteConfig.NetFrameworkVersion } else { "Unknown" }
            OSType = if ($functionApp.OSType) { $functionApp.OSType } elseif ($functionApp.Kind -like "*linux*") { "Linux" } else { "Windows" }
            PlanType = if ($functionApp.PlanType) { $functionApp.PlanType } else { "Unknown" }
            ExtensionBundleId = "N/A"
            ExtensionBundleVersion = "N/A"
            FunctionsWorkerRuntime = "N/A"
            FunctionsExtensionVersion = "N/A"
            NetFrameworkVersion = "N/A"
            JavaVersion = "N/A"
            NodeVersion = "N/A"
            PythonVersion = "N/A"
            PowerShellVersion = "N/A"
            HostJsonError = $null
            Kind = $functionApp.Kind
            State = $functionApp.State
        }
        
        # Extract relevant app settings
        if ($appSettings) {
            $result.FunctionsWorkerRuntime = if ($appSettings["FUNCTIONS_WORKER_RUNTIME"]) { $appSettings["FUNCTIONS_WORKER_RUNTIME"] } else { "N/A" }
            $result.FunctionsExtensionVersion = if ($appSettings["FUNCTIONS_EXTENSION_VERSION"]) { $appSettings["FUNCTIONS_EXTENSION_VERSION"] } else { "N/A" }
            $result.NetFrameworkVersion = if ($appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"]) { $appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"] } else { "N/A" }
            
            # Check for specific runtime versions
            if ($appSettings.ContainsKey("WEBSITE_NODE_DEFAULT_VERSION")) {
                $result.NodeVersion = $appSettings["WEBSITE_NODE_DEFAULT_VERSION"]
            }
            if ($appSettings.ContainsKey("FUNCTIONS_WORKER_RUNTIME_VERSION")) {
                switch ($result.FunctionsWorkerRuntime) {
                    "java" { $result.JavaVersion = $appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"] }
                    "python" { $result.PythonVersion = $appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"] }
                    "powershell" { $result.PowerShellVersion = $appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"] }
                }
            }
        }
        
        # Try to get host.json to find extension bundle information
        try {
            # Get the default host key for accessing the Function App
            $hostKeys = Get-AzFunctionAppKey -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction SilentlyContinue
            
            if ($hostKeys -and $hostKeys.DefaultKey) {
                # Try to access host.json via the SCM API
                $scmUrl = "https://$FunctionAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/host.json"
                
                # Create headers with authorization
                $headers = @{
                    'Authorization' = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("`$$($FunctionAppName):$($hostKeys.DefaultKey)")))"
                    'Content-Type' = 'application/json'
                }
                
                # Try to get host.json
                $hostJsonResponse = Invoke-RestMethod -Uri $scmUrl -Headers $headers -Method Get -ErrorAction SilentlyContinue -TimeoutSec 30
                
                if ($hostJsonResponse) {
                    # Parse extension bundle information
                    if ($hostJsonResponse.extensionBundle) {
                        $result.ExtensionBundleId = if ($hostJsonResponse.extensionBundle.id) { $hostJsonResponse.extensionBundle.id } else { "N/A" }
                        $result.ExtensionBundleVersion = if ($hostJsonResponse.extensionBundle.version) { $hostJsonResponse.extensionBundle.version } else { "N/A" }
                    }
                }
            }
        }
        catch {
            $result.HostJsonError = "Could not retrieve host.json: $($_.Exception.Message)"
            Write-Warning "Could not retrieve host.json for $FunctionAppName: $($_.Exception.Message)"
        }
        
        return $result
    }
    catch {
        Write-Error "Error getting configuration for Function App $FunctionAppName`: $($_.Exception.Message)"
        return $null
    }
}

# Main script execution
try {
    Write-Host "🔍 Azure Function App Bundle Version Scanner" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    
    # Check if user is logged in to Azure
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "❌ Not logged in to Azure. Please run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✅ Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    
    # Get subscriptions to scan
    $subscriptions = @()
    if ($SubscriptionId) {
        $subscriptions = @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        Write-Host "🎯 Scanning specific subscription: $($subscriptions[0].Name)" -ForegroundColor Yellow
    } else {
        $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
        Write-Host "🌐 Scanning all accessible subscriptions ($($subscriptions.Count) found)" -ForegroundColor Yellow
    }
    
    $allResults = @()
    $totalFunctionApps = 0
    
    foreach ($subscription in $subscriptions) {
        Write-Host "`n📂 Processing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Blue
        
        # Set context to current subscription
        Set-AzContext -SubscriptionId $subscription.Id | Out-Null
        
        # Get resource groups to scan
        $resourceGroups = @()
        if ($ResourceGroupName) {
            $resourceGroups = @(Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)
            if (-not $resourceGroups) {
                Write-Warning "Resource group '$ResourceGroupName' not found in subscription '$($subscription.Name)'"
                continue
            }
        } else {
            $resourceGroups = Get-AzResourceGroup
        }
        
        Write-Host "   📁 Found $($resourceGroups.Count) resource group(s) to scan" -ForegroundColor Gray
        
        foreach ($rg in $resourceGroups) {
            Write-Host "      🔍 Scanning resource group: $($rg.ResourceGroupName)" -ForegroundColor Gray
            
            # Get Function Apps in this resource group (with fallback method)
            $functionApps = @()
            try {
                # Try Az.Functions cmdlet first
                $functionApps = Get-AzFunctionApp -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
            }
            catch {
                Write-Verbose "Az.Functions cmdlet not available, using Az.Websites fallback"
                # Fallback to Az.Websites - get all web apps and filter for function apps
                $allWebApps = Get-AzWebApp -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
                $functionApps = $allWebApps | Where-Object { $_.Kind -like "*functionapp*" }
            }
            
            if ($functionApps) {
                Write-Host "         ⚡ Found $($functionApps.Count) Function App(s)" -ForegroundColor Green
                $totalFunctionApps += $functionApps.Count
                
                foreach ($app in $functionApps) {
                    Write-Host "            📊 Analyzing: $($app.Name)" -ForegroundColor White
                    
                    $config = Get-FunctionAppConfig -ResourceGroupName $rg.ResourceGroupName -FunctionAppName $app.Name -SubscriptionId $subscription.Id
                    if ($config) {
                        $allResults += $config
                    }
                }
            } else {
                Write-Host "         ℹ️  No Function Apps found" -ForegroundColor Gray
            }
        }
    }
    
    # Display results
    Write-Host "`n📊 Scan Results Summary" -ForegroundColor Cyan
    Write-Host "========================" -ForegroundColor Cyan
    Write-Host "Total Function Apps found: $totalFunctionApps" -ForegroundColor Green
    Write-Host "Successfully analyzed: $($allResults.Count)" -ForegroundColor Green
    
    if ($allResults.Count -eq 0) {
        Write-Host "❌ No Function Apps found matching the criteria." -ForegroundColor Red
        exit 0
    }
    
    # Group by extension bundle version for summary
    $bundleVersions = $allResults | Group-Object ExtensionBundleVersion | Sort-Object Name
    Write-Host "`n📈 Extension Bundle Version Distribution:" -ForegroundColor Yellow
    foreach ($group in $bundleVersions) {
        Write-Host "   $($group.Name): $($group.Count) apps" -ForegroundColor White
    }
    
    # Group by runtime for summary
    $runtimes = $allResults | Group-Object FunctionsWorkerRuntime | Sort-Object Name
    Write-Host "`n🔧 Runtime Distribution:" -ForegroundColor Yellow
    foreach ($group in $runtimes) {
        Write-Host "   $($group.Name): $($group.Count) apps" -ForegroundColor White
    }
    
    Write-Host "`n📋 Detailed Results:" -ForegroundColor Cyan
    Write-Host "====================" -ForegroundColor Cyan
    
    # Output results based on format
    switch ($OutputFormat) {
        "Table" {
            $allResults | Format-Table -Property FunctionAppName, ResourceGroupName, RuntimeStack, RuntimeVersion, FunctionsWorkerRuntime, FunctionsExtensionVersion, ExtensionBundleId, ExtensionBundleVersion -AutoSize
        }
        "List" {
            $allResults | Format-List -Property *
        }
        "CSV" {
            $allResults | Format-Table -Property * -AutoSize
            if ($ExportPath) {
                $allResults | Export-Csv -Path $ExportPath -NoTypeInformation
                Write-Host "✅ Results exported to: $ExportPath" -ForegroundColor Green
            }
        }
        "JSON" {
            $jsonOutput = $allResults | ConvertTo-Json -Depth 3
            Write-Host $jsonOutput
            if ($ExportPath) {
                $jsonOutput | Out-File -FilePath $ExportPath -Encoding UTF8
                Write-Host "✅ Results exported to: $ExportPath" -ForegroundColor Green
            }
        }
    }
    
    # Export to file if specified
    if ($ExportPath -and $OutputFormat -notin @("CSV", "JSON")) {
        switch ($OutputFormat) {
            "Table" {
                $allResults | Export-Csv -Path "$ExportPath.csv" -NoTypeInformation
                Write-Host "✅ Results exported to: $ExportPath.csv" -ForegroundColor Green
            }
            "List" {
                $allResults | ConvertTo-Json -Depth 3 | Out-File -FilePath "$ExportPath.json" -Encoding UTF8
                Write-Host "✅ Results exported to: $ExportPath.json" -ForegroundColor Green
            }
        }
    }
    
    Write-Host "`n🎉 Scan completed successfully!" -ForegroundColor Green
    
} catch {
    Write-Error "❌ Script execution failed: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}