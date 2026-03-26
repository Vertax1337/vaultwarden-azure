param(
    [string]$SubscriptionId = "26a416bd-13ec-4bc0-9cb2-c398a83f0482",
    [int]$DeleteTimeoutSeconds = 900,
    [int]$PollIntervalSeconds = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n$Message" -ForegroundColor Yellow
}

function Write-Ok {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-WarnMsg {
    param([string]$Message)
    Write-Host $Message -ForegroundColor DarkYellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

function Split-Lines {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @($Text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Invoke-AzText {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    $output = & az @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).TrimEnd()

    if (-not $IgnoreExitCode -and $exitCode -ne 0) {
        throw "az $($Arguments -join ' ') fehlgeschlagen:`n$text"
    }

    return $text
}

function Invoke-AzTsv {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    $text = Invoke-AzText -Arguments $Arguments -IgnoreExitCode:$IgnoreExitCode
    return @(Split-Lines -Text $text)
}

function Invoke-AzJson {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    $text = Invoke-AzText -Arguments $Arguments -IgnoreExitCode:$IgnoreExitCode
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }

    try {
        $parsed = $text | ConvertFrom-Json
    }
    catch {
        if ($IgnoreExitCode) { return @() }
        throw
    }

    if ($null -eq $parsed) { return @() }
    return @($parsed)
}

function Remove-LockById {
    param([Parameter(Mandatory)][string]$LockId)

    if ([string]::IsNullOrWhiteSpace($LockId)) { return }

    Write-Host "  Entferne Lock: $LockId"
    try {
        Invoke-AzText -Arguments @('lock', 'delete', '--ids', $LockId, '--only-show-errors') -IgnoreExitCode | Out-Null
    }
    catch {
        Write-WarnMsg "    Warnung: Konnte Lock nicht löschen: $LockId"
    }
}

function Remove-AllLocks {
    Write-Step '[1/6] Entferne alle Locks in der Subscription ...'
    $lockIds = Invoke-AzTsv -Arguments @('lock', 'list', '--query', '[].id', '-o', 'tsv') -IgnoreExitCode

    if (@($lockIds).Count -eq 0) {
        Write-Host '  Keine Locks gefunden.'
        return
    }

    foreach ($lockId in @($lockIds)) {
        Remove-LockById -LockId $lockId
    }
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string[]]$PropertyNames
    )

    foreach ($name in $PropertyNames) {
        if ($Object -and $Object.PSObject -and ($Object.PSObject.Properties.Name -contains $name)) {
            $value = $Object.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                return [string]$value
            }
        }
    }

    return $null
}

function Disable-BackupForVault {
    param(
        [Parameter(Mandatory)][string]$VaultRg,
        [Parameter(Mandatory)][string]$VaultName
    )

    Write-Host "  Prüfe Azure Files Backup-Items in Vault $VaultName ..."
    $items = Invoke-AzJson -Arguments @(
        'backup', 'item', 'list',
        '--resource-group', $VaultRg,
        '--vault-name', $VaultName,
        '--backup-management-type', 'AzureStorage',
        '--workload-type', 'AzureFileShare',
        '-o', 'json'
    ) -IgnoreExitCode

    if (@($items).Count -eq 0) {
        Write-Host '    Keine Azure Files Backup-Items gefunden.'
    }

    foreach ($item in @($items)) {
        $props = $null
        if ($item.PSObject.Properties.Name -contains 'properties') {
            $props = $item.properties
        }

        $containerCandidates = @(
            Get-PropertyValue -Object $props -PropertyNames @('containerName'),
            Get-PropertyValue -Object $item  -PropertyNames @('containerName')
        ) | Where-Object { $_ }

        $itemCandidates = @(
            Get-PropertyValue -Object $item  -PropertyNames @('name'),
            Get-PropertyValue -Object $props -PropertyNames @('name', 'itemName', 'friendlyName')
        ) | Where-Object { $_ }

        $containerName = $containerCandidates | Select-Object -First 1
        $itemName = $itemCandidates | Select-Object -First 1

        if (-not $containerName -or -not $itemName) {
            Write-WarnMsg '    Warnung: Konnte Container- oder Item-Namen nicht sicher ermitteln.'
            continue
        }

        Write-Host "    Stoppe Backup und lösche Daten: Container=$containerName | Item=$itemName"
        try {
            Invoke-AzText -Arguments @(
                'backup', 'protection', 'disable',
                '--resource-group', $VaultRg,
                '--vault-name', $VaultName,
                '--backup-management-type', 'AzureStorage',
                '--workload-type', 'AzureFileShare',
                '--container-name', $containerName,
                '--item-name', $itemName,
                '--delete-backup-data', 'true',
                '--yes',
                '--only-show-errors'
            ) -IgnoreExitCode | Out-Null
        }
        catch {
            Write-WarnMsg "      Warnung: Backup-Disable fehlgeschlagen für $itemName"
        }
    }

    Write-Host "  Prüfe registrierte Storage-Container in Vault $VaultName ..."
    $containers = Invoke-AzJson -Arguments @(
        'backup', 'container', 'list',
        '--resource-group', $VaultRg,
        '--vault-name', $VaultName,
        '--backup-management-type', 'AzureStorage',
        '-o', 'json'
    ) -IgnoreExitCode

    if (@($containers).Count -eq 0) {
        Write-Host '    Keine registrierten Storage-Container gefunden.'
    }

    foreach ($container in @($containers)) {
        $props = $null
        if ($container.PSObject.Properties.Name -contains 'properties') {
            $props = $container.properties
        }

        $candidates = @(
            Get-PropertyValue -Object $container -PropertyNames @('name'),
            Get-PropertyValue -Object $props     -PropertyNames @('containerName'),
            Get-PropertyValue -Object $props     -PropertyNames @('friendlyName')
        ) | Where-Object { $_ }

        foreach ($candidate in $candidates | Select-Object -Unique) {
            Write-Host "    Versuche Unregister: $candidate"
            Invoke-AzText -Arguments @(
                'backup', 'container', 'unregister',
                '--resource-group', $VaultRg,
                '--vault-name', $VaultName,
                '--backup-management-type', 'AzureStorage',
                '--container-name', $candidate,
                '--yes',
                '--only-show-errors'
            ) -IgnoreExitCode | Out-Null
        }
    }

    Write-Host '  Versuche Soft Delete zu deaktivieren (Best Effort) ...'
    Invoke-AzText -Arguments @(
        'backup', 'vault', 'backup-properties', 'set',
        '--resource-group', $VaultRg,
        '--name', $VaultName,
        '--soft-delete-feature-state', 'Disable',
        '--only-show-errors'
    ) -IgnoreExitCode | Out-Null
}

function Cleanup-RecoveryServicesVaults {
    Write-Step '[2/6] Bereinige Recovery Services Vaults ...'

    $vaults = Invoke-AzJson -Arguments @(
        'resource', 'list',
        '--resource-type', 'Microsoft.RecoveryServices/vaults',
        '-o', 'json'
    ) -IgnoreExitCode

    if (@($vaults).Count -eq 0) {
        Write-Host '  Keine Recovery Services Vaults gefunden.'
        return
    }

    foreach ($vault in @($vaults)) {
        $vaultName = Get-PropertyValue -Object $vault -PropertyNames @('name')
        $vaultRg = Get-PropertyValue -Object $vault -PropertyNames @('resourceGroup')
        $vaultId = Get-PropertyValue -Object $vault -PropertyNames @('id')

        if (-not $vaultName -or -not $vaultRg -or -not $vaultId) {
            Write-WarnMsg '  Warnung: Vault-Daten unvollständig, überspringe Eintrag.'
            continue
        }

        Write-Host "`n==== Recovery Services Vault: $vaultName (RG: $vaultRg) ====" -ForegroundColor Cyan
        Disable-BackupForVault -VaultRg $vaultRg -VaultName $vaultName

        Write-Host '  Versuche Vault-Ressource zu löschen ...'
        Invoke-AzText -Arguments @('resource', 'delete', '--ids', $vaultId, '--only-show-errors') -IgnoreExitCode | Out-Null
    }
}

function Queue-DeleteAllResourceGroups {
    Write-Step '[3/6] Starte Löschung aller Resource Groups ...'

    $rgNames = Invoke-AzTsv -Arguments @('group', 'list', '--query', '[].name', '-o', 'tsv') -IgnoreExitCode
    $rgNames = @($rgNames | Where-Object { $_ -and $_ -ne 'NetworkWatcherRG' })

    if ($rgNames.Count -eq 0) {
        Write-Ok '  Keine Resource Groups mehr vorhanden.'
        return @()
    }

    foreach ($rg in $rgNames) {
        Write-Host "  Lösche RG: $rg"
        Invoke-AzText -Arguments @('group', 'delete', '--name', $rg, '--yes', '--no-wait', '--only-show-errors') -IgnoreExitCode | Out-Null
    }

    return @($rgNames)
}

function Wait-ForRgDeletion {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [int]$TimeoutSeconds = 900,
        [int]$PollSeconds = 10
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $exists = (Invoke-AzText -Arguments @('group', 'exists', '--name', $ResourceGroupName, '-o', 'tsv') -IgnoreExitCode).Trim().ToLowerInvariant()
        if ($exists -ne 'true') {
            return $true
        }
        Start-Sleep -Seconds $PollSeconds
    }

    return $false
}

function Remove-ResourcesInsideRg {
    param([Parameter(Mandatory)][string]$ResourceGroupName)

    Write-Host "  Entferne Locks in RG: $ResourceGroupName"
    $lockIds = Invoke-AzTsv -Arguments @('lock', 'list', '--resource-group', $ResourceGroupName, '--query', '[].id', '-o', 'tsv') -IgnoreExitCode
    foreach ($lockId in @($lockIds)) {
        Remove-LockById -LockId $lockId
    }

    $resourceIds = Invoke-AzTsv -Arguments @(
        'resource', 'list',
        '--resource-group', $ResourceGroupName,
        '--query', '[].id',
        '-o', 'tsv'
    ) -IgnoreExitCode

    foreach ($resId in @($resourceIds)) {
        if ([string]::IsNullOrWhiteSpace($resId)) { continue }
        Write-Host "    Lösche Ressource direkt: $resId"
        Invoke-AzText -Arguments @('resource', 'delete', '--ids', $resId, '--only-show-errors') -IgnoreExitCode | Out-Null
    }

    Write-Host "  Versuche RG erneut zu löschen: $ResourceGroupName"
    Invoke-AzText -Arguments @('group', 'delete', '--name', $ResourceGroupName, '--yes', '--no-wait', '--only-show-errors') -IgnoreExitCode | Out-Null
}

function Get-RgResourceSummary {
    param([Parameter(Mandatory)][string]$ResourceGroupName)

    $resources = Invoke-AzJson -Arguments @('resource', 'list', '--resource-group', $ResourceGroupName, '-o', 'json') -IgnoreExitCode
    if (@($resources).Count -eq 0) { return @() }

    return @(
        $resources | ForEach-Object {
            [PSCustomObject]@{
                name = Get-PropertyValue -Object $_ -PropertyNames @('name')
                type = Get-PropertyValue -Object $_ -PropertyNames @('type')
                id   = Get-PropertyValue -Object $_ -PropertyNames @('id')
            }
        }
    )
}

Write-Info 'Aktuelle Subscription setzen ...'
Invoke-AzText -Arguments @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
$accountTable = Invoke-AzText -Arguments @('account', 'show', '--output', 'table')
Write-Host $accountTable

Remove-AllLocks
Cleanup-RecoveryServicesVaults
Remove-AllLocks

$rgNames = Queue-DeleteAllResourceGroups
if (@($rgNames).Count -eq 0) {
    exit 0
}

Write-Step '[4/6] Warte auf Löschung der Resource Groups ...'
$stillExisting = New-Object System.Collections.Generic.List[string]
foreach ($rg in @($rgNames)) {
    Write-Host "  Prüfe RG: $rg"
    $deleted = Wait-ForRgDeletion -ResourceGroupName $rg -TimeoutSeconds $DeleteTimeoutSeconds -PollSeconds $PollIntervalSeconds
    if ($deleted) {
        Write-Ok "    OK: $rg gelöscht"
    }
    else {
        Write-WarnMsg "    Noch vorhanden: $rg"
        $stillExisting.Add($rg)
    }
}

if ($stillExisting.Count -gt 0) {
    Write-Step '[5/6] Aggressiver Nachgang für verbliebene Resource Groups ...'
    foreach ($rg in $stillExisting) {
        Remove-ResourcesInsideRg -ResourceGroupName $rg
    }
}

Write-Step '[6/6] Abschlussprüfung ...'
$finalRemaining = New-Object System.Collections.Generic.List[string]
$remainingDetails = @{}

foreach ($rg in @($rgNames)) {
    $exists = (Invoke-AzText -Arguments @('group', 'exists', '--name', $rg, '-o', 'tsv') -IgnoreExitCode).Trim().ToLowerInvariant()
    if ($exists -eq 'true') {
        $finalRemaining.Add($rg)
        $remainingDetails[$rg] = Get-RgResourceSummary -ResourceGroupName $rg
    }
}

if ($finalRemaining.Count -eq 0) {
    Write-Ok "`nAlle Resource Groups wurden gelöscht."
    exit 0
}

Write-Fail "`nDiese Resource Groups sind noch vorhanden:"
foreach ($rg in $finalRemaining) {
    Write-Host " - $rg" -ForegroundColor Red
    $details = $remainingDetails[$rg]
    foreach ($item in @($details)) {
        Write-Host "    * $($item.type) :: $($item.name)"
    }
}

$reportPath = Join-Path -Path (Get-Location) -ChildPath 'delete-report.json'
$remainingDetails | ConvertTo-Json -Depth 20 | Set-Content -Path $reportPath -Encoding UTF8
Write-WarnMsg "`nDetails wurden gespeichert in: $reportPath"
exit 1
