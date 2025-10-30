#Requires -Modules Az.Functions, Az.Accounts

<#
.SYNOPSIS
    Quick Azure Function App Extension Bundle Version Scanner

.DESCRIPTION
    A simplified script to quickly find Function App extension bundle versions.
    Focuses on the most important information with minimal dependencies.

.EXAMPLE
    .\Get-FunctionAppBundles-Simple.ps1
    
.EXAMPLE
    .\Get-FunctionAppBundles-Simple.ps1 | Export-Csv -Path "FunctionAppBundles.csv" -NoTypeInformation
#>

param(
    [string]$SubscriptionId = $null
)

function Get-SimpleFunctionAppInfo {
    param($App, $SubscriptionName)
    
    try {
        # Get app settings
        $settings = $App.ApplicationSetting
        
        $result = [PSCustomObject]@{
            SubscriptionName = $SubscriptionName
            ResourceGroup = $App.ResourceGroupName
            FunctionAppName = $App.Name
            Location = $App.Location
            Runtime = $settings["FUNCTIONS_WORKER_RUNTIME"] ?? "Unknown"
            ExtensionVersion = $settings["FUNCTIONS_EXTENSION_VERSION"] ?? "Unknown"
            RuntimeVersion = $settings["FUNCTIONS_WORKER_RUNTIME_VERSION"] ?? "Unknown"
            PlanType = $App.PlanType
            OSType = $App.OSType
            State = $App.State
        }
        
        # Try to get extension bundle info from site config
        try {
            $siteConfig = Get-AzWebApp -ResourceGroupName $App.ResourceGroupName -Name $App.Name
            if ($siteConfig.SiteConfig.AppSettings) {
                $bundleSettings = $siteConfig.SiteConfig.AppSettings | Where-Object { $_.Name -like "*BUNDLE*" -or $_.Name -like "*EXTENSION*" }
                if ($bundleSettings) {
                    $result | Add-Member -NotePropertyName "AdditionalBundleInfo" -NotePropertyValue ($bundleSettings | ForEach-Object { "$($_.Name)=$($_.Value)" } | Join-String -Separator "; ")
                }
            }
        }
        catch {
            # Ignore errors getting additional bundle info
        }
        
        return $result
    }
    catch {
        Write-Warning "Error processing $($App.Name): $($_.Exception.Message)"
        return $null
    }
}

# Main execution
Write-Host "🔍 Quick Function App Bundle Scanner" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# Check Azure connection
try {
    $context = Get-AzContext -ErrorAction Stop
    Write-Host "✅ Connected as: $($context.Account.Id)" -ForegroundColor Green
}
catch {
    Write-Host "❌ Not connected to Azure. Running Connect-AzAccount..." -ForegroundColor Red
    Connect-AzAccount
}

# Get subscriptions
if ($SubscriptionId) {
    $subscriptions = @(Get-AzSubscription -SubscriptionId $SubscriptionId)
}
else {
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
}

Write-Host "📂 Scanning $($subscriptions.Count) subscription(s)..." -ForegroundColor Yellow

$allApps = @()

foreach ($sub in $subscriptions) {
    Write-Host "   🔍 $($sub.Name)" -ForegroundColor Blue
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    
    # Get all Function Apps in subscription
    $functionApps = Get-AzFunctionApp
    
    Write-Host "      Found $($functionApps.Count) Function Apps" -ForegroundColor Gray
    
    foreach ($app in $functionApps) {
        $appInfo = Get-SimpleFunctionAppInfo -App $app -SubscriptionName $sub.Name
        if ($appInfo) {
            $allApps += $appInfo
        }
    }
}

# Display results
Write-Host "`n📊 Results Summary:" -ForegroundColor Cyan
Write-Host "Total Function Apps: $($allApps.Count)" -ForegroundColor Green

if ($allApps.Count -gt 0) {
    # Group by extension version
    $versionGroups = $allApps | Group-Object ExtensionVersion | Sort-Object Name
    Write-Host "`nExtension Versions:" -ForegroundColor Yellow
    $versionGroups | ForEach-Object { Write-Host "   $($_.Name): $($_.Count) apps" -ForegroundColor White }
    
    # Group by runtime
    $runtimeGroups = $allApps | Group-Object Runtime | Sort-Object Name
    Write-Host "`nRuntimes:" -ForegroundColor Yellow
    $runtimeGroups | ForEach-Object { Write-Host "   $($_.Name): $($_.Count) apps" -ForegroundColor White }
    
    Write-Host "`n📋 Detailed Results:" -ForegroundColor Cyan
    $allApps | Format-Table -Property FunctionAppName, ResourceGroup, Runtime, ExtensionVersion, RuntimeVersion, PlanType -AutoSize
    
    Write-Host "`n💡 To export to CSV: " -NoNewline -ForegroundColor Yellow
    Write-Host ".\Get-FunctionAppBundles-Simple.ps1 | Export-Csv -Path 'FunctionApps.csv' -NoTypeInformation" -ForegroundColor White
}
else {
    Write-Host "❌ No Function Apps found." -ForegroundColor Red
}

return $allApps