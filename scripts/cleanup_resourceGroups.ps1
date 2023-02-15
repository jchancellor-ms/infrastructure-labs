try {
    "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

#Get all resource groups where the tag conditions for deletion are met
$resourceGroups = get-azresourceGroup | Where-Object { 
    #resourceGroup doesn't have locks
    (
            (get-AzResourceLock -ResourceGroupName $_.ResourceGroupName).count -eq 0
    ) 
} |
Where-Object {
    #CreatedDate tag is missing or
        (($_.Tags.CreatedDate) -eq $null) -or
    #Created date tag is older than 7 days and the delete date tag has expired
        (((New-TimeSpan -Start ($_.Tags.CreatedDate) -End (get-Date).AddDays(-7)).TotalDays -gt 7) -and
        ((New-Timespan -Start (get-Date)  -End ($_.Tags.DeleteDate)) -lt 0) )  
}

#Attempt deletion of the identified resource groups.  If locked, they should error and continue.
foreach ($ResourceGroup in $ResourceGroups) {    
    Write-Output ("Deleting resources in resource group " + $ResourceGroup.ResourceGroupName + " with Delete Date tag " + $ResourceGroup.Tags.DeleteDate)
    try {
        remove-azresourcegroup -name $ResourceGroup.resourcegroupname -force -AsJob -errorAction continue 
    }
    catch {
        Write-Error -Message $_.Exception
    }
}

Get-Job | Wait-Job
