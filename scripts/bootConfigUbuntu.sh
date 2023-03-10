az vm extension set \
  --resource-group azhoplab-rg-westus3-a1 \
  --vm-name test-vm \
  --name customScript \
  --publisher Microsoft.Azure.Extensions \
  --settings '{"fileUris": ["https://raw.githubusercontent.com/me/project/hello.sh"],"commandToExecute": "./hello.sh"}'