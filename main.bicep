targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the Vaultwarden Container App')
param appName string = 'vaultwarden'

@description('Public URL of your Vaultwarden instance (used for email links etc.). Example: https://vault.example.tld')
param domain string

@description('Container image to use for Vaultwarden')
param vaultwardenImage string = 'vaultwarden/server:latest'

@description('CPU cores for the container')
param cpuCores string = '0.25'

@description('Memory in GiB for the container (CPU:RAM ratio must be 1:2)')
param memorySize string = '0.5'

@description('Allow insecure HTTP traffic (disable for production)')
param allowInsecureHttp bool = true

@description('SMTP FROM address (e.g. vaultwarden@domain.tld)')
param smtpFrom string

@description('SMTP username')
param smtpUsername string

@description('SMTP password')
@secure()
param smtpPassword string

@description('PostgreSQL admin username')
param dbAdminUser string = 'vaultwarden'

@description('PostgreSQL admin password (avoid URL-breaking characters)')
@secure()
param dbPassword string

@description('PostgreSQL SKU name')
param postgresSkuName string = 'Standard_B1ms'

@description('PostgreSQL storage size in GB')
param postgresStorageGB int = 32

@description('Storage account SKU for Azure Files')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_GZRS'
  'Standard_RAGZRS'
])
param storageAccountSku string = 'Standard_LRS'

var storageAccountName = toLower('${appName}files${uniqueString(resourceGroup().id)}')
var fileShareName = 'vaultwarden'
var postgresServerName = toLower('${appName}-pg-${uniqueString(resourceGroup().id)}')
var postgresDbName = 'vaultwarden'
var logAnalyticsName = '${appName}-law'
var containerEnvName = '${appName}-env'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    retentionInDays: 30
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: fileService
  name: fileShareName
  properties: {
    accessTier: 'Hot'
  }
}


resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' = {
  name: postgresServerName
  location: location
  sku: {
    name: postgresSkuName
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: dbAdminUser
    administratorLoginPassword: dbPassword
    version: '15'
    storage: {
      storageSizeGB: postgresStorageGB
    }
    authConfig: {
      passwordAuth: 'Enabled'
      activeDirectoryAuth: 'Disabled'
    }    
    backup: {
      backupRetentionDays: 7
    }
  }
}

resource postgresFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-03-01-preview' = {
  parent: postgresServer
  name: 'AllowAzure'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource postgresDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-03-01-preview' = {
  parent: postgresServer
  name: postgresDbName
}

resource containerEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource containerEnvStorage 'Microsoft.App/managedEnvironments/storages@2024-03-01' = {
  parent: containerEnv
  name: 'vaultwarden-storage'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      shareName: fileShareName
      accountKey: storageAccount.listKeys().keys[0].value
      accessMode: 'ReadWrite'
    }
  }
}

var databaseUrl = 'postgresql://${dbAdminUser}:${dbPassword}@${postgresServer.name}.postgres.database.azure.com:5432/${postgresDbName}?sslmode=require'

resource vaultwardenApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: allowInsecureHttp
      }
      secrets: [
        {
          name: 'db-url'
          value: databaseUrl
        }
        {
          name: 'smtp-password'
          value: smtpPassword
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'vaultwarden'
          image: vaultwardenImage
          resources: {
            cpu: json(cpuCores)
            memory: '${memorySize}Gi'
          }
          env: [
            {
              name: 'DATABASE_URL'
              secretRef: 'db-url'
            }
            {
              name: 'DOMAIN'
              value: domain
            }
            {
              name: 'SMTP_FROM'
              value: smtpFrom
            }
            {
              name: 'SMTP_USERNAME'
              value: smtpUsername
            }
            {
              name: 'SMTP_PASSWORD'
              secretRef: 'smtp-password'
            }
          ]
          volumeMounts: [
            {
              volumeName: 'data'
              mountPath: '/data'
            }
          ]
        }
      ]
      volumes: [
        {
          name: 'data'
          storageType: 'AzureFile'
          storageName: containerEnvStorage.name
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}
