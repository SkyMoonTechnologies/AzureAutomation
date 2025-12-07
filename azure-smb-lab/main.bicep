targetScope = 'resourceGroup'

@description('Admin username for all Windows VMs')
param adminUsername string

@secure()
@description('Admin password for all Windows VMs and domain')
param adminPassword string

@secure()
@description('SafeMode/DSRM password for the domain controller')
param dsrmPassword string

@secure()
@description('SQL SA password')
param sqlSaPassword string

@description('Your public IP/CIDR for RDP access (e.g. 1.2.3.4/32)')
param allowedAdminIp string

@description('Domain FQDN')
param domainName string = 'contoso.local'

@description('Prefix for resource names')
param namePrefix string = 'smb-lab'

@description('Scripts base URI, e.g. https://raw.githubusercontent.com/you/repo/main/scripts')
param scriptsBaseUri string

var location = resourceGroup().location
var vnetName = '${namePrefix}-vnet'
var subnetName = 'default'
var adminSec = adminPassword

// ---------- Network security group (RDP from your IP) ----------
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: '${namePrefix}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-From-Admin'
        properties: {
          priority: 100
          direction: 'Inbound'
          protocol: 'Tcp'
          access: 'Allow'
          sourceAddressPrefix: allowedAdminIp
          destinationAddressPrefix: '*'
          sourcePortRange: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'Allow-VNet'
        properties: {
          priority: 200
          direction: 'Inbound'
          protocol: '*'
          access: 'Allow'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ---------- VNet + Subnet ----------
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

var subnetRef = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
var winImage = {
  publisher: 'MicrosoftWindowsServer'
  offer: 'WindowsServer'
  sku: '2022-datacenter'
  version: 'latest'
}

// ---------- Helper for NIC ----------
param vmSize string = 'Standard_B2s'

resource pipApp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: '${namePrefix}-pip-app01'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nicDc 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: '${namePrefix}-nic-dc01'
  location: location
  dependsOn: [
    vnet
  ]  
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetRef
          }
        }
      }
    ]
  }
}

resource nicFs 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: '${namePrefix}-nic-fs01'
  dependsOn: [
    vnet
  ]  
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetRef
          }
        }
      }
    ]
  }
}

resource nicSql 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: '${namePrefix}-nic-sql01'
  dependsOn: [
    vnet
  ]  
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetRef
          }
        }
      }
    ]
  }
}

resource nicApp 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: '${namePrefix}-nic-app01'
  dependsOn: [
    vnet
  ]  
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetRef
          }
          publicIPAddress: {
            id: pipApp.id
          }
        }
      }
    ]
  }
}

// ---------- DC01 VM ----------
resource vmDc 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${namePrefix}-vm-dc01'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'DC01'
      adminUsername: adminUsername
      adminPassword: adminSec
    }
    storageProfile: {
      imageReference: winImage
      osDisk: {
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicDc.id
        }
      ]
    }
  }
}

// Promote DC via Custom Script Extension
resource dcCse 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  name: '${vmDc.name}/PromoteToDC'
  location: location
  dependsOn: [
    vmDc
  ]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        '${scriptsBaseUri}/promote-dc.ps1'
      ]
      commandToExecute: 'powershell -ExecutionPolicy Bypass -File promote-dc.ps1 -DomainName "${domainName}" -SafeModePasswordPlain "${dsrmPassword}"'
    }
  }
}

// ---------- FS01 VM ----------
resource vmFs 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${namePrefix}-vm-fs01'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'FS01'
      adminUsername: adminUsername
      adminPassword: adminSec
    }
    storageProfile: {
      imageReference: winImage
      osDisk: {
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicFs.id
        }
      ]
    }
  }
}

// Join FS01 + configure shares
resource fsCse 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  name: '${vmFs.name}/JoinDomainAndFs'
  location: location
  dependsOn: [
    dcCse
    vmFs
  ]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        '${scriptsBaseUri}/join-domain-and-fs.ps1'
      ]
      commandToExecute: 'powershell -ExecutionPolicy Bypass -File join-domain-and-fs.ps1 -DomainName "${domainName}" -DomainAdminUser "Administrator" -DomainAdminPasswordPlain "${adminPassword}" -ConfigureFileServer'
    }
  }
}

// ---------- SQL01 VM ----------
resource vmSql 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${namePrefix}-vm-sql01'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2ms'
    }
    osProfile: {
      computerName: 'SQL01'
      adminUsername: adminUsername
      adminPassword: adminSec
    }
    storageProfile: {
      imageReference: winImage
      osDisk: {
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicSql.id
        }
      ]
    }
  }
}

// Join SQL01 + install SQL
resource sqlJoinCse 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  name: '${vmSql.name}/JoinDomain'
  location: location
  dependsOn: [
    dcCse
    vmSql
  ]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        '${scriptsBaseUri}/join-domain-and-fs.ps1'
      ]
      commandToExecute: 'powershell -ExecutionPolicy Bypass -File join-domain-and-fs.ps1 -DomainName "${domainName}" -DomainAdminUser "Administrator" -DomainAdminPasswordPlain "${adminPassword}"'
    }
  }
}

resource sqlInstallCse 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  name: '${vmSql.name}/InstallSql'
  location: location
  dependsOn: [
    sqlJoinCse
  ]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        '${scriptsBaseUri}/install-sql.ps1'
      ]
      commandToExecute: 'powershell -ExecutionPolicy Bypass -File install-sql.ps1 -SaPasswordPlain "${sqlSaPassword}" -DomainAdminAccount "CONTOSO\\Administrator"'
    }
  }
}

// ---------- APP01 (jumpbox) ----------
resource vmApp 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${namePrefix}-vm-app01'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'APP01'
      adminUsername: adminUsername
      adminPassword: adminSec
    }
    storageProfile: {
      imageReference: winImage
      osDisk: {
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicApp.id
        }
      ]
    }
  }
}

// Join APP01 to domain (no FS/SQL)
resource appJoinCse 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  name: '${vmApp.name}/JoinDomain'
  location: location
  dependsOn: [
    dcCse
    vmApp
  ]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        '${scriptsBaseUri}/join-domain-and-fs.ps1'
      ]
      commandToExecute: 'powershell -ExecutionPolicy Bypass -File join-domain-and-fs.ps1 -DomainName "${domainName}" -DomainAdminUser "Administrator" -DomainAdminPasswordPlain "${adminPassword}"'
    }
  }
}

// ---------- Outputs ----------
output jumpboxPublicIp string = pipApp.properties.ipAddress
output domain string = domainName
