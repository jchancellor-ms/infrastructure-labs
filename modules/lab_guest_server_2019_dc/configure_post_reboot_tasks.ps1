#Add the KDS root key for configuring GMSA accounts
Add-KdsRootKey -EffectiveTime ((get-date).addhours(-10))

# Create the security group
New-ADGroup -Name "Windows_K8s_Nodes" -SamAccountName "WinK8sUsers" -GroupScope DomainLocal

# Create the gMSA
New-ADServiceAccount -Name "${app_name}" -DnsHostName "${app_name}.${active_directory_domain}" -ServicePrincipalNames "host/${app_name}", "host/${app_name}.${active_directory_domain}" -PrincipalsAllowedToRetrieveManagedPassword "WinK8sUsers"

# Add your container hosts to the security group
#Add-ADGroupMember -Identity "WinK8s" -Members ${windows_nodes}

# Create the standard user account. This account information needs to be stored in a secret store and will be retrieved by the ccg.exe hosted plug-in to retrieve the gMSA password. Replace 'StandardUser01' and 'p@ssw0rd' with a unique username and password. We recommend using a random, long, machine-generated password.
New-ADUser -Name "${app_ad_user}" -AccountPassword (ConvertTo-SecureString -AsPlainText "${app_ad_user_pass}" -Force) -Enabled 1 

# Add your container hosts to the security group
Add-ADGroupMember -Identity "WinK8sUsers" -Members "${app_ad_user}"


