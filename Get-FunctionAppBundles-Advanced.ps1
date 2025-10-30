#Requires -Modules Az.Accounts, Az.Profile

<#
.SYNOPSIS
    Advanced Azure Function App Bundle Version Scanner using REST API

.DESCRIPTION
    Uses Azure REST APIs to get detailed Function App configuration including:
    - host.json extension bundle configuration
    - Detailed runtime and extension versions
    - Binding information

.PARAMETER SubscriptionId
    Target subscription ID. If not provided, scans current subscription.

.PARAMETER ResourceGroupName
    Target resource group. If not provided, scans all resource groups.

.PARAMETER FunctionAppName
    Target specific Function App. If not provided, scans all Function Apps.

.EXAMPLE
    .\Get-FunctionAppBundles-Advanced.ps1
    
.EXAMPLE
    .\Get-FunctionAppBundles-Advanced.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012"
    
.EXAMPLE
    .\Get-FunctionAppBundles-Advanced.ps1 -ResourceGroupName "MyRG" -FunctionAppName "MyFunctionApp"
#>

param(
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$FunctionAppName
)

function Get-AzureAccessToken {
    try {
        $context = Get-AzContext
        if (-not $context) {
            throw "No Azure context found. Please run Connect-AzAccount."
        }
        
        $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id, $null, "Never", $null, "https://management.azure.com/").AccessToken
        return $token
    }
    catch {
        # Alternative method for newer Az modules
        $token = Get-AzAccessToken -ResourceUrl "https://management.azure.com/"
        return $token.Token
    }
}

function Invoke-AzureRestAPI {
    param(
        [string]$Uri,
        [string]$AccessToken,
        [string]$Method = "GET"
    )
    
    $headers = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type' = 'application/json'
    }
    
    try {
        $response = Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method -ErrorAction Stop
        return $response
    }
    catch {
        Write-Warning "REST API call failed for $Uri`: $($_.Exception.Message)"
        return $null
    }
}

function Get-FunctionAppHostJson {
    param(
        [string]$ResourceGroupName,
        [string]$FunctionAppName,
        [string]$SubscriptionId,
        [string]$AccessToken
    )
    
    try {
        # Get Function App configuration
        $configUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$FunctionAppName/config/web?api-version=2022-03-01"
        $config = Invoke-AzureRestAPI -Uri $configUri -AccessToken $AccessToken
        
        # Try to get host.json via different methods
        $hostJsonContent = $null
        
        # Method 1: Try SCM API
        try {
            $scmUri = "https://$FunctionAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/host.json"
            $publishingCredentials = Get-AzWebAppPublishingProfile -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -OutputFile $null -Format WebDeploy
            
            if ($publishingCredentials) {
                $creds = ([xml]$publishingCredentials).publishData.publishProfile | Where-Object { $_.publishMethod -eq "MSDeploy" } | Select-Object -First 1
                $username = $creds.userName
                $password = $creds.userPWD
                
                $basicAuth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$username`:$password"))
                $scmHeaders = @{
                    'Authorization' = "Basic $basicAuth"
                    'Content-Type' = 'application/json'
                }
                
                $hostJsonContent = Invoke-RestMethod -Uri $scmUri -Headers $scmHeaders -Method Get -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Verbose "SCM API method failed: $($_.Exception.Message)"
        }
        
        # Method 2: Try Functions API
        if (-not $hostJsonContent) {
            try {
                $functionsUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$FunctionAppName/hostruntime/admin/host/status?api-version=2022-03-01"
                $hostStatus = Invoke-AzureRestAPI -Uri $functionsUri -AccessToken $AccessToken
                
                if ($hostStatus -and $hostStatus.properties -and $hostStatus.properties.extensionBundle) {
                    $hostJsonContent = @{
                        extensionBundle = $hostStatus.properties.extensionBundle
                    }
                }
            }
            catch {
                Write-Verbose "Functions API method failed: $($_.Exception.Message)"
            }
        }
        
        return $hostJsonContent
    }
    catch {
        Write-Warning "Error getting host.json for $FunctionAppName`: $($_.Exception.Message)"
        return $null
    }
}

function Get-DetailedFunctionAppInfo {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$FunctionAppName,
        [string]$AccessToken
    )
    
    Write-Host "   📊 Analyzing: $FunctionAppName" -ForegroundColor White
    
    try {
        # Get Function App details via REST API
        $appUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$FunctionAppName?api-version=2022-03-01"
        $app = Invoke-AzureRestAPI -Uri $appUri -AccessToken $AccessToken
        
        if (-not $app) {
            Write-Warning "Could not retrieve Function App details for $FunctionAppName"
            return $null
        }
        
        # Get app settings
        $settingsUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$FunctionAppName/config/appsettings/list?api-version=2022-03-01"
        $settingsResponse = Invoke-AzureRestAPI -Uri $settingsUri -AccessToken $AccessToken -Method POST
        $settings = @{}
        if ($settingsResponse -and $settingsResponse.properties) {
            $settings = $settingsResponse.properties
        }
        
        # Get host.json information
        $hostJson = Get-FunctionAppHostJson -ResourceGroupName $ResourceGroupName -FunctionAppName $FunctionAppName -SubscriptionId $SubscriptionId -AccessToken $AccessToken
        
        # Build result object
        $result = [PSCustomObject]@{
            SubscriptionId = $SubscriptionId
            ResourceGroupName = $ResourceGroupName
            FunctionAppName = $FunctionAppName
            Location = $app.location
            Kind = $app.kind
            State = $app.properties.state
            HostNames = ($app.properties.hostNames -join ", ")
            RuntimeStack = $app.properties.siteConfig.linuxFxVersion ?? $app.properties.siteConfig.windowsFxVersion ?? "Unknown"
            FunctionsWorkerRuntime = $settings["FUNCTIONS_WORKER_RUNTIME"] ?? "Unknown"
            FunctionsExtensionVersion = $settings["FUNCTIONS_EXTENSION_VERSION"] ?? "Unknown"
            FunctionsWorkerRuntimeVersion = $settings["FUNCTIONS_WORKER_RUNTIME_VERSION"] ?? "Unknown"
            NodeVersion = $settings["WEBSITE_NODE_DEFAULT_VERSION"] ?? "N/A"
            DotNetVersion = $settings["FUNCTIONS_WORKER_RUNTIME_VERSION"] ?? "N/A"
            ExtensionBundleId = "N/A"
            ExtensionBundleVersion = "N/A"
            ExtensionBundleSource = "N/A"
            HostJsonFound = $false
            PlanName = $app.properties.serverFarmId?.Split('/')[-1] ?? "Unknown"
            PlanTier = "Unknown"
            LastModified = $app.properties.lastModifiedTimeUtc
        }
        
        # Extract extension bundle information from host.json
        if ($hostJson -and $hostJson.extensionBundle) {
            $result.ExtensionBundleId = $hostJson.extensionBundle.id ?? "N/A"
            $result.ExtensionBundleVersion = $hostJson.extensionBundle.version ?? "N/A"
            $result.ExtensionBundleSource = $hostJson.extensionBundle.source ?? "N/A"
            $result.HostJsonFound = $true
        }
        
        # Get App Service Plan details
        if ($app.properties.serverFarmId) {
            $planUri = "https://management.azure.com$($app.properties.serverFarmId)?api-version=2022-03-01"
            $plan = Invoke-AzureRestAPI -Uri $planUri -AccessToken $AccessToken
            if ($plan) {
                $result.PlanTier = $plan.sku.tier ?? "Unknown"
            }
        }
        
        return $result
    }
    catch {
        Write-Error "Error processing Function App $FunctionAppName`: $($_.Exception.Message)"
        return $null
    }
}

# Main script execution
Write-Host "🔍 Advanced Azure Function App Bundle Scanner" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

try {
    # Check Azure connection
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "❌ Not connected to Azure. Running Connect-AzAccount..." -ForegroundColor Red
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    Write-Host "✅ Connected as: $($context.Account.Id)" -ForegroundColor Green
    
    # Get access token
    Write-Host "🔑 Getting access token..." -ForegroundColor Yellow
    $accessToken = Get-AzureAccessToken
    
    # Set subscription context
    if ($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        $currentSub = Get-AzSubscription -SubscriptionId $SubscriptionId
    } else {
        $currentSub = $context.Subscription
        $SubscriptionId = $currentSub.Id
    }
    
    Write-Host "🎯 Scanning subscription: $($currentSub.Name)" -ForegroundColor Blue
    
    $results = @()
    
    if ($FunctionAppName -and $ResourceGroupName) {
        # Scan specific Function App
        Write-Host "🔍 Scanning specific Function App: $FunctionAppName" -ForegroundColor Yellow
        $result = Get-DetailedFunctionAppInfo -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -FunctionAppName $FunctionAppName -AccessToken $accessToken
        if ($result) {
            $results += $result
        }
    } else {
        # Get resource groups
        $resourceGroups = @()
        if ($ResourceGroupName) {
            $resourceGroups = @($ResourceGroupName)
        } else {
            $rgUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourcegroups?api-version=2022-09-01"
            $rgResponse = Invoke-AzureRestAPI -Uri $rgUri -AccessToken $accessToken
            $resourceGroups = $rgResponse.value | ForEach-Object { $_.name }
        }
        
        Write-Host "📁 Found $($resourceGroups.Count) resource group(s)" -ForegroundColor Gray
        
        foreach ($rg in $resourceGroups) {
            Write-Host "   🔍 Scanning resource group: $rg" -ForegroundColor Gray
            
            # Get Function Apps in resource group
            $appsUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$rg/providers/Microsoft.Web/sites?api-version=2022-03-01"
            $appsResponse = Invoke-AzureRestAPI -Uri $appsUri -AccessToken $accessToken
            
            if ($appsResponse -and $appsResponse.value) {
                $functionApps = $appsResponse.value | Where-Object { $_.kind -like "*functionapp*" }
                
                if ($functionApps) {
                    Write-Host "      ⚡ Found $($functionApps.Count) Function App(s)" -ForegroundColor Green
                    
                    foreach ($app in $functionApps) {
                        $result = Get-DetailedFunctionAppInfo -SubscriptionId $SubscriptionId -ResourceGroupName $rg -FunctionAppName $app.name -AccessToken $accessToken
                        if ($result) {
                            $results += $result
                        }
                    }
                } else {
                    Write-Host "      ℹ️  No Function Apps found" -ForegroundColor Gray
                }
            }
        }
    }
    
    # Display results
    Write-Host "`n📊 Scan Results" -ForegroundColor Cyan
    Write-Host "===============" -ForegroundColor Cyan
    Write-Host "Total Function Apps analyzed: $($results.Count)" -ForegroundColor Green
    
    if ($results.Count -gt 0) {
        # Summary statistics
        $bundleStats = $results | Group-Object ExtensionBundleVersion | Sort-Object Name
        Write-Host "`n📈 Extension Bundle Versions:" -ForegroundColor Yellow
        $bundleStats | ForEach-Object { 
            Write-Host "   $($_.Name): $($_.Count) apps" -ForegroundColor White 
        }
        
        $runtimeStats = $results | Group-Object FunctionsWorkerRuntime | Sort-Object Name
        Write-Host "`n🔧 Runtime Distribution:" -ForegroundColor Yellow
        $runtimeStats | ForEach-Object { 
            Write-Host "   $($_.Name): $($_.Count) apps" -ForegroundColor White 
        }
        
        $hostJsonStats = $results | Group-Object HostJsonFound
        Write-Host "`n📄 Host.json Analysis:" -ForegroundColor Yellow
        $hostJsonStats | ForEach-Object { 
            $status = if ($_.Name -eq "True") { "Found" } else { "Not Found/Accessible" }
            Write-Host "   $status`: $($_.Count) apps" -ForegroundColor White 
        }
        
        Write-Host "`n📋 Detailed Results:" -ForegroundColor Cyan
        $results | Format-Table -Property FunctionAppName, ResourceGroupName, FunctionsWorkerRuntime, FunctionsExtensionVersion, ExtensionBundleId, ExtensionBundleVersion, HostJsonFound -AutoSize
        
        Write-Host "`n💾 Export Options:" -ForegroundColor Yellow
        Write-Host "CSV: `$results | Export-Csv -Path 'FunctionAppBundles.csv' -NoTypeInformation" -ForegroundColor Gray
        Write-Host "JSON: `$results | ConvertTo-Json -Depth 3 | Out-File 'FunctionAppBundles.json'" -ForegroundColor Gray
        
        # Return results for further processing
        return $results
    } else {
        Write-Host "❌ No Function Apps found." -ForegroundColor Red
    }
    
} catch {
    Write-Error "❌ Script execution failed: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
}