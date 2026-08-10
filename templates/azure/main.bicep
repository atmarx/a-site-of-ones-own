targetScope = 'resourceGroup'

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Short lowercase prefix used in Azure resource names.')
@minLength(2)
@maxLength(20)
param namePrefix string = 'rwh'

@description('Deployment environment name.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'prod'

@description('Non-root sudo user created on the VM.')
@minLength(3)
@maxLength(32)
param adminUsername string = 'webadmin'

@description('OpenSSH public key text. Private keys must never be supplied.')
@secure()
param sshPublicKey string

@description('Public IPv4 CIDRs allowed to access SSH and Virtualmin/Webmin. The deployment wrapper rejects 0.0.0.0/0.')
@minLength(1)
param adminSourceCidrs array

@description('Operational owner included in resource tags.')
param owner string = 'Research Web Hosting'

@description('Data classification included in resource tags.')
param dataClassification string = 'Public'

@description('Azure VM size.')
param vmSize string = 'Standard_D2as_v7'

@description('OS disk size in GiB.')
@minValue(32)
param osDiskSizeGB int = 32

@description('OS managed disk SKU.')
@allowed([
  'StandardSSD_LRS'
  'Premium_LRS'
])
param osDiskSku string = 'StandardSSD_LRS'

@description('Data disk size in GiB. Existing managed disks can grow but cannot shrink.')
@minValue(64)
param dataDiskSizeGB int = 64

@description('Data managed disk SKU.')
@allowed([
  'StandardSSD_LRS'
  'Premium_LRS'
])
param dataDiskSku string = 'StandardSSD_LRS'

@description('VNet address prefix.')
param vnetAddressPrefix string = '10.44.0.0/16'

@description('Web-host subnet address prefix.')
param subnetAddressPrefix string = '10.44.1.0/24'

@description('Create CanNotDelete locks on the public IP, data disk, and backup storage account.')
param enableDeletionLocks bool = true

@description('Additional Azure resource tags. Required service tags override duplicate keys.')
param tags object = {}

var rockyCommunityGalleryName = 'rocky-dc1c6aa6-905b-4d9c-9577-63ccc28c482a'
var rockyImageDefinitionName = 'RESF-Rocky-10-x86_64-LVM'
var rockyImageVersion = '10.2.20260525'
var rockyImageVersionId = '/CommunityGalleries/${rockyCommunityGalleryName}/Images/${rockyImageDefinitionName}/Versions/${rockyImageVersion}'
var restrictedAdminSourceCidrs = filter(adminSourceCidrs, cidr => cidr != '0.0.0.0/0')

var compactPrefix = toLower(replace('${namePrefix}${environment}', '-', ''))
var uniqueSuffix = uniqueString(subscription().id, resourceGroup().id)
var publicDnsLabel = take(toLower('${namePrefix}-${environment}-${uniqueSuffix}'), 63)
var vmName = take('${namePrefix}-${environment}-01', 64)
var networkSecurityGroupName = '${namePrefix}-${environment}-nsg'
var virtualNetworkName = '${namePrefix}-${environment}-vnet'
var subnetName = 'webhost'
var publicIpName = '${namePrefix}-${environment}-pip'
var nicName = '${namePrefix}-${environment}-nic'
var dataDiskName = '${namePrefix}-${environment}-data-01'
var backupStorageAccountName = take('${compactPrefix}${uniqueSuffix}', 24)
var backupContainerName = 'virtualmin-backups'

var requiredTags = {
  Application: 'Research Web Hosting'
  Environment: environment
  ManagedBy: 'Bicep'
  Owner: owner
  DataClassification: dataClassification
}
var resourceTags = union(tags, requiredTags)

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: networkSecurityGroupName
  location: location
  tags: resourceTags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-Internet'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-HTTPS-Internet'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SSH-Administrators'
        properties: {
          priority: 200
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefixes: restrictedAdminSourceCidrs
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-Webmin-Administrators'
        properties: {
          priority: 210
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '10000'
          sourceAddressPrefixes: restrictedAdminSourceCidrs
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Deny-VNet-Inbound'
        properties: {
          priority: 3000
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Deny-SMTP25-Internet'
        properties: {
          priority: 100
          access: 'Deny'
          direction: 'Outbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '25'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
        }
      }
      {
        name: 'Deny-Private-Networks-Outbound'
        properties: {
          priority: 110
          access: 'Deny'
          direction: 'Outbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefixes: [
            '10.0.0.0/8'
            '172.16.0.0/12'
            '192.168.0.0/16'
          ]
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: virtualNetworkName
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
              locations: [
                '*'
              ]
            }
          ]
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

var subnetResourceId = resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, subnetName)

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 15
    dnsSettings: {
      domainNameLabel: publicDnsLabel
    }
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  tags: resourceTags
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: subnetResourceId
          }
          publicIPAddress: {
            id: publicIp.id
          }
          primary: true
        }
      }
    ]
  }
}

resource dataDisk 'Microsoft.Compute/disks@2024-03-02' = {
  name: dataDiskName
  location: location
  tags: union(resourceTags, {
    DataRole: 'Websites and MariaDB'
  })
  sku: {
    name: dataDiskSku
  }
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: dataDiskSizeGB
    networkAccessPolicy: 'DenyAll'
    publicNetworkAccess: 'Disabled'
  }
}

resource backupStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: backupStorageAccountName
  location: location
  tags: union(resourceTags, {
    DataRole: 'Off-host Virtualmin backups'
  })
  sku: {
    name: 'Standard_GRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    dnsEndpointType: 'Standard'
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          action: 'Allow'
          id: subnetResourceId
        }
      ]
      ipRules: []
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: backupStorageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: true
      retentionInDays: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 30
      allowPermanentDelete: false
    }
    isVersioningEnabled: true
  }
}

resource backupContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: backupContainerName
  properties: {
    publicAccess: 'None'
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: true
  }
}

resource backupLifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: backupStorageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          enabled: true
          name: 'expire-old-virtualmin-backups'
          type: 'Lifecycle'
          definition: {
            actions: {
              baseBlob: {
                delete: {
                  daysAfterModificationGreaterThan: 400
                }
              }
              version: {
                delete: {
                  daysAfterCreationGreaterThan: 30
                }
              }
            }
            filters: {
              blobTypes: [
                'blockBlob'
              ]
              prefixMatch: [
                '${backupContainerName}/'
              ]
            }
          }
        }
      ]
    }
  }
}

var growScriptBase64 = base64(loadTextContent('bootstrap/grow-data-disk.sh'))
var backupScriptBase64 = base64(loadTextContent('bootstrap/virtualmin-backup.sh'))
var bootstrapSource = loadTextContent('bootstrap/virtualmin-bootstrap.sh')
var bootstrapWithHost = replace(bootstrapSource, '__HOST_FQDN__', publicIp.properties.dnsSettings.fqdn)
var bootstrapWithAdmin = replace(bootstrapWithHost, '__ADMIN_USERNAME__', adminUsername)
var bootstrapWithStorage = replace(bootstrapWithAdmin, '__BACKUP_STORAGE_ACCOUNT__', backupStorageAccount.name)
var bootstrapWithContainer = replace(bootstrapWithStorage, '__BACKUP_CONTAINER__', backupContainer.name)
var bootstrapWithCidrs = replace(bootstrapWithContainer, '__ADMIN_SOURCE_CIDRS__', join(restrictedAdminSourceCidrs, ','))
var bootstrapWithGrowScript = replace(bootstrapWithCidrs, '__GROW_SCRIPT_BASE64__', growScriptBase64)
var bootstrapScript = replace(bootstrapWithGrowScript, '__BACKUP_SCRIPT_BASE64__', backupScriptBase64)

resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: vmName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    storageProfile: {
      diskControllerType: 'NVMe'
      imageReference: {
        communityGalleryImageId: rockyImageVersionId
      }
      osDisk: {
        name: '${vmName}-os'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
        diskSizeGB: osDiskSizeGB
        managedDisk: {
          storageAccountType: osDiskSku
        }
      }
      dataDisks: [
        {
          name: dataDisk.name
          lun: 0
          createOption: 'Attach'
          caching: 'None'
          deleteOption: 'Detach'
          diskSizeGB: dataDiskSizeGB
          managedDisk: {
            id: dataDisk.id
            storageAccountType: dataDiskSku
          }
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: base64(bootstrapScript)
      allowExtensionOperations: true
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'AutomaticByPlatform'
        }
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
          properties: {
            primary: true
            deleteOption: 'Detach'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

var storageBlobDataContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
)

resource backupRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(backupContainer.id, virtualMachine.id, storageBlobDataContributorRoleId)
  scope: backupContainer
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: virtualMachine.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource publicIpLock 'Microsoft.Authorization/locks@2020-05-01' = if (enableDeletionLocks) {
  name: 'protect-public-ip'
  scope: publicIp
  properties: {
    level: 'CanNotDelete'
    notes: 'Customer DNS records depend on this static public IP.'
  }
}

resource dataDiskLock 'Microsoft.Authorization/locks@2020-05-01' = if (enableDeletionLocks) {
  name: 'protect-web-data'
  scope: dataDisk
  properties: {
    level: 'CanNotDelete'
    notes: 'This disk contains website files and MariaDB data.'
  }
}

resource backupStorageLock 'Microsoft.Authorization/locks@2020-05-01' = if (enableDeletionLocks) {
  name: 'protect-backups'
  scope: backupStorageAccount
  properties: {
    level: 'CanNotDelete'
    notes: 'This storage account contains off-host Virtualmin backups.'
  }
}

output publicIpAddress string = publicIp.properties.ipAddress
output hostFqdn string = publicIp.properties.dnsSettings.fqdn
output sshCommand string = 'ssh ${adminUsername}@${publicIp.properties.dnsSettings.fqdn}'
output virtualminUrl string = 'https://${publicIp.properties.dnsSettings.fqdn}:10000/'
output vmName string = virtualMachine.name
output vmResourceId string = virtualMachine.id
output dataDiskResourceId string = dataDisk.id
output backupContainerUri string = 'https://${backupStorageAccount.name}.blob.${az.environment().suffixes.storage}/${backupContainer.name}'
output bootstrapStatusCommand string = 'az vm run-command invoke -g ${resourceGroup().name} -n ${virtualMachine.name} --command-id RunShellScript --scripts "systemctl is-active virtualmin-bootstrap.service; test -f /var/lib/research-web-hosting/bootstrap-complete"'
