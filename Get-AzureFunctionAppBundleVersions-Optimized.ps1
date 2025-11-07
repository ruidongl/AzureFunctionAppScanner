# Azure Function App Bundle Scanner - Optimized Version
# Uses resource provider scanning for better performance
# Requires Az.Accounts and Az.Resources modules

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

# Function to get Function App configuration using optimized method
function Get-FunctionAppConfigOptimized {
    param(
        [string]$ResourceGroupName,
        [string]$FunctionAppName,
        [string]$SubscriptionId,
        [object]$FunctionAppResource
    )
    
    try {
        Write-Verbose "Getting configuration for Function App: $FunctionAppName"
        
        # Get detailed Function App information
        $functionApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction Stop
        
        # Convert app settings format
        $appSettings = @{}
        if ($functionApp.SiteConfig.AppSettings) {
            foreach ($setting in $functionApp.SiteConfig.AppSettings) {
                $appSettings[$setting.Name] = $setting.Value
            }
        }
        
        # Initialize result object with resource information
        $result = [PSCustomObject]@{
            SubscriptionId = $SubscriptionId
            SubscriptionName = (Get-AzSubscription -SubscriptionId $SubscriptionId).Name
            ResourceGroupName = $ResourceGroupName
            FunctionAppName = $FunctionAppName
            Location = $FunctionAppResource.Location
            Kind = $FunctionAppResource.Kind
            ResourceType = $FunctionAppResource.ResourceType
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
            ResourceId = $FunctionAppResource.ResourceId
            Tags = if ($FunctionAppResource.Tags) { ($FunctionAppResource.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; " } else { "None" }
        }
        
        return $result
    }
    catch {
        Write-Error "Error getting configuration for Function App $FunctionAppName`: $($_.Exception.Message)"
        return $null
    }
}

# Function to get all Function Apps in a subscription using resource provider
function Get-FunctionAppsInSubscription {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupFilter = $null
    )
    
    Write-Host "      Using optimized resource provider scan..." -ForegroundColor Cyan
    
    # Get all Function Apps directly using resource provider queries
    # This is much more efficient than scanning each resource group individually
    $resourceQueries = @(
        "Microsoft.Web/sites[?kind contains 'functionapp']",
        "Microsoft.Web/sites[?kind contains 'functionapp,linux']",
        "Microsoft.Web/sites[?kind contains 'functionapp,workflowapp']"
    )
    
    $allFunctionApps = @()
    
    foreach ($query in $resourceQueries) {
        try {
            Write-Verbose "Executing resource query: $query"
            $resources = Search-AzGraph -Query "Resources | where type =~ 'microsoft.web/sites' and kind contains 'functionapp' | where subscriptionId == '$SubscriptionId'" -ErrorAction SilentlyContinue
            
            if ($resources) {
                # Filter by resource group if specified
                if ($ResourceGroupFilter) {
                    $resources = $resources | Where-Object { $_.resourceGroup -eq $ResourceGroupFilter }
                }
                
                $allFunctionApps += $resources
            }
        }
        catch {
            Write-Verbose "Resource Graph query failed, falling back to Get-AzResource: $($_.Exception.Message)"
            # Fallback to traditional method if Resource Graph is not available
            $resources = Get-AzResource -ResourceType "Microsoft.Web/sites" -ErrorAction SilentlyContinue | 
                         Where-Object { $_.Kind -like "*functionapp*" }
            
            if ($ResourceGroupFilter) {
                $resources = $resources | Where-Object { $_.ResourceGroupName -eq $ResourceGroupFilter }
            }
            
            # Convert to match Resource Graph format
            $resources = $resources | ForEach-Object {
                [PSCustomObject]@{
                    name = $_.Name
                    resourceGroup = $_.ResourceGroupName
                    location = $_.Location
                    kind = $_.Kind
                    type = $_.ResourceType
                    id = $_.ResourceId
                    tags = $_.Tags
                    subscriptionId = $SubscriptionId
                }
            }
            
            $allFunctionApps += $resources
        }
    }
    
    # Remove duplicates based on resource ID
    $uniqueFunctionApps = $allFunctionApps | Sort-Object id -Unique
    
    Write-Host "      Found $($uniqueFunctionApps.Count) Function App(s) using optimized scan" -ForegroundColor Green
    
    return $uniqueFunctionApps
}

# Main script execution
try {
    Write-Host "Azure Function App Bundle Version Scanner - Optimized" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    
    # Check if user is logged in to Azure
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not logged in to Azure. Please run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    
    # Check for required modules
    $requiredModules = @("Az.Accounts", "Az.Resources", "Az.Websites")
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            Write-Warning "Module $module is not installed. Some features may not work optimally."
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
    
    $allResults = @()
    $totalFunctionApps = 0
    $totalScanTime = Measure-Command {
        
        foreach ($subscription in $subscriptions) {
            Write-Host ""
            Write-Host "Processing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Blue
            
            # Set context to current subscription
            Set-AzContext -SubscriptionId $subscription.Id | Out-Null
            
            $subscriptionScanTime = Measure-Command {
                # Use optimized Function App discovery
                $functionApps = Get-FunctionAppsInSubscription -SubscriptionId $subscription.Id -ResourceGroupFilter $ResourceGroupName
                
                if ($functionApps -and $functionApps.Count -gt 0) {
                    $totalFunctionApps += $functionApps.Count
                    
                    # Group by resource group for processing
                    $functionAppsByRG = $functionApps | Group-Object resourceGroup
                    
                    foreach ($rgGroup in $functionAppsByRG) {
                        $rgName = $rgGroup.Name
                        Write-Host "      Processing resource group: $rgName ($($rgGroup.Count) apps)" -ForegroundColor Gray
                        
                        foreach ($app in $rgGroup.Group) {
                            Write-Host "         Analyzing: $($app.name)" -ForegroundColor White
                            
                            # Convert resource graph result to resource object format
                            $resourceObj = [PSCustomObject]@{
                                Name = $app.name
                                ResourceGroupName = $app.resourceGroup
                                Location = $app.location
                                Kind = $app.kind
                                ResourceType = $app.type
                                ResourceId = $app.id
                                Tags = $app.tags
                            }
                            
                            $config = Get-FunctionAppConfigOptimized -ResourceGroupName $rgName -FunctionAppName $app.name -SubscriptionId $subscription.Id -FunctionAppResource $resourceObj
                            if ($config) {
                                $allResults += $config
                            }
                        }
                    }
                } else {
                    Write-Host "      No Function Apps found in this subscription" -ForegroundColor Gray
                }
            }
            
            Write-Host "      Subscription scan completed in $([math]::Round($subscriptionScanTime.TotalSeconds, 2)) seconds" -ForegroundColor DarkGray
        }
    }
    
    # Display results
    Write-Host ""
    Write-Host "Scan Results Summary" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host "Total scan time: $([math]::Round($totalScanTime.TotalSeconds, 2)) seconds" -ForegroundColor Green
    Write-Host "Total Function Apps found: $totalFunctionApps" -ForegroundColor Green
    Write-Host "Successfully analyzed: $($allResults.Count)" -ForegroundColor Green
    Write-Host "Average time per app: $([math]::Round($totalScanTime.TotalSeconds / [math]::Max($totalFunctionApps, 1), 2)) seconds" -ForegroundColor Green
    
    if ($allResults.Count -eq 0) {
        Write-Host "No Function Apps found matching the criteria." -ForegroundColor Red
        exit 0
    }
    
    # Group by extension version for summary
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
    
    # Group by subscription for summary
    if ($subscriptions.Count -gt 1) {
        $subscriptionGroups = $allResults | Group-Object SubscriptionName | Sort-Object Name
        Write-Host ""
        Write-Host "Subscription Distribution:" -ForegroundColor Yellow
        foreach ($group in $subscriptionGroups) {
            Write-Host "   $($group.Name): $($group.Count) apps" -ForegroundColor White
        }
    }
    
    Write-Host ""
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    Write-Host "================" -ForegroundColor Cyan
    
    # Output results based on format
    switch ($OutputFormat) {
        "Table" {
            $allResults | Format-Table -Property FunctionAppName, ResourceGroupName, RuntimeStack, FunctionsExtensionVersion, FunctionsWorkerRuntimeVersion, AlwaysOn, State -AutoSize
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
    Write-Host "Optimized scan completed successfully!" -ForegroundColor Green
    Write-Host "Performance improvement: Scanned $totalFunctionApps apps in $([math]::Round($totalScanTime.TotalSeconds, 2)) seconds" -ForegroundColor Green
    
    # Return results
    return $allResults
    
} catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}