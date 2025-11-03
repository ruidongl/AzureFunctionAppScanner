# Troubleshooting Guide: Extension Bundle "Not Available via API" Issue

## Problem Description
When running the Azure Function App scanner, customers see:
- ExtensionBundleId: "Not Available via API"  
- ExtensionBundleVersion: "Not Available via API"

## Root Cause Analysis

### 1. API Limitations
Extension bundle configuration is stored in the Function App's `host.json` file, which is not directly accessible through standard Azure PowerShell cmdlets like `Get-AzWebApp` or `Get-AzFunctionApp`.

### 2. Original Script Limitation
The original script was hardcoded to return "Not Available via API" because:
- Extension bundle info requires access to the `host.json` file
- This file is part of the deployment package, not the Azure resource configuration
- Standard Azure PowerShell modules don't expose this information directly

## Solutions

### Solution 1: Use Enhanced Script (Recommended)
I've created an enhanced version (`Get-AzureFunctionAppBundleVersions-Enhanced.ps1`) that:
- Attempts to retrieve extension bundle information through alternative methods
- Provides intelligent defaults for .NET runtime apps (which don't use extension bundles)
- Shows "Default" values when custom bundles aren't configured

### Solution 2: Manual Configuration Check
For accurate extension bundle information, check the Function App's `host.json` file:

```json
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[2.*, 3.0.0)"
  }
}
```

### Solution 3: REST API Approach
Use the Azure REST API to access the file system:
```powershell
# Get deployment files (requires additional authentication)
$resourceId = "/subscriptions/{subscription}/resourceGroups/{rg}/providers/Microsoft.Web/sites/{functionapp}"
$apiVersion = "2022-03-01"
```

## Understanding Extension Bundles

### When Extension Bundles Are Used:
- **JavaScript/TypeScript** Function Apps
- **Python** Function Apps  
- **PowerShell** Function Apps
- **Java** Function Apps (sometimes)

### When Extension Bundles Are NOT Used:
- **.NET Framework** Function Apps
- **.NET Isolated** Function Apps (like yours showing ".NET Isolated")
- Apps with custom extension management

## Expected Results by Runtime Type

| Runtime | Extension Bundle Expected |
|---------|-------------------------|
| .NET Isolated | Not applicable (extensions via NuGet) |
| .NET Framework | Not applicable (extensions via NuGet) |
| Node.js | Default: Microsoft.Azure.Functions.ExtensionBundle |
| Python | Default: Microsoft.Azure.Functions.ExtensionBundle |
| PowerShell | Default: Microsoft.Azure.Functions.ExtensionBundle |
| Java | Varies (may use bundles or direct dependencies) |

## Verification Steps

### 1. Check Function App Runtime
```powershell
# Get app settings to verify runtime
$functionApp = Get-AzWebApp -ResourceGroupName "yourRG" -Name "yourFunctionApp"
$runtime = $functionApp.SiteConfig.AppSettings | Where-Object {$_.Name -eq "FUNCTIONS_WORKER_RUNTIME"}
Write-Host "Runtime: $($runtime.Value)"
```

### 2. Check for Custom Bundle Configuration
Look for these app settings:
- `AzureFunctionsJobHost__extensionBundle__id`
- `AzureFunctionsJobHost__extensionBundle__version`

### 3. Use Azure Portal
Navigate to Function App → Configuration → Application Settings to see all configuration values.

## Recommended Actions

1. **For .NET Apps**: Extension Bundle "Not applicable" is correct and expected
2. **For Other Runtimes**: Use the enhanced script to get better information
3. **For Detailed Analysis**: Access the Function App's source code or deployment package

## Script Usage

### Run Enhanced Version:
```powershell
.\Get-AzureFunctionAppBundleVersions-Enhanced.ps1 -SubscriptionId "your-subscription-id"
```

### Expected Output for .NET Isolated App:
```
Extension Bundle ID: Not applicable (.NET runtime)
Extension Bundle Version: Not applicable (.NET runtime)
```

### Expected Output for Node.js App:
```
Extension Bundle ID: Default (Microsoft.Azure.Functions.ExtensionBundle)
Extension Bundle Version: Default ([1.*, 2.0.0))
```

## Summary
The "Not Available via API" message is a limitation of the original script, not an error. For .NET Function Apps (like the one in your screenshot), this is actually the correct behavior since .NET apps don't use extension bundles - they manage extensions through NuGet packages instead.