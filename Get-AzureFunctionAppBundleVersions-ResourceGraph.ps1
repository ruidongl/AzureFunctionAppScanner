# Azure Function App Scanner with Resource Graph Optimization and Enhanced Runtime Detection
# Addresses: "FunctionsWorkerRuntimeVersion still N/A" + Performance optimization

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

# Check required modules
$requiredModules = @('Az.Accounts', 'Az.Websites')
foreach ($module in $requiredModules) {
    if (-not (Get-Module -Name $module -ListAvailable)) {
        Write-Error "Required module '$module' is not installed. Install with: Install-Module -Name $module"
        exit 1
    }
    Import-Module -Name $module -Force
}

# Check Resource Graph module if requested
if ($UseResourceGraph) {
    if (Get-Module -Name 'Az.ResourceGraph' -ListAvailable) {
        try {
            Write-Host "🔍 Checking Az.ResourceGraph compatibility..." -ForegroundColor Cyan
            Import-Module -Name 'Az.ResourceGraph' -Force -ErrorAction Stop
            Write-Host "  ✅ Az.ResourceGraph module loaded successfully" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠️ Az.ResourceGraph compatibility issue: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  🔄 Disabling Resource Graph, using traditional scanning" -ForegroundColor Yellow
            $UseResourceGraph = $false
        }
    } else {
        Write-Host "Az.ResourceGraph module not found. Using traditional scanning." -ForegroundColor Yellow
        $UseResourceGraph = $false
    }
}

# Resource Graph discovery function
function Find-FunctionAppsWithResourceGraph {
    param([string[]]$SubscriptionIds, [string]$ResourceGroupName)
    
    try {
        Write-Host "  📊 Executing Resource Graph query..." -ForegroundColor Cyan
        
        $query = "resources | where type =~ 'Microsoft.Web/sites' | where kind contains 'functionapp' | project subscriptionId, resourceGroup, name, location, kind, properties | order by subscriptionId, resourceGroup, name"
        
        if ($ResourceGroupName) {
            $query = $query.Replace("| order by", "| where resourceGroup =~ '$ResourceGroupName' | order by")
        }
        
        if ($SubscriptionIds -and $SubscriptionIds.Count -gt 0) {
            $subscriptionFilter = ($SubscriptionIds | ForEach-Object { "'$_'" }) -join ","
            $query = $query.Replace("| where type", "| where subscriptionId in ($subscriptionFilter) | where type")
        }
        
        $functionApps = Search-AzGraph -Query $query -First 1000
        
        if ($functionApps) {
            Write-Host "  ✅ Found $($functionApps.Count) Function App(s)" -ForegroundColor Green
            return $functionApps
        } else {
            Write-Host "  ⚠️ No Function Apps found" -ForegroundColor Yellow
            return @()
        }
        
    } catch {
        Write-Host "  ❌ Resource Graph query failed: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Enhanced Function App analysis
function Get-FunctionAppDetails {
    param([string]$ResourceGroupName, [string]$FunctionAppName, [string]$SubscriptionId)
    
    try {
        $functionApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction Stop
        $appSettings = @{}
        if ($functionApp.SiteConfig.AppSettings) {
            $functionApp.SiteConfig.AppSettings | ForEach-Object { $appSettings[$_.Name] = $_.Value }
        }
        
        # Enhanced runtime detection
        $workerRuntimeVersion = "N/A"
        $runtimeStack = "Unknown"
        
        # Determine runtime stack
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
            } else {
                $runtimeStack = "dotnet-isolated"  # Default for Windows Function Apps
            }
        }
        
        # Enhanced runtime version detection
        if ($appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"]) {
            $workerRuntimeVersion = $appSettings["FUNCTIONS_WORKER_RUNTIME_VERSION"]
        } else {
            switch ($runtimeStack) {
                "python" {
                    if ($appSettings["PYTHON_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["PYTHON_VERSION"]
                    } elseif ($functionApp.SiteConfig.LinuxFxVersion -match "PYTHON\|(.+)") {
                        $workerRuntimeVersion = $matches[1]
                    }
                }
                "node" {
                    if ($appSettings["WEBSITE_NODE_DEFAULT_VERSION"]) {
                        $workerRuntimeVersion = $appSettings["WEBSITE_NODE_DEFAULT_VERSION"]
                    } elseif ($functionApp.SiteConfig.LinuxFxVersion -match "NODE\|(.+)") {
                        $workerRuntimeVersion = $matches[1]
                    }
                }
                { $_ -in @("dotnet", "dotnet-isolated") } {
                    if ($functionApp.SiteConfig.NetFrameworkVersion) {
                        $netVersion = $functionApp.SiteConfig.NetFrameworkVersion
                        if ($runtimeStack -eq "dotnet-isolated") {
                            $workerRuntimeVersion = "$netVersion (Isolated)"
                        } else {
                            $workerRuntimeVersion = "$netVersion (In-Process)"
                        }
                    }
                }
            }
        }
        
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
            FunctionsWorkerRuntimeVersion = $workerRuntimeVersion
            PythonVersion = if ($appSettings["PYTHON_VERSION"]) { $appSettings["PYTHON_VERSION"] } else { "N/A" }
            NodeVersion = if ($appSettings["WEBSITE_NODE_DEFAULT_VERSION"]) { $appSettings["WEBSITE_NODE_DEFAULT_VERSION"] } else { "N/A" }
            NetFrameworkVersion = if ($functionApp.SiteConfig.NetFrameworkVersion) { $functionApp.SiteConfig.NetFrameworkVersion } else { "N/A" }
            LinuxFxVersion = if ($functionApp.SiteConfig.LinuxFxVersion) { $functionApp.SiteConfig.LinuxFxVersion } else { "N/A" }
            AlwaysOn = $functionApp.SiteConfig.AlwaysOn
            Use32BitWorkerProcess = $functionApp.SiteConfig.Use32BitWorkerProcess
            DefaultDocuments = $functionApp.SiteConfig.DefaultDocuments -join ", "
            ExtensionBundleId = "Not Available via API"
            ExtensionBundleVersion = "Not Available via API"
            LastModifiedTime = $functionApp.LastModifiedTimeUtc
        }
    } catch {
        Write-Warning "Failed to analyze Function App '$FunctionAppName': $($_.Exception.Message)"
        return $null
    }
}

# Main execution
try {
    Write-Host "Azure Function App Scanner with Resource Graph Optimization" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "Not connected to Azure. Run Connect-AzAccount first."
        exit 1
    }
    Write-Host "Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    
    # Get subscriptions
    $subscriptions = @()
    if ($SubscriptionId) {
        $subscriptions = @(Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop)
        Write-Host "Scanning specific subscription: $($subscriptions[0].Name)" -ForegroundColor Yellow
    } else {
        $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
        Write-Host "Scanning all accessible subscriptions ($($subscriptions.Count) found)" -ForegroundColor Yellow
    }
    
    $allResults = @()
    
    # Try Resource Graph approach first
    if ($UseResourceGraph) {
        Write-Host ""
        Write-Host "🚀 Using Azure Resource Graph for high-performance discovery..." -ForegroundColor Cyan
        
        $subscriptionIds = $subscriptions | ForEach-Object { $_.Id }
        $resourceGraphFunctionApps = Find-FunctionAppsWithResourceGraph -SubscriptionIds $subscriptionIds -ResourceGroupName $ResourceGroupName
        
        if ($resourceGraphFunctionApps) {
            Write-Host "✅ Resource Graph optimization successful!" -ForegroundColor Green
            
            $functionAppsBySubscription = $resourceGraphFunctionApps | Group-Object -Property subscriptionId
            
            foreach ($subGroup in $functionAppsBySubscription) {
                $currentSubscription = $subscriptions | Where-Object { $_.Id -eq $subGroup.Name }
                Set-AzContext -SubscriptionId $currentSubscription.Id | Out-Null
                
                Write-Host ""
                Write-Host "Processing subscription: $($currentSubscription.Name) ($($currentSubscription.Id))" -ForegroundColor Blue
                Write-Host "   Found $($subGroup.Group.Count) Function App(s) via Resource Graph" -ForegroundColor Green
                
                foreach ($app in $subGroup.Group) {
                    Write-Host "      Analyzing: $($app.name) (Resource Group: $($app.resourceGroup))" -ForegroundColor White
                    $config = Get-FunctionAppDetails -ResourceGroupName $app.resourceGroup -FunctionAppName $app.name -SubscriptionId $currentSubscription.Id
                    if ($config) { $allResults += $config }
                }
            }
        } else {
            Write-Host "⚠️ Resource Graph returned no results. Falling back to traditional scanning..." -ForegroundColor Yellow
            $UseResourceGraph = $false
        }
    }
    
    # Traditional scanning fallback
    if (-not $UseResourceGraph -or -not $resourceGraphFunctionApps) {
        Write-Host ""
        Write-Host "🔍 Using traditional resource group scanning..." -ForegroundColor Yellow
        
        foreach ($subscription in $subscriptions) {
            Write-Host ""
            Write-Host "Processing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Blue
            Set-AzContext -SubscriptionId $subscription.Id | Out-Null
            
            $resourceGroups = @()
            if ($ResourceGroupName) {
                $resourceGroups = @(Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)
            } else {
                $resourceGroups = Get-AzResourceGroup
            }
            
            Write-Host "   Found $($resourceGroups.Count) resource group(s) to scan" -ForegroundColor Gray
            
            foreach ($rg in $resourceGroups) {
                Write-Host "      Scanning resource group: $($rg.ResourceGroupName)" -ForegroundColor Gray
                
                $webApps = Get-AzWebApp -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
                $functionApps = $webApps | Where-Object { $_.Kind -like "*functionapp*" }
                
                if ($functionApps) {
                    Write-Host "         Found $($functionApps.Count) Function App(s)" -ForegroundColor Green
                    foreach ($app in $functionApps) {
                        Write-Host "            Analyzing: $($app.Name)" -ForegroundColor White
                        $config = Get-FunctionAppDetails -ResourceGroupName $rg.ResourceGroupName -FunctionAppName $app.Name -SubscriptionId $subscription.Id
                        if ($config) { $allResults += $config }
                    }
                } else {
                    Write-Host "         No Function Apps found" -ForegroundColor Gray
                }
            }
        }
    }
    
    # Display results
    Write-Host ""
    Write-Host "Scan Results Summary" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host "Total Function Apps found: $($allResults.Count)" -ForegroundColor Green
    
    if ($allResults.Count -eq 0) {
        Write-Host "No Function Apps found." -ForegroundColor Red
        exit 0
    }
    
    # Show detailed results
    Write-Host ""
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    Write-Host "================" -ForegroundColor Cyan
    $allResults | Format-Table -Property FunctionAppName, ResourceGroupName, RuntimeStack, FunctionsExtensionVersion, FunctionsWorkerRuntimeVersion, AlwaysOn, State -AutoSize
    
    Write-Host ""
    Write-Host "✅ Scan completed successfully!" -ForegroundColor Green
    
    # Return results
    return $allResults
    
} catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}