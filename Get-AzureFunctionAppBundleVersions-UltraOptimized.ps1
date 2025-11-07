# Azure Function App Bundle Scanner - Ultra-Optimized with Resource Graph
# Uses Azure Resource Graph for maximum performance
# Requires Az.Accounts, Az.Resources, Az.Websites, and Az.ResourceGraph modules

param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Table", "List", "CSV", "JSON")]
    [string]$OutputFormat = "Table",
    
    [Parameter(Mandatory = $false)]
    [string]$ExportPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$FastScan
)

# Function to get Function Apps using Azure Resource Graph (fastest method)
function Get-FunctionAppsWithResourceGraph {
    param(
        [string[]]$SubscriptionIds,
        [string]$ResourceGroupFilter = $null
    )
    
    Write-Host "      Using Azure Resource Graph for ultra-fast scanning..." -ForegroundColor Cyan
    
    # Build the query
    $query = @"
Resources
| where type =~ 'microsoft.web/sites'
| where kind contains 'functionapp'
| where subscriptionId in ({0})
| project name, resourceGroup, location, kind, type, id, tags, subscriptionId, properties
| order by name asc
"@ -f (($SubscriptionIds | ForEach-Object { "'$_'" }) -join ', ')
    
    # Add resource group filter if specified
    if ($ResourceGroupFilter) {
        $query += "`n| where resourceGroup =~ '$ResourceGroupFilter'"
    }
    
    try {
        Write-Verbose "Executing Azure Resource Graph query"
        $resources = Search-AzGraph -Query $query -First 1000
        
        Write-Host "      Found $($resources.Count) Function App(s) using Resource Graph" -ForegroundColor Green
        return $resources
    }
    catch {
        Write-Warning "Azure Resource Graph query failed: $($_.Exception.Message)"
        Write-Host "      Falling back to traditional scanning method..." -ForegroundColor Yellow
        return $null
    }
}

# Function to get Function App configuration in batch (for fast scan)
function Get-FunctionAppConfigBatch {
    param(
        [array]$FunctionApps,
        [hashtable]$SubscriptionNames
    )
    
    $results = @()
    $totalApps = $FunctionApps.Count
    $currentApp = 0
    
    foreach ($app in $FunctionApps) {
        $currentApp++
        $percentComplete = [math]::Round(($currentApp / $totalApps) * 100, 1)
        
        Write-Progress -Activity "Analyzing Function Apps" -Status "Processing $($app.name) ($currentApp of $totalApps)" -PercentComplete $percentComplete
        
        try {
            if ($FastScan) {
                # Fast scan - only get basic information without detailed app settings
                $result = [PSCustomObject]@{
                    SubscriptionId = $app.subscriptionId
                    SubscriptionName = $SubscriptionNames[$app.subscriptionId]
                    ResourceGroupName = $app.resourceGroup
                    FunctionAppName = $app.name
                    Location = $app.location
                    Kind = $app.kind
                    ResourceType = $app.type
                    State = "Unknown (FastScan)"
                    RuntimeStack = "Unknown (FastScan)"
                    FunctionsExtensionVersion = "Unknown (FastScan)"
                    FunctionsWorkerRuntimeVersion = "N/A (FastScan)"
                    NodeVersion = "N/A (FastScan)"
                    NetFrameworkVersion = "N/A (FastScan)"
                    AlwaysOn = "Unknown (FastScan)"
                    Use32BitWorkerProcess = "Unknown (FastScan)"
                    DefaultDocuments = "N/A (FastScan)"
                    ExtensionBundleId = "Not Available via API"
                    ExtensionBundleVersion = "Not Available via API"
                    LastModifiedTime = "Unknown (FastScan)"
                    ResourceId = $app.id
                    Tags = if ($app.tags) { ($app.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "None" }
                }
            }
            else {
                # Full scan - get detailed information
                # Set context to the subscription
                Set-AzContext -SubscriptionId $app.subscriptionId | Out-Null
                
                $functionApp = Get-AzWebApp -ResourceGroupName $app.resourceGroup -Name $app.name -ErrorAction Stop
                
                # Convert app settings format
                $appSettings = @{}
                if ($functionApp.SiteConfig.AppSettings) {
                    foreach ($setting in $functionApp.SiteConfig.AppSettings) {
                        $appSettings[$setting.Name] = $setting.Value
                    }
                }
                
                $result = [PSCustomObject]@{
                    SubscriptionId = $app.subscriptionId
                    SubscriptionName = $SubscriptionNames[$app.subscriptionId]
                    ResourceGroupName = $app.resourceGroup
                    FunctionAppName = $app.name
                    Location = $app.location
                    Kind = $app.kind
                    ResourceType = $app.type
                    State = $functionApp.State
                    RuntimeStack = if ($appSettings["FUNCTIONS_WORKER_RUNTIME"]) { $appSettings["FUNCTIONS_WORKER_RUNTIME"] } else { "Unknown" }
                    FunctionsExtensionVersion = if ($appSettings["FUNCTIONS_EXTENSION_VERSION"]) { $appSettings["FUNCTIONS_EXTENSION_VERSION"] } else { "Unknown" }
                    FunctionsWorkerRuntimeVersion = if ($appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"]) { $appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"] } else { "N/A" }
                    NodeVersion = if ($appSettings["WEBSITE_NODE_DEFAULT_VERSION"]) { $appSettings["WEBSITE_NODE_DEFAULT_VERSION"] } else { "N/A" }
                    NetFrameworkVersion = if ($functionApp.SiteConfig.NetFrameworkVersion) { $functionApp.SiteConfig.NetFrameworkVersion } else { "N/A" }
                    AlwaysOn = $functionApp.SiteConfig.AlwaysOn
                    Use32BitWorkerProcess = $functionApp.SiteConfig.Use32BitWorkerProcess
                    DefaultDocuments = ($functionApp.SiteConfig.DefaultDocuments -join ", ")
                    ExtensionBundleId = "Not Available via API"
                    ExtensionBundleVersion = "Not Available via API"
                    LastModifiedTime = $functionApp.LastModifiedTimeUtc
                    ResourceId = $app.id
                    Tags = if ($app.tags) { ($app.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "None" }
                }
            }
            
            $results += $result
        }
        catch {
            Write-Warning "Error processing Function App $($app.name): $($_.Exception.Message)"
        }
    }
    
    Write-Progress -Activity "Analyzing Function Apps" -Completed
    return $results
}

# Main script execution
try {
    Write-Host "Azure Function App Bundle Version Scanner - Ultra-Optimized" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    
    if ($FastScan) {
        Write-Host "FAST SCAN MODE: Basic information only (much faster)" -ForegroundColor Yellow
    }
    
    # Check if user is logged in to Azure
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not logged in to Azure. Please run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    
    # Check for required modules
    $requiredModules = @("Az.Accounts", "Az.Resources", "Az.ResourceGraph")
    if (-not $FastScan) {
        $requiredModules += "Az.Websites"
    }
    
    $missingModules = @()
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Warning "Missing modules: $($missingModules -join ', '). Install with: Install-Module $($missingModules -join ', ')"
        if ($missingModules -contains "Az.ResourceGraph") {
            Write-Host "Falling back to less optimized scanning..." -ForegroundColor Yellow
        }
    }
    
    # Get subscriptions to scan
    $subscriptions = @()
    if ($SubscriptionId) {
        $subscriptions = @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        Write-Host "Scanning specific subscription: $($subscriptions[0].Name)" -ForegroundColor Yellow
    } else {
        $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
        Write-Host "Scanning all accessible subscriptions ($($subscriptions.Count) found)" -ForegroundColor Yellow
    }
    
    # Create subscription name lookup
    $subscriptionNames = @{}
    foreach ($sub in $subscriptions) {
        $subscriptionNames[$sub.Id] = $sub.Name
    }
    
    $allResults = @()
    $totalScanTime = Measure-Command {
        
        # Try to use Azure Resource Graph for ultra-fast scanning
        $subscriptionIds = $subscriptions | ForEach-Object { $_.Id }
        $functionApps = Get-FunctionAppsWithResourceGraph -SubscriptionIds $subscriptionIds -ResourceGroupFilter $ResourceGroupName
        
        if ($functionApps) {
            Write-Host ""
            Write-Host "Resource Graph scan found $($functionApps.Count) Function Apps across all subscriptions" -ForegroundColor Green
            
            if ($functionApps.Count -gt 0) {
                # Process all Function Apps in batch
                $allResults = Get-FunctionAppConfigBatch -FunctionApps $functionApps -SubscriptionNames $subscriptionNames
            }
        }
        else {
            # Fallback to per-subscription scanning
            Write-Host "Using fallback scanning method..." -ForegroundColor Yellow
            
            foreach ($subscription in $subscriptions) {
                Write-Host ""
                Write-Host "Processing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Blue
                
                Set-AzContext -SubscriptionId $subscription.Id | Out-Null
                
                # Get Function Apps using traditional method
                if ($ResourceGroupName) {
                    $resources = Get-AzResource -ResourceType "Microsoft.Web/sites" -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
                } else {
                    $resources = Get-AzResource -ResourceType "Microsoft.Web/sites" -ErrorAction SilentlyContinue
                }
                
                $functionApps = $resources | Where-Object { $_.Kind -like "*functionapp*" }
                
                if ($functionApps) {
                    Write-Host "   Found $($functionApps.Count) Function App(s)" -ForegroundColor Green
                    
                    # Convert to Resource Graph format for consistency
                    $convertedApps = $functionApps | ForEach-Object {
                        [PSCustomObject]@{
                            name = $_.Name
                            resourceGroup = $_.ResourceGroupName
                            location = $_.Location
                            kind = $_.Kind
                            type = $_.ResourceType
                            id = $_.ResourceId
                            tags = $_.Tags
                            subscriptionId = $subscription.Id
                        }
                    }
                    
                    $results = Get-FunctionAppConfigBatch -FunctionApps $convertedApps -SubscriptionNames $subscriptionNames
                    $allResults += $results
                }
            }
        }
    }
    
    # Display results
    Write-Host ""
    Write-Host "Scan Results Summary" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host "Total scan time: $([math]::Round($totalScanTime.TotalSeconds, 2)) seconds" -ForegroundColor Green
    Write-Host "Total Function Apps found: $($allResults.Count)" -ForegroundColor Green
    if ($allResults.Count -gt 0) {
        Write-Host "Average time per app: $([math]::Round($totalScanTime.TotalSeconds / $allResults.Count, 2)) seconds" -ForegroundColor Green
    }
    
    if ($allResults.Count -eq 0) {
        Write-Host "No Function Apps found matching the criteria." -ForegroundColor Red
        exit 0
    }
    
    # Group by extension version for summary (skip for fast scan)
    if (-not $FastScan) {
        $extensionVersions = $allResults | Group-Object FunctionsExtensionVersion | Sort-Object Name
        Write-Host ""
        Write-Host "Extension Version Distribution:" -ForegroundColor Yellow
        foreach ($group in $extensionVersions) {
            Write-Host "   $($group.Name): $($group.Count) apps" -ForegroundColor White
        }
        
        # Group by runtime for summary
        $runtimes = $allResults | Group-Object RuntimeStack | Sort-Object Name
        Write-Host ""
        Write-Host "Runtime Distribution:" -ForegroundColor Yellow
        foreach ($group in $runtimes) {
            Write-Host "   $($group.Name): $($group.Count) apps" -ForegroundColor White
        }
    }
    
    # Group by subscription for summary
    if ($subscriptions.Count -gt 1) {
        $subscriptionGroups = $allResults | Group-Object SubscriptionName | Sort-Object Name
        Write-Host ""
        Write-Host "Subscription Distribution:" -ForegroundColor Yellow
        foreach ($group in $subscriptionGroups) {
            Write-Host "   $($group.Name): $($group.Count) apps" -ForegroundColor White
        }
    }
    
    # Group by resource group
    $resourceGroupGroups = $allResults | Group-Object ResourceGroupName | Sort-Object Count -Descending | Select-Object -First 10
    Write-Host ""
    Write-Host "Top 10 Resource Groups by Function App Count:" -ForegroundColor Yellow
    foreach ($group in $resourceGroupGroups) {
        Write-Host "   $($group.Name): $($group.Count) apps" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    Write-Host "================" -ForegroundColor Cyan
    
    # Output results based on format
    switch ($OutputFormat) {
        "Table" {
            if ($FastScan) {
                $allResults | Format-Table -Property FunctionAppName, ResourceGroupName, SubscriptionName, Location, Kind -AutoSize
            } else {
                $allResults | Format-Table -Property FunctionAppName, ResourceGroupName, RuntimeStack, FunctionsExtensionVersion, FunctionsWorkerRuntimeVersion, AlwaysOn, State -AutoSize
            }
        }
        "List" {
            $allResults | Format-List -Property *
        }
        "CSV" {
            $allResults | Format-Table -Property * -AutoSize
            if ($ExportPath) {
                $allResults | Export-Csv -Path $ExportPath -NoTypeInformation
                Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
            }
        }
        "JSON" {
            $jsonOutput = $allResults | ConvertTo-Json -Depth 3
            Write-Host $jsonOutput
            if ($ExportPath) {
                $jsonOutput | Out-File -FilePath $ExportPath -Encoding UTF8
                Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
            }
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
    Write-Host "Ultra-optimized scan completed successfully!" -ForegroundColor Green
    Write-Host "Performance: Scanned $($allResults.Count) apps in $([math]::Round($totalScanTime.TotalSeconds, 2)) seconds using $(if ($functionApps) { 'Azure Resource Graph' } else { 'Traditional scanning' })" -ForegroundColor Green
    
    if ($FastScan) {
        Write-Host "Note: Run without -FastScan switch for detailed configuration information" -ForegroundColor Cyan
    }
    
    # Return results
    return $allResults
    
} catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}