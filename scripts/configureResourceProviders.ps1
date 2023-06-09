Param(
      [Parameter(Mandatory=$True)]
      [string[]]$subscription
 )

$context = Get-AzContext -ErrorAction SilentlyContinue
if (!$context) {
    Connect-AzAccount
}

Set-AzContext -Subscription $subscription
$providerState = (Get-AzResourceProvider | Select-Object ProviderNamespace, RegistrationState | Where-object ProviderNamespace -eq 'Microsoft.ManagedServices')
if (!($providerState.RegistrationState -eq 'Registered')){
    Register-AzResourceProvider -ProviderNamespace 'Microsoft.ManagedServices'
}

