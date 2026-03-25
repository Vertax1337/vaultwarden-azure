Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    param([string]$StartPath = $PSScriptRoot)
    return (Resolve-Path (Join-Path $StartPath '..' '..')).Path
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
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 50
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
        $list = @()
        foreach ($item in $InputObject) {
            $list += ,(ConvertTo-HashtableDeep -InputObject $item)
        }
        return $list
    }
    return $InputObject
}

function Get-CustomerPaths {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$CustomerCode
    )
    $customerRoot = Join-Path $RepoRoot ('customers/{0}' -f $CustomerCode)
    $artifactsRoot = Join-Path $customerRoot 'artifacts'
    return @{
        CustomerRoot = $customerRoot
        ConfigPath = Join-Path $customerRoot 'deployment.config.json'
        AzureParametersPath = Join-Path $customerRoot 'azure.parameters.json'
        CustomerReadmePath = Join-Path $customerRoot 'README.md'
        ArtifactsRoot = $artifactsRoot
        DeployOutputPath = Join-Path $artifactsRoot 'last-deploy-output.json'
        CloudflareStatePath = Join-Path $artifactsRoot 'cloudflare-state.json'
    }
}

function Get-HostnameFromUrl {
    param([Parameter(Mandatory)][string]$Url)
    $uri = [Uri]$Url
    return $uri.Host
}

function Get-RelativeHostLabel {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$ZoneName
    )
    if ($Hostname -eq $ZoneName) { return '@' }
    $suffix = '.{0}' -f $ZoneName
    if (-not $Hostname.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
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

function New-CustomerReadmeContent {
    param([Parameter(Mandatory)]$Config)
@"
# $($Config.customerCode)

- Resource Group: `$($Config.azure.resourceGroupName)`
- Location: `$($Config.azure.location)`
- URL: `$($Config.domain.url)`
- Edge-Modus: `$($Config.edge.mode)`
- WAF: `$($Config.edge.enableWaf)`
- Rate Limit: `$($Config.edge.enableRateLimit)`
- Origin Lockdown: `$($Config.edge.lockOriginToCloudflare)`

> `deployment.config.json` ist die persistente Kundenkonfiguration.
> `azure.parameters.json` wird pro Deployment neu generiert und kann Secrets enthalten. Deshalb ist diese Datei per `.gitignore` ausgeschlossen.
"@
}
