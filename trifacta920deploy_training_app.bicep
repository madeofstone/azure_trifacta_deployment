// Deployment Name is used to prefix all resources
param deploymentName string
param deploymentString  string = substring(guid(uniqueString(resourceGroup().id)), 0, 2)

// Parameters - If no default given, then param is required. Existing components can also be used.
@description('This is the object ID for the service princpal(enterprise application) associated with the registered app for Trifacta.')
@secure()
param servicePrincipalObjectId string
param location string = resourceGroup().location
param networkSecurityGroupName string = '${deploymentName}-${deploymentString}-nsg'
param subnetName string = 'default'
param virtualNetworkName string = '${deploymentName}-${deploymentString}-net'
param publicIpAddressName string = '${deploymentName}-${deploymentString}-pip2'
param publicIpAddressType string = 'static'
param publicIpAddressSku string = 'Basic'
param virtualMachineName string = '${deploymentName}-${deploymentString}-vm2'
param virtualMachineSize string = 'Standard_D8s_v3'
param adminUsername string = 'trifactaAdmin'
@secure()
param sshKey string
param trifactaStorageAccountName string = 'trifacta${deploymentString}storage'
param databricksWorkspaceName string = '${deploymentName}-${deploymentString}-db'
param databricksMRGID string = '${subscription().id}/resourceGroups/${deploymentName}-${deploymentString}-dbrg'
param containerName string = 'trifacta'
param keyVaultName string = '${deploymentName}-${deploymentString}-kv'

//Variables
var networkInterfaceName = '${deploymentName}-${deploymentString}-int2'
var vnetId = virtualNetworkName_resource.id
var subnetRef = '${vnetId}/subnets/${subnetName}'


// Resources

// Network Interface
resource networkInterface 'Microsoft.Network/networkInterfaces@2021-08-01' = {
  name: networkInterfaceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: subnetRef
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpAddressName_resource.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: networkSecurityGroupName_resource.id
    }
  }
}

// Network Security Group
resource networkSecurityGroupName_resource 'Microsoft.Network/networkSecurityGroups@2019-02-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          priority: 300
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'Trifacta_Service'
        properties: {
          priority: 200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '3005'
            '80'
            '443'
          ]
        }
      }
    ]
  }
}

// Virtual Network for Trifacta node
resource virtualNetworkName_resource 'Microsoft.Network/virtualNetworks@2019-04-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.2.0/24'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.1.2.0/24'
          serviceEndpoints: [
            {
              service: 'Microsoft.KeyVault'
            }
          ]
        }
      }
    ]
  }
}

//Public IP address
resource publicIpAddressName_resource 'Microsoft.Network/publicIPAddresses@2021-08-01' = {
  name: publicIpAddressName
  location: location
  properties: {
    publicIPAllocationMethod: publicIpAddressType
    dnsSettings: {
      domainNameLabel: toLower('${deploymentName}${deploymentString}23')
    }
  }
  sku: {
    name: publicIpAddressSku
  }
}

// Virtual Machine
resource virtualMachine 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: virtualMachineName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: virtualMachineSize
    }
    storageProfile: {
      osDisk: {
        name: '${virtualMachineName}_OSDISK'
        createOption: 'FromImage'
        diskSizeGB: 128 
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
      imageReference: {
        publisher: 'RedHat'
        offer: 'RHEL'
        sku: '82gen2'
        version: 'latest'
    }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    osProfile: {
      computerName: virtualMachineName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              keyData: sshKey
              path: '/home/${adminUsername}/.ssh/authorized_keys'
            }
          ]
        }
      }
    }
  }
}

// Storage Account (ADLSgen2)
resource trifactaStorageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: trifactaStorageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
    }
    isHnsEnabled: true
    supportsHttpsTrafficOnly: true
  }
}

//Storage container
resource blobServiceContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-09-01' = {
  name: '${trifactaStorageAccount.name}/default/${containerName}'
}

// Storage Blob Data Contributor role for trifacta registered app SP
resource storageAccountRoleName 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(uniqueString(trifactaStorageAccountName))
  scope: trifactaStorageAccount
  properties: {
    roleDefinitionId: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    principalId: servicePrincipalObjectId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault
resource keyVaultName_resource 'Microsoft.KeyVault/vaults@2021-10-01' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: servicePrincipalObjectId
        permissions: {
          keys: [
            'get'
            'list'
            'update'
            'create'
            'import'
            'delete'
            'recover'
            'backup'
            'restore'
          ]
          secrets: [
            'get'
            'list'
            'set'
            'delete'
            'recover'
            'backup'
            'restore'
          ]
          certificates: [
            'get'
            'list'
            'update'
            'create'
            'import'
            'delete'
            'recover'
            'backup'
            'restore'
            'managecontacts'
            'manageissuers'
            'getissuers'
            'listissuers'
            'setissuers'
            'deleteissuers'
          ]
        }
      }
    ]
    tenantId: subscription().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: [
        {
          id: '${virtualNetworkName_resource.id}/subnets/default'
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
  }
}

// Databricks Workspace
resource databricksWorkspace 'Microsoft.Databricks/workspaces@2018-04-01' = {
  name: databricksWorkspaceName
  location: location
  properties: {
    managedResourceGroupId: databricksMRGID
  }
}

output adminUsername string = adminUsername
output trifactaInstanceName string = virtualMachineName
output trifactaURL string = publicIpAddressName_resource.properties.dnsSettings.fqdn
output keyvaultURI string = keyVaultName_resource.properties.vaultUri
output directoryid string = keyVaultName_resource.properties.tenantId
output databricksURL string = databricksWorkspace.properties.workspaceUrl
output storagecontainer string = containerName
output storageaccount string = trifactaStorageAccountName
output vmid string = virtualMachine.identity.principalId
