param(
  [string]$DomainName = "contoso.local",
  [string]$DomainAdminUser = "Administrator",
  [string]$DomainAdminPasswordPlain,
  [switch]$ConfigureFileServer
)

$sec = ConvertTo-SecureString $DomainAdminPasswordPlain -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("$DomainName\$DomainAdminUser", $sec)

# Join domain if not already
if (-not (Get-WmiObject Win32_ComputerSystem).PartOfDomain) {
  Add-Computer -DomainName $DomainName -Credential $cred -Force
}

# Optional file server config (only on FS01)
if ($ConfigureFileServer) {
  New-Item -Path "C:\Shares" -ItemType Directory -Force | Out-Null
  "Company","Finance","HR","IT","Projects" | ForEach-Object {
    New-Item -Path "C:\Shares\$_" -ItemType Directory -Force | Out-Null
  }

  Import-Module ActiveDirectory

  $groups = @{
    "GRP_Company_RW"  = "C:\Shares\Company"
    "GRP_Finance_RW"  = "C:\Shares\Finance"
    "GRP_HR_RW"       = "C:\Shares\HR"
    "GRP_IT_RW"       = "C:\Shares\IT"
    "GRP_Projects_RW" = "C:\Shares\Projects"
  }

  foreach ($g in $groups.Keys) {
    if (-not (Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue)) {
      New-ADGroup -Name $g -GroupScope Global -GroupCategory Security | Out-Null
    }
  }

  foreach ($g in $groups.GetEnumerator()) {
    $path = $g.Value
    $group = "CONTOSO\$($g.Key)"
    icacls $path /grant "$group:(OI)(CI)(M)" /T | Out-Null
    $shareName = Split-Path $path -Leaf
    if (-not (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue)) {
      New-SmbShare -Name $shareName -Path $path -FullAccess $group | Out-Null
    }
  }
}

Restart-Computer -Force
