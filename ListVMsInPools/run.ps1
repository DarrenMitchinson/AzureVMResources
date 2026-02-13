# Input bindings are passed in via param block.
param($Timer, $resourceGroupName)
# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

# Initialize array to store VM data
$vmData = @()

# Define CSV output path (you can modify this path as needed)
$csvOutputPath = ".\CTS_VM_Report_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"

# Get all pools from the tenant
$pools = Get-AzWvdHostPool -ResourceGroupName $resourceGroupName

Write-Host "Collecting VM data from pools..." -ForegroundColor Green

# Loop through each pool
foreach ($pool in $pools) {
    Write-Host "Processing Pool: $($pool.Name)" -ForegroundColor Cyan
    
    # Get all virtual machines in the current pool
    $vms = Get-BrokerMachine -DesktopGroupName $pool.Name
    
    # Loop through each virtual machine
    foreach ($vm in $vms) {
        Write-Host "  Processing VM: $($vm.MachineName)" -ForegroundColor Yellow
        
        # Create custom object with VM properties
        $vmObject = [PSCustomObject]@{
            PoolName = $pool.Name
            VMName = $vm.MachineName
            ResourceGroup = $vm.ResourceGroupName
            HostingServer = $vm.HostedMachineName
            PowerState = $vm.PowerState
            RegistrationState = $vm.RegistrationState
            MaintenanceMode = $vm.InMaintenanceMode
            SessionState = $vm.SessionState
            UserSessions = $vm.SessionCount
            OSType = $vm.OSType
            AgentVersion = $vm.AgentVersion
            ReportDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        }
        
        # Add VM object to the array
        $vmData += $vmObject
    }
}

# Export data to CSV
if ($vmData.Count -gt 0) {
    $vmData | Export-Csv -Path $csvOutputPath -NoTypeInformation
    Write-Host "`nSuccess! VM data exported to: $csvOutputPath" -ForegroundColor Green
    Write-Host "Total VMs processed: $($vmData.Count)" -ForegroundColor Green
} else {
    Write-Host "`nWarning: No VM data found to export." -ForegroundColor Yellow
}

# Display summary
Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "=========" -ForegroundColor Cyan
foreach ($pool in ($vmData | Group-Object PoolName)) {
    Write-Host "Pool '$($pool.Name)': $($pool.Count) VMs" -ForegroundColor White
}