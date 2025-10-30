# Azure Function App Bundle Version Scanner

A comprehensive PowerShell script to analyze Azure Function Apps and retrieve their extension bundle versions, runtime configurations, and deployment settings across Azure subscriptions.

## 📋 Overview

This script scans Azure subscriptions to identify Function Apps and extracts detailed configuration information including:
- Function App runtime stack and versions
- Extension bundle configurations
- App Service Plan details
- Application settings
- Host.json configuration (where accessible)
- Performance and scaling settings

## 🚀 Features

### Core Capabilities
- ✅ **Multi-subscription scanning** - Analyze all accessible subscriptions or target specific ones
- ✅ **Resource group filtering** - Scan specific resource groups or all groups
- ✅ **Multiple output formats** - Table, List, CSV, and JSON export options
- ✅ **Comprehensive analysis** - Runtime versions, extension bundles, and configuration details
- ✅ **Progress reporting** - Real-time feedback during large-scale scans
- ✅ **Error handling** - Graceful handling of access issues and missing resources

### Compatibility
- ✅ **PowerShell 5.1 Compatible** - Works with Windows PowerShell
- ✅ **Fallback mechanisms** - Uses Az.Websites when Az.Functions is unavailable
- ✅ **Flexible authentication** - Works with existing Azure PowerShell sessions

## 📦 Prerequisites

### Required Azure PowerShell Modules
```powershell
# Install required modules (run as Administrator or with -Scope CurrentUser)
Install-Module -Name Az.Accounts -Force -AllowClobber
Install-Module -Name Az.Websites -Force -AllowClobber
Install-Module -Name Az.Resources -Force -AllowClobber

# Optional (enhanced functionality)
Install-Module -Name Az.Functions -Force -AllowClobber
```

### Azure Authentication
```powershell
# Connect to Azure
Connect-AzAccount

# Optional: Set specific subscription context
Set-AzContext -SubscriptionId "your-subscription-id"
```

## 📖 Usage

### Script Files
- **`Get-AzureFunctionAppBundleVersions-Compatible.ps1`** - Main script (PowerShell 5.1 compatible)
- **`Get-AzureFunctionAppBundleVersions.ps1`** - Advanced version (requires newer PowerShell)

### Basic Syntax
```powershell
.\Get-AzureFunctionAppBundleVersions-Compatible.ps1 [parameters]
```

### Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `SubscriptionId` | String | Target subscription ID | Current subscription |
| `ResourceGroupName` | String | Target resource group name | All resource groups |
| `OutputFormat` | String | Output format: Table, List, CSV, JSON | Table |
| `ExportPath` | String | File path for exporting results | None |

## 🎯 Usage Examples

### 1. Basic Scan - Current Subscription
```powershell
# Scan all Function Apps in current subscription
.\Get-AzureFunctionAppBundleVersions-Compatible.ps1
```

### 2. Target Specific Subscription
```powershell
# Scan specific subscription
.\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -SubscriptionId "15228dc1-0ebf-40f8-a51f-2e6023f1766c"
```

### 3. Resource Group Filtering
```powershell
# Scan specific resource group
.\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -ResourceGroupName "my-function-apps-rg"
```

### 4. Export to CSV
```powershell
# Export results to CSV file
.\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -OutputFormat CSV -ExportPath "C:\Reports\FunctionApps.csv"
```

### 5. JSON Export for API Integration
```powershell
# Export to JSON for further processing
.\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -OutputFormat JSON -ExportPath "C:\Reports\FunctionApps.json"
```

### 6. Detailed List View
```powershell
# Show all properties in list format
.\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -OutputFormat List
```

### 7. Verbose Execution
```powershell
# Run with detailed progress information
.\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -Verbose
```

## 📊 Sample Output

### Console Output
```
Azure Function App Bundle Version Scanner
=========================================
Connected to Azure as: user@company.com
Scanning specific subscription: Production-Subscription

Processing subscription: Production-Subscription (12345678-1234-1234-1234-123456789012)
   Found 5 resource group(s) to scan
      Scanning resource group: rg-functions-prod
         Found 3 Function App(s)
            Analyzing: MyFunctionApp1
            Analyzing: MyFunctionApp2
            Analyzing: MyFunctionApp3

Scan Results Summary
===================
Total Function Apps found: 3
Successfully analyzed: 3

Extension Version Distribution:
   ~4: 2 apps
   ~3: 1 apps

Runtime Distribution:
   dotnet-isolated: 2 apps
   node: 1 apps

Detailed Results:
================
FunctionAppName    ResourceGroupName    RuntimeStack     FunctionsExtensionVersion
---------------    -----------------    ------------     -------------------------
MyFunctionApp1     rg-functions-prod    dotnet-isolated  ~4
MyFunctionApp2     rg-functions-prod    dotnet-isolated  ~4
MyFunctionApp3     rg-functions-prod    node             ~3
```

### CSV Export Sample
```csv
SubscriptionId,SubscriptionName,ResourceGroupName,FunctionAppName,Location,RuntimeStack,FunctionsExtensionVersion,State
12345...,Production-Subscription,rg-functions-prod,MyFunctionApp1,East US,dotnet-isolated,~4,Running
12345...,Production-Subscription,rg-functions-prod,MyFunctionApp2,East US,dotnet-isolated,~4,Running
```

## 📋 Information Collected

The script extracts the following information for each Function App:

### Basic Information
- **SubscriptionId** - Azure subscription identifier
- **SubscriptionName** - Subscription display name
- **ResourceGroupName** - Resource group name
- **FunctionAppName** - Function App name
- **Location** - Azure region
- **State** - Running/Stopped status

### Runtime Configuration
- **RuntimeStack** - Primary runtime (dotnet-isolated, node, python, java, powershell)
- **FunctionsExtensionVersion** - Functions runtime version (~4, ~3, etc.)
- **FunctionsWorkerRuntimeVersion** - Specific runtime version
- **NetFrameworkVersion** - .NET Framework version
- **NodeVersion** - Node.js version (if applicable)

### Deployment Settings
- **Kind** - App kind (functionapp, functionapp,linux, etc.)
- **AlwaysOn** - Always On setting (Consumption plans: false)
- **Use32BitWorkerProcess** - Platform architecture
- **DefaultDocuments** - Default document list

### Extension Information
- **ExtensionBundleId** - Extension bundle identifier
- **ExtensionBundleVersion** - Bundle version range
- **LastModifiedTime** - Last deployment/modification time

## 🔧 Troubleshooting

### Common Issues and Solutions

#### "Not logged in to Azure"
```powershell
# Solution: Connect to Azure
Connect-AzAccount
```

#### "Module not found" errors
```powershell
# Solution: Install required modules
Install-Module -Name Az.Accounts, Az.Websites, Az.Resources -Force -Scope CurrentUser
```

#### "Access denied" or permission errors
```powershell
# Check your Azure permissions
Get-AzRoleAssignment -SignInName (Get-AzContext).Account.Id

# Required permissions:
# - Reader role on subscriptions/resource groups
# - For detailed analysis: Contributor role may be needed
```

#### Script execution policy errors
```powershell
# Check current execution policy
Get-ExecutionPolicy

# Set execution policy (run as Administrator)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### Empty results when Function Apps exist
```powershell
# Verify you're in the correct subscription
Get-AzContext

# Check if Function Apps are visible
Get-AzWebApp | Where-Object { $_.Kind -like "*functionapp*" }
```

## 💡 Use Cases

### 1. Compliance Auditing
```powershell
# Find Function Apps with outdated extension versions
$results = .\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -OutputFormat CSV
$outdated = $results | Where-Object { $_.FunctionsExtensionVersion -eq "~3" }
$outdated | Export-Csv -Path "OutdatedFunctionApps.csv" -NoTypeInformation
```

### 2. Migration Planning
```powershell
# Group Function Apps by runtime for migration assessment
$results = .\Get-AzureFunctionAppBundleVersions-Compatible.ps1
$byRuntime = $results | Group-Object RuntimeStack
$byRuntime | Format-Table Name, Count -AutoSize
```

### 3. Cost Optimization
```powershell
# Identify Always On settings for cost optimization
$results = .\Get-AzureFunctionAppBundleVersions-Compatible.ps1
$alwaysOnApps = $results | Where-Object { $_.AlwaysOn -eq $true }
Write-Host "Function Apps with Always On enabled: $($alwaysOnApps.Count)"
```

### 4. Security Assessment
```powershell
# Find Function Apps that may need security updates
$results = .\Get-AzureFunctionAppBundleVersions-Compatible.ps1
$securityReview = $results | Where-Object { 
    $_.FunctionsExtensionVersion -eq "~2" -or 
    $_.FunctionsExtensionVersion -eq "~1" 
}
$securityReview | Export-Csv -Path "SecurityReview.csv" -NoTypeInformation
```

### 5. Environment Comparison
```powershell
# Compare Function Apps across environments
$prod = .\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -SubscriptionId "prod-sub-id"
$dev = .\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -SubscriptionId "dev-sub-id"

# Compare runtime versions
Compare-Object $prod.FunctionsExtensionVersion $dev.FunctionsExtensionVersion
```

## 🔄 Automation and Integration

### Scheduled Execution
```powershell
# Create scheduled task for monthly reporting
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -OutputFormat CSV -ExportPath C:\Reports\Monthly-FunctionApps.csv"
$trigger = New-ScheduledTaskTrigger -Monthly -At 9am -DaysOfMonth 1
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -TaskName "Function App Audit"
```

### Azure DevOps Integration
```yaml
# Azure DevOps pipeline step
- task: AzurePowerShell@5
  displayName: 'Audit Function Apps'
  inputs:
    azureSubscription: 'Azure-Service-Connection'
    ScriptType: 'FilePath'
    ScriptPath: '$(System.DefaultWorkingDirectory)/scripts/Get-AzureFunctionAppBundleVersions-Compatible.ps1'
    ScriptArguments: '-OutputFormat JSON -ExportPath $(Build.ArtifactStagingDirectory)/function-apps.json'
    azurePowerShellVersion: 'LatestVersion'
```

### PowerBI Integration
```powershell
# Export data for PowerBI consumption
$results = .\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -OutputFormat CSV
$results | Export-Csv -Path "C:\PowerBI\FunctionApps.csv" -NoTypeInformation

# PowerBI can then import this CSV for dashboard creation
```

## 🛡️ Security Considerations

### Permissions Required
- **Reader** role on target subscriptions/resource groups
- **Contributor** role for enhanced host.json analysis (optional)

### Data Handling
- Script does not store credentials
- Uses existing Azure PowerShell session authentication
- Exported files may contain sensitive configuration data
- Ensure exported files are stored securely

### Best Practices
```powershell
# Use service principals for automated execution
$credential = Get-Credential
Connect-AzAccount -ServicePrincipal -Credential $credential -TenantId "tenant-id"

# Limit scope to specific subscriptions
.\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -SubscriptionId "specific-subscription-id"

# Secure export locations
.\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -ExportPath "C:\SecureReports\FunctionApps.csv"
```

## 📈 Performance Tips

### For Large Environments
1. **Target specific subscriptions** to reduce scan time
2. **Use resource group filtering** for focused analysis
3. **Export to CSV** for processing large datasets
4. **Run during off-peak hours** for production environments

### Optimization Settings
```powershell
# For faster execution in large environments
$ProgressPreference = 'SilentlyContinue'  # Disable progress bars
.\Get-AzureFunctionAppBundleVersions-Compatible.ps1 -SubscriptionId "target-sub"
```

## 🤝 Contributing

### Enhancement Ideas
- Support for Azure Government clouds
- Integration with Azure Resource Graph for faster queries
- Additional filtering capabilities
- Enhanced export formats
- Performance optimizations for large tenants

### Reporting Issues
When reporting issues, please include:
- PowerShell version (`$PSVersionTable`)
- Azure PowerShell module versions (`Get-Module Az.* -ListAvailable`)
- Error messages and stack traces
- Subscription and resource group context

## 📜 License

This script is provided as-is for educational and operational purposes. Modify as needed for your environment.

---

**Note**: Always test scripts in development environments before running in production. Some operations may require elevated permissions in Azure.