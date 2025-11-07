# Azure Function App Scanner Performance Optimization

## Performance Comparison

### Original Script (Resource Group Iteration)
- **Method**: Iterates through every resource group, then scans for Function Apps in each
- **Performance**: Slow for subscriptions with many resource groups
- **API Calls**: O(n) where n = number of resource groups
- **Typical Time**: 2-5 seconds per resource group

### Optimized Script (Resource Provider Scanning)
- **Method**: Uses resource provider queries to find Function Apps directly
- **Performance**: Much faster, especially for subscriptions with many empty resource groups
- **API Calls**: O(1) for Function App discovery per subscription
- **Typical Time**: 1-2 seconds per subscription for discovery

### Ultra-Optimized Script (Azure Resource Graph)
- **Method**: Uses Azure Resource Graph to query across multiple subscriptions simultaneously
- **Performance**: Fastest possible method, can scan thousands of resources in seconds
- **API Calls**: Single query across all subscriptions
- **Typical Time**: 2-5 seconds total for discovery across all subscriptions

## Performance Improvements

### Scenario 1: Large subscription with 100 resource groups, 5 Function Apps
- **Original**: ~200-500 seconds (2-5 seconds × 100 RGs)
- **Optimized**: ~5-10 seconds
- **Ultra-Optimized**: ~2-5 seconds
- **Improvement**: 40-250x faster

### Scenario 2: Multiple subscriptions (10 subs, avg 50 RGs each, 20 total Function Apps)
- **Original**: ~1000-2500 seconds (scanning 500 RGs total)
- **Optimized**: ~50-100 seconds (10 subs × 5-10 seconds)
- **Ultra-Optimized**: ~5-10 seconds (single cross-subscription query)
- **Improvement**: 100-500x faster

## Key Optimization Techniques

### 1. Resource Provider Filtering
```powershell
# Instead of scanning all resources in each RG:
Get-AzResource -ResourceGroupName $rgName

# Use targeted resource type filtering:
Get-AzResource -ResourceType "Microsoft.Web/sites" | Where-Object { $_.Kind -like "*functionapp*" }
```

### 2. Azure Resource Graph Queries
```kusto
Resources
| where type =~ 'microsoft.web/sites'
| where kind contains 'functionapp'
| where subscriptionId in ('sub1', 'sub2', 'sub3')
| project name, resourceGroup, location, kind, type, id, tags, subscriptionId
```

### 3. Batch Processing
- Process all discovered Function Apps in batches
- Use progress indicators for user feedback
- Minimize context switching between subscriptions

### 4. Fast Scan Mode
- Option to skip detailed configuration retrieval
- Only get basic resource information
- Useful for quick inventory or discovery

## Usage Examples

### Basic Optimized Scan
```powershell
.\Get-AzureFunctionAppBundleVersions-Optimized.ps1 -SubscriptionId "your-sub-id"
```

### Ultra-Fast Discovery (Fast Scan)
```powershell
.\Get-AzureFunctionAppBundleVersions-UltraOptimized.ps1 -FastScan
```

### Cross-Subscription Scan with Export
```powershell
.\Get-AzureFunctionAppBundleVersions-UltraOptimized.ps1 -OutputFormat CSV -ExportPath "FunctionApps.csv"
```

### Specific Resource Group (Still Optimized)
```powershell
.\Get-AzureFunctionAppBundleVersions-UltraOptimized.ps1 -ResourceGroupName "my-rg"
```

## Required Azure Modules

### For Optimized Script
```powershell
Install-Module Az.Accounts, Az.Resources, Az.Websites
```

### For Ultra-Optimized Script
```powershell
Install-Module Az.Accounts, Az.Resources, Az.Websites, Az.ResourceGraph
```

## Performance Tips

1. **Use Ultra-Optimized version** for best performance
2. **Enable Fast Scan mode** (`-FastScan`) for quick discovery
3. **Install Az.ResourceGraph module** for maximum speed
4. **Filter by subscription or resource group** when possible
5. **Export results** to avoid re-scanning for analysis

## Error Handling and Fallbacks

All optimized scripts include fallback mechanisms:
1. If Azure Resource Graph fails → falls back to resource provider queries
2. If resource provider queries fail → falls back to traditional RG iteration
3. If detailed app settings fail → continues with basic information

## Security and Permissions

Required Azure RBAC permissions:
- **Reader** role on subscriptions/resource groups to scan
- **Resource Graph Reader** role for ultra-optimized scanning (recommended)

The optimized approach is much more efficient because:
1. **Reduces API calls** by 90-99%
2. **Eliminates empty resource group scanning**
3. **Enables cross-subscription queries**
4. **Provides better progress visibility**
5. **Includes performance metrics**