@description('Storage Account SKU for Azure Files. IMPORTANT: This template creates an Azure File Share. Use Standard_* SKUs for StorageV2 to avoid "File is not supported for the account".')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_GZRS'
  'Standard_RAGZRS'
])
param storageAccountSKU string = 'Standard_LRS'

@description('Vaultwarden container image. Pin a version for reproducible deployments (recommended).')
param vaultwardenImage string = 'docker.io/vaultwarden/server:1.33.2'

@description('Vaultwarden Admin API key used to access /admin page - minLength is 20')
@minLength(20)
@secure()
param AdminAPIKEY string = base64(newGuid())

@description('Container size preset in the format "<cpu>/<memoryGiB>". This enforces valid CPU:Memory pairs.')
@allowed([
  '0.25/0.5'
  '0.5/1'
  '0.75/1.5'
  '1/2'
  '1.25/2.5'
  '1.5/3'
  '1.75/3.5'
  '2/4'
])
param containerSku string = '0.25/0.5'

@description('Allow insecure HTTP. Recommended: false for production. Use HTTPS + custom domain + managed cert.')
param allowInsecureHttp bool = false

@description('Public URL of your Vaultwarden instance (used for email links, attachments, etc.). Example: https://vault.example.tld')
param domain string

@description('SMTP host (Microsoft 365 default: smtp.office365.com)')
param smtpHost string = 'smtp.office365.com'

@description('SMTP port (Microsoft 365 default: 587)')
param smtpPort string = '587'

@description('SMTP security (starttls / force_tls / off)')
@allowed([
  'starttls'
  'force_tls'
  'off'
])
param smtpSecurity string = 'starttls'

@description('SMTP FROM address (e.g. vaultwarden@domain.tld)')
param smtpFrom string

@description('SMTP username (often same as smtpFrom)')
param smtpUsername string

@description('SMTP password')
@secure()
param smtpPassword string

@description('Allow new signups (recommended: false for production)')
param signupsAllowed bool = false

@description('Require email verification for signups')
param signupsVerify bool = true

@description('Comma-separated domain whitelist for signups (empty = no restriction)')
param signupsDomainsWhitelist string = ''

@description('Show premium features in UI (Bitwarden-compatible clients)')
param showPremium bool = true

@description('Allow Azure services to access PostgreSQL via firewall rule 0.0.0.0 (public networking convenience). Recommended: false.')
param allowAzureServicesToPostgres bool = false

@description('Optional: allowlist a specific public IP range for PostgreSQL. Leave empty to skip.')
param postgresFirewallStartIp string = ''

@description('Optional: allowlist a specific public IP range for PostgreSQL. Leave empty to skip.')
param postgresFirewallEndIp string = ''

@description('PostgreSQL admin password.
IMPORTANT: Avoid URL-breaking characters like @ : / ? & % # if you use DATABASE_URL in the classic user:pass@host form (no URL-encoding in Bicep).')
@secure()
param dbPassword string

// --------------------
// Names / Derived values
// --------------------
var location = resourceGroup().location
var logWorkspaceName = 'vw-logwks${uniqueString(resourceGroup().id)}'
var storageAccountName = 'vwstorage${uniqueString(resourceGroup().id)}'
var envName = 'appenv-vaultwarden${uniqueString(resourceGroup().id)}'
var pgServerName = 'vwdbi-${uniqueString(resourceGroup().id)}'
var pgDbName = 'vaultwarden'

var skuParts = split(containerSku, '/')
var cpuCore = skuParts[0]
var memorySize = skuParts[1]

// --------------------
// Storage Account + Azure Files
// --------------------
resource storageaccount 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: storageAccountSKU
  }
  properties: {
    accessTier: 'Hot'
    allowSharedKeyAccess: true
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }

  resource fileservice 'fileServices@2025-06-01' = {
    name: 'default'
    resource vwardendata 'shares@2025-06-01' = {
      name: 'vw-data'
      properties: {
        accessTier: 'Hot'
      }
    }
  }
}

// --------------------
// Log Analytics
// --------------------
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: logWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// --------------------
// Container Apps Environment
// --------------------
resource containerAppEnv 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: envName
  location: location
  sku: {
    name: 'Consumption'
  }
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

// Link Azure File Share to Container Apps environment
resource storageLink 'Microsoft.App/managedEnvironments/storages@2025-07-01' = {
  name: 'vw-data-link'
  parent: containerAppEnv
  properties: {
    azureFile: {
      accessMode: 'ReadWrite'
      accountName: storageaccount.name
      shareName: 'vw-data'
      accountKey: storageaccount.listKeys().keys[0].value
    }
  }
}

// --------------------
// PostgreSQL Flexible Server
// --------------------
resource vwDBi 'Microsoft.DBforPostgreSQL/flexibleServers@2025-08-01' = {
  name: pgServerName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: 'vwadmin'
    administratorLoginPassword: dbPassword
    version: '14'
    storage: {
      storageSizeGB: 32
    }
    authConfig: {
      passwordAuth: 'Enabled'
      activeDirectoryAuth: 'Disabled'
    }
  }
}

// Firewall: Allow Azure services (0.0.0.0) if desired (NOT recommended by default)
resource postgresAllowAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2025-08-01' = if (allowAzureServicesToPostgres) {
  name: 'AllowAzureServices'
  parent: vwDBi
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Firewall: optional custom range
resource postgresAllowCustomRange 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2025-08-01' = if (!empty(postgresFirewallStartIp) && !empty(postgresFirewallEndIp)) {
  name: 'AllowCustomRange'
  parent: vwDBi
  properties: {
    startIpAddress: postgresFirewallStartIp
    endIpAddress: postgresFirewallEndIp
  }
}

// Create DB
resource vwDB 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2025-08-01' = {
  name: pgDbName
  parent: vwDBi
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// Correct DATABASE_URL (port + sslmode required for Azure Postgres)
var databaseUrl = 'postgresql://vwadmin:${dbPassword}@${vwDBi.properties.fullyQualifiedDomainName}:5432/${pgDbName}?sslmode=require'

// --------------------
// Container App (Vaultwarden)
// --------------------
resource vwardenApp 'Microsoft.App/containerApps@2025-07-01' = {
  name: 'vaultwarden'
  location: location
  properties: {
    environmentId: containerAppEnv.id
    configuration: {
      secrets: [
        {
          name: 'admin-token'
          value: AdminAPIKEY
        }
        {
          name: 'database-url'
          value: databaseUrl
        }
        {
          name: 'smtp-password'
          value: smtpPassword
        }
      ]
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: allowInsecureHttp
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: 'vaultwarden'
          image: vaultwardenImage
          resources: {
            cpu: json(cpuCore)
            memory: '${memorySize}Gi'
          }
          volumeMounts: [
            {
              volumeName: 'vwdatashare'
              mountPath: '/data'
            }
          ]
          env: [
            { name: 'ADMIN_TOKEN' secretRef: 'admin-token' }
            { name: 'DATABASE_URL' secretRef: 'database-url' }
            { name: 'DOMAIN' value: domain }

            { name: 'SMTP_HOST' value: smtpHost }
            { name: 'SMTP_PORT' value: smtpPort }
            { name: 'SMTP_SECURITY' value: smtpSecurity }
            { name: 'SMTP_FROM' value: smtpFrom }
            { name: 'SMTP_USERNAME' value: smtpUsername }
            { name: 'SMTP_PASSWORD' secretRef: 'smtp-password' }

            { name: 'SIGNUPS_ALLOWED' value: toLower(string(signupsAllowed)) }
            { name: 'SIGNUPS_VERIFY' value: toLower(string(signupsVerify)) }
            { name: 'SIGNUPS_DOMAINS_WHITELIST' value: signupsDomainsWhitelist }
            { name: 'SHOW_PREMIUM' value: toLower(string(showPremium)) }
          ]
        }
      ]
      volumes: [
        {
          name: 'vwdatashare'
          storageName: storageLink.name
          storageType: 'AzureFile'
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 4
      }
    }
  }
}

output containerAppFqdn string = vwardenApp.properties.configuration.ingress.fqdn
output postgresFqdn string = vwDBi.properties.fullyQualifiedDomainName
