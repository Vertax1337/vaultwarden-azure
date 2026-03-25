[CmdletBinding()]
param()

$result = Invoke-RestMethod -Uri 'https://api.cloudflare.com/client/v4/ips' -Method Get
if (-not $result.success) {
    throw 'Cloudflare IPs konnten nicht geladen werden.'
}
$result.result.ipv4_cidrs + $result.result.ipv6_cidrs
