$workSpaceQueryExport = "
union withsource = SourceTable
    AzureDiagnostics,
    AzureActivity,
    AzureMetrics,
    ContainerLog,
    ContainerLogV2,
    Perf,
    KubePodInventory,
    ContainerInventory,
    InsightsMetrics,
    KubeEvents,
    KubeServices,
    KubeNodeInventory,
    ContainerNodeInventory,
    KubeMonAgentEvents,
    ContainerServiceLog,
    Heartbeat,
    KubeHealth,
    ContainerImageInventory,
    Syslog
| where _IsBillable == true
| project _BilledSize, TimeGenerated, SourceTable, _ResourceId
| summarize BillableDataBytes = sum(_BilledSize) by bin(TimeGenerated, 24h), SourceTable, tostring(_ResourceId)
| extend splitID=split(_ResourceId, '/')
| extend subscriptionId = splitID[2]
| extend resourceGroup = splitID[4]
| extend resource = splitID[8]
| extend resourceType = splitID[6]
| extend resourceSubType = splitID[7]
| where resourceSubType == 'managedclusters'
| project BillableDataBytes/1000/1000/1000, TimeGenerated, subscriptionId, resourceGroup, resource, SourceTable"

$timespans = @()
$timespans += (New-Timespan -Start "2023-03-01 00:00:00" -End "2023-03-08 00:00:00" )
$timespans += (New-Timespan -Start "2023-03-08 00:00:00" -End "2023-03-16 00:00:00" )
$timespans += (New-Timespan -Start "2023-03-16 00:00:00" -End "2023-03-24 00:00:00" )
$timespans += (New-Timespan -Start "2023-03-24 00:00:00" -End "2023-03-31 00:00:00" )

$startTime = get-date

#$testSubscription = "1acbaf85-58aa-4f0a-a93b-9176a0f08bd3"
#get a list of subscriptions
$subscriptions = Get-AzSubscription

#for each subscription
foreach($subscription in $subscriptions) {
    Write-Host ("Processing Subscription " + $subscription.Name)
    $workspaces = $null
    #switch subscription context
    Set-AZContext -SubscriptionId $subscription.Id
    #get a list of all log analytics workspaces
    $workspaces = Get-AzOperationalInsightsWorkspace
    #if the subscription contains workspaces
    if ($workspaces.count -gt 0) {
        foreach($workspace in $workspaces) { 
            Write-Host ("---Processing Workspace " + $workspace.Name)
            #get workspace container data
            foreach($timespan in $timespans){
                $results = $null
                $results = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $workSpaceQueryExport -Timespan $timespan
                $sum = 0
                if ($results) {
                    foreach($result in $results.results){
                        $sum += $result.count
                    }
                    write-Host ("total records $sum")
                    if ($sum -gt 0) {
                        #append the results to the export file
                        $results.results | export-csv aks_table_usage.csv -append
                    }
                }    
            }        
        }
    }
}    
    
Write-host ("started at $startTime")
$stopTime = get-date
Write-Host ("ended at $stopTime")
