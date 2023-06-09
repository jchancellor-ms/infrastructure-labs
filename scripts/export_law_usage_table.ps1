#login to Azure
connect-azaccount
#set the start time to track how long the script runs
$startTime = get-date

#set the starting values (Path must exist)
$targetFile = "c:\temp\logtesting\logtest11\usage_export.csv"
$lookbackDays = 30

#set the starting date/time to today at midnight
$today = Get-Date
$today = $today.AddHours(-($today.hour))
$today = $today.AddMinutes(-($today.minute))
$today = $today.AddSeconds(-($today.Second))

$start = $today.AddDays(-($lookBackDays))
$end = $today

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
    do{
        $thisResponse = Search-AzGraph -Query $workspaceQuery -Subscription $batch.Group -SkipToken $thisResponse.SkipToken
        $response += $thisResponse
    } while ($thisResponse.SkipToken)    
}

#process each workspace
foreach($workspace in $response.Data){
    Write-Host ("---Processing Workspace " + $workspace.name + " for usage data between " + $start + " and " + $end + ".")
    Set-AZContext -SubscriptionId $workspace.subscriptionId
    #get a list of tables in the workspace
    $thisWorkspace = Get-AzOperationalInsightsWorkspace -Name $workspace.name -ResourceGroupName $workspace.resourceGroup
    $workspaceName = $workspace.name
    $queryDaily = "Usage
    | where IsBillable = True
    | where TimeGenerated between (datetime(" + $start + ") .. datetime(" + $end + "))
    | extend splitId = split(ResourceUri, '/')
    | extend subscriptionId = splitId[2]
    | extend targetWorkspace = '$workspaceName'
    | project TimeGenerated, ResourceUri, DataType, Solution, AvgLatencyInSeconds, Quantity, QuantityUnit, IsBillable, Type, targetWorkspace, subscriptionId"
    $results = $null
    $results = Invoke-AzOperationalInsightsQuery -WorkspaceId $thisWorkspace.CustomerId -Query $queryDaily
    if ($results.results){
        $results.results | export-csv $targetFile -append    
    }
}

Write-host ("started at $startTime")
$stopTime = get-date
Write-Host ("ended at $stopTime")

