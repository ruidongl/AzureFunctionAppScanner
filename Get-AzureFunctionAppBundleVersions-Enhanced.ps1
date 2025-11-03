# Azure Function App Bundle Version Scanner - Enhanced Version
# Compatible with PowerShell 5.1 and newer
# Author: Generated for Azure Function App analysis
# Date: October 31, 2025

param(
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$FunctionAppName,
    [ValidateSet("Table", "List", "CSV", "JSON")]
    [string]$OutputFormat = "Table",
    [string]$ExportPath
)

# Function to get extension bundle information from host.json
function Get-ExtensionBundleInfo {
    param(
        [string]$FunctionAppName,
        [string]$ResourceGroupName
    )
    
    try {
        # Try to get the site config which may include host.json information
        $siteConfig = Get-AzWebAppSlot -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -Slot "production" -ErrorAction SilentlyContinue
        
        # Alternative approach: Try to get app settings that might contain bundle info
        $appSettings = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName | Select-Object -ExpandProperty SiteConfig | Select-Object -ExpandProperty AppSettings
        
        # Convert app settings to hashtable for easier lookup
        $settingsHash = @{}
        if ($appSettings) {
            foreach ($setting in $appSettings) {
                $settingsHash[$setting.Name] = $setting.Value
            }
        }
        
        # Check for extension bundle related settings
        $bundleId = "Default (Microsoft.Azure.Functions.ExtensionBundle)"
        $bundleVersion = "Default ([1.*, 2.0.0))"
        
        # Try to get custom bundle configuration if available
        if ($settingsHash["AzureFunctionsJobHost__extensionBundle__id"]) {
            $bundleId = $settingsHash["AzureFunctionsJobHost__extensionBundle__id"]
        }
        if ($settingsHash["AzureFunctionsJobHost__extensionBundle__version"]) {
            $bundleVersion = $settingsHash["AzureFunctionsJobHost__extensionBundle__version"]
        }
        
        # Check if no extension bundle is configured (for .NET apps)
        $runtime = $settingsHash["FUNCTIONS_WORKER_RUNTIME"]
        if ($runtime -eq "dotnet" -or $runtime -eq "dotnet-isolated") {
            $bundleId = "Not applicable (.NET runtime)"
            $bundleVersion = "Not applicable (.NET runtime)"
        }
        
        return @{
            ExtensionBundleId = $bundleId
            ExtensionBundleVersion = $bundleVersion
        }
    }
    catch {
        Write-Verbose "Could not retrieve extension bundle info for $FunctionAppName`: $($_.Exception.Message)"
        return @{
            ExtensionBundleId = "Unable to determine"
            ExtensionBundleVersion = "Unable to determine"
        }
    }
}

# Function to get Function App configuration
function Get-FunctionAppConfig {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$FunctionAppName
    )
    
    try {
        Write-Verbose "Getting configuration for Function App: $FunctionAppName"
        
        # Get the Function App
        $functionApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName
        if (-not $functionApp) {
            Write-Warning "Function App '$FunctionAppName' not found in resource group '$ResourceGroupName'"
            return $null
        }
        
        # Get app settings
        $appSettings = @{}
        if ($functionApp.SiteConfig.AppSettings) {
            foreach ($setting in $functionApp.SiteConfig.AppSettings) {
                $appSettings[$setting.Name] = $setting.Value
            }
        }
        
        # Get extension bundle information
        $bundleInfo = Get-ExtensionBundleInfo -FunctionAppName $FunctionAppName -ResourceGroupName $ResourceGroupName
        
        # Determine runtime information
        $runtime = "Unknown"
        $runtimeVersion = "N/A"
        
        if ($appSettings["FUNCTIONS_WORKER_RUNTIME"]) {
            $workerRuntime = $appSettings["FUNCTIONS_WORKER_RUNTIME"]
            switch ($workerRuntime) {
                "dotnet" { $runtime = ".NET Framework" }
                "dotnet-isolated" { $runtime = ".NET Isolated" }
                "node" { $runtime = "Node.js" }
                "python" { $runtime = "Python" }
                "java" { $runtime = "Java" }
                "powershell" { $runtime = "PowerShell" }
                default { $runtime = $workerRuntime }
            }
        }
        
        if ($appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"]) {
            $runtimeVersion = $appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"]
        }
        
        # Initialize result object
        $result = [PSCustomObject]@{
            SubscriptionId = $SubscriptionId
            SubscriptionName = (Get-AzSubscription -SubscriptionId $SubscriptionId).Name
            ResourceGroupName = $ResourceGroupName
            FunctionAppName = $FunctionAppName
            Location = $functionApp.Location
            Kind = $functionApp.Kind
            State = $functionApp.State
            RuntimeStack = $runtime
            RuntimeVersion = $runtimeVersion
            FunctionsExtensionVersion = if ($appSettings["FUNCTIONS_EXTENSION_VERSION"]) { $appSettings["FUNCTIONS_EXTENSION_VERSION"] } else { "Unknown" }
            NodeVersion = if ($appSettings["WEBSITE_NODE_DEFAULT_VERSION"]) { $appSettings["WEBSITE_NODE_DEFAULT_VERSION"] } else { "N/A" }
            NetFrameworkVersion = if ($functionApp.SiteConfig.NetFrameworkVersion) { $functionApp.SiteConfig.NetFrameworkVersion } else { "N/A" }
            AlwaysOn = $functionApp.SiteConfig.AlwaysOn
            Use32BitWorkerProcess = $functionApp.SiteConfig.Use32BitWorkerProcess
            DefaultDocuments = ($functionApp.SiteConfig.DefaultDocuments -join ", ")
            ExtensionBundleId = $bundleInfo.ExtensionBundleId
            ExtensionBundleVersion = $bundleInfo.ExtensionBundleVersion
            LastModifiedTime = $functionApp.LastModifiedTimeUtc
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
    Write-Host "Azure Function App Bundle Version Scanner (Enhanced)" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    
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
    $totalFunctionApps = 0
    
    foreach ($subscription in $subscriptions) {
        Write-Host ""
        Write-Host "Processing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Blue
        
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
        
        Write-Host "   Found $($resourceGroups.Count) resource group(s) to scan" -ForegroundColor Gray
        
        foreach ($rg in $resourceGroups) {
            Write-Host "      Scanning resource group: $($rg.ResourceGroupName)" -ForegroundColor Gray
            
            # Get Function Apps in this resource group
            try {
                # Try using Az.Functions module first
                $functionApps = @()
                try {
                    if (Get-Command Get-AzFunctionApp -ErrorAction SilentlyContinue) {
                        $functionApps = Get-AzFunctionApp -ResourceGroupName $rg.ResourceGroupName
                    }
                } catch {
                    Write-Verbose "Az.Functions module not available or failed, using fallback method"
                }
                
                # Fallback to using Az.Websites
                if ($functionApps.Count -eq 0) {
                    $webApps = Get-AzWebApp -ResourceGroupName $rg.ResourceGroupName
                    $functionApps = $webApps | Where-Object { 
                        $_.Kind -like "*functionapp*" -or 
                        $_.SiteConfig.AppSettings.Name -contains "FUNCTIONS_EXTENSION_VERSION" 
                    }
                }
                
                if ($FunctionAppName) {
                    $functionApps = $functionApps | Where-Object { $_.Name -eq $FunctionAppName }
                }
                
                Write-Host "         Found $($functionApps.Count) Function App(s)" -ForegroundColor Gray
                $totalFunctionApps += $functionApps.Count
                
                foreach ($app in $functionApps) {
                    Write-Host "            Analyzing: $($app.Name)" -ForegroundColor White
                    
                    $config = Get-FunctionAppConfig -SubscriptionId $subscription.Id -ResourceGroupName $rg.ResourceGroupName -FunctionAppName $app.Name
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
    Write-Host " Azure Function App Bundle Scanner Results" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    
    if ($allResults.Count -eq 0) {
        Write-Host "No Function Apps found matching the criteria." -ForegroundColor Yellow
        exit 0
    }
    
    # Group results by subscription for better organization
    $groupedResults = $allResults | Group-Object SubscriptionName
    
    foreach ($group in $groupedResults) {
        Write-Host "Subscription: $($group.Name)" -ForegroundColor Yellow
        Write-Host "Subscription ID: $($group.Group[0].SubscriptionId)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host " Function Apps Found: $($group.Group.Count)" -ForegroundColor Green
        Write-Host ""
        
        switch ($OutputFormat) {
            "Table" {
                $group.Group | Format-Table -Property FunctionAppName, ResourceGroupName, Location, State, RuntimeStack, FunctionsExtensionVersion, ExtensionBundleId, ExtensionBundleVersion, AlwaysOn -AutoSize
            }
            "List" {
                foreach ($result in $group.Group) {
                    Write-Host " Detailed Results:" -ForegroundColor Cyan
                    Write-Host "===================" -ForegroundColor Cyan
                    Write-Host "Function App Name: $($result.FunctionAppName)" -ForegroundColor White
                    Write-Host "Resource Group: $($result.ResourceGroupName)" -ForegroundColor White
                    Write-Host "Location: $($result.Location)" -ForegroundColor White
                    Write-Host "State: $($result.State)" -ForegroundColor White
                    Write-Host "Runtime: $($result.RuntimeStack)" -ForegroundColor White
                    Write-Host "Runtime Version: $($result.RuntimeVersion)" -ForegroundColor White
                    Write-Host "Functions Extension Version: $($result.FunctionsExtensionVersion)" -ForegroundColor White
                    Write-Host "Extension Bundle ID: $($result.ExtensionBundleId)" -ForegroundColor White
                    Write-Host "Extension Bundle Version: $($result.ExtensionBundleVersion)" -ForegroundColor White
                    Write-Host "Always On: $($result.AlwaysOn)" -ForegroundColor White
                    Write-Host "Platform: $(if ($result.Use32BitWorkerProcess) { '32-bit' } else { '64-bit' })" -ForegroundColor White
                    Write-Host ""
                }
            }
            "CSV" {
                $allResults | Export-Csv -Path $ExportPath -NoTypeInformation
                Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
            }
            "JSON" {
                $allResults | ConvertTo-Json -Depth 3 | Out-File -FilePath $ExportPath -Encoding UTF8
                Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
            }
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host " Summary:" -ForegroundColor Yellow
    $runtimeSummary = $allResults | Group-Object RuntimeStack
    foreach ($runtime in $runtimeSummary) {
        Write-Host " $($runtime.Count) Function App(s) using $($runtime.Name) runtime" -ForegroundColor Gray
    }
    
    $versionSummary = $allResults | Group-Object FunctionsExtensionVersion
    foreach ($version in $versionSummary) {
        Write-Host " $($version.Count) Function App(s) using Functions Extension Version $($version.Name)" -ForegroundColor Gray
    }
    
    $bundleSummary = $allResults | Group-Object ExtensionBundleId
    foreach ($bundle in $bundleSummary) {
        if ($bundle.Name -ne "Not applicable (.NET runtime)") {
            Write-Host " $($bundle.Count) Function App(s) using Extension Bundle: $($bundle.Name)" -ForegroundColor Gray
        }
    }
    
    # Export to file if specified
    if ($ExportPath -and $OutputFormat -notin @("CSV", "JSON")) {
        switch ($OutputFormat) {
            "Table" {
                $allResults | Export-Csv -Path "$ExportPath.csv" -NoTypeInformation
                Write-Host "Results exported to: $ExportPath.csv" -ForegroundColor Green
            }
            "List" {
                $allResults | ConvertTo-Json -Depth 3 | Out-File -FilePath "$ExportPath.json" -Encoding UTF8
                Write-Host "Results exported to: $ExportPath.json" -ForegroundColor Green
            }
        }
    }
    
    Write-Host ""
    Write-Host "Scan completed successfully!" -ForegroundColor Green
    
    # Return results
    return $allResults
    
} catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}