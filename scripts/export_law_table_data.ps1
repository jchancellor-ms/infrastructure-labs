#login to Azure
connect-azaccount

#get a list of subscriptions
$subscriptions = Get-AzSubscription

$query = 'Usage
| where TimeGenerated > ago(1d)
| summarize  SizeMB = sum(Quantity), SizeGB = sum(Quantity)/1000 by DataType, IsBillable, ResourceUri'

#for each subscription
foreach($subscription in $subscriptions) {
    Write-Host ("Processing Subscription " + $subscription.Name)
    $workspaces = $null
    #switch subscription context
    Set-AZContext -SubscriptionId $subscription.Id
    #get a list of all log analytics workspaces
    $workspaces = Get-AzOperationalInsightsWorkspace
    if ($workspaces.count -gt 0) {
        foreach($workspace in $workspaces) { 
            Write-Host ("Processing Workspace " + $workspace.Name)
            #get space details for the workspaces
            $results = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $query
            $sum = 0
            foreach($result in $results.results){
                $sum += $result.count
            }
            if ($sum -gt 0) {
                #append the results to the export file
                $results.results | export-csv full_export.csv -append
            }
        }
    }        
} 

