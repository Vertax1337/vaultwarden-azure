Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    param([string]$StartPath = $PSScriptRoot)
    $current = Resolve-Path $StartPath
    if ($current.Path -and (Test-Path -LiteralPath $current.Path -PathType Leaf)) {
        $current = Split-Path -Parent $current.Path | Resolve-Path
    }
    while ($current) {
        if ((Test-Path -LiteralPath (Join-Path $current.Path 'main.json')) -and (Test-Path -LiteralPath (Join-Path $current.Path 'Readme.md'))) {
            return $current.Path
        }
        $parentPath = Split-Path -Parent $current.Path
        if ([string]::IsNullOrWhiteSpace($parentPath) -or $parentPath -eq $current.Path) { break }
        $current = Resolve-Path $parentPath
    }
    throw 'RepoRoot konnte nicht ermittelt werden.'
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host $Title
    Write-Host ('=' * 72)
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('[+] {0}' -f $Message)
}

function Read-TextWithDefault {
    param(
        [Parameter(Mandatory)][string]$Label,
        [string]$Default = '',
        [switch]$Required
    )
    while ($true) {
        $prompt = if ([string]::IsNullOrWhiteSpace($Default)) { $Label } else { '{0} [{1}]' -f $Label, $Default }
        $value = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
        if ($Required -and [string]::IsNullOrWhiteSpace($value)) {
            Write-Warning ('{0} darf nicht leer sein.' -f $Label)
            continue
        }
        return $value
    }
}

function Read-BooleanWithDefault {
    param(
        [Parameter(Mandatory)][string]$Label,
        [bool]$Default = $true
    )
    $defaultToken = if ($Default) { 'Y/n' } else { 'y/N' }
    while ($true) {
        $raw = Read-Host ('{0} [{1}]' -f $Label, $defaultToken)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        switch -Regex ($raw.Trim()) {
            '^(y|yes|j|ja|1|true)$' { return $true }
            '^(n|no|nein|0|false)$' { return $false }
            default { Write-Warning 'Bitte ja/nein eingeben.' }
        }
    }
}

function Read-ChoiceWithDefault {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][hashtable]$Choices,
        [Parameter(Mandatory)][string]$DefaultKey
    )
    while ($true) {
        Write-Host ''
        Write-Host $Label
        foreach ($key in ($Choices.Keys | Sort-Object)) {
            $marker = if ($key -eq $DefaultKey) { '*' } else { ' ' }
            Write-Host ('  [{0}] {1}{2}' -f $key, $marker, $Choices[$key])
        }
        $selected = Read-Host ('Auswahl [{0}]' -f $DefaultKey)
        if ([string]::IsNullOrWhiteSpace($selected)) { $selected = $DefaultKey }
        $selected = $selected.Trim()
        if ($Choices.ContainsKey($selected)) { return $selected }
        Write-Warning 'Ungültige Auswahl.'
    }
}

function Save-JsonUtf8 {
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][string]$Path,
        [int]$Depth = 20
    )
    $dir = Split-Path -Parent $Path
    if ($dir) { Ensure-Directory -Path $dir | Out-Null }
    $json = $Data | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return $json | ConvertFrom-Json -Depth 50
    }
    return $json | ConvertFrom-Json
}

function ConvertTo-HashtableDeep {
    param([Parameter(Mandatory)]$InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-HashtableDeep -InputObject $InputObject[$key]
        }
        return $hash
    }
    if ($InputObject -is [pscustomobject]) {
        $hash = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $hash[$prop.Name] = ConvertTo-HashtableDeep -InputObject $prop.Value
        }
        return $hash
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = [System.Collections.ArrayList]::new()
        foreach ($item in $InputObject) {
            $list.Add((ConvertTo-HashtableDeep -InputObject $item)) | Out-Null
        }
        return ,$list.ToArray()
    }
    return $InputObject
}

function Convert-DomainToSlug {
    param([Parameter(Mandatory)][string]$Domain)
    $slug = ($Domain.ToLowerInvariant() -replace '[^a-z0-9]+', '-')
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw 'Aus der Vaultwarden-Domäne konnte kein gültiger technischer Slug abgeleitet werden.'
    }
    return $slug
}

function Convert-SlugToAppName {
    param([Parameter(Mandatory)][string]$Slug)
    $appName = (($Slug -replace '[^a-z0-9]', '')).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($appName)) { $appName = 'vault' }
    if ($appName.Length -gt 10) { $appName = $appName.Substring(0, 10) }
    return $appName
}

function Get-DefaultZoneFromHostname {
    param([Parameter(Mandatory)][string]$Hostname)
    $labels = @($Hostname -split '\.')
    if ($labels.Count -le 2) { return $Hostname.ToLowerInvariant() }
    return (($labels | Select-Object -Skip 1) -join '.').ToLowerInvariant()
}

function Get-RegionCode {
    param([Parameter(Mandatory)][string]$Location)
    $normalized = ($Location -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    $known = @{
        germanywestcentral = 'gwc'
        northeurope = 'neu'
        westeurope = 'weu'
        germanynorth = 'gn'
        eastus = 'eus'
        eastus2 = 'eus2'
        westus = 'wus'
        westus2 = 'wus2'
        westus3 = 'wus3'
        centralus = 'cus'
        southcentralus = 'scus'
        uksouth = 'uks'
        ukwest = 'ukw'
        swedencentral = 'swec'
        francecentral = 'frc'
        italynorth = 'itn'
        spaincentral = 'spc'
        polandcentral = 'plc'
        switzerlandnorth = 'chn'
        canadacentral = 'cac'
        austriaeast = 'ate'
    }
    if ($known.ContainsKey($normalized)) { return $known[$normalized] }
    $tokens = [System.Text.RegularExpressions.Regex]::Matches($normalized, '[a-z]+|\d+') | ForEach-Object { $_.Value }
    if ($tokens.Count -eq 0) { return 'loc' }
    $abbr = ($tokens | ForEach-Object {
        if ($_ -match '^\d+$') { $_ }
        elseif ($_.Length -le 3) { $_ }
        else { $_.Substring(0,1) }
    }) -join ''
    if ([string]::IsNullOrWhiteSpace($abbr)) { return 'loc' }
    return $abbr.ToLowerInvariant()
}

function Get-CustomerSlugFromVaultwardenDomain {
    param([Parameter(Mandatory)][string]$VaultwardenDomain)
    $hostname = $VaultwardenDomain.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($hostname)) { return 'vaultwarden' }
    $zoneName = Get-DefaultZoneFromHostname -Hostname $hostname
    $zoneLabels = @($zoneName -split '\.')
    if ($zoneLabels.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($zoneLabels[0])) {
        return Convert-DomainToSlug -Domain $zoneLabels[0]
    }
    return Convert-DomainToSlug -Domain $hostname
}

function Get-DefaultResourceGroupName {
    param(
        [Parameter(Mandatory)][string]$Environment,
        [Parameter(Mandatory)][string]$Location,
        [string]$VaultwardenDomain
    )
    $envPart = ($Environment -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($envPart)) { $envPart = 'prod' }
    $regionPart = Get-RegionCode -Location $Location
    $customerPart = if ([string]::IsNullOrWhiteSpace($VaultwardenDomain)) { 'vaultwarden' } else { Get-CustomerSlugFromVaultwardenDomain -VaultwardenDomain $VaultwardenDomain }
    return ('rg-{0}-vault-{1}-{2}' -f $customerPart, $envPart, $regionPart)
}

function Get-CustomerPaths {
    param(
        [string]$RepoRoot,
        [string]$CustomersRoot,
        [Parameter(Mandatory)][string]$CustomerCode
    )
    if ([string]::IsNullOrWhiteSpace($CustomersRoot)) {
        if ([string]::IsNullOrWhiteSpace($RepoRoot)) { throw 'RepoRoot oder CustomersRoot muss angegeben werden.' }
        $CustomersRoot = Join-Path $RepoRoot 'customers'
    }
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $RepoRoot = Split-Path -Parent $CustomersRoot
    }
    $customerRoot = Join-Path $CustomersRoot $CustomerCode
    $artifactsRoot = Join-Path $customerRoot 'artifacts'
    $currentRoot = Join-Path $RepoRoot 'current'
    return @{
        CustomerRoot = $customerRoot
        ConfigPath = Join-Path $customerRoot 'deployment.config.json'
        AzureParametersPath = Join-Path $customerRoot 'azure.parameters.json'
        CustomerReadmePath = Join-Path $customerRoot 'README.md'
        ArtifactsRoot = $artifactsRoot
        DeployOutputPath = Join-Path $artifactsRoot 'last-deploy-output.json'
        CloudflareStatePath = Join-Path $artifactsRoot 'cloudflare-state.json'
        CurrentRoot = $currentRoot
        CurrentConfigPath = Join-Path $currentRoot 'deployment.config.json'
        CurrentAzureParametersPath = Join-Path $currentRoot 'azure.parameters.json'
        CurrentDeployToAzureTemplatePath = Join-Path $currentRoot 'main.deploytoazure.json'
        CurrentReadmePath = Join-Path $currentRoot 'README.md'
    }
}

function Get-AvailableCustomerCodes {
    param([Parameter(Mandatory)][string]$CustomersRoot)
    if (-not (Test-Path -LiteralPath $CustomersRoot)) { return @() }
    $dirs = Get-ChildItem -LiteralPath $CustomersRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^\.' } |
        Sort-Object Name
    return @($dirs | ForEach-Object { $_.Name })
}

function Get-HostnameFromUrl {
    param([Parameter(Mandatory)][string]$Url)
    $uri = [Uri]$Url
    return $uri.Host
}

function Test-ValidHostnameInZone {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$ZoneName
    )
    if ($Hostname -eq $ZoneName) { return $true }
    $suffix = '.{0}' -f $ZoneName
    return $Hostname.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-RelativeHostLabel {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$ZoneName
    )
    if ($Hostname -eq $ZoneName) { return '@' }
    $suffix = '.{0}' -f $ZoneName
    if (-not (Test-ValidHostnameInZone -Hostname $Hostname -ZoneName $ZoneName)) {
        throw "Hostname '$Hostname' liegt nicht in Zone '$ZoneName'."
    }
    return $Hostname.Substring(0, $Hostname.Length - $suffix.Length)
}

function Get-SubdomainVerificationRecordName {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$ZoneName
    )
    $relative = Get-RelativeHostLabel -Hostname $Hostname -ZoneName $ZoneName
    if ($relative -eq '@') { return 'asuid' }
    return 'asuid.{0}' -f $relative
}

function ConvertFrom-SecureStringPlain {
    param([Parameter(Mandatory)][SecureString]$SecureString)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Convert-CidrsToIngressRestrictions {
    param([Parameter(Mandatory)][string[]]$Cidrs)
    $rules = @()
    foreach ($cidr in $Cidrs) {
        $rules += [ordered]@{
            name = ('allow-' + ($cidr -replace '[:./]', '-'))
            description = ('Allow ' + $cidr)
            ipAddressRange = $cidr
            action = 'Allow'
        }
    }
    return $rules
}

function Normalize-IngressRestrictionParameterValue {
    param([Parameter(Mandatory)]$InputValue)
    $values = @($InputValue)
    if ($values.Count -eq 0) { return @() }
    $first = $values[0]
    if ($first -is [string]) {
        return @(Convert-CidrsToIngressRestrictions -Cidrs @($values))
    }
    return $values
}

function New-RandomPlaintextSecret {
    param([int]$Bytes = 32)
    $buffer = New-Object byte[] $Bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($buffer)
    return [Convert]::ToBase64String($buffer).TrimEnd('=').Replace('+','-').Replace('/','_')
}

function Test-AzCliPresent {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI (az) wurde nicht gefunden.'
    }
}

function Test-OpenSslPresent {
    if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
        throw 'openssl wurde nicht gefunden.'
    }
}

function Invoke-CloudflareApi {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ApiToken,
        $Body,
        [switch]$AllowNotFound
    )
    $base = 'https://api.cloudflare.com/client/v4'
    $headers = @{ Authorization = 'Bearer ' + $ApiToken }
    if ($null -ne $Body) { $headers['Content-Type'] = 'application/json' }
    try {
        if ($null -ne $Body) {
            $payload = $Body | ConvertTo-Json -Depth 20 -Compress
            $response = Invoke-RestMethod -Method $Method -Uri ($base + $Path) -Headers $headers -Body $payload
        }
        else {
            $response = Invoke-RestMethod -Method $Method -Uri ($base + $Path) -Headers $headers
        }
        if (-not $response.success) {
            $message = ($response.errors | ForEach-Object { $_.message }) -join '; '
            throw "Cloudflare API Fehler: $message"
        }
        return $response.result
    }
    catch {
        $statusCode = $null
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
        if ($AllowNotFound -and $statusCode -eq 404) { return $null }
        throw
    }
}

function Get-SuggestedInvitationOrgName {
    param([Parameter(Mandatory)][string]$ZoneName)
    return $ZoneName
}

function Get-SuggestedSignupsDomainsWhitelist {
    param([Parameter(Mandatory)][string]$ZoneName)
    return $ZoneName
}

function New-CustomerReadmeContent {
    param([Parameter(Mandatory)]$Config)
@"
# $($Config.customerCode)

- Kunden-Nr.: `$($Config.customerNumber)`
- Vaultwarden-Domäne: `$($Config.domain.hostname)`
- Resource Group: `$($Config.azure.resourceGroupName)`
- Location: `$($Config.azure.location)`
- URL: `$($Config.domain.url)`
- Edge-Modus: `$($Config.edge.mode)`
- WAF: `$($Config.edge.enableWaf)`
- Rate Limit: `$($Config.edge.enableRateLimit)`
- Origin Lockdown: `$($Config.edge.lockOriginToCloudflare)`

> `deployment.config.json` ist die persistente Kundenkonfiguration.
> `azure.parameters.json` wird pro Deployment neu generiert und kann Secrets enthalten. Deshalb ist diese Datei per `.gitignore` ausgeschlossen.
> Erweiterte ARM-Parameter stehen unter `azure.advancedArmParameters` in der Kundenkonfiguration.
"@
}
