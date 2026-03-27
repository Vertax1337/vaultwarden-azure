function Show-SingleChoiceMenu {
    param(
        [string]$Title = 'Aktion waehlen',
        [Parameter(Mandatory)]
        [object[]]$Items,
        [string]$DefaultKey = '1'
    )

    if (-not $Items -or $Items.Count -eq 0) {
        throw 'Keine Menueeintraege vorhanden.'
    }

    $index = 0

    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ([string]$Items[$i].Key -eq $DefaultKey) {
            $index = $i
            break
        }
    }

    function Invoke-FallbackMenu {
        while ($true) {
            Clear-Host
            Write-Host $Title
            Write-Host ''
            foreach ($item in $Items) {
                Write-Host ('[{0}] {1}' -f $item.Key, $item.Text)
            }

            Write-Host ''
            $inputValue = Read-Host ('Auswahl [{0}]' -f $DefaultKey)

            if ([string]::IsNullOrWhiteSpace($inputValue)) {
                $inputValue = $DefaultKey
            }

            $inputValue = $inputValue.Trim()

            foreach ($item in $Items) {
                if ([string]$item.Key -eq $inputValue) {
                    return $inputValue
                }
            }

            Write-Host ''
            Write-Host 'Ungueltige Auswahl. Enter zum Fortfahren...'
            [void][System.Console]::ReadKey($true)
        }
    }

    if ([System.Console]::IsInputRedirected -or [System.Console]::IsOutputRedirected) {
        return Invoke-FallbackMenu
    }

    $oldCursorVisible = $true

    try {
        try {
            $oldCursorVisible = [System.Console]::CursorVisible
            [System.Console]::CursorVisible = $false
        }
        catch {
        }

        while ($true) {
            Clear-Host
            Write-Host $Title
            Write-Host ''
            Write-Host 'Pfeile = bewegen, Enter = waehlen, Zahl = direkt waehlen, Esc = beenden'
            Write-Host ''

            for ($i = 0; $i -lt $Items.Count; $i++) {
                $prefix = ' '
                if ($i -eq $index) {
                    $prefix = '>'
                }

                Write-Host ('{0} [{1}] {2}' -f $prefix, $Items[$i].Key, $Items[$i].Text)
            }

            $keyInfo = [System.Console]::ReadKey($true)

            switch ($keyInfo.Key) {
                'UpArrow' {
                    if ($index -gt 0) {
                        $index--
                    }
                    else {
                        $index = $Items.Count - 1
                    }
                    continue
                }

                'DownArrow' {
                    if ($index -lt ($Items.Count - 1)) {
                        $index++
                    }
                    else {
                        $index = 0
                    }
                    continue
                }

                'Enter' {
                    return [string]$Items[$index].Key
                }

                'Escape' {
                    return '0'
                }

                default {
                    $typed = [string]$keyInfo.KeyChar

                    if ($typed -match '^\d$') {
                        for ($j = 0; $j -lt $Items.Count; $j++) {
                            if ([string]$Items[$j].Key -eq $typed) {
                                return $typed
                            }
                        }
                    }
                }
            }
        }
    }
    finally {
        try {
            [System.Console]::CursorVisible = $oldCursorVisible
        }
        catch {
        }
    }
}

$menuItems = @(
    [pscustomobject]@{
        Key  = '1'
        Text = 'Neues Kundendeployment anlegen und deployen'
    }
    [pscustomobject]@{
        Key  = '2'
        Text = 'Vorhandene Konfiguration deployen'
    }
    [pscustomobject]@{
        Key  = '3'
        Text = 'Vorhandene Konfiguration bearbeiten und deployen'
    }
    [pscustomobject]@{
        Key  = '4'
        Text = 'Repair mit vorhandener Konfiguration'
    }
    [pscustomobject]@{
        Key  = '5'
        Text = 'Update mit vorhandener Konfiguration'
    }
    [pscustomobject]@{
        Key  = '6'
        Text = 'Nur Kunden-/Parameterdateien erzeugen'
    }
    [pscustomobject]@{
        Key  = '0'
        Text = 'Beenden'
    }
)

while ($true) {
    $choice = Show-SingleChoiceMenu -Title 'Stammmenue' -Items $menuItems -DefaultKey '1'

    switch ($choice) {
        '1' {
            Clear-Host
            Write-Host 'Aktion 1 ausgewaehlt'
            Read-Host 'Enter zum Zurueckkehren ins Menue'
        }

        '2' {
            Clear-Host
            Write-Host 'Aktion 2 ausgewaehlt'
            Read-Host 'Enter zum Zurueckkehren ins Menue'
        }

        '3' {
            Clear-Host
            Write-Host 'Aktion 3 ausgewaehlt'
            Read-Host 'Enter zum Zurueckkehren ins Menue'
        }

        '4' {
            Clear-Host
            Write-Host 'Aktion 4 ausgewaehlt'
            Read-Host 'Enter zum Zurueckkehren ins Menue'
        }

        '5' {
            Clear-Host
            Write-Host 'Aktion 5 ausgewaehlt'
            Read-Host 'Enter zum Zurueckkehren ins Menue'
        }

        '6' {
            Clear-Host
            Write-Host 'Aktion 6 ausgewaehlt'
            Read-Host 'Enter zum Zurueckkehren ins Menue'
        }

        '0' {
            exit 0
        }

        default {
            exit 1
        }
    }
}
