param(
  [string]$DomainName = "contoso.local",
  [string]$SafeModePasswordPlain
)

$sec = ConvertTo-SecureString $SafeModePasswordPlain -AsPlainText -Force

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

Install-ADDSForest `
  -DomainName $DomainName `
  -SafeModeAdministratorPassword $sec `
  -Force

# The server will reboot automatically after promotion
