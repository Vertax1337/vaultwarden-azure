[CmdletBinding()]
param()

if ($env:CLOUDFLARE_IP_RANGES_JSON) {
    $items = $env:CLOUDFLARE_IP_RANGES_JSON | ConvertFrom-Json -Depth 20
    return @($items)
}
if ($env:CLOUDFLARE_IP_RANGES_FILE -and (Test-Path -LiteralPath $env:CLOUDFLARE_IP_RANGES_FILE)) {
    $items = Get-Content -LiteralPath $env:CLOUDFLARE_IP_RANGES_FILE -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    return @($items)
}

$result = Invoke-RestMethod -Uri 'https://api.cloudflare.com/client/v4/ips' -Method Get
if (-not $result.success) {
    throw 'Cloudflare IPs konnten nicht geladen werden.'
}
$result.result.ipv4_cidrs + $result.result.ipv6_cidrs
