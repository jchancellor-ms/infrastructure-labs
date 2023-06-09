$subscriptionId = '<subID>'
Set-AZContext -SubscriptionId $subscriptionId
$workspaceName = "test"
$workspaceRG = "test"
$workspace = Get-AzOperationalInsightsWorkspace -Name $workspaceName -ResourceGroupName $workspaceRG

$timespans = @{}
$timespans.add("weekone", @{start="2023-04-01 00:00:00"; end="2023-04-08 00:00:00" })
$timespans.add("weektwo", @{start="2023-03-08 00:00:00"; end="2023-03-16 00:00:00" })
$timespans.add("weekthree", @{start="2023-03-16 00:00:00"; end="2023-03-24 00:00:00" })
$timespans.add("weekfour", @{start="2023-03-24 00:00:00"; end="2023-03-31 00:00:00" })

$tableName = "StorageBlobLogs"
foreach($timespan in $timespans.keys){  
    $tableQuery = "$tableName
        | where _isBillable = True
        | where TimeGenerated between (datetime(" + $timespans.item($timespan).start + ") .. datetime(" + $timespans.item($timespan).end + "))
        | summarize ingestTotal = sum(_BilledSize)/1000/1000/1000 by _ResourceId, ingestDay = bin(TimeGenerated, 1d)
        | extend splitID=split(_ResourceId, '/')
        | extend subscriptionId = splitID[2]
        | extend resourceGroup = splitID[4]
        | extend resource = splitID[8]
        | extend resourceType = splitID[6]
        | extend resourceSubType = splitID[7]
        | extend tableName = '$tableName'
        | extend targetWorkspace = '$workspaceName'
        | project ingestDay, ingestTotal, subscriptionId, resourceGroup, resourceType, resourceSubType, resource, tableName, targetWorkspace"
    write-host($tableQuery)
    $results = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $tableQuery 
    $results.results | export-csv testexport2.csv -append
}




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

#write the workspace inventory to the target location
$response.Data| export-csv $targetFileLawInventory -append