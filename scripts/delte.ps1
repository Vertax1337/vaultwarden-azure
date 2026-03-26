param(
    [string]$SubscriptionId = "26a416bd-13ec-4bc0-9cb2-c398a83f0482"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "`n$Message" -ForegroundColor Yellow
}

function Split-Lines {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @($Text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Invoke-AzTsv {
    param([string[]]$Args)
    $out = & az @Args 2>$null
    return @(Split-Lines -Text $out)
}

function Invoke-AzJson {
    param([string[]]$Args)
    $out = & az @Args 2>$null
    if ([string]::IsNullOrWhiteSpace($out)) { return @() }
    try {
        $parsed = $out | ConvertFrom-Json
    } catch {
        return @()
    }
    return @($parsed)
}

function Remove-LockById {
    param([string]$LockId)
    if ([string]::IsNullOrWhiteSpace($LockId)) { return }
    Write-Host "  Entferne Lock: $LockId"
    try {
        & az lock delete --ids $LockId --only-show-errors | Out-Null
    } catch {
        Write-Host "    Warnung: Konnte Lock nicht löschen: $LockId" -ForegroundColor DarkYellow
    }
}

function Remove-All-Locks {
    Write-Step "[1/6] Entferne alle Locks in der Subscription ..."
    $lockIds = Invoke-AzTsv -Args @('lock','list','--query','[].id','-o','tsv')
    if ($lockIds.Count -eq 0) {
        Write-Host "  Keine Locks gefunden."
        return
    }
    foreach ($lockId in $lockIds) {
        Remove-LockById -LockId $lockId
    }
}

function Disable-BackupForVault {
    param(
        [string]$VaultRg,
        [string]$VaultName
    )

    Write-Host "  Prüfe Azure Files Backup-Items in Vault $VaultName ..."

    $items = Invoke-AzJson -Args @(
        'backup','item','list',
        '--resource-group',$VaultRg,
        '--vault-name',$VaultName,
        '--backup-management-type','AzureStorage',
        '--workload-type','AzureFileShare',
        '-o','json'
    )

    if ($items.Count -eq 0) {
        Write-Host "    Keine Azure Files Backup-Items gefunden."
    }

    foreach ($item in $items) {
        $containerName = $null
        $itemName = $null

        if ($item.PSObject.Properties.Name -contains 'properties') {
            $props = $item.properties
            if ($props.PSObject.Properties.Name -contains 'containerName') {
                $containerName = $props.containerName
            }
            if ($props.PSObject.Properties.Name -contains 'friendlyName' -and -not $itemName) {
                $itemName = $props.friendlyName
            }
        }
        if (-not $itemName -and $item.PSObject.Properties.Name -contains 'name') {
            $itemName = $item.name
        }

        if ($containerName -and $itemName) {
            Write-Host "    Stoppe Backup und lösche Daten: Container=$containerName | Item=$itemName"
            try {
                & az backup protection disable \
                    --resource-group $VaultRg \
                    --vault-name $VaultName \
                    --backup-management-type AzureStorage \
                    --workload-type AzureFileShare \
                    --container-name $containerName \
                    --item-name $itemName \
                    --delete-backup-data true \
                    --yes \
                    --only-show-errors | Out-Null
            } catch {
                Write-Host "      Warnung: Backup-Disable fehlgeschlagen für $itemName" -ForegroundColor DarkYellow
            }
        }
    }

    Write-Host "  Prüfe registrierte Storage Accounts in Vault $VaultName ..."
    $containers = Invoke-AzJson -Args @(
        'backup','container','list',
        '--resource-group',$VaultRg,
        '--vault-name',$VaultName,
        '--backup-management-type','AzureStorage',
        '-o','json'
    )

    if ($containers.Count -eq 0) {
        Write-Host "    Keine registrierten Storage Accounts gefunden."
    }

    foreach ($container in $containers) {
        $containerName = $null
        if ($container.PSObject.Properties.Name -contains 'properties') {
            $props = $container.properties
            if ($props.PSObject.Properties.Name -contains 'friendlyName') {
                $containerName = $props.friendlyName
            }
            if (-not $containerName -and $props.PSObject.Properties.Name -contains 'containerName') {
                $containerName = $props.containerName
            }
        }
        if (-not $containerName -and $container.PSObject.Properties.Name -contains 'name') {
            $containerName = $container.name
        }

        if ($containerName) {
            Write-Host "    Unregister Storage Account: $containerName"
            try {
                & az backup container unregister \
                    --resource-group $VaultRg \
                    --vault-name $VaultName \
                    --backup-management-type AzureStorage \
                    --container-name $containerName \
                    --yes \
                    --only-show-errors | Out-Null
            } catch {
                Write-Host "      Warnung: Unregister fehlgeschlagen für $containerName" -ForegroundColor DarkYellow
            }
        }
    }

    Write-Host "  Versuche Soft Delete / Security Features zu entschärfen (Best Effort) ..."
    try {
        & az backup vault backup-properties set \
            --resource-group $VaultRg \
            --name $VaultName \
            --soft-delete-feature-state Disable \
            --only-show-errors | Out-Null
    } catch {
        Write-Host "    Hinweis: Soft Delete konnte per CLI nicht geändert werden." -ForegroundColor DarkYellow
    }
}

function Cleanup-RecoveryServicesVaults {
    Write-Step "[2/6] Bereinige Recovery Services Vaults ..."

    $vaults = Invoke-AzJson -Args @(
        'resource','list',
        '--resource-type','Microsoft.RecoveryServices/vaults',
        '-o','json'
    )

    if ($vaults.Count -eq 0) {
        Write-Host "  Keine Recovery Services Vaults gefunden."
        return
    }

    foreach ($vault in $vaults) {
        $vaultName = $vault.name
        $vaultRg = $vault.resourceGroup
        Write-Host "`n==== Recovery Services Vault: $vaultName (RG: $vaultRg) ====" -ForegroundColor Cyan
        Disable-BackupForVault -VaultRg $vaultRg -VaultName $vaultName

        Write-Host "  Lösche Vault-Ressource per ARM ..."
        try {
            & az resource delete --ids $vault.id --only-show-errors | Out-Null
        } catch {
            Write-Host "    Warnung: Vault konnte noch nicht gelöscht werden: $vaultName" -ForegroundColor DarkYellow
        }
    }
}

function Remove-ResourcesInGroup {
    param([string]$ResourceGroupName)

    $resourceIds = Invoke-AzTsv -Args @(
        'resource','list',
        '--resource-group',$ResourceGroupName,
        '--query','[].id',
        '-o','tsv'
    )

    foreach ($resId in $resourceIds) {
        if ([string]::IsNullOrWhiteSpace($resId)) { continue }
        Write-Host "    Lösche Ressource direkt: $resId"
        try {
            & az resource delete --ids $resId --only-show-errors | Out-Null
        } catch {
            Write-Host "      Warnung: Resource delete fehlgeschlagen: $resId" -ForegroundColor DarkYellow
        }
    }
}

function Delete-AllResourceGroups {
    Write-Step "[3/6] Lösche alle Resource Groups ..."

    $rgs = Invoke-AzTsv -Args @('group','list','--query','[].name','-o','tsv')
    if ($rgs.Count -eq 0) {
        Write-Host "  Keine Resource Groups gefunden."
        return @()
    }

    $failed = @()

    foreach ($rg in $rgs) {
        Write-Host "`n==== RG: $rg ====" -ForegroundColor Cyan

        # Vorher nochmal Locks nur in dieser RG auflösen
        $rgLocks = Invoke-AzTsv -Args @('lock','list','--resource-group',$rg,'--query','[].id','-o','tsv')
        foreach ($lockId in $rgLocks) {
            Remove-LockById -LockId $lockId
        }

        Write-Host "  Lösche RG: $rg"
        try {
            & az group delete --name $rg --yes --only-show-errors | Out-Null
        } catch {
            Write-Host "    Erste RG-Löschung fehlgeschlagen, versuche Einzelressourcen ..." -ForegroundColor DarkYellow
            Remove-ResourcesInGroup -ResourceGroupName $rg
            try {
                & az group delete --name $rg --yes --only-show-errors | Out-Null
            } catch {
                Write-Host "    Warnung: RG delete final fehlgeschlagen: $rg" -ForegroundColor DarkYellow
            }
        }

        $exists = (& az group exists --name $rg -o tsv 2>$null)
        if ($exists -eq 'true') {
            $failed += $rg
            Write-Host "  FEHLER: RG konnte nicht gelöscht werden: $rg" -ForegroundColor Red
        } else {
            Write-Host "  OK: RG gelöscht: $rg" -ForegroundColor Green
        }
    }

    return @($failed)
}

function Build-Report {
    param([string[]]$FailedGroups)

    Write-Step "[4/6] Erstelle Abschlussreport ..."

    $remainingGroups = Invoke-AzTsv -Args @('group','list','--query','[].name','-o','tsv')
    $remainingLocks = Invoke-AzTsv -Args @('lock','list','--query','[].id','-o','tsv')
    $remainingVaults = Invoke-AzJson -Args @('resource','list','--resource-type','Microsoft.RecoveryServices/vaults','-o','json')

    $report = [pscustomobject]@{
        TimestampUtc         = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        SubscriptionId       = $SubscriptionId
        FailedGroups         = @($FailedGroups)
        RemainingGroups      = @($remainingGroups)
        RemainingLockIds     = @($remainingLocks)
        RemainingVaults      = @($remainingVaults | ForEach-Object { [pscustomobject]@{ name = $_.name; resourceGroup = $_.resourceGroup; id = $_.id } })
    }

    $reportPath = Join-Path -Path (Get-Location) -ChildPath 'delete-report.json'
    $report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath -Encoding UTF8
    Write-Host "  Report gespeichert: $reportPath"
}

Write-Host "Aktuelle Subscription setzen ..." -ForegroundColor Cyan
& az account set --subscription $SubscriptionId
& az account show --output table

Remove-All-Locks
Cleanup-RecoveryServicesVaults
$failed = Delete-AllResourceGroups
Build-Report -FailedGroups $failed

Write-Step "[5/6] Abschluss"
$remaining = Invoke-AzTsv -Args @('group','list','--query','[].name','-o','tsv')
if ($remaining.Count -eq 0) {
    Write-Host "Alle Resource Groups wurden gelöscht." -ForegroundColor Green
} else {
    Write-Host "Verbliebene Resource Groups:" -ForegroundColor Red
    foreach ($rg in $remaining) { Write-Host " - $rg" }
}

Write-Step "[6/6] Fertig"
