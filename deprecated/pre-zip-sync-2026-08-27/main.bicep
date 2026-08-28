@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Kosten/Zuordnung: Umgebung (prod/test/dev)')
@allowed([
  'prod'
  'test'
  'dev'
])
param environment string = 'prod'

@description('Deployment mode for edge hardening. none = Azure-only/basic, cloudflare-managed = production path with post-deploy Cloudflare automation.')
@allowed([
  'none'
  'cloudflare-managed'
])
param edgeMode string = 'none'

@description('If true, apply ACA ingress IP restrictions using ingressAllowedCidrs. Intended for the Cloudflare-managed production path.')
param enableIngressIpRestrictions bool = false

@description('Allowed CIDR ranges for ACA ingress when enableIngressIpRestrictions=true. Example: Cloudflare edge IP ranges.')
param ingressAllowedCidrs array = []

@description('Optional customer-facing hostname (for example vault.example.com). Used by the production wrapper/documentation. The ARM deployment itself does not bind the hostname.')
param customHostname string = ''

@description('Traceability: BSSE Deploy-Ref (z.B. Git Tag oder Commit SHA)')
param bsseRef string = ''

@description('Name of the Vaultwarden Container App')
@maxLength(10)
param appName string = 'vault'

@description('Container image to use for Vaultwarden (pin a version for reproducible deployments)')
param vaultwardenImage string = 'vaultwarden/server:1.35.3-alpine'

@description('CPU cores for the container')
param cpuCores string = '0.25'

@description('Memory in GiB for the container (CPU:RAM ratio must be 1:2)')
param memorySize string = '0.5'

@description('Allow insecure HTTP traffic (recommended: false for production)')
param allowInsecureHttp bool = false

@description('Enable Azure Monitor diagnostic settings for Key Vault and PostgreSQL Flexible Server (Log Analytics).')
param diagnosticsEnabled bool = true

@description('Optional forceUpdateTag for the bootstrap deploymentScript. Change this value to force a controlled rerun without changing app settings.')
param deploymentScriptForceUpdateTag string = ''

@description('Public URL of your Vaultwarden instance. MUST include https:// (example: https://sub.domain.tld)')
@minLength(9)
param domainUrl string

@description('Vaultwarden ADMIN_TOKEN als App-ENV setzen. Default true fuer Erstdeployment/Bootstrap/Tests. Fuer den produktiven Steady State nach erfolgreichem Setup auf false setzen, damit ADMIN_TOKEN nicht mehr an die App durchgereicht wird. Achtung: Falls admin_token bereits in /data/config.json persistiert wurde, dort ebenfalls entfernen, sonst bleibt das Admin-Panel aktiv.')
param adminPanelEnabled bool = true

@description('Vaultwarden ENV: INVITATION_ORG_NAME. Organization name shown in invitation mails.')
param invitationOrgName string = 'Vaultwarden'

@description('Vaultwarden ENV: SIGNUPS_DOMAINS_WHITELIST. Comma-separated email domains allowed to self-register.')
param signupsDomainsWhitelist string = ''

@description('Vaultwarden ENV: ORG_CREATION_USERS. Optional comma-separated user emails allowed to create organizations. Empty = all users.')
param orgCreationUsers string = ''

@description('Explizite Root-Domain für Mailrouting und Default-Absender (z. B. example.com). Wird verwendet für: ACS Foundation (als Standard-Domain wenn acsDomainName leer) und den automatischen Default-Absender wenn smtpFrom leer bleibt. Für Direct Send muss smtpHost immer explizit gesetzt werden (kein automatischer MX-Lookup). Keine Ableitung aus domainUrl.')
param mailRootDomain string = ''

@description('Wenn true, nutzt Vaultwarden SMTP Submission mit Auth (empfohlener Produktiv-Default). Wenn false, wird Direct Send ohne Auth verwendet – smtpHost muss dann explizit angegeben werden. Wichtig für Vaultwarden: In diesem Modus werden SMTP_USERNAME, SMTP_PASSWORD und SMTP_AUTH_MECHANISM nicht an die App durchgereicht; bereits im Vaultwarden-Adminbereich gespeicherte SMTP-Auth-Werte in /data/config.json müssen bei einem Moduswechsel ggf. separat bereinigt werden.')
param smtpUseAuth bool = true

@description('SMTP FROM address (z. B. vaultwarden@domain.tld). Für Produktion explizit setzen.')
param smtpFrom string = ''

@description('Anzeigename im From-Header.')
param smtpFromName string = 'Vaultwarden'

@description('Vaultwarden ENV: HELO_NAME. Empty = derive host name from DOMAIN / domainUrl.')
param heloName string = ''

@description('SMTP-Host. SMTP Auth: smtp.office365.com (Default wenn leer). Direct Send: Pflichtfeld – MX-Endpunkt der Mail-Domain (z.B. mx01.example-com.mail.protection.outlook.com). MX-Lookup zur Laufzeit wird nicht mehr unterstützt; der Wert muss vor dem Deployment bekannt sein.')
param smtpHost string = ''

@description('SMTP port (M365 default: 587)')
param smtpPort string = '587'

@description('SMTP security (starttls / force_tls / off)')
@allowed([
  'starttls'
  'force_tls'
  'off'
])
param smtpSecurity string = 'starttls'

@description('SMTP username (often same as smtpFrom)')
param smtpUsername string = ''

@description('SMTP password')
@secure()
param smtpPassword string = ''

@description('Optional (nur SMTP Auth): SMTP Auth Mechanism. Mögliche Werte u.a.: Plain, Login, Xoauth2 (auch kommasepariert).')
@allowed([
  ''
  'Plain'
  'Login'
  'Xoauth2'
  'Plain,Login'
  'Login,Plain'
])
param smtpAuthMechanism string = ''

@description('Mail-Modus: direct_send (kein Auth, MX-Endpunkt direkt), smtp_auth (klassisches SMTP Relay mit Auth), acs_smtp (Azure Communication Services SMTP). Wird als Source of Truth durch alle Schichten propagiert.')
@allowed([
  'direct_send'
  'smtp_auth'
  'acs_smtp'
])
param mailMode string = 'smtp_auth'

@description('Enable Vaultwarden SSO (OIDC) for Web Vault login (requires Vaultwarden >= 1.35).')
param ssoEnabled bool = false

@description('If true, only SSO login is allowed (no email/password). Use with care.')
param ssoOnly bool = false

@description('OIDC authority/issuer base URL. For Entra ID use https://login.microsoftonline.com/<TENANT_ID>/v2.0 and do not append /.well-known/openid-configuration.')
param ssoAuthority string = ''

@description('OIDC Client ID / Application (client) ID.')
param ssoClientId string = ''

@description('OIDC Client Secret / App secret value.')
@secure()
param ssoClientSecret string = ''

@description('OIDC scopes passed to Vaultwarden. For Entra ID the default openid profile email offline_access User.Read is recommended.')
param ssoScopes string = 'openid profile email offline_access User.Read'

@description('Enable mobile push notifications (requires Bitwarden push relay credentials).')
param pushEnabled bool = false

@description('Bitwarden push installation id (from https://bitwarden.com/host/). Treated as secret and stored in Key Vault.')
@secure()
param pushInstallationId string = ''

@description('Bitwarden push installation key (from https://bitwarden.com/host/). Treated as secret and stored in Key Vault.')
@secure()
param pushInstallationKey string = ''

@description('Use Bitwarden EU push relay / identity endpoints. Select this only when the Installation ID / Key were requested for the EU region.')
param pushUseEuServers bool = false

@description('Optional: deploy Azure Communication Services foundation resources (Email Service, Email Domain resource, Communication Service) together with the core stack. Domain verification, domain linking and SMTP username activation remain manual post-deploy steps.')
param acsDeployFoundation bool = false

@description('ACS data location for Email Service and Communication Service, e.g. Germany, Europe or UnitedStates. Email Service and Communication Service must use the same geography.')
param acsDataLocation string = 'Germany'

@description('Custom domain to prepare in ACS Email, e.g. example.com. Leer = verwende mailRootDomain. Es gibt keine automatische Ableitung mehr aus domainUrl.')
param acsDomainName string = ''

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

@description('Enable Azure Backup for the Azure File Share used by Vaultwarden (/data).')
param azureFilesBackupEnabled bool = true

@description('Time of day (HH:MM) when backup should run. MM must be 00 or 30.')
param azureFilesBackupScheduleRunTime string = '05:30'

@description('Windows timezone name for the backup schedule, e.g. UTC, W. Europe Standard Time.')
param azureFilesBackupTimeZone string = 'UTC'

@description('Number of days to retain daily Azure Files backups.')
param azureFilesBackupDailyRetentionDays int = 30

@description('Days of week used for weekly retention points.')
param azureFilesBackupWeeklyDaysOfWeek array = [
  'Sunday'
  'Tuesday'
  'Thursday'
]

@description('Number of weeks to retain weekly Azure Files backups.')
param azureFilesBackupWeeklyRetentionWeeks int = 12

@description('PostgreSQL SKU name')
param postgresSkuName string = 'Standard_B1ms'

@description('PostgreSQL major version. New deployments should use the latest supported version. Existing servers cannot be downgraded.')
@allowed([
  '15'
  '16'
  '17'
])
param postgresVersion string = '16'

@description('PostgreSQL storage size in GB')
param postgresStorageGB int = 32

@description('Point-in-time restore retention in Tagen für PostgreSQL Flexible Server.')
@minValue(7)
@maxValue(35)
param postgresBackupRetentionDays int = 14

@description('Allow Azure services to access PostgreSQL (0.0.0.0 firewall rule). Must be true for Container Apps without VNet/NAT (standard path). The firewall rule is always deployed.')
param allowAzureServicesToPostgres bool = true

@description('Azure PostgreSQL Flexible Server administrator login. Required for server creation and initial bootstrap only; not used by the Vaultwarden app itself.')
param dbAdminUser string = 'vaultwarden'

@description('Azure PostgreSQL Flexible Server administrator password. Required for server creation and initial bootstrap only; not stored in Key Vault and not used as Vaultwarden app credential.')
@secure()
param dbPassword string = concat(toUpper(newGuid()), newGuid())

@description('HIBP (Have I Been Pwned) API key. Stored in Key Vault. Leave empty to use placeholder \'00000-00000-00000\'.')
@secure()
param hibpApiKey string = ''

var templateLinkUri = (contains(deployment().properties, 'templateLink')
  ? (contains(deployment().properties.templateLink, 'uri') ? deployment().properties.templateLink.uri : '')
  : '')
var templateLinkRefRaw = (contains(templateLinkUri, 'raw.githubusercontent.com')
  ? split(templateLinkUri, '/')[5]
  : templateLinkUri)
var bsseRefRaw = (empty(bsseRef) ? (empty(templateLinkRefRaw) ? 'local' : templateLinkRefRaw) : bsseRef)
var bsseRefEffective = (empty(bsseRefRaw) ? '' : substring(bsseRefRaw, 0, min(length(bsseRefRaw), 256)))
var commonTags = {
  Environment: environment
  'bsse:ref': bsseRefEffective
}
var ingressIpSecurityRestrictions = (enableIngressIpRestrictions ? ingressAllowedCidrs : [])
var storageAccountName = toLower(take('${appName}files${uniqueString(resourceGroup().id)}', 24))
var fileShareName = 'vaultwarden'
var postgresServerName = toLower('${appName}-pg-${uniqueString(resourceGroup().id)}')
var postgresDbName = 'vaultwarden'
var postgresTier = (startsWith(postgresSkuName, 'Standard_B')
  ? 'Burstable'
  : (startsWith(postgresSkuName, 'Standard_D')
      ? 'GeneralPurpose'
      : (startsWith(postgresSkuName, 'Standard_E') ? 'MemoryOptimized' : 'Burstable')))
var postgresFqdn = '${postgresServerName}.postgres.database.azure.com'
var postgresPort = '5432'
var dbAppUser = 'vw_app'
var kvSecretDbAppPasswordName = 'vw-db-app-password'
var logAnalyticsName = '${appName}-law'
var containerEnvName = '${appName}-env'
var keyVaultName = toLower('vwkv${uniqueString(resourceGroup().id,appName)}')
var kvSecretAdminTokenName = 'vw-admin-token'
var kvSecretDatabaseUrlName = 'vw-database-url'
var kvSecretSmtpPasswordName = 'vw-smtp-password'
var roleKeyVaultSecretsOfficer = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
)
var roleKeyVaultSecretsUser = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4633458b-17de-408a-b874-0445c86b69e6'
)
var domainHostDefault = split(domainHostWithPortDefault, ':')[0]
var vwEnvBase = [
  {
    name: 'DATABASE_URL'
    secretRef: 'database-url'
  }
  {
    name: 'DOMAIN'
    value: domainUrl
  }
  {
    name: 'EMAIL_2FA_AUTO_FALLBACK'
    value: 'true'
  }
  {
    name: 'HTTP_REQUEST_BLOCK_NON_GLOBAL_IPS'
    value: 'true'
  }
  {
    name: 'IP_HEADER'
    value: 'X-Forwarded-For'
  }
  {
    name: 'INVITATIONS_ALLOWED'
    value: 'true'
  }
  {
    name: 'SHOW_PASSWORD_HINT'
    value: 'false'
  }
  {
    name: 'DISABLE_2FA_REMEMBER'
    value: 'true'
  }
  {
    name: 'EMAIL_2FA_ENFORCE_ON_VERIFIED_INVITE'
    value: 'true'
  }
  {
    name: 'ENFORCE_SINGLE_ORG_WITH_RESET_PW_POLICY'
    value: 'true'
  }
  {
    name: 'PASSWORD_HINTS_ALLOWED'
    value: 'false'
  }
  {
    name: 'SIGNUPS_VERIFY'
    value: 'true'
  }
  {
    name: 'SIGNUPS_ALLOWED'
    value: 'false'
  }
  {
    name: 'HIBP_API_KEY'
    secretRef: 'hibp-api-key'
  }
]
var vwEnvSmtpCommon = [
  {
    name: 'SMTP_FROM'
    value: (empty(smtpFrom) ? (empty(mailRootDomainEffective) ? '' : 'vault@${mailRootDomainEffective}') : smtpFrom)
  }
  {
    name: 'SMTP_FROM_NAME'
    value: smtpFromName
  }
  {
    name: 'HELO_NAME'
    value: (empty(heloName) ? domainHostDefault : heloName)
  }
  {
    name: 'SMTP_PORT'
    value: ((mailMode == 'direct_send') ? '25' : string(smtpPort))
  }
  {
    name: 'SMTP_SECURITY'
    value: ((mailMode == 'direct_send') ? 'starttls' : smtpSecurity)
  }
]
var vwEnvSmtpAuthCore = [
  {
    name: 'SMTP_USERNAME'
    value: smtpUsername
  }
  {
    name: 'SMTP_PASSWORD'
    secretRef: 'smtp-password'
  }
]
var vwSecretsBase = [
  {
    name: 'admin-token'
    keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/${kvSecretAdminTokenName}'
    identity: appName_id.id
  }
  {
    name: 'database-url'
    keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/${kvSecretDatabaseUrlName}'
    identity: appName_id.id
  }
]
var vwSecretsSmtp = [
  {
    name: 'smtp-password'
    keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/${kvSecretSmtpPasswordName}'
    identity: appName_id.id
  }
]
var recoveryServicesVaultName = '${namePrefix}-rsv'
var azureFilesBackupFabric = 'Azure'
var azureFilesBackupManagementType = 'AzureStorage'
var azureFilesBackupPolicyName = '${namePrefix}-afiles-daily'
var azureFilesBackupScheduleRunTimes = [
  '2020-01-01T${azureFilesBackupScheduleRunTime}:00Z'
]
var azureFilesBackupTimeZone_var = azureFilesBackupTimeZone
var azureFilesBackupDailyRetentionDurationCount = azureFilesBackupDailyRetentionDays
var azureFilesBackupDaysOfTheWeek = azureFilesBackupWeeklyDaysOfWeek
var azureFilesBackupWeeklyRetentionDurationCount = azureFilesBackupWeeklyRetentionWeeks
var namePrefix = toLower('${appName}${substring(uniqueString(resourceGroup().id),0,6)}')
var deploymentScriptName = '${appName}-ensure-kv-secrets'
var deploymentScriptApiVersion = '2023-08-01'
var kvSecretSsoClientSecretName = 'sso-client-secret'
var kvSecretPushInstallationKeyName = 'push-installation-key'
var vwSecretsSso = [
  {
    name: 'sso-client-secret'
    keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/${kvSecretSsoClientSecretName}'
    identity: appName_id.id
  }
]
var vwSecretsPush = [
  {
    name: 'push-installation-id'
    keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/${kvSecretPushInstallationIdName}'
    identity: appName_id.id
  }
  {
    name: 'push-installation-key'
    keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/${kvSecretPushInstallationKeyName}'
    identity: appName_id.id
  }
]
var vwEnvSso = [
  {
    name: 'SSO_ENABLED'
    value: 'true'
  }
  {
    name: 'SSO_ONLY'
    value: toLower(string(ssoOnly))
  }
  {
    name: 'SSO_AUTHORITY'
    value: ssoAuthority
  }
  {
    name: 'SSO_SCOPES'
    value: ssoScopes
  }
  {
    name: 'SSO_CLIENT_ID'
    value: ssoClientId
  }
  {
    name: 'SSO_CLIENT_SECRET'
    secretRef: 'sso-client-secret'
  }
]
var vwEnvPush = [
  {
    name: 'PUSH_ENABLED'
    value: 'true'
  }
  {
    name: 'PUSH_INSTALLATION_ID'
    secretRef: 'push-installation-id'
  }
  {
    name: 'PUSH_INSTALLATION_KEY'
    secretRef: 'push-installation-key'
  }
  {
    name: 'PUSH_RELAY_URI'
    value: (pushUseEuServers ? 'https://api.bitwarden.eu' : 'https://api.bitwarden.com')
  }
  {
    name: 'PUSH_IDENTITY_URI'
    value: (pushUseEuServers ? 'https://identity.bitwarden.eu' : 'https://identity.bitwarden.com')
  }
]
var vwEnvOptional = concat(
  (empty(invitationOrgName)
    ? json('[]')
    : [
        {
          name: 'INVITATION_ORG_NAME'
          value: invitationOrgName
        }
      ]),
  (empty(signupsDomainsWhitelist)
    ? json('[]')
    : [
        {
          name: 'SIGNUPS_DOMAINS_WHITELIST'
          value: signupsDomainsWhitelist
        }
      ]),
  (empty(orgCreationUsers)
    ? json('[]')
    : [
        {
          name: 'ORG_CREATION_USERS'
          value: orgCreationUsers
        }
      ])
)
var vwEnvAdminToken = (adminPanelEnabled
  ? [
      {
        name: 'ADMIN_TOKEN'
        secretRef: 'admin-token'
      }
    ]
  : json('[]'))
var vwEnvSmtpAuthMechanism = (((mailMode == 'direct_send') || empty(smtpAuthMechanism))
  ? json('[]')
  : [
      {
        name: 'SMTP_AUTH_MECHANISM'
        value: smtpAuthMechanism
      }
    ])
var useAcsFoundation = (acsDeployFoundation && (!empty(acsDomainNameEffective)))
var acsEmailServiceName = toLower('${appName}-email-${substring(uniqueString(resourceGroup().id),0,6)}')
var acsDomainNameEffective = (empty(acsDomainName) ? mailRootDomainEffective : toLower(acsDomainName))
var acsCommunicationServiceName = toLower('${appName}-acs-${substring(uniqueString(resourceGroup().id),0,6)}')
var domainHostWithPortDefault = split(replace(replace(domainUrl, 'https://', ''), 'http://', ''), '/')[0]
var mailRootDomainEffective = toLower(mailRootDomain)
var kvSecretPushInstallationIdName = 'push-installation-id'
var roleReader = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'acdd72a7-3385-48ef-bd42-f606fba81ae7'
)
var kvSecretHibpApiKeyName = 'vw-hibp-api-key'
var vwSecretsHibp = [
  {
    name: 'hibp-api-key'
    keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/${kvSecretHibpApiKeyName}'
    identity: appName_id.id
  }
]

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    retentionInDays: 30
  }
  tags: commonTags
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
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
  tags: commonTags
}

resource storageAccountName_default 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource storageAccountName_default_fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: storageAccountName_default
  name: fileShareName
  properties: {
    accessTier: 'Hot'
  }
}

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
    enabledForTemplateDeployment: false
    enabledForDiskEncryption: false
    publicNetworkAccess: 'Enabled'
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
  }
  tags: commonTags
}

resource appName_id 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${appName}-id'
  location: location
  tags: commonTags
}

resource appName_kv_writer_id 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${appName}-kv-writer-id'
  location: location
  tags: commonTags
}

resource Microsoft_KeyVault_vaults_keyVaultName_Microsoft_ManagedIdentity_userAssignedIdentities_appName_kv_writer_id_roleKeyVaultSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, appName_kv_writer_id.id, roleKeyVaultSecretsOfficer)
  properties: {
    roleDefinitionId: roleKeyVaultSecretsOfficer
    principalId: reference(appName_kv_writer_id.id, '2023-01-31').principalId
    principalType: 'ServicePrincipal'
  }
}

resource Microsoft_KeyVault_vaults_keyVaultName_Microsoft_ManagedIdentity_userAssignedIdentities_appName_id_roleKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, appName_id.id, roleKeyVaultSecretsUser)
  properties: {
    roleDefinitionId: roleKeyVaultSecretsUser
    principalId: reference(appName_id.id, '2023-01-31').principalId
    principalType: 'ServicePrincipal'
  }
}

resource Microsoft_DBforPostgreSQL_flexibleServers_postgresServerName_Microsoft_ManagedIdentity_userAssignedIdentities_appName_kv_writer_id_roleReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: postgresServer
  name: guid(postgresServer.id, appName_kv_writer_id.id, roleReader)
  properties: {
    roleDefinitionId: roleReader
    principalId: reference(appName_kv_writer_id.id, '2023-01-31').principalId
    principalType: 'ServicePrincipal'
  }
}

resource appName_ensure_kv_secrets 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${appName}-ensure-kv-secrets'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appName_kv_writer_id.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.81.0'
    timeout: 'PT1H'
    retentionInterval: 'PT1H'
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
        name: 'SMTP_PASSWORD_SECRET'
        value: kvSecretSmtpPasswordName
      }
      {
        name: 'SMTP_PASSWORD_VALUE'
        secureValue: smtpPassword
      }
      {
        name: 'DATABASE_URL_SECRET'
        value: kvSecretDatabaseUrlName
      }
      {
        name: 'POSTGRES_FQDN'
        value: postgresFqdn
      }
      {
        name: 'POSTGRES_PORT'
        value: string(postgresPort)
      }
      {
        name: 'POSTGRES_DBNAME'
        value: postgresDbName
      }
      {
        name: 'DB_ADMIN_USER'
        value: dbAdminUser
      }
      {
        name: 'TLS_SSLMODE'
        value: 'require'
      }
      {
        name: 'POSTGRES_SERVER_NAME'
        value: postgresServerName
      }
      {
        name: 'DB_ADMIN_PASSWORD'
        secureValue: dbPassword
      }
      {
        name: 'DB_APP_USER'
        value: dbAppUser
      }
      {
        name: 'DB_APP_PASSWORD_SECRET'
        value: kvSecretDbAppPasswordName
      }
      {
        name: 'UAMI_CLIENT_ID'
        value: reference(appName_kv_writer_id.id, '2018-11-30').clientId
      }
      {
        name: 'RESOURCE_GROUP_NAME'
        value: resourceGroup().name
      }
      {
        name: 'SMTP_FROM_INPUT'
        value: smtpFrom
      }
      {
        name: 'SMTP_USE_AUTH'
        value: string(smtpUseAuth)
      }
      {
        name: 'SMTP_HOST_INPUT'
        value: smtpHost
      }
      {
        name: 'DOMAIN_URL'
        value: domainUrl
      }
      {
        name: 'SSO_ENABLED'
        value: string(ssoEnabled)
      }
      {
        name: 'SSO_CLIENT_SECRET_SECRET'
        value: kvSecretSsoClientSecretName
      }
      {
        name: 'SSO_CLIENT_SECRET_VALUE'
        secureValue: ssoClientSecret
      }
      {
        name: 'SSO_AUTHORITY_INPUT'
        value: ssoAuthority
      }
      {
        name: 'SSO_CLIENT_ID_INPUT'
        value: ssoClientId
      }
      {
        name: 'SSO_ONLY'
        value: string(ssoOnly)
      }
      {
        name: 'PUSH_ENABLED'
        value: string(pushEnabled)
      }
      {
        name: 'PUSH_INSTALLATION_ID_SECRET'
        value: kvSecretPushInstallationIdName
      }
      {
        name: 'PUSH_INSTALLATION_ID_VALUE'
        secureValue: pushInstallationId
      }
      {
        name: 'PUSH_INSTALLATION_KEY_SECRET'
        value: kvSecretPushInstallationKeyName
      }
      {
        name: 'PUSH_INSTALLATION_KEY_VALUE'
        secureValue: pushInstallationKey
      }
      {
        name: 'SMTP_USERNAME_INPUT'
        value: smtpUsername
      }
      {
        name: 'MAIL_ROOT_DOMAIN'
        value: mailRootDomain
      }
      {
        name: 'ACS_DEPLOY_FOUNDATION'
        value: string(acsDeployFoundation)
      }
      {
        name: 'ACS_DOMAIN_NAME'
        value: acsDomainName
      }
      {
        name: 'MAIL_MODE'
        value: mailMode
      }
      {
        name: 'HIBP_API_KEY_SECRET'
        value: kvSecretHibpApiKeyName
      }
      {
        name: 'HIBP_API_KEY_VALUE'
        secureValue: hibpApiKey
      }
    ]
    scriptContent: 'set -euo pipefail\n\necho "[vault-ensure-kv-secrets] ensuring Key Vault secrets exist in $KEYVAULT_NAME ..."\n\n# Ensure we are authenticated (deploymentScripts should use the assigned managed identity, but harden against missing session)\nif ! az account show 1>/dev/null 2>/dev/null; then\n  echo "[vault-ensure-kv-secrets] az account not available - logging in with managed identity"\n  if [ -n "\${UAMI_CLIENT_ID:-}" ]; then\n    az login --identity --client-id "$UAMI_CLIENT_ID" 1>/dev/null\n  else\n    az login --identity 1>/dev/null\n  fi\nfi\n\n# ------------------------------------------------------------\n# Input validation\n# ------------------------------------------------------------\nif [ "\${MAIL_MODE:-smtp_auth}" != "direct_send" ]; then\n  if [ -z "\${SMTP_USERNAME_INPUT:-}" ]; then\n    echo "[vault-ensure-kv-secrets] ERROR: smtpUseAuth=true (mailMode=\${MAIL_MODE:-smtp_auth}) requires smtpUsername."\n    exit 1\n  fi\n  if [ -z "\${SMTP_PASSWORD_VALUE:-}" ]; then\n    echo "[vault-ensure-kv-secrets] ERROR: smtpUseAuth=true requires smtpPassword."\n    exit 1\n  fi\nfi\n\nif [ -z "\${SMTP_FROM_INPUT:-}" ] && [ -z "\${MAIL_ROOT_DOMAIN:-}" ]; then\n  echo "[vault-ensure-kv-secrets] ERROR: Either smtpFrom or mailRootDomain must be set."\n  echo "[vault-ensure-kv-secrets] Auto-generating SMTP_FROM from domainUrl is intentionally no longer supported."\n  exit 1\nfi\n\nif [ "\${MAIL_MODE:-smtp_auth}" = "direct_send" ] && [ -z "\${SMTP_HOST_INPUT:-}" ]; then\n  echo "[vault-ensure-kv-secrets] ERROR: Direct Send (mailMode=direct_send) requires an explicit smtpHost parameter."\n  echo "[vault-ensure-kv-secrets] MX lookup is not supported in Azure DeploymentScript environments."\n  echo "[vault-ensure-kv-secrets] Set the smtpHost parameter to the MX endpoint of your mail domain."\n  exit 1\nfi\n\n# Mail mode consistency check\nMAIL_MODE="\${MAIL_MODE:-smtp_auth}"\necho "[vault-ensure-kv-secrets] Mail mode: \${MAIL_MODE}"\nif [ "\${MAIL_MODE}" = "acs_smtp" ] && [ -n "\${SMTP_HOST_INPUT:-}" ] && [ "\${SMTP_HOST_INPUT}" != "smtp.azurecomm.net" ]; then\n  echo "[vault-ensure-kv-secrets] WARNING: mailMode=acs_smtp but smtpHost is not smtp.azurecomm.net (got: \${SMTP_HOST_INPUT})"\nfi\n\n# domainUrl validation\ncase "\${DOMAIN_URL:-}" in\n  https://*)\n    ;;\n  *)\n    echo "[vault-ensure-kv-secrets] ERROR: domainUrl must start with https:// (got: \'\${DOMAIN_URL:-}\')."\n    exit 1\n    ;;\nesac\n\nif [ "\${SSO_ENABLED:-false}" = "true" ]; then\n  if [ -z "\${SSO_AUTHORITY_INPUT:-}" ]; then\n    echo "[vault-ensure-kv-secrets] ERROR: ssoEnabled=true requires ssoAuthority."\n    exit 1\n  fi\n  if [ -z "\${SSO_CLIENT_ID_INPUT:-}" ]; then\n    echo "[vault-ensure-kv-secrets] ERROR: ssoEnabled=true requires ssoClientId."\n    exit 1\n  fi\n  if [ -z "\${SSO_CLIENT_SECRET_VALUE:-}" ]; then\n    echo "[vault-ensure-kv-secrets] ERROR: ssoEnabled=true requires ssoClientSecret."\n    exit 1\n  fi\nfi\n\nif [ "\${SSO_ONLY:-false}" = "true" ] && [ "\${SSO_ENABLED:-false}" != "true" ]; then\n  echo "[vault-ensure-kv-secrets] ERROR: ssoOnly=true requires ssoEnabled=true."\n  exit 1\nfi\n\nif [ "\${PUSH_ENABLED:-false}" = "true" ]; then\n  if [ -z "\${PUSH_INSTALLATION_ID_VALUE:-}" ]; then\n    echo "[vault-ensure-kv-secrets] ERROR: pushEnabled=true requires pushInstallationId."\n    exit 1\n  fi\n  if [ -z "\${PUSH_INSTALLATION_KEY_VALUE:-}" ]; then\n    echo "[vault-ensure-kv-secrets] ERROR: pushEnabled=true requires pushInstallationKey."\n    exit 1\n  fi\nfi\n\nif [ "\${ACS_DEPLOY_FOUNDATION:-false}" = "true" ]; then\n  _acs_domain="\${ACS_DOMAIN_NAME:-\${MAIL_ROOT_DOMAIN:-}}"\n  if [ -z "\${_acs_domain}" ]; then\n    echo "[vault-ensure-kv-secrets] WARNING: acsDeployFoundation=true, but neither acsDomainName nor mailRootDomain is set."\n    echo "[vault-ensure-kv-secrets] WARNING: ACS Foundation resources will NOT be deployed. Set acsDomainName or mailRootDomain to enable ACS."\n  fi\nfi\n\nWAIT_RETRIES="\${WAIT_RETRIES:-60}"\nWAIT_SLEEP_SECONDS="\${WAIT_SLEEP_SECONDS:-10}"\nexport WAIT_RETRIES WAIT_SLEEP_SECONDS\n\nPG_EXEC_STDOUT=/tmp/pg-connect.out\nPG_EXEC_STDERR=/tmp/pg-connect.err\n\n# ------------------------------------------------------------\n# Install psql (PostgreSQL client) – replaces rdbms-connect\n# ------------------------------------------------------------\nensure_psql() {\n  if command -v psql 1>/dev/null 2>/dev/null; then\n    echo "[vault-ensure-kv-secrets] psql already available: $(psql --version 2>/dev/null || true)"\n    return 0\n  fi\n  echo "[vault-ensure-kv-secrets] psql not found, installing postgresql-client..."\n  if command -v apk 1>/dev/null 2>/dev/null; then\n    apk add --no-cache postgresql-client 1>/dev/null 2>&1 && echo "[vault-ensure-kv-secrets] psql installed via apk" && return 0\n  fi\n  if command -v tdnf 1>/dev/null 2>/dev/null; then\n    tdnf install -y postgresql 1>/dev/null 2>&1 && echo "[vault-ensure-kv-secrets] psql installed via tdnf" && return 0\n  fi\n  if command -v apt-get 1>/dev/null 2>/dev/null; then\n    apt-get update -qq 1>/dev/null 2>&1 && apt-get install -y -qq postgresql-client 1>/dev/null 2>&1 && echo "[vault-ensure-kv-secrets] psql installed via apt-get" && return 0\n  fi\n  echo "[vault-ensure-kv-secrets] ERROR: Could not install psql. No supported package manager found (tried apk, tdnf, apt-get)."\n  return 1\n}\n\n# Build psql connection environment (reused for connectivity check and SQL execution)\nbuild_psql_env() {\n  export PGHOST="$POSTGRES_FQDN"\n  export PGPORT="\${POSTGRES_PORT:-5432}"\n  export PGUSER="$DB_ADMIN_USER"\n  export PGPASSWORD="$DB_ADMIN_PASSWORD"\n  export PGSSLMODE="\${TLS_SSLMODE:-require}"\n}\n\nrun_psql() {\n  local db="$1"\n  shift\n  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db" --no-password --set=ON_ERROR_STOP=1 "$@"\n}\n\nprint_pg_server_diagnostics() {\n  echo "[vault-ensure-kv-secrets] PostgreSQL server diagnostics (show):"\n  az postgres flexible-server show -g "$RESOURCE_GROUP_NAME" -n "$POSTGRES_SERVER_NAME" -o json || true\n}\n\nprint_pg_firewall_diagnostics() {\n  echo "[vault-ensure-kv-secrets] PostgreSQL firewall rules:"\n  az postgres flexible-server firewall-rule list -g "$RESOURCE_GROUP_NAME" -n "$POSTGRES_SERVER_NAME" -o json || true\n}\n\nprint_pg_database_diagnostics() {\n  echo "[vault-ensure-kv-secrets] PostgreSQL databases:"\n  az postgres flexible-server db list -g "$RESOURCE_GROUP_NAME" -s "$POSTGRES_SERVER_NAME" -o json || true\n}\n\nprint_pg_connectivity_diagnostics() {\n  local exit_code="\${1:-}"\n  local stdout_file="\${2:-}"\n  local stderr_file="\${3:-}"\n  echo "[vault-ensure-kv-secrets] PostgreSQL connectivity diagnostics:"\n  echo "[vault-ensure-kv-secrets] psql exit code: \${exit_code:-unknown}"\n  if [ -n "$stdout_file" ] && [ -f "$stdout_file" ] && [ -s "$stdout_file" ]; then\n    echo "[vault-ensure-kv-secrets] psql stdout:"\n    cat "$stdout_file" || true\n  fi\n  if [ -n "$stderr_file" ] && [ -f "$stderr_file" ] && [ -s "$stderr_file" ]; then\n    echo "[vault-ensure-kv-secrets] psql stderr:"\n    cat "$stderr_file" || true\n  fi\n  print_pg_server_diagnostics\n  print_pg_firewall_diagnostics\n  print_pg_database_diagnostics\n}\n\necho "[vault-ensure-kv-secrets] waiting for Key Vault permissions..."\nfor i in $(seq 1 "$WAIT_RETRIES"); do\n  if az keyvault secret list --vault-name "$KEYVAULT_NAME" --maxresults 1 1>/dev/null 2>/dev/null; then\n    echo "[vault-ensure-kv-secrets] Key Vault access OK"\n    break\n  fi\n  echo "[vault-ensure-kv-secrets] Key Vault access not ready yet ($i/$WAIT_RETRIES), sleeping \${WAIT_SLEEP_SECONDS}s..."\n  sleep "$WAIT_SLEEP_SECONDS"\n  if [ "$i" -eq "$WAIT_RETRIES" ]; then\n    echo "[vault-ensure-kv-secrets] ERROR: Key Vault permissions not ready after $((WAIT_RETRIES*WAIT_SLEEP_SECONDS))s"\n    exit 1\n  fi\ndone\n\n# Install psql before PostgreSQL operations\nif ! ensure_psql; then\n  echo "[vault-ensure-kv-secrets] ERROR: psql installation failed. Cannot proceed with PostgreSQL bootstrap."\n  exit 1\nfi\nbuild_psql_env\n\n# ------------------------------------------------------------\n# Wait for PostgreSQL provisioning and connectivity\n# ------------------------------------------------------------\nPG_STATE_WAIT_RETRIES="\${PG_STATE_WAIT_RETRIES:-180}"\nPG_CONNECT_WAIT_RETRIES="\${PG_CONNECT_WAIT_RETRIES:-60}"\n\necho "[vault-ensure-kv-secrets] waiting for PostgreSQL provisioning state Succeeded..."\nif ! az postgres flexible-server wait -g "$RESOURCE_GROUP_NAME" -n "$POSTGRES_SERVER_NAME" --created --interval "$WAIT_SLEEP_SECONDS" --timeout "$((PG_STATE_WAIT_RETRIES*WAIT_SLEEP_SECONDS))" 1>/dev/null; then\n  echo "[vault-ensure-kv-secrets] ERROR: PostgreSQL provisioningState did not reach Succeeded within $((PG_STATE_WAIT_RETRIES*WAIT_SLEEP_SECONDS))s"\n  print_pg_server_diagnostics\n  print_pg_firewall_diagnostics\n  exit 1\nfi\n\necho "[vault-ensure-kv-secrets] waiting for PostgreSQL state Ready..."\nfor i in $(seq 1 "$PG_STATE_WAIT_RETRIES"); do\n  PG_STATE=$(az postgres flexible-server show -g "$RESOURCE_GROUP_NAME" -n "$POSTGRES_SERVER_NAME" --query state -o tsv 2>/dev/null || true)\n  if [ "$PG_STATE" = "Ready" ]; then\n    echo "[vault-ensure-kv-secrets] PostgreSQL state is Ready"\n    break\n  fi\n  echo "[vault-ensure-kv-secrets] PostgreSQL state=\${PG_STATE:-unknown} ($i/$PG_STATE_WAIT_RETRIES), sleeping \${WAIT_SLEEP_SECONDS}s..."\n  sleep "$WAIT_SLEEP_SECONDS"\n  if [ "$i" -eq "$PG_STATE_WAIT_RETRIES" ]; then\n    echo "[vault-ensure-kv-secrets] ERROR: PostgreSQL state did not become Ready within $((PG_STATE_WAIT_RETRIES*WAIT_SLEEP_SECONDS))s"\n    print_pg_server_diagnostics\n    print_pg_firewall_diagnostics\n    exit 1\n  fi\ndone\n\necho "[vault-ensure-kv-secrets] waiting for PostgreSQL connectivity (via psql)..."\nfor i in $(seq 1 "$PG_CONNECT_WAIT_RETRIES"); do\n  PG_EXEC_EXIT=0\n  run_psql postgres -c "SELECT 1" 1>"$PG_EXEC_STDOUT" 2>"$PG_EXEC_STDERR"\n  PG_EXEC_EXIT=$?\n  if [ "$PG_EXEC_EXIT" -eq 0 ]; then\n    echo "[vault-ensure-kv-secrets] PostgreSQL reachable (psql)"\n    rm -f "$PG_EXEC_STDOUT" "$PG_EXEC_STDERR"\n    break\n  fi\n  LAST_PG_ERROR=$(cat "$PG_EXEC_STDERR" 2>/dev/null | sed \':a;N;$!ba;s/[[:space:]]\\+/ /g\' | sed \'s/^ //; s/ $//\' || true)\n  LAST_PG_STDOUT=$(cat "$PG_EXEC_STDOUT" 2>/dev/null | sed \':a;N;$!ba;s/[[:space:]]\\+/ /g\' | sed \'s/^ //; s/ $//\' || true)\n  echo "[vault-ensure-kv-secrets] PostgreSQL not ready yet ($i/$PG_CONNECT_WAIT_RETRIES), sleeping \${WAIT_SLEEP_SECONDS}s..."\n  echo "[vault-ensure-kv-secrets] last connectivity exit code: \${PG_EXEC_EXIT}"\n  if [ -n "\${LAST_PG_ERROR:-}" ]; then\n    echo "[vault-ensure-kv-secrets] last connectivity error: \${LAST_PG_ERROR}"\n  fi\n  if [ -n "\${LAST_PG_STDOUT:-}" ]; then\n    echo "[vault-ensure-kv-secrets] last connectivity stdout: \${LAST_PG_STDOUT}"\n  fi\n  sleep "$WAIT_SLEEP_SECONDS"\n  if [ "$i" -eq "$PG_CONNECT_WAIT_RETRIES" ]; then\n    echo "[vault-ensure-kv-secrets] ERROR: PostgreSQL not reachable after $((PG_CONNECT_WAIT_RETRIES*WAIT_SLEEP_SECONDS))s"\n    print_pg_connectivity_diagnostics "$PG_EXEC_EXIT" "$PG_EXEC_STDOUT" "$PG_EXEC_STDERR"\n    if [ -n "\${LAST_PG_ERROR:-}" ]; then\n      echo "[vault-ensure-kv-secrets] final connectivity error: \${LAST_PG_ERROR}"\n    fi\n    rm -f "$PG_EXEC_STDOUT" "$PG_EXEC_STDERR"\n    exit 1\n  fi\ndone\nrm -f "$PG_EXEC_STDOUT" "$PG_EXEC_STDERR"\n\n# ------------------------------------------------------------\n# Secrets in Key Vault\n# ------------------------------------------------------------\n\n# --- ADMIN_TOKEN ---\nif az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$ADMIN_TOKEN_SECRET" 1>/dev/null 2>/dev/null; then\n  echo "ADMIN_TOKEN secret already exists."\nelse\n  echo "Creating ADMIN_TOKEN secret..."\n  ADMIN_TOKEN=$(python3 - << \'PY\'\nimport secrets, base64\nprint(base64.urlsafe_b64encode(secrets.token_bytes(48)).decode(\'utf-8\').rstrip(\'=\'))\nPY\n)\n  az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$ADMIN_TOKEN_SECRET" --value "$ADMIN_TOKEN" 1>/dev/null\n  echo "ADMIN_TOKEN secret created."\nfi\n\n# --- SMTP password ---\nif [ "\${MAIL_MODE:-smtp_auth}" != "direct_send" ]; then\n  CURRENT_SMTP_PASSWORD=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$SMTP_PASSWORD_SECRET" --query value -o tsv 2>/dev/null || echo "")\n  if [ -z "$CURRENT_SMTP_PASSWORD" ] || [ "$CURRENT_SMTP_PASSWORD" != "$SMTP_PASSWORD_VALUE" ]; then\n    echo "Setting SMTP password secret..."\n    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$SMTP_PASSWORD_SECRET" --value "$SMTP_PASSWORD_VALUE" 1>/dev/null\n    echo "SMTP password secret set."\n  else\n    echo "SMTP password secret already up to date."\n  fi\nelse\n  echo "SMTP auth disabled (mailMode=direct_send). Skipping SMTP password secret."\nfi\n\n# --- SSO client secret (OIDC) ---\nif [ "\${SSO_ENABLED:-false}" = "true" ]; then\n  CURRENT_SSO_SECRET=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$SSO_CLIENT_SECRET_SECRET" --query value -o tsv 2>/dev/null || echo "")\n  if [ -z "$CURRENT_SSO_SECRET" ] || [ "$CURRENT_SSO_SECRET" != "$SSO_CLIENT_SECRET_VALUE" ]; then\n    echo "Setting SSO client secret..."\n    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$SSO_CLIENT_SECRET_SECRET" --value "$SSO_CLIENT_SECRET_VALUE" 1>/dev/null\n    echo "SSO client secret set."\n  else\n    echo "SSO client secret already up to date."\n  fi\nelse\n  echo "SSO disabled. Skipping SSO client secret."\nfi\n\n# --- Push installation id / key (Bitwarden push relay) ---\nif [ "\${PUSH_ENABLED:-false}" = "true" ]; then\n  CURRENT_PUSH_ID=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$PUSH_INSTALLATION_ID_SECRET" --query value -o tsv 2>/dev/null || echo "")\n  if [ -z "$CURRENT_PUSH_ID" ] || [ "$CURRENT_PUSH_ID" != "$PUSH_INSTALLATION_ID_VALUE" ]; then\n    echo "Setting Push installation id..."\n    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$PUSH_INSTALLATION_ID_SECRET" --value "$PUSH_INSTALLATION_ID_VALUE" 1>/dev/null\n    echo "Push installation id set."\n  else\n    echo "Push installation id already up to date."\n  fi\nelse\n  echo "Push notifications disabled. Skipping Push installation id."\nfi\n\n# --- Push installation key (Bitwarden push relay) ---\nif [ "\${PUSH_ENABLED:-false}" = "true" ]; then\n  CURRENT_PUSH_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$PUSH_INSTALLATION_KEY_SECRET" --query value -o tsv 2>/dev/null || echo "")\n  if [ -z "$CURRENT_PUSH_KEY" ] || [ "$CURRENT_PUSH_KEY" != "$PUSH_INSTALLATION_KEY_VALUE" ]; then\n    echo "Setting Push installation key..."\n    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$PUSH_INSTALLATION_KEY_SECRET" --value "$PUSH_INSTALLATION_KEY_VALUE" 1>/dev/null\n    echo "Push installation key set."\n  else\n    echo "Push installation key already up to date."\n  fi\nelse\n  echo "Push notifications disabled. Skipping Push installation key."\nfi\n\n\n# --- HIBP API Key ---\nif [ -n "\${HIBP_API_KEY_VALUE:-}" ]; then\n  CURRENT_HIBP=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$HIBP_API_KEY_SECRET" --query value -o tsv 2>/dev/null || echo "")\n  if [ -z "$CURRENT_HIBP" ] || [ "$CURRENT_HIBP" != "$HIBP_API_KEY_VALUE" ]; then\n    echo "Setting HIBP_API_KEY secret..."\n    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$HIBP_API_KEY_SECRET" --value "$HIBP_API_KEY_VALUE" 1>/dev/null\n    echo "HIBP_API_KEY secret set."\n  else\n    echo "HIBP_API_KEY secret already up to date."\n  fi\nelse\n  if ! az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$HIBP_API_KEY_SECRET" 1>/dev/null 2>/dev/null; then\n    echo "Setting HIBP_API_KEY placeholder secret (no real key provided)..."\n    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$HIBP_API_KEY_SECRET" --value "00000-00000-00000" 1>/dev/null\n    echo "HIBP_API_KEY placeholder set."\n  else\n    echo "HIBP_API_KEY secret already exists. Not overwriting with placeholder."\n  fi\nfi\n\n# --- App DB password (least-privilege user for Vaultwarden) ---\nif az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$DB_APP_PASSWORD_SECRET" 1>/dev/null 2>/dev/null; then\n  echo "App DB password secret already exists."\n  DB_APP_PASSWORD=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$DB_APP_PASSWORD_SECRET" --query value -o tsv)\nelse\n  echo "Creating App DB password secret..."\n  DB_APP_PASSWORD=$(python3 - << \'PY\'\nimport secrets\nprint(secrets.token_urlsafe(32))\nPY\n)\n  az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$DB_APP_PASSWORD_SECRET" --value "$DB_APP_PASSWORD" 1>/dev/null\n  echo "App DB password secret created."\nfi\n\nexport DB_APP_PASSWORD="$DB_APP_PASSWORD"\nSQL_TMP_DIR=$(mktemp -d)\nexport SQL_TMP_DIR\ntrap \'rm -rf "$SQL_TMP_DIR"\' EXIT\n\n# ------------------------------------------------------------\n# Provision least-privilege role & grants (idempotent)\n# ------------------------------------------------------------\necho "Provisioning Postgres role \'$DB_APP_USER\' and database privileges (idempotent) ..."\npython3 - <<\'PY\'\nimport os\nfrom pathlib import Path\n\ndef qident(s: str) -> str:\n    return \'"\' + s.replace(\'"\', \'""\') + \'"\'\n\ndef qlit(s: str) -> str:\n    return "\'" + s.replace("\'", "\'\'") + "\'"\n\napp_user = os.environ[\'DB_APP_USER\']\napp_pw = os.environ[\'DB_APP_PASSWORD\']\ndb_name = os.environ[\'POSTGRES_DBNAME\']\nout_dir = Path(os.environ[\'SQL_TMP_DIR\'])\n\nadmin_sql = f\'\'\'DO $$\nBEGIN\n  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = {qlit(app_user)}) THEN\n    CREATE ROLE {qident(app_user)} LOGIN PASSWORD {qlit(app_pw)};\n  END IF;\nEND\n$$;\n\nALTER ROLE {qident(app_user)} WITH LOGIN PASSWORD {qlit(app_pw)} NOCREATEDB NOCREATEROLE NOINHERIT;\nGRANT CONNECT ON DATABASE {qident(db_name)} TO {qident(app_user)};\n\'\'\'\n\ndb_sql = f\'GRANT USAGE, CREATE ON SCHEMA public TO {qident(app_user)};\\n\'\n\n(out_dir / \'bootstrap-admin.sql\').write_text(admin_sql)\n(out_dir / \'bootstrap-db.sql\').write_text(db_sql)\nPY\n\nPG_EXEC_EXIT=0\nrun_psql postgres -f "$SQL_TMP_DIR/bootstrap-admin.sql" 1>"$PG_EXEC_STDOUT" 2>"$PG_EXEC_STDERR"\nPG_EXEC_EXIT=$?\nif [ "$PG_EXEC_EXIT" -ne 0 ]; then\n  echo "[vault-ensure-kv-secrets] ERROR: PostgreSQL bootstrap-admin.sql failed"\n  print_pg_connectivity_diagnostics "$PG_EXEC_EXIT" "$PG_EXEC_STDOUT" "$PG_EXEC_STDERR"\n  exit 1\nfi\nPG_EXEC_EXIT=0\nrun_psql "$POSTGRES_DBNAME" -f "$SQL_TMP_DIR/bootstrap-db.sql" 1>"$PG_EXEC_STDOUT" 2>"$PG_EXEC_STDERR"\nPG_EXEC_EXIT=$?\nif [ "$PG_EXEC_EXIT" -ne 0 ]; then\n  echo "[vault-ensure-kv-secrets] ERROR: PostgreSQL bootstrap-db.sql failed"\n  print_pg_connectivity_diagnostics "$PG_EXEC_EXIT" "$PG_EXEC_STDOUT" "$PG_EXEC_STDERR"\n  exit 1\nfi\necho "Postgres provisioning done."\n\n# ------------------------------------------------------------\n# DATABASE_URL (PostgreSQL connection string for Vaultwarden)\n# ------------------------------------------------------------\nENCODED_APP_PASSWORD=$(python3 - << \'PY\'\nimport os, urllib.parse\nprint(urllib.parse.quote(os.environ.get("DB_APP_PASSWORD",""), safe=""))\nPY\n)\n\nDATABASE_URL="postgresql://\${DB_APP_USER}:\${ENCODED_APP_PASSWORD}@\${POSTGRES_FQDN}:\${POSTGRES_PORT}/\${POSTGRES_DBNAME}?sslmode=\${TLS_SSLMODE}"\n\nif az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$DATABASE_URL_SECRET" 1>/dev/null 2>/dev/null; then\n  CURRENT_DBURL=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$DATABASE_URL_SECRET" --query value -o tsv || echo "")\n  if echo "$CURRENT_DBURL" | grep -qiE \'^postgres(ql)?://\'; then\n    if echo "$CURRENT_DBURL" | grep -q "://\${DB_ADMIN_USER}:"; then\n      echo "DATABASE_URL currently uses admin user; updating to app user..."\n      az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$DATABASE_URL_SECRET" --value "$DATABASE_URL" 1>/dev/null\n      echo "DATABASE_URL secret updated."\n    else\n      echo "DATABASE_URL secret already exists and looks valid."\n    fi\n  else\n    echo "DATABASE_URL secret exists but looks invalid; updating to PostgreSQL URL..."\n    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$DATABASE_URL_SECRET" --value "$DATABASE_URL" 1>/dev/null\n    echo "DATABASE_URL secret updated."\n  fi\nelse\n  echo "Creating DATABASE_URL secret..."\n  az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$DATABASE_URL_SECRET" --value "$DATABASE_URL" 1>/dev/null\n  echo "DATABASE_URL secret created."\nfi\n\n# ------------------------------------------------------------\n# SMTP host resolution\n# ------------------------------------------------------------\n# SMTP Auth:   smtp.office365.com (or SMTP_HOST_INPUT if set)\n# Direct Send: SMTP_HOST_INPUT is required (MX lookup not supported\n#              in Azure DeploymentScript; validated early above)\n\nMX_HOST=""\nif [ "\${MAIL_MODE:-smtp_auth}" != "direct_send" ]; then\n  if [ -n "\${SMTP_HOST_INPUT:-}" ]; then\n    MX_HOST="\${SMTP_HOST_INPUT}"\n  else\n    MX_HOST="smtp.office365.com"\n  fi\nelse\n  MX_HOST="\${SMTP_HOST_INPUT}"\nfi\necho "[vault-ensure-kv-secrets] SMTP host resolved: \${MX_HOST}"\n\ncat > "$AZ_SCRIPTS_OUTPUT_PATH" <<JSON\n{\n  "status": "ok",\n  "smtp_host": "\${MX_HOST}"\n}\nJSON\n\necho "Done."\n'
    forceUpdateTag: deploymentScriptForceUpdateTag
  }
  dependsOn: [
    keyVault
    Microsoft_KeyVault_vaults_keyVaultName_Microsoft_ManagedIdentity_userAssignedIdentities_appName_kv_writer_id_roleKeyVaultSecretsOfficer

    postgresServer
    postgresServerName_postgresDb
    Microsoft_DBforPostgreSQL_flexibleServers_postgresServerName_Microsoft_ManagedIdentity_userAssignedIdentities_appName_kv_writer_id_roleReader
    postgresServerName_AllowAzure
  ]
}

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: postgresServerName
  location: location
  sku: {
    name: postgresSkuName
    tier: postgresTier
  }
  properties: {
    administratorLogin: dbAdminUser
    administratorLoginPassword: dbPassword
    version: postgresVersion
    storage: {
      storageSizeGB: postgresStorageGB
    }
    authConfig: {
      passwordAuth: 'Enabled'
      activeDirectoryAuth: 'Disabled'
    }
    backup: {
      backupRetentionDays: postgresBackupRetentionDays
    }
  }
  tags: commonTags
}

resource postgresServerName_AllowAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-03-01-preview' = {
  parent: postgresServer
  name: 'AllowAzure'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource postgresServerName_postgresDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-03-01-preview' = {
  parent: postgresServer
  name: '${postgresDbName}'
}

resource containerEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalytics.id, '2023-09-01').customerId
        sharedKey: listKeys(logAnalytics.id, '2023-09-01').primarySharedKey
      }
    }
  }
  tags: commonTags
}

resource containerEnvName_vaultwarden_storage 'Microsoft.App/managedEnvironments/storages@2024-03-01' = {
  parent: containerEnv
  name: 'vaultwarden-storage'
  properties: {
    azureFile: {
      accountName: storageAccountName
      shareName: fileShareName
      accountKey: listKeys(storageAccount.id, '2023-05-01').keys[0].value
      accessMode: 'ReadWrite'
    }
  }
  dependsOn: [
    storageAccountName_default_fileShare
  ]
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appName_id.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: allowInsecureHttp
        ipSecurityRestrictions: ingressIpSecurityRestrictions
      }
      secrets: concat(
        vwSecretsBase,
        ((mailMode != 'direct_send') ? vwSecretsSmtp : json('[]')),
        (ssoEnabled ? vwSecretsSso : json('[]')),
        (pushEnabled ? vwSecretsPush : json('[]')),
        vwSecretsHibp
      )
      activeRevisionsMode: 'Single'
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
          env: concat(
            vwEnvAdminToken,
            vwEnvBase,
            vwEnvOptional,
            vwEnvSmtpCommon,
            [
              {
                name: 'SMTP_HOST'
                value: (empty(smtpHost) ? 'smtp.office365.com' : smtpHost)
              }
            ],
            ((mailMode != 'direct_send') ? vwEnvSmtpAuthCore : json('[]')),
            vwEnvSmtpAuthMechanism,
            (ssoEnabled ? vwEnvSso : json('[]')),
            (pushEnabled ? vwEnvPush : json('[]'))
          )
          volumeMounts: [
            {
              volumeName: 'data'
              mountPath: '/data'
            }
          ]
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/alive'
                port: 80
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 5
              timeoutSeconds: 3
              failureThreshold: 30
              successThreshold: 1
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/alive'
                port: 80
                scheme: 'HTTP'
              }
              initialDelaySeconds: 0
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/alive'
                port: 80
                scheme: 'HTTP'
              }
              initialDelaySeconds: 0
              periodSeconds: 10
              timeoutSeconds: 3
              failureThreshold: 3
              successThreshold: 1
            }
          ]
        }
      ]
      volumes: [
        {
          name: 'data'
          storageType: 'AzureFile'
          storageName: 'vaultwarden-storage'
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
  tags: commonTags
  dependsOn: [
    containerEnvName_vaultwarden_storage
    appName_ensure_kv_secrets
    Microsoft_KeyVault_vaults_keyVaultName_Microsoft_ManagedIdentity_userAssignedIdentities_appName_id_roleKeyVaultSecretsUser
    postgresServerName_postgresDb
  ]
}

resource acsEmailService 'Microsoft.Communication/emailServices@2025-09-01' = if (useAcsFoundation) {
  name: acsEmailServiceName
  location: 'global'
  tags: commonTags
  properties: {
    dataLocation: acsDataLocation
  }
}

resource acsEmailServiceName_acsDomainNameEffective 'Microsoft.Communication/emailServices/domains@2025-09-01' = if (useAcsFoundation) {
  parent: acsEmailService
  name: '${acsDomainNameEffective}'
  location: 'global'
  properties: {
    domainManagement: 'CustomerManaged'
    userEngagementTracking: 'Disabled'
  }
}

resource acsCommunicationService 'Microsoft.Communication/communicationServices@2025-09-01' = if (useAcsFoundation) {
  name: acsCommunicationServiceName
  location: 'global'
  tags: commonTags
  properties: {
    dataLocation: acsDataLocation
    disableLocalAuth: false
    publicNetworkAccess: 'Enabled'
  }
}

resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2021-12-01' = if (azureFilesBackupEnabled) {
  name: recoveryServicesVaultName
  location: location
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {}
}

resource recoveryServicesVaultName_azureFilesBackupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2021-12-01' = if (azureFilesBackupEnabled) {
  parent: recoveryServicesVault
  name: '${azureFilesBackupPolicyName}'
  properties: {
    backupManagementType: azureFilesBackupManagementType
    schedulePolicy: {
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: azureFilesBackupScheduleRunTimes
      schedulePolicyType: 'SimpleSchedulePolicy'
    }
    retentionPolicy: {
      dailySchedule: {
        retentionTimes: azureFilesBackupScheduleRunTimes
        retentionDuration: {
          count: azureFilesBackupDailyRetentionDurationCount
          durationType: 'Days'
        }
      }
      weeklySchedule: {
        daysOfTheWeek: azureFilesBackupDaysOfTheWeek
        retentionTimes: azureFilesBackupScheduleRunTimes
        retentionDuration: {
          count: azureFilesBackupWeeklyRetentionDurationCount
          durationType: 'Weeks'
        }
      }
      retentionPolicyType: 'LongTermRetentionPolicy'
    }
    timeZone: azureFilesBackupTimeZone_var
    workLoadType: 'AzureFileShare'
  }
}

resource recoveryServicesVaultName_azureFilesBackupFabric_storagecontainer_Storage_name_storageAccount 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers@2021-12-01' = if (azureFilesBackupEnabled) {
  name: '${recoveryServicesVaultName}/${azureFilesBackupFabric}/storagecontainer;Storage;${resourceGroup().name};${storageAccountName}'
  properties: {
    backupManagementType: azureFilesBackupManagementType
    containerType: 'StorageContainer'
    sourceResourceId: storageAccount.id
  }
  dependsOn: [
    recoveryServicesVault
  ]
}

resource recoveryServicesVaultName_azureFilesBackupFabric_storagecontainer_Storage_name_storageAccountName_AzureFileShare_fileShare 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2021-12-01' = if (azureFilesBackupEnabled) {
  name: '${recoveryServicesVaultName}/${azureFilesBackupFabric}/storagecontainer;Storage;${resourceGroup().name};${storageAccountName}/AzureFileShare;${fileShareName}'
  properties: {
    protectedItemType: 'AzureFileShareProtectedItem'
    sourceResourceId: storageAccount.id
    policyId: recoveryServicesVaultName_azureFilesBackupPolicy.id
    isInlineInquiry: true
  }
  dependsOn: [
    recoveryServicesVaultName_azureFilesBackupFabric_storagecontainer_Storage_name_storageAccount
    recoveryServicesVault
    storageAccountName_default_fileShare
  ]
}

resource appName_kv_diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (diagnosticsEnabled) {
  scope: keyVault
  name: '${appName}-kv-diag'
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource appName_pg_diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (diagnosticsEnabled) {
  scope: postgresServer
  name: '${appName}-pg-diag'
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'PostgreSQLLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output containerAppFqdn string = reference(app.id, '2024-03-01').configuration.ingress.fqdn
output keyVaultName string = keyVaultName
output smtpServerResolved string = (smtpUseAuth
  ? '${(empty(smtpHost)?'smtp.office365.com':smtpHost)}:${string(smtpPort)}'
  : '${reference(resourceId('Microsoft.Resources/deploymentScripts',deploymentScriptName),deploymentScriptApiVersion).outputs.smtp_host}:25')
output nextSteps array = [
  'Bind the final custom domain and certificate to the Container App before go-live.'
  'Run the smoke tests from docs/HowToInstall/Operation-Playbook.md.'
  'Verify restore paths for PostgreSQL and Azure Files before storing production data.'
]
output acsFoundationEnabled bool = useAcsFoundation
output acsEmailServiceName string = (useAcsFoundation ? acsEmailServiceName : '')
output acsCommunicationServiceName string = (useAcsFoundation ? acsCommunicationServiceName : '')
output acsEmailDomain string = (useAcsFoundation ? acsDomainNameEffective : '')
output acsEmailDomainResourceId string = (useAcsFoundation ? acsEmailServiceName_acsDomainNameEffective.id : '')
output acsNextSteps array = (useAcsFoundation
  ? [
      'Set the ACS DNS records for the prepared email domain.'
      'Wait until the ACS email domain shows as verified.'
      'Link the verified ACS email domain to the Communication Service.'
      'Create the ACS SMTP username for the Entra application and assign the required role.'
      'Redeploy main.json with smtpHost=smtp.azurecomm.net and the final ACS SMTP credentials.'
    ]
  : [])
output edgeMode string = edgeMode
output containerAppName string = appName
output containerAppEnvironmentName string = containerEnvName
output customHostname string = customHostname
output ingressIpRestrictionsEnabled bool = enableIngressIpRestrictions
output ingressIpRestrictionsCount int = length(ingressAllowedCidrs)
