#login to Azure
connect-azaccount

#set the start time to track how long the script runs
$startTime = get-date

#set the starting values (Path must exist)
$targetFileSecurityEvent = "c:\temp\logtesting\logtest10\securityevent_export.csv"

$lookbackDays = 30
$largeTableSize = 50
#set the starting date/time to today at midnight
$today = Get-Date
$today = $today.AddHours(-($today.hour))
$today = $today.AddMinutes(-($today.minute))
$today = $today.AddSeconds(-($today.Second))

$start = $today.AddDays(-($lookBackDays))
$end = $today.AddDays(-1)

#set the tableSize query used to validate the tables and breakout the large workspaces
$tableSize = 'Usage
| where DataType == "SecurityEvent"
| where TimeGenerated between (datetime(' + $start + ') .. datetime(' + $end + '))
| summarize ingestTotal = sum(Quantity)/1000 by tostring(DataType), ingestDay = bin(TimeGenerated, 1d)
| summarize dayTotals = sum(ingestTotal), DayCount = count() by tostring(DataType)
| extend tableAverage = dayTotals/DayCount 
| order by tableAverage desc'

#use the resource graph to get a list of workspaces
$workspaceQuery = 'resources
| where type == "microsoft.operationalinsights/workspaces"
| extend namelower = tolower(name)
| extend laproperties = todynamic(properties)
| extend sku = tostring(laproperties.sku.name)
| extend modifiedDate = todatetime(laproperties.modifiedDate)
| summarize modifiedDate = arg_max(modifiedDate,*) by name
| join kind=inner (
resources
| where type == "microsoft.operationalinsights/workspaces"
| extend namelower = tolower(name)
| extend laproperties = todynamic(properties)
| extend sku = tostring(laproperties.sku.name)
| extend modifiedDate = todatetime(laproperties.modifiedDate)
| extend retention = tostring(laproperties.retentionInDays)
) on namelower and modifiedDate
| project name, location, sku, retention, subscriptionId, resourceGroup'

# Fetch the full array of subscription IDs
$subscriptions = Get-AzSubscription
$subscriptionIds = $subscriptions.Id

# Create a counter, set the batch size, and prepare a variable for the results
$counter = [PSCustomObject] @{ Value = 0 }
$batchSize = 1000
$response = @()

# Group the subscriptions into batches
$subscriptionsBatch = $subscriptionIds | Group -Property { [math]::Floor($counter.Value++ / $batchSize) }

# Run the query for each batch and get all the paginated results
foreach ($batch in $subscriptionsBatch){ 
    $thisResponse = Search-AzGraph -Query $workspaceQuery -Subscription $batch.Group 
    $response += $thisResponse 
    while ($thisResponse.SkipToken)   {
        $thisResponse = Search-AzGraph -Query $workspaceQuery -Subscription $batch.Group -SkipToken $thisResponse.SkipToken
        $response += $thisResponse
    }  
}

#process each workspace
foreach($workspace in $response.Data){
    Write-Host ("---Processing Workspace " + $workspace.name)
    Set-AZContext -SubscriptionId $workspace.subscriptionId
    #get a list of tables in the workspace
    $thisWorkspace = Get-AzOperationalInsightsWorkspace -Name $workspace.name -ResourceGroupName $workspace.resourceGroup
    $tables = Invoke-AzOperationalInsightsQuery -WorkspaceId $thisWorkspace.CustomerId -Query $tableSize 
    foreach($table in $tables.results) {
        Write-Host ("------Processing Table " + $table.DataType + " with average daily ingest of " + $table.tableAverage + " GB")
        #if table has records process it
        if ([float]$table.tableAverage -gt 0) {
            #if Table is large query one day at a time to avoid query timeouts, otherwise get the whole date range
            if ([float]$table.tableAverage -lt $largeTableSize){
                $endDays = $lookBackDays
            } else {
                $endDays = 1
            }
            #set the starting values for the loop and queries
            $lookBackDaysThis = $lookBackDays
            $tableName = $table.DataType
            $workspaceName = $workspace.name
            While($lookBackDaysThis -gt 0) {
                $start = $today.AddDays(-($lookBackDaysThis))
                $end = $today.AddDays(-($lookBackDaysThis-$endDays))
                Write-Host ("---------Processing Date range from " + $start + " to " + $end + ".")
                $tableQuery = "$tableName
                        | where _isBillable = True
                        | where TimeGenerated between (datetime(" + $start + ") .. datetime(" + $end + "))
                        | summarize ingestTotal = sum(_BilledSize)/1000/1000/1000 by _ResourceId, EventID, ingestDay = bin(TimeGenerated, 1d)
                        | extend splitID=split(_ResourceId, '/')
                        | extend subscriptionId = splitID[2]
                        | extend resourceGroup = splitID[4]
                        | extend resource = splitID[8]
                        | extend resourceType = splitID[6]
                        | extend resourceSubType = splitID[7]
                        | extend tableName = '$tableName'
                        | extend targetWorkspace = '$workspaceName'
                        | project ingestDay, ingestTotal, EventID, subscriptionId, resourceGroup, resourceType, resourceSubType, resource, tableName, targetWorkspace"
                $results = $null
                $results = Invoke-AzOperationalInsightsQuery -WorkspaceId $thisWorkspace.CustomerId -Query $tableQuery 
                #$sum = 0
                if ($results.results) {
                        $results.results | export-csv $targetFileSecurityEvent -append
                }   
            $lookBackDaysThis += -($endDays) 
            } 
        }       
    }
}

Write-host ("started at $startTime")
$stopTime = get-date
Write-Host ("ended at $stopTime")




#Failing tables
#too long to process (shorten the time frame)
#NetworkMonitoring (no _resourceID)
#SecurityAlert (No Logs)
#SqlAtpStatus (no _resourceId)
#Anomalies ()
#AuditLogs (No resourceID)
#SigninLogs (No ResourceId)
