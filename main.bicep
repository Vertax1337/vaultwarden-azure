targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the Vaultwarden Container App')
param appName string = 'vaultwarden'

@description('Public URL of your Vaultwarden instance. MUST include https:// (example: https://sub.domain.tld)')
param domainUrl string

@description('Container image to use for Vaultwarden (pin a version for reproducible deployments)')
param vaultwardenImage string = 'vaultwarden/server:1.33.2'

@description('CPU cores for the container')
param cpuCores string = '0.25'

@description('Memory in GiB for the container (CPU:RAM ratio must be 1:2)')
param memorySize string = '0.5'

@description('Allow insecure HTTP traffic (recommended: false for production)')
param allowInsecureHttp bool = false

// --------------------
// SMTP (Microsoft 365 defaults)
// --------------------
@description('SMTP host (M365 default: smtp.office365.com)')
param smtpHost string = 'smtp.office365.com'

@description('SMTP port (M365 default: 587)')
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

// --------------------
// PostgreSQL
// --------------------
@description('PostgreSQL admin username')
param dbAdminUser string = 'vaultwarden'

@description('PostgreSQL admin password (will be stored in Key Vault for later retrieval)')
@secure()
param dbPassword string

@description('PostgreSQL SKU name')
param postgresSkuName string = 'Standard_B1ms'

@description('PostgreSQL storage size in GB')
param postgresStorageGB int = 32

@description('Allow Azure services to access PostgreSQL (0.0.0.0 firewall rule). Recommended: false.')
param allowAzureServicesToPostgres bool = false

// --------------------
// Storage
// --------------------
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

// --------------------
// Derived names
// --------------------
var storageAccountName = toLower('${appName}files${uniqueString(resourceGroup().id)}')
var fileShareName = 'vaultwarden'

var postgresServerName = toLower('${appName}-pg-${uniqueString(resourceGroup().id)}')
var postgresDbName = 'vaultwarden'
var postgresFqdn = '${postgresServerName}.postgres.database.azure.com'
var postgresPort = '5432'

var logAnalyticsName = '${appName}-law'
var containerEnvName = '${appName}-env'

// Key Vault (for ADMIN_TOKEN + DB password persistence)
var keyVaultName = toLower('vwkv${uniqueString(resourceGroup().id)}')
var kvSecretAdminTokenName = 'vw-admin-token'
var kvSecretDbPasswordName = 'vw-db-password'

// Role definition IDs (built-in)
var roleKeyVaultSecretsOfficer = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
var roleKeyVaultSecretsUser    = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

// --------------------
// Log Analytics
// --------------------
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    retentionInDays: 30
  }
}

// --------------------
// Storage Account + Azure Files share
// --------------------
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
    supportsHttpsTrafficOnly: true
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

// --------------------
// Key Vault (RBAC authorization)
// --------------------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    publicNetworkAccess: 'Enabled'
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
  }
}

// --------------------
// Identities (one for the app, one for the secret-writer script)
// --------------------
resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${appName}-id'
  location: location
}

resource secretWriterIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${appName}-kv-writer-id'
  location: location
}

// RBAC: writer can set secrets
resource kvSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, secretWriterIdentity.id, roleKeyVaultSecretsOfficer)
  scope: keyVault
  properties: {
    roleDefinitionId: roleKeyVaultSecretsOfficer
    principalId: secretWriterIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC: app can read secrets
resource kvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, appIdentity.id, roleKeyVaultSecretsUser)
  scope: keyVault
  properties: {
    roleDefinitionId: roleKeyVaultSecretsUser
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// --------------------
// Deployment Script: ensure ADMIN_TOKEN + DB password exist in Key Vault
// - ADMIN_TOKEN is generated if missing
// - DB password is stored (from secure param) if missing
// --------------------
resource ensureKvSecrets 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${appName}-ensure-kv-secrets'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${secretWriterIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.60.0'
    timeout: 'PT30M'
    retentionInterval: 'P1D'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      {
        name: 'KEYVAULT_NAME'
        value: keyVaultName
      }
      {
        name: 'ADMIN_TOKEN_SECRET'
        value: kvSecretAdminTokenName
      }
      {
        name: 'DB_PASSWORD_SECRET'
        value: kvSecretDbPasswordName
      }
    ]
    // secure env var, so password is not exposed in script logs
    secureEnvironmentVariables: [
      {
        name: 'DB_PASSWORD_VALUE'
        secureValue: dbPassword
      }
    ]
    scriptContent: '''
set -euo pipefail

echo "Ensuring Key Vault secrets exist in $KEYVAULT_NAME ..."

# ADMIN_TOKEN: generate if missing
if az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$ADMIN_TOKEN_SECRET" 1>/dev/null 2>/dev/null; then
  echo "ADMIN_TOKEN secret already exists."
else
  echo "Creating ADMIN_TOKEN secret..."
  ADMIN_TOKEN=$(python3 - << 'PY'
import secrets, base64
print(base64.urlsafe_b64encode(secrets.token_bytes(48)).decode('utf-8').rstrip('='))
PY
)
  az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$ADMIN_TOKEN_SECRET" --value "$ADMIN_TOKEN" 1>/dev/null
  echo "ADMIN_TOKEN secret created."
fi

# DB password: store if missing
if az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$DB_PASSWORD_SECRET" 1>/dev/null 2>/dev/null; then
  echo "DB password secret already exists."
else
  echo "Creating DB password secret..."
  az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$DB_PASSWORD_SECRET" --value "$DB_PASSWORD_VALUE" 1>/dev/null
  echo "DB password secret created."
fi

echo "Done."
'''
  }
  dependsOn: [
    keyVault
    kvSecretsOfficer
  ]
}

// --------------------
// PostgreSQL Flexible Server (uses secure param dbPassword)
// --------------------
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

resource postgresFirewallAllowAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-03-01-preview' = if (allowAzureServicesToPostgres) {
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

// --------------------
// Container Apps Environment
// --------------------
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

// Link Azure Files to Container Apps environment
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

// --------------------
// Vaultwarden Container App
// - ADMIN_TOKEN comes from Key Vault via managed identity
// - DB password comes from Key Vault via managed identity
// - No DATABASE_URL concatenation (linter clean)
// - DOMAIN is passed as full https URL
// - Full M365 SMTP env vars
// --------------------
resource vaultwardenApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: allowInsecureHttp
      }
      secrets: [
        // Key Vault references (requires app identity + Key Vault RBAC)
        {
          name: 'admin-token'
          keyVaultUrl: 'https://${keyVaultName}.${environment().suffixes.keyvaultDns}/secrets/${kvSecretAdminTokenName}'
          identity: appIdentity.id
        }
        {
          name: 'db-password'
          keyVaultUrl: 'https://${keyVaultName}.${environment().suffixes.keyvaultDns}/secrets/${kvSecretDbPasswordName}'
          identity: appIdentity.id
        }
        // SMTP password remains a direct secret from secure param
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
            // Admin UI
            {
              name: 'ADMIN_TOKEN'
              secretRef: 'admin-token'
            }

            // DB (split env vars, no URL)
            {
              name: 'DATABASE_HOST'
              value: postgresFqdn
            }
            {
              name: 'DATABASE_PORT'
              value: postgresPort
            }
            {
              name: 'DATABASE_NAME'
              value: postgresDbName
            }
            {
              name: 'DATABASE_USERNAME'
              value: dbAdminUser
            }
            {
              name: 'DATABASE_PASSWORD'
              secretRef: 'db-password'
            }
            {
              name: 'DATABASE_SSLMODE'
              value: 'require'
            }

            // Required by you: must be full https URL
            {
              name: 'DOMAIN'
              value: domainUrl
            }

            // SMTP
            {
              name: 'SMTP_HOST'
              value: smtpHost
            }
            {
              name: 'SMTP_PORT'
              value: smtpPort
            }
            {
              name: 'SMTP_SECURITY'
              value: smtpSecurity
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
  dependsOn: [
    ensureKvSecrets
    kvSecretsUser
    postgresDb
  ]
}

output containerAppFqdn string = vaultwardenApp.properties.configuration.ingress.fqdn
output keyVaultName string = keyVault.name
