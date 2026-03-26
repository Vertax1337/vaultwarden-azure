param(
    [string]$SubscriptionId = '26a416bd-13ec-4bc0-9cb2-c398a83f0482'
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Text)
    Write-Host "`n$Text" -ForegroundColor Yellow
}

function Invoke-Az {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args,
        [switch]$AllowFailure
    )

    $allArgs = @($Args) + @('--only-show-errors')
    $previousErrorActionPreference = $ErrorActionPreference

    try {
        $ErrorActionPreference = 'Continue'
        $raw = & az @allArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $lines = @($raw | ForEach-Object { "$_".TrimEnd() })

    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        $joined = ($lines -join "`n")
        throw "az $($allArgs -join ' ') failed with exit code $exitCode`n$joined"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $lines
    }
}

function Get-AzTsvLines {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args,
        [switch]$AllowFailure
    )

    $result = Invoke-Az -Args (@($Args) + @('-o', 'tsv')) -AllowFailure:$AllowFailure
    if ($result.ExitCode -ne 0) {
        return @()
    }

    return @(
        $result.Output |
            ForEach-Object { "$_".Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-AzJsonArray {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args,
        [switch]$AllowFailure
    )

    $result = Invoke-Az -Args (@($Args) + @('-o', 'json')) -AllowFailure:$AllowFailure
    if ($result.ExitCode -ne 0) {
        return @()
    }

    $text = ($result.Output -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text) -or $text -eq 'null') {
        return @()
    }

    $obj = $text | ConvertFrom-Json
    if ($obj -is [System.Array]) {
        return @($obj)
    }

    return @($obj)
}

function Remove-AllLocks {
    Write-Step '[1/5] Entferne alle Locks in der Subscription ...'
    $lockIds = Get-AzTsvLines -Args @('lock', 'list', '--query', '[].id') -AllowFailure

    if ($lockIds.Count -eq 0) {
        Write-Host '  Keine Locks gefunden.'
        return
    }

    foreach ($lockId in $lockIds) {
        Write-Host "  Entferne Lock: $lockId"
        $result = Invoke-Az -Args @('lock', 'delete', '--ids', $lockId) -AllowFailure
        if ($result.ExitCode -ne 0) {
            Write-Host '    Lock konnte nicht entfernt werden, fahre fort.' -ForegroundColor DarkYellow
            foreach ($line in $result.Output) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    Write-Host "    $line" -ForegroundColor DarkYellow
                }
            }
        }
    }
}

function Cleanup-RecoveryVault {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultRg,
        [Parameter(Mandatory = $true)]
        [string]$VaultName,
        [Parameter(Mandatory = $true)]
        [string]$VaultId
    )

    Write-Host "`n==== Recovery Services Vault: $VaultName (RG: $VaultRg) ====" -ForegroundColor Cyan

    Write-Host '  Suche Azure Files Backup-Items ...'
    $items = Get-AzJsonArray -Args @(
        'backup', 'item', 'list',
        '--resource-group', $VaultRg,
        '--vault-name', $VaultName,
        '--backup-management-type', 'AzureStorage',
        '--workload-type', 'AzureFileShare',
        '--query', '[].{itemName:name,containerName:properties.containerName,friendlyName:properties.friendlyName}'
    ) -AllowFailure

    if ($items.Count -gt 0) {
        foreach ($item in $items) {
            $containerName = "$($item.containerName)".Trim()
            $itemName = "$($item.itemName)".Trim()
            if ([string]::IsNullOrWhiteSpace($containerName) -or [string]::IsNullOrWhiteSpace($itemName)) {
                continue
            }

            Write-Host "  Stoppe Backup + lösche Backup-Daten: Container='$containerName' Item='$itemName'"
            $result = Invoke-Az -Args @(
                'backup', 'protection', 'disable',
                '--resource-group', $VaultRg,
                '--vault-name', $VaultName,
                '--backup-management-type', 'AzureStorage',
                '--workload-type', 'AzureFileShare',
                '--container-name', $containerName,
                '--item-name', $itemName,
                '--delete-backup-data', 'true',
                '--yes'
            ) -AllowFailure

            if ($result.ExitCode -ne 0) {
                Write-Host '    Stop Backup/Delete Backup Data fehlgeschlagen, fahre fort.' -ForegroundColor DarkYellow
                foreach ($line in $result.Output) {
                    if (-not [string]::IsNullOrWhiteSpace($line)) {
                        Write-Host "    $line" -ForegroundColor DarkYellow
                    }
                }
            }
        }
    }
    else {
        Write-Host '  Keine Azure Files Backup-Items gefunden.'
    }

    Write-Host '  Liste registrierte AzureStorage-Container ...'
    $containers = Get-AzJsonArray -Args @(
        'backup', 'container', 'list',
        '--resource-group', $VaultRg,
        '--vault-name', $VaultName,
        '--backup-management-type', 'AzureStorage',
        '--query', '[].{name:name,friendlyName:properties.friendlyName}'
    ) -AllowFailure

    if ($containers.Count -gt 0) {
        foreach ($container in $containers) {
            $containerName = "$($container.name)".Trim()
            if ([string]::IsNullOrWhiteSpace($containerName)) {
                $containerName = "$($container.friendlyName)".Trim()
            }
            if ([string]::IsNullOrWhiteSpace($containerName)) {
                continue
            }

            Write-Host "  Unregister Container: $containerName"
            $result = Invoke-Az -Args @(
                'backup', 'container', 'unregister',
                '--resource-group', $VaultRg,
                '--vault-name', $VaultName,
                '--backup-management-type', 'AzureStorage',
                '--container-name', $containerName,
                '--yes'
            ) -AllowFailure

            if ($result.ExitCode -ne 0) {
                Write-Host '    Unregister fehlgeschlagen, fahre fort.' -ForegroundColor DarkYellow
                foreach ($line in $result.Output) {
                    if (-not [string]::IsNullOrWhiteSpace($line)) {
                        Write-Host "    $line" -ForegroundColor DarkYellow
                    }
                }
            }
        }
    }
    else {
        Write-Host '  Keine registrierten AzureStorage-Container gefunden.'
    }

    Write-Host '  Deaktiviere Soft Delete / Hybrid Security (best effort, erst nach Container-Bereinigung) ...'
    $softDeleteResult = Invoke-Az -Args @(
        'backup', 'vault', 'backup-properties', 'set',
        '--name', $VaultName,
        '--resource-group', $VaultRg,
        '--soft-delete-feature-state', 'Disable',
        '--hybrid-backup-security-features', 'Disable'
    ) -AllowFailure

    if ($softDeleteResult.ExitCode -ne 0) {
        Write-Host '    Soft Delete/Hybrid Security konnte nicht geändert werden, fahre fort.' -ForegroundColor DarkYellow
        foreach ($line in $softDeleteResult.Output) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-Host "    $line" -ForegroundColor DarkYellow
            }
        }
    }

    Write-Host '  Liste soft-deleted Container (Info) ...'
    $softDeleted = Get-AzTsvLines -Args @(
        'backup', 'vault', 'list-soft-deleted-containers',
        '--name', $VaultName,
        '--resource-group', $VaultRg,
        '--backup-management-type', 'AzureStorage',
        '--query', '[].name'
    ) -AllowFailure

    if ($softDeleted.Count -gt 0) {
        Write-Host '  Soft-deleted Container vorhanden:' -ForegroundColor DarkYellow
        foreach ($name in $softDeleted) {
            Write-Host "    $name" -ForegroundColor DarkYellow
        }
    }

    Write-Host '  Versuche Vault-Ressource zu löschen ...'
    $deleteResult = Invoke-Az -Args @('resource', 'delete', '--ids', $VaultId) -AllowFailure
    if ($deleteResult.ExitCode -ne 0) {
        Write-Host '    Vault-Löschung noch blockiert. Weiter mit RG-/Ressourcen-Löschung.' -ForegroundColor DarkYellow
        foreach ($line in $deleteResult.Output) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-Host "    $line" -ForegroundColor DarkYellow
            }
        }
    }
}

Write-Host 'Aktuelle Subscription setzen ...' -ForegroundColor Cyan
$null = Invoke-Az -Args @('account', 'set', '--subscription', $SubscriptionId)
& az account show --output table

Remove-AllLocks

Write-Step '[2/5] Bereinige Recovery Services Vaults ...'
$vaults = Get-AzJsonArray -Args @(
    'resource', 'list',
    '--resource-type', 'Microsoft.RecoveryServices/vaults',
    '--query', '[].{id:id,name:name,resourceGroup:resourceGroup}'
) -AllowFailure

if ($vaults.Count -eq 0) {
    Write-Host '  Keine Recovery Services Vaults gefunden.'
}
else {
    foreach ($vault in $vaults) {
        $vaultId = "$($vault.id)".Trim()
        $vaultName = "$($vault.name)".Trim()
        $vaultRg = "$($vault.resourceGroup)".Trim()
        if ([string]::IsNullOrWhiteSpace($vaultId) -or [string]::IsNullOrWhiteSpace($vaultName) -or [string]::IsNullOrWhiteSpace($vaultRg)) {
            continue
        }

        Cleanup-RecoveryVault -VaultRg $vaultRg -VaultName $vaultName -VaultId $vaultId
    }
}

Remove-AllLocks

Write-Step '[3/5] Lösche alle Resource Groups ...'
$rgs = Get-AzTsvLines -Args @('group', 'list', '--query', '[].name') -AllowFailure
$failedRgs = @()

foreach ($rg in $rgs) {
    Write-Host "  Lösche RG: $rg"
    $result = Invoke-Az -Args @('group', 'delete', '--name', $rg, '--yes') -AllowFailure
    if ($result.ExitCode -ne 0) {
        Write-Host "  RG-Löschung fehlgeschlagen: $rg" -ForegroundColor Red
        foreach ($line in $result.Output) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-Host "    $line" -ForegroundColor Red
            }
        }
        $failedRgs += $rg
    }
}

Write-Step '[4/5] Prüfe verbliebene Resource Groups ...'
$remainingRgs = Get-AzTsvLines -Args @('group', 'list', '--query', '[].name') -AllowFailure
if ($remainingRgs.Count -eq 0) {
    Write-Host '  Keine Resource Groups mehr vorhanden.' -ForegroundColor Green
}
else {
    foreach ($rg in $remainingRgs) {
        Write-Host "  Verbleibt: $rg" -ForegroundColor DarkYellow
    }
}

Write-Step '[5/5] Schreibe Report ...'
$report = [pscustomobject]@{
    SubscriptionId     = $SubscriptionId
    TimestampUtc       = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    RemainingGroups    = @($remainingRgs)
    FailedDeleteGroups = @($failedRgs)
}

$reportPath = Join-Path -Path (Get-Location) -ChildPath 'delete-report.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath -Encoding UTF8
Write-Host "  Report geschrieben: $reportPath" -ForegroundColor Cyan
