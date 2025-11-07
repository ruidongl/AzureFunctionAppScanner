# Azure Function App Bundle Scanner - PowerShell 5.1 Compatible with Resource Graph Optimization
# Requires Az.Accounts, Az.Websites, and Az.ResourceGraph modules

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
    [switch]$UseResourceGraph = $false
)

# Check and import required modules
$requiredModules = @('Az.Accounts', 'Az.Websites')
$optionalModules = @('Az.ResourceGraph')

foreach ($module in $requiredModules) {
    if (-not (Get-Module -Name $module -ListAvailable)) {
        Write-Error "Required module '$module' is not installed. Please install it using: Install-Module -Name $module"
        exit 1
    }
    Import-Module -Name $module -Force
}

# Check for optional Az.ResourceGraph module
if ($UseResourceGraph) {
    if (Get-Module -Name 'Az.ResourceGraph' -ListAvailable) {
        try {
            # Check version compatibility before importing
            $azAccountsVersion = (Get-Module -Name 'Az.Accounts' | Select-Object -First 1).Version
            $resourceGraphModule = Get-Module -Name 'Az.ResourceGraph' -ListAvailable | Select-Object -First 1
            
            Write-Host "Checking Az.ResourceGraph compatibility..." -ForegroundColor Cyan
            Write-Host "  Az.Accounts version: $azAccountsVersion" -ForegroundColor Gray
            Write-Host "  Az.ResourceGraph version: $($resourceGraphModule.Version)" -ForegroundColor Gray
            
            # Try to import the module
            Import-Module -Name 'Az.ResourceGraph' -Force -ErrorAction Stop
            Write-Host "  âœ… Az.ResourceGraph module loaded successfully" -ForegroundColor Green
        } catch {
            Write-Host "  âš ï¸ Az.ResourceGraph module compatibility issue:" -ForegroundColor Yellow
            Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  ðŸ”„ Disabling Resource Graph optimization, using traditional scanning" -ForegroundColor Yellow
            $UseResourceGraph = $false
        }
    } else {
        Write-Host "Az.ResourceGraph module not found. Using traditional scanning." -ForegroundColor Yellow
        Write-Host "For better performance, install it using: Install-Module -Name Az.ResourceGraph" -ForegroundColor Cyan
        $UseResourceGraph = $false
    }
}

# Function to discover Function Apps using Azure Resource Graph (much faster)
function Find-FunctionAppsWithResourceGraph {
    param(
        [string[]]$SubscriptionIds,
        [string]$ResourceGroupName
    )
    
    try {
        Write-Host "  ðŸ“Š Executing Resource Graph query across specified subscriptions..." -ForegroundColor Cyan
        
        # Build the Resource Graph query
        $query = @"
resources
| where type =~ 'Microsoft.Web/sites'
| where kind contains 'functionapp'
| project subscriptionId, resourceGroup, name, location, kind, properties
| order by subscriptionId, resourceGroup, name
"@

        # Add resource group filter if specified
        if ($ResourceGroupName) {
            $query = $query.Replace("| order by", "| where resourceGroup =~ '$ResourceGroupName'`n| order by")
        }
        
        # Add subscription filter if specified
        if ($SubscriptionIds -and $SubscriptionIds.Count -gt 0) {
            $subscriptionFilter = $SubscriptionIds | ForEach-Object { "'$_'" } 
            $subscriptionFilterString = $subscriptionFilter -join ","
            $query = $query.Replace("| where type", "| where subscriptionId in ($subscriptionFilterString)`n| where type")
        }
        
        Write-Verbose "Resource Graph Query: $query"
        
        # Execute the query
        $functionApps = Search-AzGraph -Query $query -First 1000
        
        if ($functionApps) {
            Write-Host "  âœ… Resource Graph found $($functionApps.Count) Function App(s) across all specified subscriptions" -ForegroundColor Green
            return $functionApps
        } else {
            Write-Host "  âš ï¸ No Function Apps found using Resource Graph" -ForegroundColor Yellow
            return @()
        }
        
    } catch {
        Write-Host "  âŒ Resource Graph query failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  ðŸ”„ Falling back to traditional resource group scanning..." -ForegroundColor Yellow
        return $null
    }
}

# Function to get Function App configuration using compatible methods
function Get-FunctionAppConfigCompatible {
    param(
        [string]$ResourceGroupName,
        [string]$FunctionAppName,
        [string]$SubscriptionId
    )
    
    try {
        Write-Verbose "Getting configuration for Function App: $FunctionAppName"
        
        # Use Az.Websites which is more compatible
        $functionApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction Stop
        
        # Convert app settings format
        $appSettings = @{}
        if ($functionApp.SiteConfig.AppSettings) {
            foreach ($setting in $functionApp.SiteConfig.AppSettings) {
                $appSettings[$setting.Name] = $setting.Value
            }
        }
        
        # Enhanced Runtime Stack Detection with multiple fallback methods
        $runtimeStack = "Unknown"
        if ($appSettings["FUNCTIONS_WORKER_RUNTIME"]) {
            $runtimeStack = $appSettings["FUNCTIONS_WORKER_RUNTIME"]
            # Check for isolated worker process
            if ($runtimeStack -eq "dotnet" -and $appSettings["FUNCTIONS_INPROC_SCOPE_ALIAS"] -eq $null -and $functionApp.SiteConfig.NetFrameworkVersion -like "v6*") {
                $runtimeStack = "dotnet-isolated"
            }
        } elseif ($functionApp.Kind -like "*linux*") {
            # For Linux Function Apps, analyze LinuxFxVersion
            if ($functionApp.SiteConfig.LinuxFxVersion) {
                $linuxFx = $functionApp.SiteConfig.LinuxFxVersion.ToLower()
                if ($linuxFx -like "*python*") { $runtimeStack = "python" }
                elseif ($linuxFx -like "*node*") { $runtimeStack = "node" }
                elseif ($linuxFx -like "*dotnet*") { 
                    # Check if it's isolated based on .NET version
                    if ($linuxFx -like "*dotnet|6*" -or $linuxFx -like "*dotnet|7*" -or $linuxFx -like "*dotnet|8*") {
                        $runtimeStack = "dotnet-isolated"
                    } else {
                        $runtimeStack = "dotnet"
                    }
                }
                elseif ($linuxFx -like "*java*") { $runtimeStack = "java" }
                elseif ($linuxFx -like "*powershell*") { $runtimeStack = "powershell" }
            }
        } elseif ($functionApp.SiteConfig.NetFrameworkVersion) {
            # For Windows apps, determine if isolated or in-process
            if ($functionApp.SiteConfig.NetFrameworkVersion -like "v6*" -or $functionApp.SiteConfig.NetFrameworkVersion -like "v7*" -or $functionApp.SiteConfig.NetFrameworkVersion -like "v8*") {
                # .NET 6+ typically indicates isolated worker process
                $runtimeStack = "dotnet-isolated"
            } else {
                $runtimeStack = "dotnet"
            }
        }
        
        # Enhanced Functions Worker Runtime Version Detection with comprehensive fallbacks
        $workerRuntimeVersion = "N/A"
        if ($appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"]) {
            $workerRuntimeVersion = $appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"]
        } else {
            # Multiple fallback methods based on runtime type
            switch ($runtimeStack) {
                "python" {
                    # Try multiple Python version sources
                    if ($appSettings["PYTHON_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["PYTHON_VERSION"]
                    } elseif ($functionApp.SiteConfig.LinuxFxVersion -match "PYTHON\|(.+)") {
                        $workerRuntimeVersion = $matches[1]
                    } elseif ($appSettings["PYTHONPATH"]) {
                        # Sometimes version can be inferred from Python path
                        Write-Verbose "Found Python path, version may be determinable: $($appSettings["PYTHONPATH"])"
                        $workerRuntimeVersion = "Check Python path"
                    } else {
                        $workerRuntimeVersion = "Python (version not specified)"
                    }
                }
                "node" {
                    # Try multiple Node.js version sources
                    if ($appSettings["WEBSITE_NODE_DEFAULT_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["WEBSITE_NODE_DEFAULT_VERSION"]
                    } elseif ($functionApp.SiteConfig.LinuxFxVersion -match "NODE\|(.+)") {
                        $workerRuntimeVersion = $matches[1]
                    } elseif ($appSettings["NODE_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["NODE_VERSION"]
                    } else {
                        $workerRuntimeVersion = "Node.js (version not specified)"
                    }
                }
                { $_ -in @("dotnet", "dotnet-isolated") } {
                    # Try multiple .NET version sources
                    if ($functionApp.SiteConfig.NetFrameworkVersion) {
                        # Map .NET Framework version to more descriptive format
                        $netVersion = $functionApp.SiteConfig.NetFrameworkVersion
                        if ($runtimeStack -eq "dotnet-isolated") {
                            $workerRuntimeVersion = "$netVersion (Isolated)"
                        } else {
                            $workerRuntimeVersion = "$netVersion (In-Process)"
                        }
                    } elseif ($appSettings["DOTNET_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["DOTNET_VERSION"]
                    } elseif ($functionApp.SiteConfig.LinuxFxVersion -match "DOTNET\|(.+)") {
                        $workerRuntimeVersion = $matches[1]
                        if ($runtimeStack -eq "dotnet-isolated") {
                            $workerRuntimeVersion += " (Isolated)"
                        }
                    } elseif ($appSettings["FUNCTIONS_EXTENSION_VERSION"] -like "~4*") {
                        # For Functions v4, determine .NET version based on runtime type
                        if ($runtimeStack -eq "dotnet-isolated") {
                            $workerRuntimeVersion = ".NET 6.0+ (Isolated - Functions v4)"
                        } else {
                            $workerRuntimeVersion = ".NET 6.0+ (In-Process - Functions v4)"
                        }
                    } elseif ($appSettings["FUNCTIONS_EXTENSION_VERSION"] -like "~3*") {
                        $workerRuntimeVersion = ".NET Core 3.1 (Functions v3)"
                    } else {
                        if ($runtimeStack -eq "dotnet-isolated") {
                            $workerRuntimeVersion = ".NET (Isolated worker process)"
                        } else {
                            $workerRuntimeVersion = ".NET (In-process)"
                        }
                    }
                }
                "java" {
                    # Try multiple Java version sources
                    if ($appSettings["JAVA_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["JAVA_VERSION"]
                    } elseif ($functionApp.SiteConfig.LinuxFxVersion -match "JAVA\|(.+)") {
                        $workerRuntimeVersion = $matches[1]
                    } elseif ($functionApp.SiteConfig.JavaVersion) {
                        $workerRuntimeVersion = $functionApp.SiteConfig.JavaVersion
                    } else {
                        $workerRuntimeVersion = "Java (version not specified)"
                    }
                }
                "powershell" {
                    # Try PowerShell version sources
                    if ($appSettings["POWERSHELL_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["POWERSHELL_VERSION"]
                    } elseif ($functionApp.SiteConfig.LinuxFxVersion -match "POWERSHELL\|(.+)") {
                        $workerRuntimeVersion = $matches[1]
                    } elseif ($appSettings["FUNCTIONS_EXTENSION_VERSION"] -like "~4*") {
                        $workerRuntimeVersion = "PowerShell 7.x (Functions v4)"
                    } elseif ($appSettings["FUNCTIONS_EXTENSION_VERSION"] -like "~3*") {
                        $workerRuntimeVersion = "PowerShell 7.0 (Functions v3)"
                    } else {
                        $workerRuntimeVersion = "PowerShell (version not specified)"
                    }
                }
                default {
                    $workerRuntimeVersion = "Unknown runtime"
                }
            }
        }
        
        # Initialize result object with enhanced information
        $result = [PSCustomObject]@{
            SubscriptionId = $SubscriptionId
            SubscriptionName = (Get-AzSubscription -SubscriptionId $SubscriptionId).Name
            ResourceGroupName = $ResourceGroupName
            FunctionAppName = $FunctionAppName
            Location = $functionApp.Location
            Kind = $functionApp.Kind
            State = $functionApp.State
            RuntimeStack = $runtimeStack
            FunctionsExtensionVersion = if ($appSettings["FUNCTIONS_EXTENSION_VERSION"]) { $appSettings["FUNCTIONS_EXTENSION_VERSION"] } else { "Unknown" }
            FunctionsWorkerRuntimeVersion = $workerRuntimeVersion
            NodeVersion = if ($appSettings["WEBSITE_NODE_DEFAULT_VERSION"]) { $appSettings["WEBSITE_NODE_DEFAULT_VERSION"] } else { "N/A" }
            PythonVersion = if ($runtimeStack -eq "python" -and $appSettings["PYTHON_VERSION"]) { $appSettings["PYTHON_VERSION"] } else { "N/A" }
            NetFrameworkVersion = if ($functionApp.SiteConfig.NetFrameworkVersion) { $functionApp.SiteConfig.NetFrameworkVersion } else { "N/A" }
            LinuxFxVersion = if ($functionApp.SiteConfig.LinuxFxVersion) { $functionApp.SiteConfig.LinuxFxVersion } else { "N/A" }
            AlwaysOn = $functionApp.SiteConfig.AlwaysOn
            Use32BitWorkerProcess = $functionApp.SiteConfig.Use32BitWorkerProcess
            DefaultDocuments = ($functionApp.SiteConfig.DefaultDocuments -join ", ")
            ExtensionBundleId = "Not Available via API"
            ExtensionBundleVersion = "Not Available via API"
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
    Write-Host "Azure Function App Bundle Version Scanner" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    
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
    
    # Try Resource Graph approach first (much more efficient)
    if ($UseResourceGraph) {
        Write-Host ""
        Write-Host "ðŸš€ Using Azure Resource Graph for high-performance Function App discovery..." -ForegroundColor Cyan
        
        $subscriptionIds = $subscriptions | ForEach-Object { $_.Id }
        $resourceGraphFunctionApps = Find-FunctionAppsWithResourceGraph -SubscriptionIds $subscriptionIds -ResourceGroupName $ResourceGroupName
        
        if ($resourceGraphFunctionApps) {
            Write-Host "âœ… Resource Graph optimization successful!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Processing Function Apps found via Resource Graph..." -ForegroundColor Blue
            
            # Group by subscription for organized processing
            $functionAppsBySubscription = $resourceGraphFunctionApps | Group-Object -Property subscriptionId
            
            foreach ($subGroup in $functionAppsBySubscription) {
                $currentSubscription = $subscriptions | Where-Object { $_.Id -eq $subGroup.Name }
                if (-not $currentSubscription) {
                    Write-Warning "Subscription $($subGroup.Name) not found in accessible subscriptions"
                    continue
                }
                
                Write-Host ""
                Write-Host "Processing subscription: $($currentSubscription.Name) ($($currentSubscription.Id))" -ForegroundColor Blue
                Write-Host "   Found $($subGroup.Group.Count) Function App(s) via Resource Graph" -ForegroundColor Green
                
                # Set context to current subscription
                Set-AzContext -SubscriptionId $currentSubscription.Id | Out-Null
                
                $totalFunctionApps += $subGroup.Group.Count
                
                foreach ($app in $subGroup.Group) {
                    Write-Host "      Analyzing: $($app.name) (Resource Group: $($app.resourceGroup))" -ForegroundColor White
                    
                    $config = Get-FunctionAppConfigCompatible -ResourceGroupName $app.resourceGroup -FunctionAppName $app.name -SubscriptionId $currentSubscription.Id
                    if ($config) {
                        $allResults += $config
                    }
                }
            }
        } else {
            Write-Host "âš ï¸ Resource Graph returned no results. Falling back to traditional scanning..." -ForegroundColor Yellow
            $UseResourceGraph = $false
        }
    }
    
    # Fallback to traditional resource group scanning if Resource Graph failed or disabled
    if (-not $UseResourceGraph -or -not $resourceGraphFunctionApps) {
        Write-Host ""
        Write-Host "ðŸ” Using traditional resource group scanning..." -ForegroundColor Yellow
    
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
            
            # Get Function Apps in this resource group using Az.Websites
            $allWebApps = Get-AzWebApp -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
            $functionApps = $allWebApps | Where-Object { $_.Kind -like "*functionapp*" }
            
            if ($functionApps) {
                Write-Host "         Found $($functionApps.Count) Function App(s)" -ForegroundColor Green
                $totalFunctionApps += $functionApps.Count
                
                foreach ($app in $functionApps) {
                    Write-Host "            Analyzing: $($app.Name)" -ForegroundColor White
                    
                    $config = Get-FunctionAppConfigCompatible -ResourceGroupName $rg.ResourceGroupName -FunctionAppName $app.Name -SubscriptionId $subscription.Id
                    if ($config) {
                        $allResults += $config
                    }
                }
            } else {
                Write-Host "         No Function Apps found" -ForegroundColor Gray
            }
        }
    }
    } # End of traditional scanning fallback
    
    # Display results
    Write-Host ""
    Write-Host "Scan Results Summary" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host "Total Function Apps found: $totalFunctionApps" -ForegroundColor Green
    Write-Host "Successfully analyzed: $($allResults.Count)" -ForegroundColor Green
    
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
    
    # Show runtime version detection success
    $totalApps = $allResults.Count
    $appsWithRuntimeVersion = ($allResults | Where-Object { 
        $_.FunctionsWorkerRuntimeVersion -ne "N/A" -and 
        $_.FunctionsWorkerRuntimeVersion -ne "Unknown runtime" 
    }).Count
    
    Write-Host ""
    Write-Host "Runtime Version Detection Success:" -ForegroundColor Cyan
    Write-Host "   Apps with detected runtime version: $appsWithRuntimeVersion/$totalApps ($([math]::Round($appsWithRuntimeVersion/$totalApps*100, 1))%)" -ForegroundColor Green
    
    # Show apps still missing runtime version info
    $appsWithMissingVersion = $allResults | Where-Object { 
        $_.FunctionsWorkerRuntimeVersion -eq "N/A" -or 
        $_.FunctionsWorkerRuntimeVersion -eq "Unknown runtime" 
    }
    
    if ($appsWithMissingVersion.Count -gt 0) {
        Write-Host "   Apps with missing runtime version:" -ForegroundColor Yellow
        foreach ($app in $appsWithMissingVersion) {
            Write-Host "      $($app.FunctionAppName) ($($app.RuntimeStack))" -ForegroundColor White
        }
    }
    
    Write-Host ""
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    Write-Host "================" -ForegroundColor Cyan
    
    # Output results based on format
    switch ($OutputFormat) {
        "Table" {
            $allResults | Format-Table -Property FunctionAppName, ResourceGroupName, RuntimeStack, FunctionsExtensionVersion, FunctionsWorkerRuntimeVersion, PythonVersion, NodeVersion, AlwaysOn, State -AutoSize
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
    Write-Host "Scan completed successfully!" -ForegroundColor Green
    
    # Return results
    return $allResults
    
} catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
