#login to Azure
connect-azaccount

$startTime = get-date
$tableSize = 'Usage
| summarize recordCount = count(TimeGenerated) by tostring(DataType)'

$testSubscription = "<subid>"

$workspaces = $null
    #switch subscription context
    Set-AZContext -SubscriptionId $testSubscription
    #get a list of all log analytics workspaces
    $workspaces = Get-AzOperationalInsightsWorkspace
    #if the subscription contains worksapces
    if ($workspaces.count -gt 0) {
        foreach($workspace in $workspaces) { 
            Write-Host ("---Processing Workspace " + $workspace.Name)
            #get a list of tables in the workspace
            $tables = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $tableSize 
            foreach($table in $tables.results) {
                Write-Host ("------Processing Table " + $table.DataType)
                if ($table.recordCount -gt 0) {
                    $tableName = $table.DataType
                    $workspaceName = $workspace.name
                    $tableQuery = "$tableName
                    | extend splitID=split(_ResourceId, '/')
                    | extend subscriptionId = splitID[2]
                    | extend resourceGroup = splitID[4]
                    | extend resource = splitID[8]
                    | extend resourceType = splitID[6]
                    | extend resourceSubType = splitID[7]
                    | where _isBillable = True
                    | summarize ingestTotal = sum(_BilledSize)/1024/1024 by tostring(subscriptionId), tostring(resourceGroup), tostring(resourceType), tostring(resourceSubType), tostring(resource), ingestDay = bin(TimeGenerated, 1d), tableName = tostring('$tableName'), targetWorkspace=tostring('$workspaceName')"
                    #Write-Host $workspace.CustomerId
                    #Write-Host $tableQuery
                    $results = $null
                    $results = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $tableQuery -ErrorAction SilentlyContinue
                    $sum = 0
                    if ($results) {
                        foreach($result in $results.results){
                            $sum += $result.count
                        }
                        if ($sum -gt 0) {
                            #append the results to the export file
                            $results.results | export-csv source_export.csv -append
                        }
                    }                    
                }                   
            }           
        }
    }        


Write-host ("started at $startTime")
$stopTime = get-date
Write-Host ("ended at $stopTime")