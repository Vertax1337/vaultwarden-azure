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
    [string]$StorageAccountSku,
    [string]$PostgresSkuName,
    [int]$PostgresStorageGB,
    [int]$PostgresBackupRetentionDays
)

. (Join-Path $PSScriptRoot 'lib/VaultwardenDeployment.Common.ps1')
$script:InvocationBoundParameters = $PSBoundParameters

function Get-AdvancedParameterValue {
    param([hashtable]$Advanced, [string]$Name, $Default = $null)
    if ($Advanced -and $Advanced.ContainsKey($Name)) { return $Advanced[$Name] }
    return $Default
}

function New-EmptyAdvancedArmParameters {
    return [ordered]@{
        adminPanelEnabled = $true
        invitationOrgName = ''
        signupsDomainsWhitelist = ''
        orgCreationUsers = ''
        diagnosticsEnabled = $true
        allowInsecureHttp = $true
        ssoEnabled = $false
        ssoOnly = $false
        ssoAuthority = ''
        ssoClientId = ''
        ssoScopes = 'openid profile email offline_access User.Read'
        pushEnabled = $false
        pushInstallationId = ''
        pushUseEuServers = $false
        acsDeployFoundation = $false
        acsDataLocation = 'Germany'
        acsDomainName = ''
        storageAccountSku = 'Standard_LRS'
        postgresSkuName = 'Standard_B1ms'
        postgresStorageGB = 32
        postgresBackupRetentionDays = 14
        allowAzureServicesToPostgres = $true
    }
}

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
            useAuth = [bool]$SmtpUseAuth
            mailRootDomain = $MailRootDomain
            from = $SmtpFrom
            fromName = $SmtpFromName
            host = $SmtpHost
            port = $SmtpPort
            security = $SmtpSecurity
            username = $SmtpUsername
            passwordSource = if ($SmtpUseAuth) { 'prompt' } else { 'none' }
        }
        secrets = [ordered]@{
            smtpPasswordSource = if ($SmtpUseAuth) { 'prompt' } else { 'none' }
            cloudflareApiTokenSource = if ($Mode -eq 'cloudflare-managed') { 'prompt-or-env' } else { 'not-required' }
            ssoClientSecretSource = if ($Secrets.ContainsKey('ssoClientSecretSource')) { $Secrets.ssoClientSecretSource } else { 'none' }
            pushInstallationKeySource = if ($Secrets.ContainsKey('pushInstallationKeySource')) { $Secrets.pushInstallationKeySource } else { 'none' }
        }
    }
}

function Get-InteractiveAction {
    $choices = [ordered]@{
        '1' = 'Neues Kundendeployment anlegen und deployen'
        '2' = 'Vorhandene Konfiguration deployen'
        '3' = 'Vorhandene Konfiguration bearbeiten und deployen'
        '4' = 'Repair mit vorhandener Konfiguration'
        '5' = 'Update mit vorhandener Konfiguration'
        '6' = 'Nur Kunden-/Parameterdateien erzeugen'
        '0' = 'Beenden'
    }
    return Read-ChoiceWithDefault -Label 'Aktion wählen' -Choices $choices -DefaultKey '1'
}

function Select-CustomerCodeInteractive {
    param([Parameter(Mandatory)][string]$CustomersRoot)
    $customers = Get-AvailableCustomerCodes -CustomersRoot $CustomersRoot
    if ($customers.Count -eq 0) {
        throw 'Keine vorhandenen Kundenkonfigurationen gefunden.'
    }
    Write-Host ''
    Write-Host 'Vorhandene Kundenkonfigurationen:'
    for ($i = 0; $i -lt $customers.Count; $i++) {
        $cfgPath = Join-Path (Join-Path $CustomersRoot $customers[$i]) 'deployment.config.json'
        $display = $customers[$i]
        if (Test-Path -LiteralPath $cfgPath) {
            try {
                $cfg = Read-JsonFile -Path $cfgPath
                $display = '{0}  |  Kunden-Nr.: {1}  |  Domäne: {2}' -f $customers[$i], $cfg.customerNumber, $cfg.domain.hostname
            } catch { }
        }
        Write-Host ('  [{0}] {1}' -f ($i + 1), $display)
    }
    while ($true) {
        $raw = Read-Host 'Auswahl (Nummer oder Ordnername)'
        if ($raw -match '^\d+$') {
            $idx = [int]$raw - 1
            if ($idx -ge 0 -and $idx -lt $customers.Count) { return $customers[$idx] }
        }
        if ($customers -contains $raw) { return $raw }
        Write-Warning 'Ungültige Auswahl.'
    }
}

function New-AdvancedArmParametersInteractive {
    param(
        [hashtable]$ExistingAdvanced,
        [Parameter(Mandatory)][string]$ZoneName
    )
    $advancedInput = if ($ExistingAdvanced) { $ExistingAdvanced } else { New-EmptyAdvancedArmParameters }
    $advanced = ConvertTo-HashtableDeep -InputObject $advancedInput

    $advanced.adminPanelEnabled = Read-BooleanWithDefault -Label 'Admin Panel für Bootstrap aktiv?' -Default ([bool](Get-AdvancedParameterValue -Advanced $advanced -Name 'adminPanelEnabled' -Default $true))
    $advanced.invitationOrgName = Read-TextWithDefault -Label 'Invitation Org Name' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'invitationOrgName' -Default (Get-SuggestedInvitationOrgName -ZoneName $ZoneName)))
    $advanced.signupsDomainsWhitelist = Read-TextWithDefault -Label 'Signups Domains Whitelist' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'signupsDomainsWhitelist' -Default (Get-SuggestedSignupsDomainsWhitelist -ZoneName $ZoneName)))
    $advanced.orgCreationUsers = Read-TextWithDefault -Label 'Org Creation Users' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'orgCreationUsers' -Default ''))
    $advanced.diagnosticsEnabled = Read-BooleanWithDefault -Label 'Diagnostics aktiv?' -Default ([bool](Get-AdvancedParameterValue -Advanced $advanced -Name 'diagnosticsEnabled' -Default $true))
    # allowInsecureHttp is always true (ACA handles TLS at the edge)
    $advanced.allowInsecureHttp = $true
    $advanced.storageAccountSku = Read-TextWithDefault -Label 'Storage Account SKU' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'storageAccountSku' -Default 'Standard_LRS')) -Required
    $advanced.postgresSkuName = Read-TextWithDefault -Label 'PostgreSQL SKU' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'postgresSkuName' -Default 'Standard_B1ms')) -Required
    $advanced.postgresStorageGB = [int](Read-TextWithDefault -Label 'PostgreSQL Storage GB' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'postgresStorageGB' -Default '32')) -Required)
    $advanced.postgresBackupRetentionDays = [int](Read-TextWithDefault -Label 'PostgreSQL Backup Retention Days' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'postgresBackupRetentionDays' -Default '14')) -Required)
    # allowAzureServicesToPostgres is always true in the standard path (no VNet/NAT)
    $advanced.allowAzureServicesToPostgres = $true

    if ($advanced.ssoEnabled) {
        $advanced.ssoOnly = Read-BooleanWithDefault -Label 'SSO Only aktivieren?' -Default ([bool](Get-AdvancedParameterValue -Advanced $advanced -Name 'ssoOnly' -Default $false))
        $advanced.ssoAuthority = Read-TextWithDefault -Label 'SSO Authority' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'ssoAuthority' -Default '')) -Required
        $advanced.ssoClientId = Read-TextWithDefault -Label 'SSO Client ID' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'ssoClientId' -Default '')) -Required
        $advanced.ssoScopes = Read-TextWithDefault -Label 'SSO Scopes' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'ssoScopes' -Default 'openid profile email offline_access User.Read')) -Required
    }
    else {
        $advanced.ssoOnly = $false
        $advanced.ssoAuthority = ''
        $advanced.ssoClientId = ''
        $advanced.ssoScopes = 'openid profile email offline_access User.Read'
    }

    if ($advanced.pushEnabled) {
        $advanced.pushInstallationId = Read-TextWithDefault -Label 'Push Installation ID' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'pushInstallationId' -Default '')) -Required
        $advanced.pushUseEuServers = Read-BooleanWithDefault -Label 'EU Push Server verwenden?' -Default ([bool](Get-AdvancedParameterValue -Advanced $advanced -Name 'pushUseEuServers' -Default $false))
    }
    else {
        $advanced.pushInstallationId = ''
        $advanced.pushUseEuServers = $false
    }

    if ($advanced.acsDeployFoundation) {
        $advanced.acsDataLocation = Read-TextWithDefault -Label 'ACS Data Location' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'acsDataLocation' -Default 'Germany')) -Required
        $advanced.acsDomainName = Read-TextWithDefault -Label 'ACS Domain Name' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'acsDomainName' -Default ''))
    }
    else {
        $advanced.acsDomainName = ''
        $advanced.acsDataLocation = 'Germany'
    }

    return $advanced
}

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

function New-CustomerConfigInteractive {
    param([hashtable]$ExistingConfig)

    Write-Section 'Vaultwarden Customer Deployment Setup'

    $customerNumber = Read-TextWithDefault -Label 'Kunden-Nr.' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.customerNumber } else { '' })) -Required
    $defaultDomain = if ($ExistingConfig) { $ExistingConfig.domain.hostname } else { 'vault.example.com' }
    $vaultwardenDomain = (Read-TextWithDefault -Label 'Vaultwarden-Domäne' -Default $defaultDomain -Required).Trim().ToLowerInvariant()
    $zoneName = (Read-TextWithDefault -Label 'Cloudflare Zone' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.domain.zoneName } else { Get-DefaultZoneFromHostname -Hostname $vaultwardenDomain })) -Required).Trim().ToLowerInvariant()
    if (-not (Test-ValidHostnameInZone -Hostname $vaultwardenDomain -ZoneName $zoneName)) {
        throw "Vaultwarden-Domäne '$vaultwardenDomain' passt nicht zur Zone '$zoneName'."
    }
    $customerCode = Convert-DomainToSlug -Domain $vaultwardenDomain
    $location = Read-TextWithDefault -Label 'Azure Region' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.azure.location } else { 'germanywestcentral' })) -Required
    $environment = Read-TextWithDefault -Label 'Environment (prod/test/dev)' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.azure.environment } else { 'prod' })) -Required
    $resourceGroupDefault = if ($ExistingConfig) { $ExistingConfig.azure.resourceGroupName } else { Get-DefaultResourceGroupName -Environment $environment -Location $location -VaultwardenDomain $vaultwardenDomain }
    $resourceGroupName = Read-TextWithDefault -Label 'Resource Group' -Default ([string]$resourceGroupDefault) -Required

    $currentMode = if ($ExistingConfig) { $ExistingConfig.edge.mode } else { 'cloudflare-managed' }
    $useCloudflare = Read-BooleanWithDefault -Label 'Cloudflare-managed Production Mode verwenden?' -Default ($currentMode -eq 'cloudflare-managed')
    $mode = if ($useCloudflare) { 'cloudflare-managed' } else { 'basic' }
    $mailRootDomain = (Read-TextWithDefault -Label 'Mail Root Domain' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.mailRootDomain } else { $zoneName })) -Required).Trim().ToLowerInvariant()
    $smtpUseAuthValue = Read-BooleanWithDefault -Label 'SMTP Auth verwenden?' -Default ([bool]$(if ($ExistingConfig) { $ExistingConfig.smtp.useAuth } else { $true }))
    $smtpFrom = Read-TextWithDefault -Label 'SMTP From' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.from } else { 'vaultwarden@' + $mailRootDomain }))
    $smtpFromNameValue = Read-TextWithDefault -Label 'SMTP From Name' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.fromName } else { 'Vaultwarden' }))
    # SMTP Auth: SMTP Host is NOT prompted in the main wizard flow.
    # The default (smtp.office365.com) is used unless the existing config already has a custom host.
    # To override, supply -SmtpHost via CLI or edit the deployment.config.json manually.
    # Direct Send: SMTP Host (MX endpoint) is always prompted explicitly - it is mandatory and cannot be defaulted.
    $smtpHostValue = ''
    $smtpPortValue = ''
    $smtpSecurityValue = 'starttls'
    $smtpUsernameValue = ''
    if ($smtpUseAuthValue) {
        # SMTP Auth: silently preserve existing host or default to smtp.office365.com.
        # No interactive prompt for host in the main wizard path.
        $existingSmtpHost = if ($ExistingConfig) { [string]$ExistingConfig.smtp.host } else { '' }
        $smtpHostValue = if (-not [string]::IsNullOrWhiteSpace($existingSmtpHost)) { $existingSmtpHost } else { 'smtp.office365.com' }
        $smtpPortValue = Read-TextWithDefault -Label 'SMTP Port' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.port } else { '587' })) -Required
        $smtpSecurityValue = Read-TextWithDefault -Label 'SMTP Security' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.security } else { 'starttls' })) -Required
        $smtpUsernameValue = Read-TextWithDefault -Label 'SMTP Username' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.username } else { $smtpFrom })) -Required
    }
    else {
        # Direct Send: MX lookup is not supported at deployment time (Azure DeploymentScript lacks dig/nslookup).
        # The MX endpoint must be provided explicitly here and will be written directly to the parameter file.
        $smtpHostValue = Read-TextWithDefault -Label 'SMTP Host (MX-Endpunkt für Direct Send, z.B. mx01.example-com.mail.protection.outlook.com)' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.host } else { '' })) -Required
    }

    $enableWafValue = if ($ExistingConfig) { [bool]$ExistingConfig.edge.enableWaf } else { $true }
    $enableRateLimitValue = if ($ExistingConfig) { [bool]$ExistingConfig.edge.enableRateLimit } else { $true }
    if ($mode -eq 'cloudflare-managed') {
        $enableWafValue = Read-BooleanWithDefault -Label 'Cloudflare WAF-Regel für /admin aktivieren?' -Default $enableWafValue
        $enableRateLimitValue = Read-BooleanWithDefault -Label 'Cloudflare Rate Limit für Login-Endpunkte aktivieren?' -Default $enableRateLimitValue
    }

    $advancedArm = if ($ExistingConfig) { ConvertTo-HashtableDeep -InputObject $ExistingConfig.azure.advancedArmParameters } else { New-EmptyAdvancedArmParameters }
    $ssoDefault = if ($ExistingConfig) { [bool]$advancedArm.ssoEnabled } else { $true }
    $advancedArm.ssoEnabled = Read-BooleanWithDefault -Label 'SSO aktivieren?' -Default $ssoDefault
    $pushDefault = if ($ExistingConfig) { [bool]$advancedArm.pushEnabled } else { $true }
    $advancedArm.pushEnabled = Read-BooleanWithDefault -Label 'Push aktivieren?' -Default $pushDefault
    $acsDefault = if ($ExistingConfig) { [bool]$advancedArm.acsDeployFoundation } else { $true }
    $advancedArm.acsDeployFoundation = Read-BooleanWithDefault -Label 'ACS Foundation deployen?' -Default $acsDefault

    $existingOrAdvancedDefault = ($null -ne $ExistingConfig) -or $advancedArm.ssoEnabled -or $advancedArm.pushEnabled -or $advancedArm.acsDeployFoundation
    $editAdvanced = Read-BooleanWithDefault -Label 'Erweiterte Template-Optionen bearbeiten?' -Default $existingOrAdvancedDefault
    if ($editAdvanced) {
        $advancedArm = New-AdvancedArmParametersInteractive -ExistingAdvanced $advancedArm -ZoneName $zoneName
    }
    else {
        if ([string]::IsNullOrWhiteSpace([string]$advancedArm.invitationOrgName)) { $advancedArm.invitationOrgName = Get-SuggestedInvitationOrgName -ZoneName $zoneName }
        if ([string]::IsNullOrWhiteSpace([string]$advancedArm.signupsDomainsWhitelist)) { $advancedArm.signupsDomainsWhitelist = Get-SuggestedSignupsDomainsWhitelist -ZoneName $zoneName }
        if (-not $advancedArm.ssoEnabled) {
            $advancedArm.ssoOnly = $false
            $advancedArm.ssoAuthority = ''
            $advancedArm.ssoClientId = ''
            $advancedArm.ssoScopes = 'openid profile email offline_access User.Read'
        }
        if (-not $advancedArm.pushEnabled) {
            $advancedArm.pushInstallationId = ''
            $advancedArm.pushUseEuServers = $false
        }
        if (-not $advancedArm.acsDeployFoundation) {
            $advancedArm.acsDomainName = ''
            $advancedArm.acsDataLocation = 'Germany'
        }
    }

    $secrets = @{}
    if ($advancedArm.ssoEnabled) { $secrets.ssoClientSecretSource = 'prompt' }
    if ($advancedArm.pushEnabled) { $secrets.pushInstallationKeySource = 'prompt' }

    return New-CustomerConfigObject -CustomerNumber $customerNumber -VaultwardenDomain $vaultwardenDomain -ZoneName $zoneName -ResourceGroupName $resourceGroupName -Environment $environment -Location $location -Mode $mode -MailRootDomain $mailRootDomain -SmtpUseAuth:$smtpUseAuthValue -SmtpFrom $smtpFrom -SmtpFromName $smtpFromNameValue -SmtpHost $smtpHostValue -SmtpPort $smtpPortValue -SmtpSecurity $smtpSecurityValue -SmtpUsername $smtpUsernameValue -EnableWaf:$enableWafValue -EnableRateLimit:$enableRateLimitValue -AdvancedArmParameters $advancedArm -Secrets $secrets
}

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
$action = $null
if (-not $NonInteractive -and [string]::IsNullOrWhiteSpace($CustomerNumber) -and -not $Repair -and -not $Update) {
    $action = Get-InteractiveAction
    switch ($action) {
        '0' { return }
        '1' { $config = New-CustomerConfigInteractive }
        '2' {
            $customerCode = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
            $pathsForLoad = Get-CustomerPaths -RepoRoot $repoRoot -CustomersRoot $CustomersRoot -CustomerCode $customerCode
            $config = ConvertTo-HashtableDeep -InputObject (Read-JsonFile -Path $pathsForLoad.ConfigPath)
        }
        '3' {
            $customerCode = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
            $pathsForLoad = Get-CustomerPaths -RepoRoot $repoRoot -CustomersRoot $CustomersRoot -CustomerCode $customerCode
            $loaded = ConvertTo-HashtableDeep -InputObject (Read-JsonFile -Path $pathsForLoad.ConfigPath)
            $config = New-CustomerConfigInteractive -ExistingConfig $loaded
        }
        '4' {
            $Repair = $true
            $CustomerNumber = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
        }
        '5' {
            $Update = $true
            $CustomerNumber = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
        }
        '6' {
            $GenerateOnly = $true
            $config = New-CustomerConfigInteractive
        }
    }
}

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
    # Early validation for CLI/NonInteractive path: Direct Send requires explicit smtpHost
    if (-not $effectiveSmtpUseAuth -and [string]::IsNullOrWhiteSpace($SmtpHost)) {
        throw 'Direct Send (SmtpUseAuth nicht gesetzt) erfordert einen expliziten -SmtpHost-Parameter (MX-Endpunkt). MX-Lookup wird zur Deployment-Zeit nicht unterstützt.'
    }
    $effectiveEnableWaf = if ($Mode -eq 'cloudflare-managed') { $EnableWaf.IsPresent -or (-not $script:InvocationBoundParameters.ContainsKey('EnableWaf')) } else { $false }
    $effectiveEnableRateLimit = if ($Mode -eq 'cloudflare-managed') { $EnableRateLimit.IsPresent -or (-not $script:InvocationBoundParameters.ContainsKey('EnableRateLimit')) } else { $false }
    $advanced = Build-AdvancedArmParametersFromCli -ExistingAdvanced (New-EmptyAdvancedArmParameters) -ZoneName $CloudflareZone
    $secretMeta = @{}
    if ($advanced.ssoEnabled) { $secretMeta.ssoClientSecretSource = 'prompt-or-cli' }
    if ($advanced.pushEnabled) { $secretMeta.pushInstallationKeySource = 'prompt-or-cli' }
    $config = New-CustomerConfigObject -CustomerNumber $CustomerNumber -VaultwardenDomain $VaultwardenDomain -ZoneName $CloudflareZone -ResourceGroupName $ResourceGroupName -Environment $Environment -Location $Location -Mode $Mode -MailRootDomain $MailRootDomain -SmtpUseAuth:$effectiveSmtpUseAuth -SmtpFrom $SmtpFrom -SmtpFromName $SmtpFromName -SmtpHost $SmtpHost -SmtpPort $(if ($SmtpPort) { $SmtpPort } else { '587' }) -SmtpSecurity $(if ($SmtpSecurity) { $SmtpSecurity } else { 'starttls' }) -SmtpUsername $SmtpUsername -EnableWaf:$effectiveEnableWaf -EnableRateLimit:$effectiveEnableRateLimit -AdvancedArmParameters $advanced -Secrets $secretMeta
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
    Write-Step 'Basic-Modus abgeschlossen. Kein Cloudflare-Postdeploy ausgeführt.'
    return $result
}

$cfToken = Get-CloudflareTokenValue -CloudflareApiToken $CloudflareApiToken
$appName = $result.properties.outputs.containerAppName.value
$envName = $result.properties.outputs.containerAppEnvironmentName.value
$appFqdn = $result.properties.outputs.containerAppFqdn.value
if (-not $appName) { $appName = $config.azure.appName }
if (-not $envName) { $envName = ('{0}-env' -f $config.azure.appName) }

Write-Step 'ACA Verification Code wird abgefragt.'
$verificationCode = az containerapp show -g $config.azure.resourceGroupName -n $appName --query customDomainVerificationId -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($verificationCode)) {
    throw 'ACA customDomainVerificationId konnte nicht gelesen werden.'
}

$cloudflareState = & (Join-Path $PSScriptRoot 'Set-CloudflareZoneConfig.ps1') -ApiToken $cfToken -ZoneName $config.domain.zoneName -Hostname $config.domain.hostname -OriginTarget $appFqdn -VerificationCode $verificationCode -EnableWaf:$config.edge.enableWaf -EnableRateLimit:$config.edge.enableRateLimit -StatePath $paths.CloudflareStatePath
$zoneId = $cloudflareState.zoneId
$bindResult = & (Join-Path $PSScriptRoot 'Bind-AcaCustomDomain.ps1') -ApiToken $cfToken -ZoneId $zoneId -Hostname $config.domain.hostname -ResourceGroupName $config.azure.resourceGroupName -ContainerAppName $appName -EnvironmentName $envName -ArtifactsRoot $paths.ArtifactsRoot
& (Join-Path $PSScriptRoot 'Set-CloudflareZoneConfig.ps1') -ApiToken $cfToken -ZoneName $config.domain.zoneName -Hostname $config.domain.hostname -OriginTarget $appFqdn -VerificationCode $verificationCode -EnableWaf:$config.edge.enableWaf -EnableRateLimit:$config.edge.enableRateLimit -EnableProxy -StatePath $paths.CloudflareStatePath | Out-Null

if (-not $SkipOriginLockdown -and $config.edge.lockOriginToCloudflare) {
    Write-Step 'Cloudflare-Origin-Lockdown wird per ARM-Parameter und Redeploy angewendet.'
    & (Join-Path $PSScriptRoot 'Set-AcaIngressRestrictions.ps1') -CustomerConfigPath $paths.ConfigPath -Redeploy -TemplateFile $templateFile -OutputPath $paths.DeployOutputPath | Out-Null
}

Write-Step 'Production-Deployment mit Cloudflare abgeschlossen.'
[ordered]@{
    configPath = $paths.ConfigPath
    azureParametersPath = $paths.AzureParametersPath
    deploymentOutputPath = $paths.DeployOutputPath
    cloudflareStatePath = $paths.CloudflareStatePath
    bindResult = $bindResult
}
