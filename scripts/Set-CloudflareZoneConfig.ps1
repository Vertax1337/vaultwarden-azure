[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ApiToken,
    [Parameter(Mandatory)][string]$ZoneName,
    [Parameter(Mandatory)][string]$Hostname,
    [Parameter(Mandatory)][string]$OriginTarget,
    [Parameter(Mandatory)][string]$VerificationCode,
    [bool]$EnableWaf = $true,
    [bool]$EnableRateLimit = $true,
    [switch]$EnableProxy,
    [string]$StatePath
)

. (Join-Path $PSScriptRoot 'lib/VaultwardenDeployment.Common.ps1')

function Resolve-ZoneId {
    param([string]$ApiToken,[string]$ZoneName)
    $zones = Invoke-CloudflareApi -Method GET -Path ('/zones?name={0}' -f [Uri]::EscapeDataString($ZoneName)) -ApiToken $ApiToken
    if (-not $zones -or $zones.Count -lt 1) { throw "Cloudflare-Zone '$ZoneName' wurde nicht gefunden." }
    return $zones[0].id
}

function Set-DnsRecord {
    param([string]$ApiToken,[string]$ZoneId,[string]$Type,[string]$Name,[string]$Content,[bool]$Proxied = $false,[int]$Ttl = 1)
    $query = '/zones/{0}/dns_records?type={1}&name={2}' -f $ZoneId, [Uri]::EscapeDataString($Type), [Uri]::EscapeDataString($Name)
    $existing = Invoke-CloudflareApi -Method GET -Path $query -ApiToken $ApiToken
    $body = @{ type = $Type; name = $Name; content = $Content; ttl = $Ttl }
    if ($Type -in @('CNAME','A','AAAA')) { $body.proxied = $Proxied }
    if ($existing -and $existing.Count -gt 0) {
        $id = $existing[0].id
        return Invoke-CloudflareApi -Method PUT -Path ('/zones/{0}/dns_records/{1}' -f $ZoneId, $id) -ApiToken $ApiToken -Body $body
    }
    return Invoke-CloudflareApi -Method POST -Path ('/zones/{0}/dns_records' -f $ZoneId) -ApiToken $ApiToken -Body $body
}

function Set-ZoneSetting {
    param([string]$ApiToken,[string]$ZoneId,[string]$SettingId,[string]$Value)
    return Invoke-CloudflareApi -Method PATCH -Path ('/zones/{0}/settings/{1}' -f $ZoneId, $SettingId) -ApiToken $ApiToken -Body @{ value = $Value }
}

function Set-PhaseRuleset {
    param([string]$ApiToken,[string]$ZoneId,[string]$Phase,[array]$Rules)
    $existing = Invoke-CloudflareApi -Method GET -Path ('/zones/{0}/rulesets/phases/{1}/entrypoint' -f $ZoneId, $Phase) -ApiToken $ApiToken -AllowNotFound
    if ($null -eq $existing) {
        $body = @{
            name = 'BSSE Managed Entry Point'
            description = 'BSSE managed zone-level phase entry point'
            kind = 'zone'
            phase = $Phase
            rules = $Rules
        }
        return Invoke-CloudflareApi -Method POST -Path ('/zones/{0}/rulesets' -f $ZoneId) -ApiToken $ApiToken -Body $body
    }
    $body = @{
        id = $existing.id
        name = $existing.name
        description = $existing.description
        kind = $existing.kind
        phase = $existing.phase
        rules = $Rules
    }
    return Invoke-CloudflareApi -Method PUT -Path ('/zones/{0}/rulesets/phases/{1}/entrypoint' -f $ZoneId, $Phase) -ApiToken $ApiToken -Body $body
}


function Merge-ManagedRules {
    param(
        [array]$ExistingRules,
        [array]$ManagedRules,
        [string]$ManagedPrefix = 'BSSE Managed - '
    )
    $preserved = @()
    foreach ($rule in @($ExistingRules)) {
        if ($null -eq $rule.description -or -not ([string]$rule.description).StartsWith($ManagedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $preserved += $rule
        }
    }
    return @($preserved + @($ManagedRules))
}

$zoneId = Resolve-ZoneId -ApiToken $ApiToken -ZoneName $ZoneName
$txtName = Get-SubdomainVerificationRecordName -Hostname $Hostname -ZoneName $ZoneName

Write-Step 'Cloudflare-DNS wird konfiguriert.'
Set-DnsRecord -ApiToken $ApiToken -ZoneId $zoneId -Type 'CNAME' -Name $Hostname -Content $OriginTarget -Proxied:$EnableProxy | Out-Null
Set-DnsRecord -ApiToken $ApiToken -ZoneId $zoneId -Type 'TXT' -Name $txtName -Content $VerificationCode | Out-Null

if ($EnableProxy) {
    Write-Step 'Cloudflare SSL-Modus wird auf strict gesetzt.'
    Set-ZoneSetting -ApiToken $ApiToken -ZoneId $zoneId -SettingId 'ssl' -Value 'strict' | Out-Null
}


$customEntry = Invoke-CloudflareApi -Method GET -Path ('/zones/{0}/rulesets/phases/http_request_firewall_custom/entrypoint' -f $zoneId) -ApiToken $ApiToken -AllowNotFound
if ($EnableWaf) {
    Write-Step 'Cloudflare Custom Rule für /admin wird gesetzt.'
    $rule = @{
        action = 'managed_challenge'
        expression = '(http.request.uri.path starts_with "/admin")'
        description = 'BSSE Managed - Protect Vaultwarden admin path'
        enabled = $true
    }
    $merged = Merge-ManagedRules -ExistingRules $customEntry.rules -ManagedRules @($rule)
    Set-PhaseRuleset -ApiToken $ApiToken -ZoneId $zoneId -Phase 'http_request_firewall_custom' -Rules $merged | Out-Null
}
elseif ($customEntry) {
    $merged = Merge-ManagedRules -ExistingRules $customEntry.rules -ManagedRules @()
    Set-PhaseRuleset -ApiToken $ApiToken -ZoneId $zoneId -Phase 'http_request_firewall_custom' -Rules $merged | Out-Null
}

$rateEntry = Invoke-CloudflareApi -Method GET -Path ('/zones/{0}/rulesets/phases/http_ratelimit/entrypoint' -f $zoneId) -ApiToken $ApiToken -AllowNotFound
if ($EnableRateLimit) {
    Write-Step 'Cloudflare Rate Limit wird gesetzt.'
    $rule = @{
        action = 'block'
        expression = '(http.request.uri.path eq "/identity/accounts/prelogin") or (http.request.uri.path eq "/identity/connect/token")'
        description = 'BSSE Managed - Vaultwarden login rate limit'
        enabled = $true
        ratelimit = @{
            characteristics = @('cf.colo.id','ip.src')
            period = 60
            requests_per_period = 20
            mitigation_timeout = 600
        }
    }
    $merged = Merge-ManagedRules -ExistingRules $rateEntry.rules -ManagedRules @($rule)
    Set-PhaseRuleset -ApiToken $ApiToken -ZoneId $zoneId -Phase 'http_ratelimit' -Rules $merged | Out-Null
}
elseif ($rateEntry) {
    $merged = Merge-ManagedRules -ExistingRules $rateEntry.rules -ManagedRules @()
    Set-PhaseRuleset -ApiToken $ApiToken -ZoneId $zoneId -Phase 'http_ratelimit' -Rules $merged | Out-Null
}

$state = [ordered]@{
    zoneId = $zoneId
    zoneName = $ZoneName
    hostname = $Hostname
    cnameTarget = $OriginTarget
    proxied = [bool]$EnableProxy
    verificationRecord = $txtName
    updatedAt = (Get-Date).ToString('o')
}
if ($StatePath) {
    Save-JsonUtf8 -Data $state -Path $StatePath
}
$state
