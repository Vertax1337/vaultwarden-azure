# Interactive flow functions for the Vaultwarden deployment wizard.
# Contains all interactive wizard helpers (config input, customer picker, ARM parameters)
# and the Start-*Flow action functions routed from Show-DeploymentMainMenu.
# All functions depend on helpers from VaultwardenDeployment.Common.ps1.
# Intended to be dot-sourced only from Invoke-CustomerDeployment.ps1.

function Select-CustomerCodeInteractive {
    param([Parameter(Mandatory)][string]$CustomersRoot)
    $customers = @(Get-AvailableCustomerCodes -CustomersRoot $CustomersRoot)
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
    Write-Host '  [0] Zurück'
    while ($true) {
        $raw = Read-Host 'Auswahl (Nummer oder Ordnername)'
        if ($raw -eq '0') { return $null }
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

# Wizard function – called by Start-NewDeploymentFlow, Start-EditAndDeployFlow, and Start-GenerateOnlyFlow.
# Collects all deployment configuration interactively from the operator.
# Mail-Modus (3 exklusive Zielzustände): direct_send / smtp_auth / acs_smtp.
# Stale-Felder des vorherigen Modus werden durch explizite Initialisierung bereinigt.
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

    # --- Mail-Modus wählen (3 exklusive Zielzustände) ---
    $mailModeChoices = [ordered]@{
        'direct_send' = 'Direct Send (kein Auth, MX-Endpunkt direkt kontaktieren)'
        'smtp_auth'   = 'SMTP Auth (klassisches SMTP Relay mit User/Passwort)'
        'acs_smtp'    = 'ACS SMTP (Azure Communication Services SMTP Relay)'
    }
    $existingMailMode = if ($ExistingConfig) { Get-MailModeFromConfig -Config $ExistingConfig } else { 'smtp_auth' }
    $mailModeValue = Read-ChoiceWithDefault -Label 'Mail-Modus' -Choices $mailModeChoices -DefaultKey $existingMailMode

    $smtpFrom = Read-TextWithDefault -Label 'SMTP From' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.from } else { 'vaultwarden@' + $mailRootDomain }))
    $smtpFromNameValue = Read-TextWithDefault -Label 'SMTP From Name' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.fromName } else { 'Vaultwarden' }))

    # SMTP host prompting depends on mail mode:
    #   smtp_auth:    prompts with default smtp.office365.com (or existing host if editing)
    #   acs_smtp:     smtp.azurecomm.net is auto-set (no prompt)
    #   direct_send:  MX endpoint is always prompted explicitly (no sensible default)
    $smtpHostValue = ''
    $smtpPortValue = ''
    $smtpSecurityValue = 'starttls'
    $smtpUsernameValue = ''

    if ($mailModeValue -eq 'direct_send') {
        # Direct Send: MX lookup is not supported at deployment time (Azure DeploymentScript lacks dig/nslookup).
        # The MX endpoint (MX-Endpunkt) must be provided explicitly here and will be written directly to the parameter file.
        $smtpHostValue = Read-TextWithDefault -Label 'SMTP Host (MX-Endpunkt für Direct Send, z.B. mx01.example-com.mail.protection.outlook.com)' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.host } else { '' })) -Required
    }
    elseif ($mailModeValue -eq 'smtp_auth') {
        # SMTP Auth: prompt for SMTP host with default smtp.office365.com.
        # If an existing smtp_auth config already has a custom host, use that as the default.
        # The operator can override it to use any SMTP relay.
        $existingSmtpHost = if ($ExistingConfig -and (Get-MailModeFromConfig -Config $ExistingConfig) -eq 'smtp_auth') { [string]$ExistingConfig.smtp.host } else { '' }
        $smtpHostDefault = if (-not [string]::IsNullOrWhiteSpace($existingSmtpHost)) { $existingSmtpHost } else { 'smtp.office365.com' }
        $smtpHostValue = Read-TextWithDefault -Label 'SMTP Host (smtp_auth-Relay, z.B. smtp.office365.com)' -Default $smtpHostDefault -Required
        $smtpPortValue = Read-TextWithDefault -Label 'SMTP Port' -Default ([string]$(if ($ExistingConfig -and (Get-MailModeFromConfig -Config $ExistingConfig) -eq 'smtp_auth') { $ExistingConfig.smtp.port } else { '587' })) -Required
        $smtpSecurityValue = Read-TextWithDefault -Label 'SMTP Security' -Default ([string]$(if ($ExistingConfig -and (Get-MailModeFromConfig -Config $ExistingConfig) -eq 'smtp_auth') { $ExistingConfig.smtp.security } else { 'starttls' })) -Required
        $smtpUsernameValue = Read-TextWithDefault -Label 'SMTP Username' -Default ([string]$(if ($ExistingConfig -and (Get-MailModeFromConfig -Config $ExistingConfig) -eq 'smtp_auth') { $ExistingConfig.smtp.username } else { $smtpFrom })) -Required
    }
    else {
        # acs_smtp: smtp.azurecomm.net is auto-set; acsDeployFoundation=true is implied.
        # Prompt only for the ACS-specific username (connection string / access key user).
        $smtpHostValue = 'smtp.azurecomm.net'
        $smtpPortValue = '587'
        $smtpSecurityValue = 'starttls'
        $smtpUsernameValue = Read-TextWithDefault -Label 'ACS SMTP Username (Azure Communication Services Verbindungszeichenfolge)' -Default ([string]$(if ($ExistingConfig -and (Get-MailModeFromConfig -Config $ExistingConfig) -eq 'acs_smtp') { $ExistingConfig.smtp.username } else { '' })) -Required
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
    # ACS Foundation: implied and auto-enabled for acs_smtp mode; prompt for other modes.
    if ($mailModeValue -eq 'acs_smtp') {
        $advancedArm.acsDeployFoundation = $true
    } else {
        $acsDefault = if ($ExistingConfig) { [bool]$advancedArm.acsDeployFoundation } else { $false }
        $advancedArm.acsDeployFoundation = Read-BooleanWithDefault -Label 'ACS Foundation deployen?' -Default $acsDefault
    }

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

    return New-CustomerConfigObject -CustomerNumber $customerNumber -VaultwardenDomain $vaultwardenDomain -ZoneName $zoneName -ResourceGroupName $resourceGroupName -Environment $environment -Location $location -Mode $mode -MailRootDomain $mailRootDomain -MailMode $mailModeValue -SmtpFrom $smtpFrom -SmtpFromName $smtpFromNameValue -SmtpHost $smtpHostValue -SmtpPort $smtpPortValue -SmtpSecurity $smtpSecurityValue -SmtpUsername $smtpUsernameValue -EnableWaf:$enableWafValue -EnableRateLimit:$enableRateLimitValue -AdvancedArmParameters $advancedArm -Secrets $secrets
}

function Start-NewDeploymentFlow {
    [CmdletBinding()]
    param()
    $config = New-CustomerConfigInteractive
    return @{ Config = $config }
}

function Start-DeployExistingFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot,
        [Parameter(Mandatory)][string]$RepoRoot
    )
    [System.Console]::Clear()
    $customerCode = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
    if ($null -eq $customerCode) { return @{ Back = $true } }
    $pathsForLoad = Get-CustomerPaths -RepoRoot $RepoRoot -CustomersRoot $CustomersRoot -CustomerCode $customerCode
    $config = ConvertTo-HashtableDeep -InputObject (Read-JsonFile -Path $pathsForLoad.ConfigPath)
    return @{ Config = $config }
}

function Start-EditAndDeployFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot,
        [Parameter(Mandatory)][string]$RepoRoot
    )
    [System.Console]::Clear()
    $customerCode = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
    if ($null -eq $customerCode) { return @{ Back = $true } }
    $pathsForLoad = Get-CustomerPaths -RepoRoot $RepoRoot -CustomersRoot $CustomersRoot -CustomerCode $customerCode
    $loaded = ConvertTo-HashtableDeep -InputObject (Read-JsonFile -Path $pathsForLoad.ConfigPath)
    $config = New-CustomerConfigInteractive -ExistingConfig $loaded
    return @{ Config = $config }
}

function Start-RepairFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot
    )
    $customerCode = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
    if ($null -eq $customerCode) { return @{ Back = $true } }
    return @{ CustomerNumber = $customerCode; Repair = $true }
}

function Start-UpdateFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot
    )
    $customerCode = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
    if ($null -eq $customerCode) { return @{ Back = $true } }
    return @{ CustomerNumber = $customerCode; Update = $true }
}

function Start-GenerateOnlyFlow {
    [CmdletBinding()]
    param()
    $config = New-CustomerConfigInteractive
    return @{ Config = $config; GenerateOnly = $true }
}
