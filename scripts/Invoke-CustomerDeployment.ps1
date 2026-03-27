# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
[CmdletBinding()]
param(
    [Alias('CustomerCode')][string]$CustomerNumber,
    [Alias('Hostname')][string]$VaultwardenDomain,
    [Alias('ZoneName')][string]$CloudflareZone,
    [string]$ResourceGroupName,
    [ValidateSet('prod','test','dev')][string]$Environment = 'prod',
    [string]$Location = 'germanywestcentral',
    [ValidateSet('basic','cloudflare-managed')][string]$Mode,
    [string]$CustomersRoot,
    [switch]$GenerateOnly,
    [switch]$NonInteractive,
    [switch]$Repair,
    [switch]$Update,
    [switch]$SmtpUseAuth,
    [string]$MailRootDomain,
    [string]$SmtpFrom,
    [string]$SmtpFromName = 'Vaultwarden',
    [string]$SmtpHost,
    [string]$SmtpPort,
    [ValidateSet('starttls','force_tls','off')][string]$SmtpSecurity,
    [string]$SmtpUsername,
    [SecureString]$SmtpPassword,
    [string]$CloudflareApiToken,
    [switch]$EnableWaf,
    [switch]$EnableRateLimit,
    [switch]$SkipOriginLockdown,
    [switch]$AdminPanelEnabled,
    [switch]$DisableAdminPanel,
    [string]$InvitationOrgName,
    [string]$SignupsDomainsWhitelist,
    [string]$OrgCreationUsers,
    [switch]$DiagnosticsEnabled,
    [switch]$DisableDiagnostics,
    [switch]$AllowInsecureHttp,
    [switch]$SsoEnabled,
    [switch]$SsoOnly,
    [string]$SsoAuthority,
    [string]$SsoClientId,
    [SecureString]$SsoClientSecret,
    [string]$SsoScopes = 'openid profile email offline_access User.Read',
    [switch]$PushEnabled,
    [string]$PushInstallationId,
    [SecureString]$PushInstallationKey,
    [switch]$PushUseEuServers,
    [switch]$AcsDeployFoundation,
    [string]$AcsDataLocation = 'Germany',
    [string]$AcsDomainName,
    [ValidateSet('direct_send','smtp_auth','acs_smtp')][string]$MailMode,
    [string]$StorageAccountSku,
    [string]$PostgresSkuName,
    [int]$PostgresStorageGB,
    [int]$PostgresBackupRetentionDays
)

. (Join-Path $PSScriptRoot 'lib/VaultwardenDeployment.Common.ps1')
. (Join-Path $PSScriptRoot 'lib/VaultwardenDeployment.Menu.ps1')
. (Join-Path $PSScriptRoot 'lib/VaultwardenDeployment.Flows.ps1')
$script:InvocationBoundParameters = $PSBoundParameters

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
# Leitet den Mail-Modus (direct_send | smtp_auth | acs_smtp) aus einer gespeicherten
# Konfiguration ab. Wird für Backward-Compatibility beim Laden älterer Configs benötigt,
# die noch kein smtp.mailMode-Feld haben.
function Get-MailModeFromConfig {
    param([Parameter(Mandatory)][hashtable]$Config)
    $stored = [string]$Config.smtp.mailMode
    if ($stored -in @('direct_send', 'smtp_auth', 'acs_smtp')) { return $stored }
    # Backward compat: derive from smtp.useAuth + acsDeployFoundation
    $useAuth = [bool]$Config.smtp.useAuth
    $acsFoundation = if ($Config.azure -and $Config.azure.advancedArmParameters) {
        [bool]$Config.azure.advancedArmParameters.acsDeployFoundation
    } else { $false }
    if ($useAuth -and $acsFoundation) { return 'acs_smtp' }
    if ($useAuth) { return 'smtp_auth' }
    return 'direct_send'
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
# Betroffen: Wizard (New-CustomerConfigInteractive), CLI-Pfad, GenerateOnly.
# Kanonische SMTP-Zustandsdefinition (smtp.mailMode ist Source of Truth):
#   direct_send: useAuth=false, kein Passwort/Username
#   smtp_auth:   useAuth=true, klassisches SMTP Relay
#   acs_smtp:    useAuth=true, smtpHost=smtp.azurecomm.net, acsDeployFoundation=true
# Beim Mail-Modus-Wechsel werden nicht mehr gültige Felder explizit leer gesetzt.
function New-CustomerConfigObject {
    param(
        [Parameter(Mandatory)][string]$CustomerNumber,
        [Parameter(Mandatory)][string]$VaultwardenDomain,
        [Parameter(Mandatory)][string]$ZoneName,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$Environment,
        [Parameter(Mandatory)][string]$Location,
        [Parameter(Mandatory)][ValidateSet('basic','cloudflare-managed')][string]$Mode,
        [Parameter(Mandatory)][string]$MailRootDomain,
        [bool]$SmtpUseAuth = $true,
        [ValidateSet('direct_send','smtp_auth','acs_smtp')][string]$MailMode,
        [string]$SmtpFrom,
        [string]$SmtpFromName = 'Vaultwarden',
        [string]$SmtpHost,
        [string]$SmtpPort,
        [string]$SmtpSecurity = 'starttls',
        [string]$SmtpUsername,
        [bool]$EnableWaf = $true,
        [bool]$EnableRateLimit = $true,
        [hashtable]$AdvancedArmParameters,
        [hashtable]$Secrets
    )

    # Normalize domain inputs to lowercase
    $VaultwardenDomain = $VaultwardenDomain.Trim().ToLowerInvariant()
    $ZoneName = $ZoneName.Trim().ToLowerInvariant()
    $MailRootDomain = $MailRootDomain.Trim().ToLowerInvariant()

    if (-not (Test-ValidHostnameInZone -Hostname $VaultwardenDomain -ZoneName $ZoneName)) {
        throw "Vaultwarden-Domäne '$VaultwardenDomain' passt nicht zur Zone '$ZoneName'."
    }
    $customerCode = Convert-DomainToSlug -Domain $VaultwardenDomain
    $appName = Convert-SlugToAppName -Slug $customerCode
    $url = 'https://' + $VaultwardenDomain
    if (-not $AdvancedArmParameters) { $AdvancedArmParameters = New-EmptyAdvancedArmParameters }
    $advanced = ConvertTo-HashtableDeep -InputObject $AdvancedArmParameters
    if ([string]::IsNullOrWhiteSpace([string]$advanced.invitationOrgName)) {
        $advanced.invitationOrgName = Get-SuggestedInvitationOrgName -ZoneName $ZoneName
    }
    if ([string]::IsNullOrWhiteSpace([string]$advanced.signupsDomainsWhitelist)) {
        $advanced.signupsDomainsWhitelist = Get-SuggestedSignupsDomainsWhitelist -ZoneName $ZoneName
    }
    if (-not $Secrets) { $Secrets = @{} }

    # Derive effective mail mode.
    # Priority: explicit $MailMode > derived from $SmtpUseAuth + $advanced.acsDeployFoundation.
    $effectiveMailMode = if ($MailMode -in @('direct_send', 'smtp_auth', 'acs_smtp')) {
        $MailMode
    } elseif ([bool]$SmtpUseAuth -and [bool]$advanced.acsDeployFoundation) {
        'acs_smtp'
    } elseif ([bool]$SmtpUseAuth) {
        'smtp_auth'
    } else {
        'direct_send'
    }

    # Derive SmtpUseAuth from effective mail mode.
    $effectiveSmtpUseAuth = ($effectiveMailMode -ne 'direct_send')

    # acs_smtp: auto-set host and ensure acsDeployFoundation=true.
    if ($effectiveMailMode -eq 'acs_smtp') {
        if ([string]::IsNullOrWhiteSpace($SmtpHost)) { $SmtpHost = 'smtp.azurecomm.net' }
        $advanced.acsDeployFoundation = $true
    }

    [ordered]@{
        customerCode = $customerCode
        customerNumber = $CustomerNumber
        metadata = [ordered]@{
            createdAt = (Get-Date).ToString('o')
            updatedAt = (Get-Date).ToString('o')
            version = 3
        }
        azure = [ordered]@{
            resourceGroupName = $ResourceGroupName
            location = $Location
            environment = $Environment
            appName = $appName
            edgeMode = if ($Mode -eq 'cloudflare-managed') { 'cloudflare-managed' } else { 'none' }
            enableIngressIpRestrictions = $false
            ingressAllowedCidrs = @()
            advancedArmParameters = $advanced
        }
        domain = [ordered]@{
            hostname = $VaultwardenDomain
            zoneName = $ZoneName
            url = $url
        }
        edge = [ordered]@{
            mode = $Mode
            enableWaf = [bool]$EnableWaf
            enableRateLimit = [bool]$EnableRateLimit
            lockOriginToCloudflare = if ($Mode -eq 'cloudflare-managed') { $true } else { $false }
        }
        smtp = [ordered]@{
            mailMode = $effectiveMailMode
            useAuth = [bool]$effectiveSmtpUseAuth
            mailRootDomain = $MailRootDomain
            from = $SmtpFrom
            fromName = $SmtpFromName
            host = $SmtpHost
            port = $SmtpPort
            security = $SmtpSecurity
            username = $SmtpUsername
            passwordSource = if ($effectiveSmtpUseAuth) { 'prompt' } else { 'none' }
        }
        secrets = [ordered]@{
            smtpPasswordSource = if ($effectiveSmtpUseAuth) { 'prompt' } else { 'none' }
            cloudflareApiTokenSource = if ($Mode -eq 'cloudflare-managed') { 'prompt-or-env' } else { 'not-required' }
            ssoClientSecretSource = if ($Secrets.ContainsKey('ssoClientSecretSource')) { $Secrets.ssoClientSecretSource } else { 'none' }
            pushInstallationKeySource = if ($Secrets.ContainsKey('pushInstallationKeySource')) { $Secrets.pushInstallationKeySource } else { 'none' }
        }
    }
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
# Betroffen: Hauptpfad (interaktiv + CLI + GenerateOnly).
# Beim Wechsel SMTP Auth → Direct Send: smtp.useAuth=false → kein SMTP-Passwort anfordern.
# Beim Wechsel Direct Send → SMTP Auth: smtp.useAuth=true → SMTP-Passwort wird hier angefordert.
function Get-RuntimeSecretParameters {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [switch]$NonInteractive,
        [switch]$GenerateOnly,
        [SecureString]$SmtpPassword,
        [SecureString]$SsoClientSecret,
        [SecureString]$PushInstallationKey
    )

    $result = @{}
    if ($Config.smtp.useAuth) {
        if ($SmtpPassword) { $result.smtpPassword = $SmtpPassword }
        elseif ($GenerateOnly -and $NonInteractive) { throw 'Für GenerateOnly im SMTP-Auth-Modus muss SmtpPassword übergeben werden.' }
        else { $result.smtpPassword = Read-Host -AsSecureString 'SMTP Password' }
    }

    $advanced = $Config.azure.advancedArmParameters
    if ($advanced.ssoEnabled) {
        if ($SsoClientSecret) { $result.ssoClientSecret = $SsoClientSecret }
        elseif ($GenerateOnly -and $NonInteractive) { throw 'SSO ist aktiviert, aber SsoClientSecret fehlt.' }
        else { $result.ssoClientSecret = Read-Host -AsSecureString 'SSO Client Secret' }
    }
    if ($advanced.pushEnabled) {
        if ($PushInstallationKey) { $result.pushInstallationKey = $PushInstallationKey }
        elseif ($GenerateOnly -and $NonInteractive) { throw 'Push ist aktiviert, aber PushInstallationKey fehlt.' }
        else { $result.pushInstallationKey = Read-Host -AsSecureString 'Push Installation Key' }
    }
    return $result
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
# Betroffen: Save-CustomerFiles (alle Pfade), temporärer Deploy-Pfad (Hauptpfad mit Secrets).
# mailMode ist Source of Truth: wird immer in ARM-Params geschrieben.
# direct_send: nur smtpHost. smtp_auth/acs_smtp: Host+Port+Security+Username+Password.
function New-CustomerAzureParameters {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$OutputPath,
        [hashtable]$SecureArmParameters,
        [switch]$IncludeSecureParameters
    )

    $params = [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = [ordered]@{
            location = @{ value = $Config.azure.location }
            environment = @{ value = $Config.azure.environment }
            appName = @{ value = $Config.azure.appName }
            domainUrl = @{ value = $Config.domain.url }
            customHostname = @{ value = $Config.domain.hostname }
            mailRootDomain = @{ value = $Config.smtp.mailRootDomain }
            smtpUseAuth = @{ value = [bool]$Config.smtp.useAuth }
            mailMode = @{ value = [string]$Config.smtp.mailMode }
            smtpFrom = @{ value = $Config.smtp.from }
            smtpFromName = @{ value = $Config.smtp.fromName }
            edgeMode = @{ value = $Config.azure.edgeMode }
            enableIngressIpRestrictions = @{ value = [bool]$Config.azure.enableIngressIpRestrictions }
            ingressAllowedCidrs = @{ value = @(Normalize-IngressRestrictionParameterValue -InputValue $Config.azure.ingressAllowedCidrs) }
        }
    }

    if ($Config.smtp.useAuth) {
        $params.parameters.smtpHost = @{ value = $Config.smtp.host }
        $params.parameters.smtpPort = @{ value = $Config.smtp.port }
        $params.parameters.smtpSecurity = @{ value = $Config.smtp.security }
        $params.parameters.smtpUsername = @{ value = $Config.smtp.username }
        if ($IncludeSecureParameters) {
            if (-not $SecureArmParameters -or -not $SecureArmParameters.ContainsKey('smtpPassword')) {
                throw 'SMTP Auth ist aktiviert, aber es wurde kein SMTP-Passwort übergeben.'
            }
            $params.parameters.smtpPassword = @{ value = (ConvertFrom-SecureStringPlain -SecureString $SecureArmParameters.smtpPassword) }
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Config.smtp.host)) {
        # Direct Send: write smtpHost so the deployment script receives SMTP_HOST_INPUT.
        # MX lookup is not performed at runtime; the host must be pre-resolved and stored here.
        $params.parameters.smtpHost = @{ value = $Config.smtp.host }
    }
    else {
        throw 'Direct Send (smtpUseAuth=false) erfordert einen expliziten smtpHost-Wert. Gib den MX-Endpunkt deiner Mail-Domain an.'
    }

    if ($Config.azure.advancedArmParameters) {
        $overrides = ConvertTo-HashtableDeep -InputObject $Config.azure.advancedArmParameters
        foreach ($key in $overrides.Keys) {
            $params.parameters[$key] = @{ value = $overrides[$key] }
        }
    }
    if ($IncludeSecureParameters -and $SecureArmParameters) {
        if ($SecureArmParameters.ContainsKey('ssoClientSecret')) {
            $params.parameters.ssoClientSecret = @{ value = (ConvertFrom-SecureStringPlain -SecureString $SecureArmParameters.ssoClientSecret) }
        }
        if ($SecureArmParameters.ContainsKey('pushInstallationKey')) {
            $params.parameters.pushInstallationKey = @{ value = (ConvertFrom-SecureStringPlain -SecureString $SecureArmParameters.pushInstallationKey) }
        }
    }

    Save-JsonUtf8 -Data $params -Path $OutputPath
    return $params
}

function New-ActiveDeployToAzureTemplate {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][hashtable]$AzureParameters,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $sourceWrapperPath = Join-Path $RepoRoot 'main.deploytoazure.json'
    $wrapper = ConvertTo-HashtableDeep -InputObject (Read-JsonFile -Path $sourceWrapperPath)
    foreach ($parameterName in @($wrapper.parameters.Keys)) {
        if ($parameterName -eq 'mainTemplateUri') { continue }
        if (-not ($AzureParameters.parameters.Keys -contains $parameterName)) { continue }
        $parameterDefinition = $wrapper.parameters[$parameterName]
        $parameterValue = $AzureParameters.parameters[$parameterName].value
        if ($parameterDefinition.type -eq 'secureString' -or $parameterDefinition.type -eq 'securestring') {
            if (-not ($parameterDefinition.Keys -contains 'defaultValue')) { $parameterDefinition.defaultValue = '' }
            continue
        }
        $parameterDefinition.defaultValue = $parameterValue
    }
    Save-JsonUtf8 -Data $wrapper -Path $OutputPath
    return $wrapper
}

function New-CurrentReadmeContent {
    param([Parameter(Mandatory)][hashtable]$Config)
@"
# current

Diese Dateien sind die **aktive Deploy-to-Azure-Kopie** für $($Config.domain.hostname).

- Quelle: ``customers/$($Config.customerCode)/...``
- Aktive Vaultwarden-Domäne: $($Config.domain.hostname)
- Resource Group Default: $($Config.azure.resourceGroupName)

Verwendung:
- Der Deploy-to-Azure-Button zeigt auf ``current/main.deploytoazure.json``.
- ``current/azure.parameters.json`` ist die dazugehörige aktive Parameterkopie.

Achtung:
- ``current/azure.parameters.json`` kann sensible Klartextwerte enthalten, wenn sie bei der Generierung übergeben wurden.
- Vor einem Push ins Git bitte prüfen, ob Secrets enthalten sind.
"@
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
# Betroffen: Alle Pfade (Wizard, CLI, GenerateOnly, Repair, Update).
# Schreibt deployment.config.json, azure.parameters.json und current/-Kopien.
function Save-CustomerFiles {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][hashtable]$Paths,
        [Parameter(Mandatory)][string]$RepoRoot,
        [hashtable]$SecureArmParameters
    )
    Ensure-Directory -Path $Paths.CustomerRoot | Out-Null
    Ensure-Directory -Path $Paths.ArtifactsRoot | Out-Null
    Ensure-Directory -Path $Paths.CurrentRoot | Out-Null

    Save-JsonUtf8 -Data $Config -Path $Paths.ConfigPath
    $azureParameters = New-CustomerAzureParameters -Config $Config -OutputPath $Paths.AzureParametersPath -SecureArmParameters $SecureArmParameters
    [System.IO.File]::WriteAllText($Paths.CustomerReadmePath, (New-CustomerReadmeContent -Config $Config), [System.Text.UTF8Encoding]::new($false))

    Save-JsonUtf8 -Data $Config -Path $Paths.CurrentConfigPath
    Save-JsonUtf8 -Data $azureParameters -Path $Paths.CurrentAzureParametersPath
    New-ActiveDeployToAzureTemplate -RepoRoot $RepoRoot -AzureParameters $azureParameters -OutputPath $Paths.CurrentDeployToAzureTemplatePath | Out-Null
    [System.IO.File]::WriteAllText($Paths.CurrentReadmePath, (New-CurrentReadmeContent -Config $Config), [System.Text.UTF8Encoding]::new($false))
}

function Get-CloudflareTokenValue {
    param([string]$CloudflareApiToken)
    if (-not [string]::IsNullOrWhiteSpace($CloudflareApiToken)) { return $CloudflareApiToken }
    if ($env:CLOUDFLARE_API_TOKEN) { return $env:CLOUDFLARE_API_TOKEN }
    $secure = Read-Host -AsSecureString 'Cloudflare API Token'
    return ConvertFrom-SecureStringPlain -SecureString $secure
}

function Build-AdvancedArmParametersFromCli {
    param(
        [hashtable]$ExistingAdvanced,
        [Parameter(Mandatory)][string]$ZoneName
    )
    $advancedInput = if ($ExistingAdvanced) { $ExistingAdvanced } else { New-EmptyAdvancedArmParameters }
    $advanced = ConvertTo-HashtableDeep -InputObject $advancedInput

    if ($DisableAdminPanel) { $advanced.adminPanelEnabled = $false }
    elseif ($AdminPanelEnabled) { $advanced.adminPanelEnabled = $true }
    if ($script:InvocationBoundParameters.ContainsKey('InvitationOrgName')) { $advanced.invitationOrgName = $InvitationOrgName }
    elseif ([string]::IsNullOrWhiteSpace([string]$advanced.invitationOrgName)) { $advanced.invitationOrgName = Get-SuggestedInvitationOrgName -ZoneName $ZoneName }
    if ($script:InvocationBoundParameters.ContainsKey('SignupsDomainsWhitelist')) { $advanced.signupsDomainsWhitelist = $SignupsDomainsWhitelist }
    elseif ([string]::IsNullOrWhiteSpace([string]$advanced.signupsDomainsWhitelist)) { $advanced.signupsDomainsWhitelist = Get-SuggestedSignupsDomainsWhitelist -ZoneName $ZoneName }
    if ($script:InvocationBoundParameters.ContainsKey('OrgCreationUsers')) { $advanced.orgCreationUsers = $OrgCreationUsers }
    if ($DisableDiagnostics) { $advanced.diagnosticsEnabled = $false }
    elseif ($DiagnosticsEnabled) { $advanced.diagnosticsEnabled = $true }
    # allowInsecureHttp and allowAzureServicesToPostgres are always true in the standard path
    $advanced.allowInsecureHttp = $true
    $advanced.allowAzureServicesToPostgres = $true
    if ($script:InvocationBoundParameters.ContainsKey('StorageAccountSku')) { $advanced.storageAccountSku = $StorageAccountSku }
    if ($script:InvocationBoundParameters.ContainsKey('PostgresSkuName')) { $advanced.postgresSkuName = $PostgresSkuName }
    if ($script:InvocationBoundParameters.ContainsKey('PostgresStorageGB')) { $advanced.postgresStorageGB = $PostgresStorageGB }
    if ($script:InvocationBoundParameters.ContainsKey('PostgresBackupRetentionDays')) { $advanced.postgresBackupRetentionDays = $PostgresBackupRetentionDays }
    if ($SsoEnabled) { $advanced.ssoEnabled = $true }
    if ($SsoOnly) { $advanced.ssoOnly = $true }
    if ($script:InvocationBoundParameters.ContainsKey('SsoAuthority')) { $advanced.ssoAuthority = $SsoAuthority }
    if ($script:InvocationBoundParameters.ContainsKey('SsoClientId')) { $advanced.ssoClientId = $SsoClientId }
    if ($script:InvocationBoundParameters.ContainsKey('SsoScopes')) { $advanced.ssoScopes = $SsoScopes }
    if ($PushEnabled) { $advanced.pushEnabled = $true }
    if ($script:InvocationBoundParameters.ContainsKey('PushInstallationId')) { $advanced.pushInstallationId = $PushInstallationId }
    if ($PushUseEuServers) { $advanced.pushUseEuServers = $true }
    if ($AcsDeployFoundation) { $advanced.acsDeployFoundation = $true }
    if ($script:InvocationBoundParameters.ContainsKey('AcsDataLocation')) { $advanced.acsDataLocation = $AcsDataLocation }
    if ($script:InvocationBoundParameters.ContainsKey('AcsDomainName')) { $advanced.acsDomainName = $AcsDomainName }
    return $advanced
}

$repoRoot = Get-RepoRoot -StartPath $PSScriptRoot
if (-not $CustomersRoot) { $CustomersRoot = Join-Path $repoRoot 'customers' }
$templateFile = Join-Path $repoRoot 'main.json'

$config = $null
$_isInteractive = (
    -not $NonInteractive -and
    [string]::IsNullOrWhiteSpace($CustomerNumber) -and
    -not $Repair -and
    -not $Update
)
$_menuState = @{}
$_menuStack = $null

do {
    if ($_isInteractive) {
        $menuResult = Show-DeploymentMainMenu -MenuState $_menuState -MenuStack $_menuStack
        $_menuState = $menuResult.MenuState
        $_menuStack = $menuResult.MenuStack

        if ($menuResult.ActionId -eq 'Exit') { return }

        $config = $null
        $Repair = $false
        $Update = $false
        $GenerateOnly = $false
        $CustomerNumber = $null

        switch ($menuResult.ActionId) {
            'NewDeployment' {
                $flowResult = Start-NewDeploymentFlow
                $config = $flowResult.Config
            }
            'DeployExisting' {
                $flowResult = Start-DeployExistingFlow -CustomersRoot $CustomersRoot -RepoRoot $repoRoot
                $config = $flowResult.Config
            }
            'EditAndDeploy' {
                $flowResult = Start-EditAndDeployFlow -CustomersRoot $CustomersRoot -RepoRoot $repoRoot
                $config = $flowResult.Config
            }
            'Repair' {
                $flowResult = Start-RepairFlow -CustomersRoot $CustomersRoot
                $Repair = $flowResult.Repair
                $CustomerNumber = $flowResult.CustomerNumber
            }
            'Update' {
                $flowResult = Start-UpdateFlow -CustomersRoot $CustomersRoot
                $Update = $flowResult.Update
                $CustomerNumber = $flowResult.CustomerNumber
            }
            'GenerateOnly' {
                $flowResult = Start-GenerateOnlyFlow
                $GenerateOnly = $flowResult.GenerateOnly
                $config = $flowResult.Config
            }
        }
    }

    # Run the deployment cycle in a child scope so that `return` inside the
    # deployment block exits only this scriptblock (not the entire script),
    # allowing the interactive menu loop to resume after each action.
    $deployResult = & {

if (($Repair -or $Update) -and -not $config) {
    if (-not $CustomerNumber) { throw 'Für Repair/Update muss der Kundenordner oder die Kunden-Nr. angegeben werden.' }
    $pathsForLoad = Get-CustomerPaths -RepoRoot $repoRoot -CustomersRoot $CustomersRoot -CustomerCode $CustomerNumber
    if (-not (Test-Path -LiteralPath $pathsForLoad.ConfigPath)) {
        throw "Kundenkonfiguration nicht gefunden: $($pathsForLoad.ConfigPath)"
    }
    $config = ConvertTo-HashtableDeep -InputObject (Read-JsonFile -Path $pathsForLoad.ConfigPath)
}
elseif (-not $config) {
    if (-not $CustomerNumber) { throw 'Kunden-Nr. ist erforderlich.' }
    if (-not $Mode) { $Mode = 'cloudflare-managed' }
    if (-not $VaultwardenDomain) { throw 'Vaultwarden-Domäne ist erforderlich.' }
    # Normalize domain inputs to lowercase
    $VaultwardenDomain = $VaultwardenDomain.Trim().ToLowerInvariant()
    if (-not $CloudflareZone) { $CloudflareZone = Get-DefaultZoneFromHostname -Hostname $VaultwardenDomain }
    $CloudflareZone = $CloudflareZone.Trim().ToLowerInvariant()
    if (-not $MailRootDomain) { $MailRootDomain = $CloudflareZone }
    $MailRootDomain = $MailRootDomain.Trim().ToLowerInvariant()
    $customerCode = Convert-DomainToSlug -Domain $VaultwardenDomain
    if (-not $ResourceGroupName) { $ResourceGroupName = Get-DefaultResourceGroupName -Environment $Environment -Location $Location -VaultwardenDomain $VaultwardenDomain }
    $effectiveSmtpUseAuth = $SmtpUseAuth.IsPresent
    # Derive effective mail mode from explicit -MailMode or fallback to -SmtpUseAuth switch.
    $effectiveMailMode = if ($MailMode -in @('direct_send', 'smtp_auth', 'acs_smtp')) {
        $MailMode
    } elseif ($effectiveSmtpUseAuth) {
        'smtp_auth'
    } else {
        'direct_send'
    }
    # Re-derive effectiveSmtpUseAuth from effective mail mode (acs_smtp also sets useAuth=true).
    $effectiveSmtpUseAuth = ($effectiveMailMode -ne 'direct_send')
    # Early validation for CLI/NonInteractive path: Direct Send requires explicit smtpHost
    if (-not $effectiveSmtpUseAuth -and [string]::IsNullOrWhiteSpace($SmtpHost)) {
        throw 'Direct Send (SmtpUseAuth nicht gesetzt) erfordert einen expliziten -SmtpHost-Parameter (MX-Endpunkt). MX-Lookup wird zur Deployment-Zeit nicht unterstützt.'
    }
    # acs_smtp: ACS SMTP Username is required
    if ($effectiveMailMode -eq 'acs_smtp' -and [string]::IsNullOrWhiteSpace($SmtpUsername)) {
        throw 'ACS SMTP (MailMode=acs_smtp) erfordert einen expliziten -SmtpUsername-Parameter (ACS SMTP Verbindungszeichenfolge).'
    }
    $effectiveEnableWaf = if ($Mode -eq 'cloudflare-managed') { $EnableWaf.IsPresent -or (-not $script:InvocationBoundParameters.ContainsKey('EnableWaf')) } else { $false }
    $effectiveEnableRateLimit = if ($Mode -eq 'cloudflare-managed') { $EnableRateLimit.IsPresent -or (-not $script:InvocationBoundParameters.ContainsKey('EnableRateLimit')) } else { $false }
    $advanced = Build-AdvancedArmParametersFromCli -ExistingAdvanced (New-EmptyAdvancedArmParameters) -ZoneName $CloudflareZone
    $secretMeta = @{}
    if ($advanced.ssoEnabled) { $secretMeta.ssoClientSecretSource = 'prompt-or-cli' }
    if ($advanced.pushEnabled) { $secretMeta.pushInstallationKeySource = 'prompt-or-cli' }
    $config = New-CustomerConfigObject -CustomerNumber $CustomerNumber -VaultwardenDomain $VaultwardenDomain -ZoneName $CloudflareZone -ResourceGroupName $ResourceGroupName -Environment $Environment -Location $Location -Mode $Mode -MailRootDomain $MailRootDomain -MailMode $effectiveMailMode -SmtpFrom $SmtpFrom -SmtpFromName $SmtpFromName -SmtpHost $SmtpHost -SmtpPort $(if ($SmtpPort) { $SmtpPort } elseif ($effectiveSmtpUseAuth) { '587' } else { '' }) -SmtpSecurity $(if ($SmtpSecurity) { $SmtpSecurity } else { 'starttls' }) -SmtpUsername $SmtpUsername -EnableWaf:$effectiveEnableWaf -EnableRateLimit:$effectiveEnableRateLimit -AdvancedArmParameters $advanced -Secrets $secretMeta
}

if ([string]::IsNullOrWhiteSpace($config.smtp.from)) {
    $config.smtp.from = 'vaultwarden@' + $config.smtp.mailRootDomain
}
$config.metadata.updatedAt = (Get-Date).ToString('o')
$paths = Get-CustomerPaths -RepoRoot $repoRoot -CustomersRoot $CustomersRoot -CustomerCode $config.customerCode
$secureArmParameters = Get-RuntimeSecretParameters -Config $config -NonInteractive:$NonInteractive -GenerateOnly:$GenerateOnly -SmtpPassword $SmtpPassword -SsoClientSecret $SsoClientSecret -PushInstallationKey $PushInstallationKey
Save-CustomerFiles -Config $config -Paths $paths -RepoRoot $repoRoot -SecureArmParameters $secureArmParameters

Write-Section 'Deployment-Zusammenfassung'
Write-Host ('Kundenordner:           {0}' -f $config.customerCode)
Write-Host ('Kunden-Nr.:             {0}' -f $config.customerNumber)
Write-Host ('Resource Group:         {0}' -f $config.azure.resourceGroupName)
Write-Host ('Location:               {0}' -f $config.azure.location)
Write-Host ('Vaultwarden-Domäne:     {0}' -f $config.domain.hostname)
Write-Host ('URL:                    {0}' -f $config.domain.url)
Write-Host ('Modus:                  {0}' -f $config.edge.mode)
Write-Host ('Config:                 {0}' -f $paths.ConfigPath)
Write-Host ('Azure Parameters:       {0}' -f $paths.AzureParametersPath)
Write-Host ('Current Config:         {0}' -f $paths.CurrentConfigPath)
Write-Host ('Current Azure Params:   {0}' -f $paths.CurrentAzureParametersPath)
Write-Host ('Current DTA Wrapper:    {0}' -f $paths.CurrentDeployToAzureTemplatePath)

if ($GenerateOnly) {
    Write-Step 'GenerateOnly aktiv: Dateien wurden geschrieben, Deployment übersprungen.'
    return
}

# --- Preserve existing ACA custom domain state before redeploy ---
# Pre-resolve nested config values into simple scalars for $using: compatibility
# (Start-ThreadJob and Start-Job only support top-level variable references).
$spinnerRgName  = $config.azure.resourceGroupName
$spinnerAcaName = $config.azure.appName
$preservedCustomDomains = Invoke-WithSpinner -Message 'ACA Custom Domain State wird gesichert' -ScriptBlock {
    @(Get-AcaCustomDomains -ResourceGroupName $using:spinnerRgName -AppName $using:spinnerAcaName)
}
# Receive-Job returns $null (not @()) when the job output is an empty array.
# Normalise here so that .Count can be used safely under Set-StrictMode -Version Latest.
if ($null -eq $preservedCustomDomains) { $preservedCustomDomains = @() }
if ($preservedCustomDomains.Count -gt 0) {
    Write-Step ("  {0} vorhandene Custom Domain(s) gefunden und im Config gespeichert." -f $preservedCustomDomains.Count)
    if (-not $config.ContainsKey('preservedInfraState')) { $config.preservedInfraState = [ordered]@{} }
    $config.preservedInfraState.customDomains = @($preservedCustomDomains | ForEach-Object {
        [ordered]@{
            name          = [string]$_.name
            certificateId = if ($null -ne $_.certificateId) { [string]$_.certificateId } else { '' }
        }
    })
    $config.preservedInfraState.customDomainsLastCapturedAt = (Get-Date).ToString('o')
    Save-JsonUtf8 -Data $config -Path $paths.ConfigPath
} else {
    Write-Step '  Keine Custom Domains vorhanden (Neudeployment oder noch nicht konfiguriert).'
}

$deploymentParametersPath = $paths.AzureParametersPath
$tempDeploymentParametersPath = $null
try {
    if ($secureArmParameters -and $secureArmParameters.Count -gt 0) {
        $tempDeploymentParametersPath = Join-Path ([System.IO.Path]::GetTempPath()) ('vaultwarden-arm-params-' + [guid]::NewGuid().ToString('N') + '.json')
        New-CustomerAzureParameters -Config $config -OutputPath $tempDeploymentParametersPath -SecureArmParameters $secureArmParameters -IncludeSecureParameters | Out-Null
        $deploymentParametersPath = $tempDeploymentParametersPath
    }

    $result = & (Join-Path $PSScriptRoot 'Deploy-AzureStack.ps1') -ResourceGroupName $config.azure.resourceGroupName -TemplateFile $templateFile -ParametersFile $deploymentParametersPath -OutputPath $paths.DeployOutputPath
}
finally {
    if ($tempDeploymentParametersPath -and (Test-Path -LiteralPath $tempDeploymentParametersPath)) {
        Remove-Item -LiteralPath $tempDeploymentParametersPath -Force -ErrorAction SilentlyContinue
    }
}

if ($config.edge.mode -eq 'basic') {
    $appNameBasic = if ($result -and $result.properties.outputs.containerAppName.value) { $result.properties.outputs.containerAppName.value } else { $config.azure.appName }
    $envNameBasic = if ($result -and $result.properties.outputs.containerAppEnvironmentName.value) { $result.properties.outputs.containerAppEnvironmentName.value } else { ('{0}-env' -f $config.azure.appName) }
    if ($preservedCustomDomains -and $preservedCustomDomains.Count -gt 0) {
        Restore-AcaCustomDomains -ResourceGroupName $config.azure.resourceGroupName -AppName $appNameBasic -EnvironmentName $envNameBasic -CustomDomains $preservedCustomDomains
    }
    Write-Step 'Basic-Modus abgeschlossen. Kein Cloudflare-Postdeploy ausgeführt.'
    return $result
}

$cfToken = Get-CloudflareTokenValue -CloudflareApiToken $CloudflareApiToken
$appName = $result.properties.outputs.containerAppName.value
$envName = $result.properties.outputs.containerAppEnvironmentName.value
$appFqdn = $result.properties.outputs.containerAppFqdn.value
if (-not $appName) { $appName = $config.azure.appName }
if (-not $envName) { $envName = ('{0}-env' -f $config.azure.appName) }

# Pre-resolve nested config/path values for $using: in Cloudflare spinner scriptblocks.
# Both Start-ThreadJob and Start-Job only support simple top-level $using:varname references.
$spinnerZoneName         = $config.domain.zoneName
$spinnerHostname         = $config.domain.hostname
$spinnerEnableWaf        = $config.edge.enableWaf
$spinnerEnableRl         = $config.edge.enableRateLimit
$spinnerCfStatePath      = $paths.CloudflareStatePath
$spinnerArtifactsRoot    = $paths.ArtifactsRoot
$spinnerConfigPath       = $paths.ConfigPath
$spinnerDeployOutputPath = $paths.DeployOutputPath

$verificationCode = Invoke-WithSpinner -Message 'ACA Verification Code wird abgefragt' -ScriptBlock {
    $code = az containerapp show -g $using:spinnerRgName -n $using:appName --query customDomainVerificationId -o tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($code)) {
        throw 'ACA customDomainVerificationId konnte nicht gelesen werden.'
    }
    $code
}

$cloudflareState = Invoke-WithSpinner -Message 'Cloudflare-Konfiguration wird gesetzt' -ScriptBlock {
    $cfScript   = Join-Path $using:PSScriptRoot 'Set-CloudflareZoneConfig.ps1'
    $token      = $using:cfToken
    $zoneName   = $using:spinnerZoneName
    $hostname   = $using:spinnerHostname
    $originFqdn = $using:appFqdn
    $verCode    = $using:verificationCode
    $enableWaf  = $using:spinnerEnableWaf
    $enableRl   = $using:spinnerEnableRl
    $statePath  = $using:spinnerCfStatePath
    & $cfScript -ApiToken $token -ZoneName $zoneName -Hostname $hostname -OriginTarget $originFqdn -VerificationCode $verCode -EnableWaf:$enableWaf -EnableRateLimit:$enableRl -StatePath $statePath
}
$zoneId = $cloudflareState.zoneId

$bindResult = Invoke-WithSpinner -Message 'Custom Domain Binding wird durchgeführt' -ScriptBlock {
    $bindScript    = Join-Path $using:PSScriptRoot 'Bind-AcaCustomDomain.ps1'
    $token         = $using:cfToken
    $zone          = $using:zoneId
    $hostname      = $using:spinnerHostname
    $resourceGroup = $using:spinnerRgName
    $containerApp  = $using:appName
    $environment   = $using:envName
    $artifacts     = $using:spinnerArtifactsRoot
    & $bindScript -ApiToken $token -ZoneId $zone -Hostname $hostname -ResourceGroupName $resourceGroup -ContainerAppName $containerApp -EnvironmentName $environment -ArtifactsRoot $artifacts
}

Invoke-WithSpinner -Message 'Cloudflare-Proxy wird aktiviert' -ScriptBlock {
    $cfScript   = Join-Path $using:PSScriptRoot 'Set-CloudflareZoneConfig.ps1'
    $token      = $using:cfToken
    $zoneName   = $using:spinnerZoneName
    $hostname   = $using:spinnerHostname
    $originFqdn = $using:appFqdn
    $verCode    = $using:verificationCode
    $enableWaf  = $using:spinnerEnableWaf
    $enableRl   = $using:spinnerEnableRl
    $statePath  = $using:spinnerCfStatePath
    & $cfScript -ApiToken $token -ZoneName $zoneName -Hostname $hostname -OriginTarget $originFqdn -VerificationCode $verCode -EnableWaf:$enableWaf -EnableRateLimit:$enableRl -EnableProxy -StatePath $statePath | Out-Null
} | Out-Null

if (-not $SkipOriginLockdown -and $config.edge.lockOriginToCloudflare) {
    Invoke-WithSpinner -Message 'Origin-Lockdown per Redeploy wird angewendet' -ScriptBlock {
        $restrictScript = Join-Path $using:PSScriptRoot 'Set-AcaIngressRestrictions.ps1'
        $configPath     = $using:spinnerConfigPath
        $template       = $using:templateFile
        $outputPath     = $using:spinnerDeployOutputPath
        & $restrictScript -CustomerConfigPath $configPath -Redeploy -TemplateFile $template -OutputPath $outputPath | Out-Null
    } | Out-Null
}

Write-Step 'Production-Deployment mit Cloudflare abgeschlossen.'
[ordered]@{
    configPath = $paths.ConfigPath
    azureParametersPath = $paths.AzureParametersPath
    deploymentOutputPath = $paths.DeployOutputPath
    cloudflareStatePath = $paths.CloudflareStatePath
    bindResult = $bindResult
}

    } # end deployment scriptblock

    if (-not $_isInteractive) { return $deployResult }

} while ($_isInteractive)
