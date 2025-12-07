param(
  [string]$SaPasswordPlain,
  [string]$DomainAdminAccount = "CONTOSO\Administrator"
)

$sa = $SaPasswordPlain
$downloadUrl = "https://go.microsoft.com/fwlink/?linkid=866658"
$setupPath = "C:\Temp\sqldev.exe"

New-Item -Path "C:\Temp" -ItemType Directory -Force | Out-Null
Invoke-WebRequest -Uri $downloadUrl -OutFile $setupPath

$arguments = @(
  "/Q",
  "/ACTION=Install",
  "/FEATURES=SQLENGINE",
  "/INSTANCENAME=MSSQLSERVER",
  "/SQLSVCACCOUNT=""NT AUTHORITY\NETWORK SERVICE""",
  "/SECURITYMODE=SQL",
  "/SAPWD=$sa",
  "/SQLSYSADMINACCOUNTS=""$DomainAdminAccount""",
  "/IACCEPTSQLSERVERLICENSETERMS"
)

Start-Process -FilePath $setupPath -ArgumentList $arguments -Wait
