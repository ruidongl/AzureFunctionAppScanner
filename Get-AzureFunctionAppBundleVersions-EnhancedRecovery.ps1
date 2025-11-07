# Azure Function App Bundle Scanner - Enhanced Version with Missing Information Recovery
# Addresses issues with FunctionsWorkerRuntimeVersion and ExtensionBundleVersion detection
# Requires Az.Accounts, Az.Resources, Az.Websites, and optionally Az.ResourceGraph modules

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

# Enhanced function to get Function App configuration with comprehensive information retrieval
function Get-FunctionAppConfigComprehensive {
    param(
        [string]$ResourceGroupName,
        [string]$FunctionAppName,
        [string]$SubscriptionId,
        [object]$FunctionAppResource,
        [hashtable]$SubscriptionNames
    )
    
    try {
        Write-Verbose "Getting enhanced configuration for Function App: $FunctionAppName"
        
        # Get detailed Function App information
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
        } elseif ($functionApp.Kind -like "*linux*") {
            # For Linux Function Apps, analyze LinuxFxVersion
            if ($functionApp.SiteConfig.LinuxFxVersion) {
                $linuxFx = $functionApp.SiteConfig.LinuxFxVersion.ToLower()
                if ($linuxFx -like "*python*") { $runtimeStack = "python" }
                elseif ($linuxFx -like "*node*") { $runtimeStack = "node" }
                elseif ($linuxFx -like "*dotnet*") { $runtimeStack = "dotnet" }
                elseif ($linuxFx -like "*java*") { $runtimeStack = "java" }
                elseif ($linuxFx -like "*powershell*") { $runtimeStack = "powershell" }
            }
        } elseif ($functionApp.SiteConfig.NetFrameworkVersion) {
            # For Windows apps, infer from .NET Framework version
            $runtimeStack = "dotnet"
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
                        $workerRuntimeVersion = "Check Python path: $($appSettings["PYTHONPATH"])"
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
                    }
                }
                "dotnet" {
                    # Try multiple .NET version sources
                    if ($functionApp.SiteConfig.NetFrameworkVersion) {
                        $workerRuntimeVersion = $functionApp.SiteConfig.NetFrameworkVersion
                    } elseif ($appSettings["DOTNET_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["DOTNET_VERSION"]
                    } elseif ($functionApp.SiteConfig.LinuxFxVersion -match "DOTNET\|(.+)") {
                        $workerRuntimeVersion = $matches[1]
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
                    }
                }
                "powershell" {
                    # Try PowerShell version sources
                    if ($appSettings["POWERSHELL_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["POWERSHELL_VERSION"]
                    } elseif ($functionApp.SiteConfig.LinuxFxVersion -match "POWERSHELL\|(.+)") {
                        $workerRuntimeVersion = $matches[1]
                    }
                }
            }
        }
        
        # Enhanced Extension Bundle Detection
        $bundleId = "Not Available"
        $bundleVersion = "Not Available"
        
        # Check app settings first
        if ($appSettings["EXTENSION_BUNDLE_ID"]) {
            $bundleId = $appSettings["EXTENSION_BUNDLE_ID"]
        }
        if ($appSettings["EXTENSION_BUNDLE_VERSION"]) {
            $bundleVersion = $appSettings["EXTENSION_BUNDLE_VERSION"]
        }
        
        # For non-.NET runtimes, make educated guesses about extension bundles
        if ($bundleId -eq "Not Available") {
            switch ($runtimeStack) {
                { $_ -in @("python", "node", "java", "powershell") } {
                    $bundleId = "Microsoft.Azure.Functions.ExtensionBundle"
                    $bundleVersion = "Likely used (check host.json)"
                }
                "dotnet" {
                    $bundleId = "Not applicable (compiled extensions)"
                    $bundleVersion = "N/A"
                }
            }
        }
        
        # Try to get more detailed version information
        $pythonVersion = "N/A"
        $nodeVersion = "N/A"
        $javaVersion = "N/A"
        $powershellVersion = "N/A"
        
        if ($runtimeStack -eq "python") {
            if ($appSettings["PYTHON_VERSION"]) {
                $pythonVersion = $appSettings["PYTHON_VERSION"]
            } elseif ($functionApp.SiteConfig.LinuxFxVersion -match "PYTHON\|(.+)") {
                $pythonVersion = $matches[1]
            }
        }
        
        if ($runtimeStack -eq "node") {
            if ($appSettings["WEBSITE_NODE_DEFAULT_VERSION"]) {
                $nodeVersion = $appSettings["WEBSITE_NODE_DEFAULT_VERSION"]
            } elseif ($functionApp.SiteConfig.LinuxFxVersion -match "NODE\|(.+)") {
                $nodeVersion = $matches[1]
            }
        }
        
        if ($runtimeStack -eq "java") {
            if ($appSettings["JAVA_VERSION"]) {
                $javaVersion = $appSettings["JAVA_VERSION"]
            } elseif ($functionApp.SiteConfig.JavaVersion) {
                $javaVersion = $functionApp.SiteConfig.JavaVersion
            }
        }
        
        if ($runtimeStack -eq "powershell") {
            if ($appSettings["POWERSHELL_VERSION"]) {
                $powershellVersion = $appSettings["POWERSHELL_VERSION"]
            }
        }
        
        # Create comprehensive result object
        $result = [PSCustomObject]@{
            SubscriptionId = $SubscriptionId
            SubscriptionName = $SubscriptionNames[$SubscriptionId]
            ResourceGroupName = $ResourceGroupName
            FunctionAppName = $FunctionAppName
            Location = $FunctionAppResource.Location
            Kind = $FunctionAppResource.Kind
            ResourceType = $FunctionAppResource.ResourceType
            State = $functionApp.State
            RuntimeStack = $runtimeStack
            FunctionsExtensionVersion = if ($appSettings["FUNCTIONS_EXTENSION_VERSION"]) { $appSettings["FUNCTIONS_EXTENSION_VERSION"] } else { "Unknown" }
            FunctionsWorkerRuntimeVersion = $workerRuntimeVersion
            PythonVersion = $pythonVersion
            NodeVersion = $nodeVersion
            JavaVersion = $javaVersion
            PowerShellVersion = $powershellVersion
            NetFrameworkVersion = if ($functionApp.SiteConfig.NetFrameworkVersion) { $functionApp.SiteConfig.NetFrameworkVersion } else { "N/A" }
            LinuxFxVersion = if ($functionApp.SiteConfig.LinuxFxVersion) { $functionApp.SiteConfig.LinuxFxVersion } else { "N/A" }
            AlwaysOn = $functionApp.SiteConfig.AlwaysOn
            Use32BitWorkerProcess = $functionApp.SiteConfig.Use32BitWorkerProcess
            DefaultDocuments = ($functionApp.SiteConfig.DefaultDocuments -join ", ")
            ExtensionBundleId = $bundleId
            ExtensionBundleVersion = $bundleVersion
            LastModifiedTime = $functionApp.LastModifiedTimeUtc
            ResourceId = $FunctionAppResource.ResourceId
            Tags = if ($FunctionAppResource.Tags) { ($FunctionAppResource.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; " } else { "None" }
            
            # Additional diagnostic information
            AppSettingsCount = $appSettings.Count
            HasCustomDomain = if ($functionApp.HostNames.Count -gt 1) { "Yes" } else { "No" }
            ScmType = if ($functionApp.SiteConfig.ScmType) { $functionApp.SiteConfig.ScmType } else { "Unknown" }
        }
        
        return $result
    }
    catch {
        Write-Error "Error getting enhanced configuration for Function App $FunctionAppName`: $($_.Exception.Message)"
        return $null
    }
}

# Main script execution with enhanced error handling
try {
    Write-Host "Azure Function App Bundle Scanner - Enhanced Information Recovery" -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    
    # Check if user is logged in to Azure
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not logged in to Azure. Please run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    
    # Check for required modules
    $requiredModules = @("Az.Accounts", "Az.Resources", "Az.Websites")
    $missingModules = @()
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Warning "Missing modules: $($missingModules -join ', '). Install with: Install-Module $($missingModules -join ', ')"
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
    $totalFunctionApps = 0
    $totalScanTime = Measure-Command {
        
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
                # Use optimized approach - get Function Apps directly
                Write-Host "      Using optimized resource provider scan..." -ForegroundColor Cyan
                $allWebApps = Get-AzResource -ResourceType "Microsoft.Web/sites" -ErrorAction SilentlyContinue
                $functionApps = $allWebApps | Where-Object { $_.Kind -like "*functionapp*" }
                
                if ($functionApps) {
                    Write-Host "      Found $($functionApps.Count) Function App(s) using resource provider scan" -ForegroundColor Green
                    $totalFunctionApps += $functionApps.Count
                    
                    foreach ($app in $functionApps) {
                        Write-Host "         Analyzing: $($app.Name)" -ForegroundColor White
                        
                        $config = Get-FunctionAppConfigComprehensive -ResourceGroupName $app.ResourceGroupName -FunctionAppName $app.Name -SubscriptionId $subscription.Id -FunctionAppResource $app -SubscriptionNames $subscriptionNames
                        if ($config) {
                            $allResults += $config
                        }
                    }
                } else {
                    Write-Host "      No Function Apps found in this subscription" -ForegroundColor Gray
                }
                continue
            }
            
            # Process specific resource groups if specified
            Write-Host "   Found $($resourceGroups.Count) resource group(s) to scan" -ForegroundColor Gray
            
            foreach ($rg in $resourceGroups) {
                Write-Host "      Scanning resource group: $($rg.ResourceGroupName)" -ForegroundColor Gray
                
                # Get Function Apps in this resource group
                $allWebApps = Get-AzWebApp -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
                $functionApps = $allWebApps | Where-Object { $_.Kind -like "*functionapp*" }
                
                if ($functionApps) {
                    Write-Host "         Found $($functionApps.Count) Function App(s)" -ForegroundColor Green
                    $totalFunctionApps += $functionApps.Count
                    
                    foreach ($app in $functionApps) {
                        Write-Host "            Analyzing: $($app.Name)" -ForegroundColor White
                        
                        # Convert WebApp object to resource format
                        $resourceObj = [PSCustomObject]@{
                            Name = $app.Name
                            ResourceGroupName = $app.ResourceGroup
                            Location = $app.Location
                            Kind = $app.Kind
                            ResourceType = "Microsoft.Web/sites"
                            ResourceId = $app.Id
                            Tags = $app.Tags
                        }
                        
                        $config = Get-FunctionAppConfigComprehensive -ResourceGroupName $rg.ResourceGroupName -FunctionAppName $app.Name -SubscriptionId $subscription.Id -FunctionAppResource $resourceObj -SubscriptionNames $subscriptionNames
                        if ($config) {
                            $allResults += $config
                        }
                    }
                } else {
                    Write-Host "         No Function Apps found" -ForegroundColor Gray
                }
            }
        }
    }
    
    # Display enhanced results
    Write-Host ""
    Write-Host "Enhanced Scan Results Summary" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan
    Write-Host "Total scan time: $([math]::Round($totalScanTime.TotalSeconds, 2)) seconds" -ForegroundColor Green
    Write-Host "Total Function Apps found: $totalFunctionApps" -ForegroundColor Green
    Write-Host "Successfully analyzed: $($allResults.Count)" -ForegroundColor Green
    if ($allResults.Count -gt 0) {
        Write-Host "Average time per app: $([math]::Round($totalScanTime.TotalSeconds / $allResults.Count, 2)) seconds" -ForegroundColor Green
    }
    
    if ($allResults.Count -eq 0) {
        Write-Host "No Function Apps found matching the criteria." -ForegroundColor Red
        exit 0
    }
    
    # Enhanced analytics
    $extensionVersions = $allResults | Group-Object FunctionsExtensionVersion | Sort-Object Name
    Write-Host ""
    Write-Host "Extension Version Distribution:" -ForegroundColor Yellow
    foreach ($group in $extensionVersions) {
        Write-Host "   $($group.Name): $($group.Count) apps" -ForegroundColor White
    }
    
    $runtimes = $allResults | Group-Object RuntimeStack | Sort-Object Name
    Write-Host ""
    Write-Host "Runtime Distribution:" -ForegroundColor Yellow
    foreach ($group in $runtimes) {
        Write-Host "   $($group.Name): $($group.Count) apps" -ForegroundColor White
    }
    
    # Show recovery success rates
    $totalApps = $allResults.Count
    $appsWithWorkerVersion = ($allResults | Where-Object { $_.FunctionsWorkerRuntimeVersion -ne "N/A" }).Count
    $appsWithBundleInfo = ($allResults | Where-Object { $_.ExtensionBundleId -ne "Not Available" }).Count
    $appsWithRuntimeStack = ($allResults | Where-Object { $_.RuntimeStack -ne "Unknown" }).Count
    
    Write-Host ""
    Write-Host "Information Recovery Success Rates:" -ForegroundColor Cyan
    Write-Host "   Runtime Stack: $appsWithRuntimeStack/$totalApps ($([math]::Round($appsWithRuntimeStack/$totalApps*100, 1))%)" -ForegroundColor White
    Write-Host "   Worker Runtime Version: $appsWithWorkerVersion/$totalApps ($([math]::Round($appsWithWorkerVersion/$totalApps*100, 1))%)" -ForegroundColor White
    Write-Host "   Extension Bundle Info: $appsWithBundleInfo/$totalApps ($([math]::Round($appsWithBundleInfo/$totalApps*100, 1))%)" -ForegroundColor White
    
    # Show apps that still have missing information
    $appsWithMissingInfo = $allResults | Where-Object { 
        $_.FunctionsWorkerRuntimeVersion -eq "N/A" -or 
        $_.RuntimeStack -eq "Unknown" -or 
        ($_.ExtensionBundleId -eq "Not Available" -and $_.RuntimeStack -in @("python", "node", "java"))
    }
    
    if ($appsWithMissingInfo.Count -gt 0) {
        Write-Host ""
        Write-Host "Apps with Missing Information ($($appsWithMissingInfo.Count)):" -ForegroundColor Red
        foreach ($app in $appsWithMissingInfo) {
            $missingItems = @()
            if ($app.FunctionsWorkerRuntimeVersion -eq "N/A") { $missingItems += "Worker Version" }
            if ($app.RuntimeStack -eq "Unknown") { $missingItems += "Runtime Stack" }
            if ($app.ExtensionBundleId -eq "Not Available" -and $app.RuntimeStack -in @("python", "node", "java")) { $missingItems += "Bundle Info" }
            
            Write-Host "   $($app.FunctionAppName): Missing $($missingItems -join ', ')" -ForegroundColor White
        }
    }
    
    Write-Host ""
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    Write-Host "================" -ForegroundColor Cyan
    
    # Output results based on format
    switch ($OutputFormat) {
        "Table" {
            $allResults | Format-Table -Property FunctionAppName, ResourceGroupName, RuntimeStack, FunctionsExtensionVersion, FunctionsWorkerRuntimeVersion, ExtensionBundleId, State -AutoSize
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
    Write-Host "Enhanced scan completed successfully!" -ForegroundColor Green
    Write-Host "This version uses multiple fallback methods to recover missing runtime and bundle information." -ForegroundColor Cyan
    
    # Return results
    return $allResults
    
} catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}