[CmdletBinding()]
param(
    [string]$CustomerCode,
    [string]$ResourceGroupName,
    [string]$Hostname,
    [string]$ZoneName,
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
    [switch]$SkipOriginLockdown
)

. (Join-Path $PSScriptRoot 'lib/VaultwardenDeployment.Common.ps1')

function New-CustomerConfigObject {
    param(
        [Parameter(Mandatory)][string]$CustomerCode,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$ZoneName,
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
        [bool]$EnableRateLimit = $true
    )

    $safeCustomerCode = ($CustomerCode -replace '[^a-zA-Z0-9]', '').ToLower()
    if ([string]::IsNullOrWhiteSpace($safeCustomerCode)) {
        throw 'CustomerCode muss mindestens ein alphanumerisches Zeichen enthalten.'
    }
    $appName = if ($safeCustomerCode.Length -gt 10) { $safeCustomerCode.Substring(0,10) } else { $safeCustomerCode }
    $url = 'https://' + $Hostname
    [ordered]@{
        customerCode = $CustomerCode
        metadata = [ordered]@{
            createdAt = (Get-Date).ToString('o')
            updatedAt = (Get-Date).ToString('o')
            version = 1
        }
        azure = [ordered]@{
            resourceGroupName = $ResourceGroupName
            location = $Location
            environment = $Environment
            appName = $appName
            edgeMode = if ($Mode -eq 'cloudflare-managed') { 'cloudflare-managed' } else { 'none' }
            enableIngressIpRestrictions = $false
            ingressAllowedCidrs = @()
            advancedArmParameters = @{}
        }
        domain = [ordered]@{
            hostname = $Hostname
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
        }
    }
}

function New-CustomerConfigInteractive {
    Write-Section 'Vaultwarden Customer Deployment Setup'
    Write-Host 'Neues oder bestehendes Kundendeployment.'

    $customerCode = Read-TextWithDefault -Label 'Kundencode' -Required
    $resourceGroupName = Read-TextWithDefault -Label 'Resource Group' -Default ('rg-' + $customerCode + '-vaultwarden') -Required
    $hostname = Read-TextWithDefault -Label 'Hostname' -Default ('vault.' + $customerCode + '.example.com') -Required
    $defaultZone = ($hostname -split '\.', 2)[1]
    $zoneName = Read-TextWithDefault -Label 'Cloudflare Zone' -Default $defaultZone -Required
    $useCloudflare = Read-BooleanWithDefault -Label 'Cloudflare-managed Production Mode verwenden?' -Default $true
    $mode = if ($useCloudflare) { 'cloudflare-managed' } else { 'basic' }
    $location = Read-TextWithDefault -Label 'Azure Region' -Default 'germanywestcentral' -Required
    $environment = Read-TextWithDefault -Label 'Environment (prod/test/dev)' -Default 'prod' -Required
    $mailRootDomain = Read-TextWithDefault -Label 'Mail Root Domain' -Default $zoneName -Required
    $smtpUseAuthValue = Read-BooleanWithDefault -Label 'SMTP Auth verwenden?' -Default $true
    $smtpFrom = Read-TextWithDefault -Label 'SMTP From' -Default ('vaultwarden@' + $mailRootDomain)
    $smtpFromNameValue = Read-TextWithDefault -Label 'SMTP From Name' -Default 'Vaultwarden'
    $smtpHostValue = ''
    $smtpPortValue = ''
    $smtpSecurityValue = 'starttls'
    $smtpUsernameValue = ''
    if ($smtpUseAuthValue) {
        $smtpHostValue = Read-TextWithDefault -Label 'SMTP Host' -Default 'smtp.office365.com' -Required
        $smtpPortValue = Read-TextWithDefault -Label 'SMTP Port' -Default '587' -Required
        $smtpSecurityValue = Read-TextWithDefault -Label 'SMTP Security' -Default 'starttls' -Required
        $smtpUsernameValue = Read-TextWithDefault -Label 'SMTP Username' -Default $smtpFrom -Required
        $script:SmtpPassword = Read-Host -AsSecureString 'SMTP Password'
    }

    $enableWafValue = $true
    $enableRateLimitValue = $true
    if ($mode -eq 'cloudflare-managed') {
        $enableWafValue = Read-BooleanWithDefault -Label 'Cloudflare WAF-Regel für /admin aktivieren?' -Default $true
        $enableRateLimitValue = Read-BooleanWithDefault -Label 'Cloudflare Rate Limit für Login-Endpunkte aktivieren?' -Default $true
    }

    return New-CustomerConfigObject -CustomerCode $customerCode -ResourceGroupName $resourceGroupName -Hostname $hostname -ZoneName $zoneName -Environment $environment -Location $location -Mode $mode -MailRootDomain $mailRootDomain -SmtpUseAuth:$smtpUseAuthValue -SmtpFrom $smtpFrom -SmtpFromName $smtpFromNameValue -SmtpHost $smtpHostValue -SmtpPort $smtpPortValue -SmtpSecurity $smtpSecurityValue -SmtpUsername $smtpUsernameValue -EnableWaf:$enableWafValue -EnableRateLimit:$enableRateLimitValue
}

function New-CustomerAzureParameters {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$OutputPath,
        [SecureString]$SmtpPassword
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
            ingressAllowedCidrs = @{ value = @($Config.azure.ingressAllowedCidrs) }
        }
    }

    if ($Config.smtp.useAuth) {
        $params.parameters.smtpHost = @{ value = $Config.smtp.host }
        $params.parameters.smtpPort = @{ value = $Config.smtp.port }
        $params.parameters.smtpSecurity = @{ value = $Config.smtp.security }
        $params.parameters.smtpUsername = @{ value = $Config.smtp.username }
        if (-not $SmtpPassword) {
            throw 'SMTP Auth ist aktiviert, aber es wurde kein SMTP-Passwort übergeben.'
        }
        $params.parameters.smtpPassword = @{ value = (ConvertFrom-SecureStringPlain -SecureString $SmtpPassword) }
    }

    if ($Config.azure.advancedArmParameters) {
        $overrides = ConvertTo-HashtableDeep -InputObject $Config.azure.advancedArmParameters
        foreach ($key in $overrides.Keys) {
            $params.parameters[$key] = @{ value = $overrides[$key] }
        }
    }

    Save-JsonUtf8 -Data $params -Path $OutputPath
    return $params
}

function Save-CustomerFiles {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][hashtable]$Paths,
        [SecureString]$SmtpPassword
    )
    Ensure-Directory -Path $Paths.CustomerRoot | Out-Null
    Ensure-Directory -Path $Paths.ArtifactsRoot | Out-Null
    Save-JsonUtf8 -Data $Config -Path $Paths.ConfigPath
    New-CustomerAzureParameters -Config $Config -OutputPath $Paths.AzureParametersPath -SmtpPassword $SmtpPassword | Out-Null
    [System.IO.File]::WriteAllText($Paths.CustomerReadmePath, (New-CustomerReadmeContent -Config $Config), [System.Text.UTF8Encoding]::new($false))
}

function Get-CloudflareTokenValue {
    param([string]$CloudflareApiToken)
    if (-not [string]::IsNullOrWhiteSpace($CloudflareApiToken)) { return $CloudflareApiToken }
    if ($env:CLOUDFLARE_API_TOKEN) { return $env:CLOUDFLARE_API_TOKEN }
    $secure = Read-Host -AsSecureString 'Cloudflare API Token'
    return ConvertFrom-SecureStringPlain -SecureString $secure
}

$repoRoot = if ($CustomersRoot) { Split-Path -Parent $CustomersRoot } else { Get-RepoRoot -StartPath $PSScriptRoot }
if (-not $CustomersRoot) { $CustomersRoot = Join-Path $repoRoot 'customers' }
$templateFile = Join-Path $repoRoot 'main.json'

$config = $null
if (-not $NonInteractive -and [string]::IsNullOrWhiteSpace($CustomerCode) -and -not $Repair -and -not $Update) {
    $config = New-CustomerConfigInteractive
}
elseif ($Repair -or $Update) {
    if (-not $CustomerCode) { throw 'Für Repair/Update muss CustomerCode angegeben werden.' }
    $pathsForLoad = Get-CustomerPaths -RepoRoot $repoRoot -CustomerCode $CustomerCode
    if (-not (Test-Path -LiteralPath $pathsForLoad.ConfigPath)) {
        throw "Kundenkonfiguration nicht gefunden: $($pathsForLoad.ConfigPath)"
    }
    $config = ConvertTo-HashtableDeep -InputObject (Read-JsonFile -Path $pathsForLoad.ConfigPath)
}
else {
    if (-not $CustomerCode) { throw 'CustomerCode ist erforderlich.' }
    if (-not $Mode) { $Mode = 'cloudflare-managed' }
    if (-not $ResourceGroupName) { $ResourceGroupName = 'rg-' + $CustomerCode + '-vaultwarden' }
    if (-not $Hostname) { throw 'Hostname ist erforderlich.' }
    if (-not $ZoneName) { throw 'ZoneName ist erforderlich.' }
    if (-not $MailRootDomain) { $MailRootDomain = $ZoneName }
    $effectiveSmtpUseAuth = $SmtpUseAuth.IsPresent
    $effectiveEnableWaf = if ($Mode -eq 'cloudflare-managed') { $EnableWaf.IsPresent -or (-not $PSBoundParameters.ContainsKey('EnableWaf')) } else { $false }
    $effectiveEnableRateLimit = if ($Mode -eq 'cloudflare-managed') { $EnableRateLimit.IsPresent -or (-not $PSBoundParameters.ContainsKey('EnableRateLimit')) } else { $false }
    $config = New-CustomerConfigObject -CustomerCode $CustomerCode -ResourceGroupName $ResourceGroupName -Hostname $Hostname -ZoneName $ZoneName -Environment $Environment -Location $Location -Mode $Mode -MailRootDomain $MailRootDomain -SmtpUseAuth:$effectiveSmtpUseAuth -SmtpFrom $SmtpFrom -SmtpFromName $SmtpFromName -SmtpHost $SmtpHost -SmtpPort $SmtpPort -SmtpSecurity $(if ($SmtpSecurity) { $SmtpSecurity } else { 'starttls' }) -SmtpUsername $SmtpUsername -EnableWaf:$effectiveEnableWaf -EnableRateLimit:$effectiveEnableRateLimit
}

if ([string]::IsNullOrWhiteSpace($config.smtp.from)) {
    $config.smtp.from = 'vaultwarden@' + $config.smtp.mailRootDomain
}
$config.metadata.updatedAt = (Get-Date).ToString('o')
$paths = Get-CustomerPaths -RepoRoot $repoRoot -CustomerCode $config.customerCode

$smtpPasswordToUse = $null
if ($config.smtp.useAuth) {
    if ($SmtpPassword) { $smtpPasswordToUse = $SmtpPassword }
    elseif ($GenerateOnly -and $NonInteractive) { throw 'Für GenerateOnly im SMTP-Auth-Modus muss SmtpPassword übergeben werden.' }
    else { $smtpPasswordToUse = Read-Host -AsSecureString 'SMTP Password' }
}

Save-CustomerFiles -Config $config -Paths $paths -SmtpPassword $smtpPasswordToUse

Write-Section 'Deployment-Zusammenfassung'
Write-Host ('Customer:               {0}' -f $config.customerCode)
Write-Host ('Resource Group:         {0}' -f $config.azure.resourceGroupName)
Write-Host ('Location:               {0}' -f $config.azure.location)
Write-Host ('URL:                    {0}' -f $config.domain.url)
Write-Host ('Modus:                  {0}' -f $config.edge.mode)
Write-Host ('Config:                 {0}' -f $paths.ConfigPath)
Write-Host ('Azure Parameters:       {0}' -f $paths.AzureParametersPath)

if ($GenerateOnly) {
    Write-Step 'GenerateOnly aktiv: Dateien wurden geschrieben, Deployment übersprungen.'
    return
}

$result = & (Join-Path $PSScriptRoot 'Deploy-AzureStack.ps1') -ResourceGroupName $config.azure.resourceGroupName -TemplateFile $templateFile -ParametersFile $paths.AzureParametersPath -OutputPath $paths.DeployOutputPath

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
