#productName = "Azure Monitor"
#armRegionName
#location
#unitPrice
#serviceFamily "Management and Governance"
#metername 100 GB Commitment Tier Capacity Reservation
#skuName 100 GB Commitment Tier
#serviceName Azure Monitor

$queryFilter = '$filter=serviceName eq ''Azure Monitor'' and contains(skuName,''Commitment'')'
$escaped = [uri]::EscapeUriString($queryFilter)
$response = Invoke-RestMethod "https://prices.azure.com/api/retail/prices?$escaped" -contenttype 'application/json'

do {
    foreach ($item in $response.items){
        #split the meter on spaces
        $meterSplit = $item.meterName.Split(" ")
        #create a new column dividing the retail price by meter[0]
        $item | Add-Member -MemberType NoteProperty -Name commitPrice -Value ([Math]::Round(($item.retailPrice/[int]$meterSplit[0]),2))
    }

    $response.Items | export-csv pricing_file_both.csv -Append
    $response = Invoke-RestMethod $response.NextPageLink -ContentType 'application/json'
}
while ($response.NextPageLink)

#add the pergb pricing data
$queryFilter = '$filter=serviceName eq ''Log Analytics'''
$escaped = [uri]::EscapeUriString($queryFilter)
$response = Invoke-RestMethod "https://prices.azure.com/api/retail/prices?$escaped" -contenttype 'application/json'

do {
    foreach ($item in $response.items){
        #set the commitPrice column to 0
        $item | Add-Member -MemberType NoteProperty -Name commitPrice -Value 0
    }
    $response.Items | export-csv pricing_file_both.csv -Append
    $response = Invoke-RestMethod $response.NextPageLink -ContentType 'application/json'
}
while ($response.NextPageLink)