az deployment group create \
  --resource-group rg-smb-lab \
  --template-file azure-smb-lab/main.bicep \
  --parameters \
    adminUsername="labadmin" \
    adminPassword="YourAdminPass123!" \
    dsrmPassword="YourDsrmPass123!" \
    sqlSaPassword="YourSqlSaPass123!" \
    allowedAdminIp="73.37.29.35/32" \
    scriptsBaseUri="https://raw.githubusercontent.com/SkyMoonTechnologies/AzureAutomation/main/azure-smb-lab/scripts"