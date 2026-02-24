# Input bindings are passed in via param block.
$resourceGroups = @("IRRICT-IXC-P-EM20-WVDCoreServices-RGRP", "IRRICT-IXC-R-EM21-WVDCoreServices-RGRP", "IRRICT-IXC-t-EM20-WVDCoreServices-RGRP");
$subscriptionID = "f0c15a2d-54ee-498c-a2e6-8b8a0e26eabb";
# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()
$version = $PSVersionTable
Write-Host "Powershell version is: $($version.PSVersion)"
# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

#work out if the script is running as a user or service principal account


try {
    Write-Host "Attempting to connect to Azure..."
    
    # Check if running in Azure Function (has managed identity)
    if ($env:MSI_ENDPOINT) {
        Write-Host "Running in Azure Function - using Managed Identity..."
        $account = Connect-AzAccount -Identity
    }
    # Check if service principal credentials are provided
    elseif ($env:AZURE_CLIENT_ID -and $env:AZURE_CLIENT_SECRET -and $env:AZURE_TENANT_ID) {
        Write-Host "Using Service Principal authentication..."
        $securePassword = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($env:AZURE_CLIENT_ID, $securePassword)
        $account = Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $env:AZURE_TENANT_ID
    }
    else {
        # Interactive authentication for local testing
        Write-Host "Using interactive authentication for local testing..."
        $existingContext = Get-AzContext -ErrorAction SilentlyContinue
        
        if ($existingContext) {
            Write-Host "Found existing context for: $($existingContext.Account.Id)"
            $account = $existingContext
        }
        else {
            Write-Host "No existing Azure context found. Proceeding with authentication..."
            $account = Connect-AzAccount -UseDeviceAuthentication    
        }
    }
    
    if ($account) {
        Write-Host "Successfully authenticated as: $($account.Context.Account.Id)"
    }
    
}
catch {
    Write-Error "Authentication failed: $_"
    throw
}
#Set the azure subscription id
Set-AzContext -SubscriptionId $subscriptionID

# Initialize array to store VM data and pool data
$vmData = @()
$poolData = @()

# Define CSV output path (you can modify this path as needed)
$csvDetailOutputPath = ".\CTS_VM_DetailedReport_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
$csvSummaryOutputPath = ".\CTS_VM_SummaryReport_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"

foreach ($resourceGroupName in $resourceGroups) { 
    Write-Host "Processing Resource Group: $resourceGroupName" -ForegroundColor Green


    # Get all pools from the tenant
    $pools = Get-AzWvdHostPool -ResourceGroupName $resourceGroupName

    Write-Host "Collecting VM data from pools..." -ForegroundColor Green
    $poolNumber = 1
    # Loop through each pool
    foreach ($pool in $pools) {
        $availableVms = 0
        $shutdownVms = 0
        $unavailableVms = 0
        Write-Host "Processing Pool: $($pool.Name)" -ForegroundColor Cyan
    
        # Get all virtual machines in the current pool    
        $vms = Get-AzWvdSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $pool.Name

        #get the region name from the tags on the pool, the tag name is _0_WTWRegion    
        $regionName = $pool.Tag["_0_WTWRegion"]

        # Loop through each virtual machine
        foreach ($vm in $vms) {
            Write-Host "  Processing VM: $($vm.Name)" -ForegroundColor Yellow
        
            # Create custom object with VM properties
            $vmObject = [PSCustomObject]@{
                Geography    = $regionName
                Region       = $pool.Location
                PoolName     = $pool.Name
                VMName       = $vm.Name
                Type         = $vm.Type
                HostNumber   = $poolNumber
                Status       = $vm.Status
                StatusTime   = $vm.LastUpdateTime
                OSVersion    = $vm.OSVersion
                AgentVersion = $vm.AgentVersion
                ReportDate   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                UpdateState  = $vm.UpdateState
                UpdateError  = $vm.UpdateErrorMessage
            }
            if ($vm.status -eq "Available") 
            { $availableVms++ } 
            elseif ($vm.status -eq "Unavailable") 
            { $unavailableVms++ } 
            elseif ($vm.status -eq "Shutdown") 
            { $shutdownVms++ }        

            # Add VM object to the array
            $vmData += $vmObject        
        }

        $vmPoolObject = [PSCustomObject]@{
            Geography      = $regionName
            Region         = $pool.Location
            PoolName       = $pool.Name
            HostNumber     = $poolNumber
            PoolTotal      = $vms.Count 
            AvailableVMs   = $availableVms 
            UnavailableVMs = $unavailableVms 
            ShutdownVMs    = $shutdownVms
        }
        $poolData += $vmPoolObject
        $poolNumber++
    }
}
# Export data to CSV
if ($vmData.Count -gt 0) {
    $vmData | Export-Csv -Path $csvDetailOutputPath -NoTypeInformation
    Write-Host "`nSuccess! VM data exported to: $csvOutputPath" -ForegroundColor Green
    Write-Host "Total VMs processed: $($vmData.Count)" -ForegroundColor Green
}
else {
    Write-Host "`nWarning: No VM data found to export." -ForegroundColor Yellow
}

if ($poolData.Count -gt 0) {
    $poolData | Export-Csv -Path $csvSummaryOutputPath -NoTypeInformation
    Write-Host "`nSuccess! Pool data exported to: $csvSummaryOutputPath" -ForegroundColor Green
    Write-Host "Total Pools processed: $($poolData.Count)" -ForegroundColor Green
}
else {
    Write-Host "`nWarning: No Pool data found to export." -ForegroundColor Yellow
}


# Display summary
Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "=========" -ForegroundColor Cyan
foreach ($pool in $poolData) {
    Write-Host "Pool '$($pool.PoolName)': $($pool.PoolTotal) VMs, $($pool.AvailableVMs) Available, $($pool.ShutdownVMs) Shutdown, $($pool.UnavailableVMs) Unavailable " -ForegroundColor White
}