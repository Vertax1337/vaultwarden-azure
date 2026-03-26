[CmdletBinding()]
param()

if ($env:CLOUDFLARE_IP_RANGES_JSON) {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $items = $env:CLOUDFLARE_IP_RANGES_JSON | ConvertFrom-Json -Depth 20
    } else {
        $items = $env:CLOUDFLARE_IP_RANGES_JSON | ConvertFrom-Json
    }
    return @($items)
}
if ($env:CLOUDFLARE_IP_RANGES_FILE -and (Test-Path -LiteralPath $env:CLOUDFLARE_IP_RANGES_FILE)) {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $items = Get-Content -LiteralPath $env:CLOUDFLARE_IP_RANGES_FILE -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    } else {
        $items = Get-Content -LiteralPath $env:CLOUDFLARE_IP_RANGES_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return @($items)
}

$result = Invoke-RestMethod -Uri 'https://api.cloudflare.com/client/v4/ips' -Method Get
if (-not $result.success) {
    throw 'Cloudflare IPs konnten nicht geladen werden.'
}
$result.result.ipv4_cidrs + $result.result.ipv6_cidrs
