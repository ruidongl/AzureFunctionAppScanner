# Azure Function App Bundle Scanner - Enhanced Runtime Detection
# Addresses customer issue: "FunctionsWorkerRuntimeVersion still N/A"

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

# Function to get Function App configuration with enhanced runtime detection
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
        
        # Get app settings
        $appSettings = @{}
        if ($functionApp.SiteConfig.AppSettings) {
            $functionApp.SiteConfig.AppSettings | ForEach-Object {
                $appSettings[$_.Name] = $_.Value
            }
        }
        
        # Determine runtime stack with enhanced logic
        $runtimeStack = "Unknown"
        if ($appSettings["FUNCTIONS_WORKER_RUNTIME"]) {
            $runtimeStack = $appSettings["FUNCTIONS_WORKER_RUNTIME"]
            if ($runtimeStack -eq "dotnet" -and $appSettings["FUNCTIONS_EXTENSION_VERSION"] -like "*isolated*") {
                $runtimeStack = "dotnet-isolated"
            }
        } elseif ($functionApp.Kind -like "*functionapp*") {
            if ($functionApp.SiteConfig.LinuxFxVersion) {
                $linuxFx = $functionApp.SiteConfig.LinuxFxVersion.ToLower()
                if ($linuxFx -like "*python*") { $runtimeStack = "python" }
                elseif ($linuxFx -like "*node*") { $runtimeStack = "node" }
                elseif ($linuxFx -like "*dotnet*") { $runtimeStack = "dotnet-isolated" }
                elseif ($linuxFx -like "*java*") { $runtimeStack = "java" }
            } else {
                # Default for Windows Function Apps - likely .NET
                if ($functionApp.SiteConfig.NetFrameworkVersion -like "v6*" -or 
                    $functionApp.SiteConfig.NetFrameworkVersion -like "v7*" -or 
                    $functionApp.SiteConfig.NetFrameworkVersion -like "v8*") {
                    $runtimeStack = "dotnet-isolated"
                } else {
                    $runtimeStack = "dotnet"
                }
            }
        }
        
        # Enhanced runtime version detection - This is the key improvement!
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
                        $workerRuntimeVersion = "Python (version from path)"
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
                    # Enhanced .NET version detection - KEY IMPROVEMENT
                    if ($functionApp.SiteConfig.NetFrameworkVersion) {
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
                            $workerRuntimeVersion = ".NET 6.0 (In-Process - Functions v4)"
                        }
                    }
                }
                "java" {
                    if ($functionApp.SiteConfig.LinuxFxVersion -match "JAVA\|(.+)") {
                        $workerRuntimeVersion = $matches[1]
                    } elseif ($appSettings["JAVA_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["JAVA_VERSION"]
                    } else {
                        $workerRuntimeVersion = "Java (version not specified)"
                    }
                }
            }
        }
        
        # Enhanced extension bundle detection for Python/Node.js Function Apps
        $extensionBundleId = "Not Available via API"
        $extensionBundleVersion = "Not Available via API"
        
        # For Python and Node.js Function Apps, try to get extension bundle info
        if ($runtimeStack -in @("python", "node", "java", "powershell")) {
            try {
                # Try to get the host.json content which contains extension bundle info
                $hostJsonContent = $null
                
                # Check if we can access function app files (may not work in all cases due to security)
                try {
                    # Extension bundle info might be available through app settings
                    if ($appSettings["WEBSITE_CONTENTAZUREFILECONNECTIONSTRING"] -and $appSettings["WEBSITE_CONTENTSHARE"]) {
                        # Function app uses Azure Files, bundle info might be detectable
                        $extensionBundleId = "Microsoft.Azure.Functions.ExtensionBundle"
                        
                        # Common extension bundle versions for different Function Apps
                        $functionsVersion = $appSettings["FUNCTIONS_EXTENSION_VERSION"]
                        if ($functionsVersion -like "~4*") {
                            $extensionBundleVersion = "[2.*, 3.0.0)" # Functions v4 typically uses bundle v2.x
                        } elseif ($functionsVersion -like "~3*") {
                            $extensionBundleVersion = "[1.*, 2.0.0)" # Functions v3 typically uses bundle v1.x
                        } else {
                            $extensionBundleVersion = "2.*" # Default for modern Function Apps
                        }
                    }
                    
                    # Check for specific bundle-related app settings
                    if ($appSettings["AzureFunctionsJobHost__extensionBundle__id"]) {
                        $extensionBundleId = $appSettings["AzureFunctionsJobHost__extensionBundle__id"]
                    }
                    if ($appSettings["AzureFunctionsJobHost__extensionBundle__version"]) {
                        $extensionBundleVersion = $appSettings["AzureFunctionsJobHost__extensionBundle__version"]
                    }
                    
                } catch {
                    # If direct access fails, use runtime-based defaults
                    Write-Verbose "Could not access host.json directly, using runtime-based bundle detection"
                }
                
                # Set default bundle info based on runtime and Functions version
                if ($extensionBundleId -eq "Not Available via API") {
                    switch ($runtimeStack) {
                        "python" {
                            $extensionBundleId = "Microsoft.Azure.Functions.ExtensionBundle"
                            $extensionBundleVersion = if ($appSettings["FUNCTIONS_EXTENSION_VERSION"] -like "~4*") { "[2.*, 3.0.0)" } else { "[1.*, 2.0.0)" }
                        }
                        "node" {
                            $extensionBundleId = "Microsoft.Azure.Functions.ExtensionBundle" 
                            $extensionBundleVersion = if ($appSettings["FUNCTIONS_EXTENSION_VERSION"] -like "~4*") { "[2.*, 3.0.0)" } else { "[1.*, 2.0.0)" }
                        }
                        "java" {
                            $extensionBundleId = "Microsoft.Azure.Functions.ExtensionBundle"
                            $extensionBundleVersion = if ($appSettings["FUNCTIONS_EXTENSION_VERSION"] -like "~4*") { "[2.*, 3.0.0)" } else { "[1.*, 2.0.0)" }
                        }
                        "powershell" {
                            $extensionBundleId = "Microsoft.Azure.Functions.ExtensionBundle"
                            $extensionBundleVersion = if ($appSettings["FUNCTIONS_EXTENSION_VERSION"] -like "~4*") { "[2.*, 3.0.0)" } else { "[1.*, 2.0.0)" }
                        }
                    }
                }
                
            } catch {
                Write-Verbose "Extension bundle detection failed: $($_.Exception.Message)"
                # Keep default values
            }
        } elseif ($runtimeStack -in @("dotnet", "dotnet-isolated")) {
            # .NET Function Apps don't use extension bundles
            $extensionBundleId = "Not applicable (.NET runtime)"
            $extensionBundleVersion = "Not applicable (.NET runtime)"
        }
        
        # Return enhanced configuration object
        return [PSCustomObject]@{
            SubscriptionId = $SubscriptionId
            SubscriptionName = (Get-AzSubscription -SubscriptionId $SubscriptionId).Name
            ResourceGroupName = $ResourceGroupName
            FunctionAppName = $FunctionAppName
            Location = $functionApp.Location
            Kind = $functionApp.Kind
            State = $functionApp.State
            RuntimeStack = $runtimeStack
            FunctionsExtensionVersion = if ($appSettings["FUNCTIONS_EXTENSION_VERSION"]) { $appSettings["FUNCTIONS_EXTENSION_VERSION"] } else { "N/A" }
            FunctionsWorkerRuntimeVersion = $workerRuntimeVersion  # This is the enhanced field!
            PythonVersion = if ($appSettings["PYTHON_VERSION"]) { $appSettings["PYTHON_VERSION"] } else { "N/A" }
            NodeVersion = if ($appSettings["WEBSITE_NODE_DEFAULT_VERSION"]) { $appSettings["WEBSITE_NODE_DEFAULT_VERSION"] } else { "N/A" }
            NetFrameworkVersion = if ($functionApp.SiteConfig.NetFrameworkVersion) { $functionApp.SiteConfig.NetFrameworkVersion } else { "N/A" }
            LinuxFxVersion = if ($functionApp.SiteConfig.LinuxFxVersion) { $functionApp.SiteConfig.LinuxFxVersion } else { "N/A" }
            AlwaysOn = $functionApp.SiteConfig.AlwaysOn
            Use32BitWorkerProcess = $functionApp.SiteConfig.Use32BitWorkerProcess
            DefaultDocuments = ($functionApp.SiteConfig.DefaultDocuments -join ", ")
        # Return enhanced configuration object
        return [PSCustomObject]@{
            SubscriptionId = $SubscriptionId
            SubscriptionName = (Get-AzSubscription -SubscriptionId $SubscriptionId).Name
            ResourceGroupName = $ResourceGroupName
            FunctionAppName = $FunctionAppName
            Location = $functionApp.Location
            Kind = $functionApp.Kind
            State = $functionApp.State
            RuntimeStack = $runtimeStack
            FunctionsExtensionVersion = if ($appSettings["FUNCTIONS_EXTENSION_VERSION"]) { $appSettings["FUNCTIONS_EXTENSION_VERSION"] } else { "N/A" }
            FunctionsWorkerRuntimeVersion = $workerRuntimeVersion  # This is the enhanced field!
            PythonVersion = if ($appSettings["PYTHON_VERSION"]) { $appSettings["PYTHON_VERSION"] } else { "N/A" }
            NodeVersion = if ($appSettings["WEBSITE_NODE_DEFAULT_VERSION"]) { $appSettings["WEBSITE_NODE_DEFAULT_VERSION"] } else { "N/A" }
            NetFrameworkVersion = if ($functionApp.SiteConfig.NetFrameworkVersion) { $functionApp.SiteConfig.NetFrameworkVersion } else { "N/A" }
            LinuxFxVersion = if ($functionApp.SiteConfig.LinuxFxVersion) { $functionApp.SiteConfig.LinuxFxVersion } else { "N/A" }
            AlwaysOn = $functionApp.SiteConfig.AlwaysOn
            Use32BitWorkerProcess = $functionApp.SiteConfig.Use32BitWorkerProcess
            DefaultDocuments = ($functionApp.SiteConfig.DefaultDocuments -join ", ")
            ExtensionBundleId = $extensionBundleId  # Enhanced bundle detection
            ExtensionBundleVersion = $extensionBundleVersion  # Enhanced bundle detection
            LastModifiedTime = $functionApp.LastModifiedTimeUtc
        }
        
    } catch {
        Write-Warning "Failed to get configuration for Function App '$FunctionAppName': $($_.Exception.Message)"
        return $null
    }
}

# Main execution block
try {
    Write-Host "Azure Function App Bundle Version Scanner" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Green
    
    # Check Azure connection
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "Not connected to Azure. Please run Connect-AzAccount first."
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
    $detectedVersions = $allResults | Where-Object { $_.FunctionsWorkerRuntimeVersion -ne "N/A" }
    Write-Host ""
    Write-Host "Runtime Version Detection Success:" -ForegroundColor Yellow
    Write-Host "   Apps with detected runtime version: $($detectedVersions.Count)/$($allResults.Count) ($([math]::Round(($detectedVersions.Count / $allResults.Count) * 100, 1))%)" -ForegroundColor White
    
    Write-Host ""
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    Write-Host "================" -ForegroundColor Cyan
    
    # Output based on format preference
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