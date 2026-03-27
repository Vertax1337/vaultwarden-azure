function Write-LineAt {
    param(
        [int]$Row,
        [string]$Text
    )

    $width = 80
    try {
        $width = [System.Console]::WindowWidth
    }
    catch {
    }

    if ($width -lt 10) {
        $width = 80
    }

    try {
        if ([System.Console]::BufferHeight -lt ($Row + 2)) {
            [System.Console]::BufferHeight = $Row + 2
        }
    }
    catch {
    }

    $outputText = $Text
    if ($outputText.Length -gt ($width - 1)) {
        $outputText = $outputText.Substring(0, $width - 1)
    }
    else {
        $outputText = $outputText.PadRight($width - 1)
    }

    [System.Console]::SetCursorPosition(0, $Row)
    [System.Console]::Write($outputText)
}

function Draw-MenuItem {
    param(
        [int]$TopRow,
        [object[]]$Items,
        [int]$Index,
        [int]$SelectedIndex
    )

    $prefix = ' '
    if ($Index -eq $SelectedIndex) {
        $prefix = '>'
    }

    $line = ('{0} [{1}] {2}' -f $prefix, $Items[$Index].Key, $Items[$Index].Text)
    Write-LineAt -Row ($TopRow + $Index) -Text $line
}

function Show-SingleChoiceMenuSmooth {
    param(
        [string]$Title = 'Stammmenue',
        [Parameter(Mandatory)]
        [object[]]$Items,
        [string]$DefaultKey = '1'
    )

    if (-not $Items -or $Items.Count -eq 0) {
        throw 'Keine Menueeintraege vorhanden.'
    }

    function Invoke-FallbackMenu {
        while ($true) {
            Write-Host ''
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

            Write-Host 'Ungueltige Auswahl.'
        }
    }

    if ([System.Console]::IsInputRedirected -or [System.Console]::IsOutputRedirected) {
        return Invoke-FallbackMenu
    }

    $selectedIndex = 0
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ([string]$Items[$i].Key -eq $DefaultKey) {
            $selectedIndex = $i
            break
        }
    }

    $titleRow = 0
    $helpRow = 2
    $menuTopRow = 4
    $messageRow = $menuTopRow + $Items.Count + 1
    $oldCursorVisible = $true

    try {
        [System.Console]::Clear()

        try {
            $oldCursorVisible = [System.Console]::CursorVisible
            [System.Console]::CursorVisible = $false
        }
        catch {
        }

        Write-LineAt -Row $titleRow -Text $Title
        Write-LineAt -Row ($titleRow + 1) -Text ''
        Write-LineAt -Row $helpRow -Text 'Pfeile = bewegen, Enter = waehlen, Zahl = direkt waehlen, Esc = beenden'
        Write-LineAt -Row ($helpRow + 1) -Text ''

        for ($i = 0; $i -lt $Items.Count; $i++) {
            Draw-MenuItem -TopRow $menuTopRow -Items $Items -Index $i -SelectedIndex $selectedIndex
        }

        Write-LineAt -Row $messageRow -Text ''
        Write-LineAt -Row ($messageRow + 1) -Text ''
        Write-LineAt -Row ($messageRow + 2) -Text ''

        while ($true) {
            $keyInfo = [System.Console]::ReadKey($true)

            switch ($keyInfo.Key) {
                'UpArrow' {
                    $oldIndex = $selectedIndex

                    if ($selectedIndex -gt 0) {
                        $selectedIndex--
                    }
                    else {
                        $selectedIndex = $Items.Count - 1
                    }

                    Draw-MenuItem -TopRow $menuTopRow -Items $Items -Index $oldIndex -SelectedIndex $selectedIndex
                    Draw-MenuItem -TopRow $menuTopRow -Items $Items -Index $selectedIndex -SelectedIndex $selectedIndex
                    continue
                }

                'DownArrow' {
                    $oldIndex = $selectedIndex

                    if ($selectedIndex -lt ($Items.Count - 1)) {
                        $selectedIndex++
                    }
                    else {
                        $selectedIndex = 0
                    }

                    Draw-MenuItem -TopRow $menuTopRow -Items $Items -Index $oldIndex -SelectedIndex $selectedIndex
                    Draw-MenuItem -TopRow $menuTopRow -Items $Items -Index $selectedIndex -SelectedIndex $selectedIndex
                    continue
                }

                'Enter' {
                    return [string]$Items[$selectedIndex].Key
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

function Show-MenuMessage {
    param(
        [Parameter(Mandatory)][string]$Message,
        [int]$MenuItemCount
    )

    $messageRow = 5 + $MenuItemCount

    Write-LineAt -Row $messageRow -Text ''
    Write-LineAt -Row ($messageRow + 1) -Text $Message
    Write-LineAt -Row ($messageRow + 2) -Text 'Taste druecken zum Zurueckkehren ins Menue...'
    [void][System.Console]::ReadKey($true)
    Write-LineAt -Row $messageRow -Text ''
    Write-LineAt -Row ($messageRow + 1) -Text ''
    Write-LineAt -Row ($messageRow + 2) -Text ''
}

$menuItems = @(
    [pscustomobject]@{ Key = '1'; Text = 'Neues Kundendeployment anlegen und deployen' }
    [pscustomobject]@{ Key = '2'; Text = 'Vorhandene Konfiguration deployen' }
    [pscustomobject]@{ Key = '3'; Text = 'Vorhandene Konfiguration bearbeiten und deployen' }
    [pscustomobject]@{ Key = '4'; Text = 'Repair mit vorhandener Konfiguration' }
    [pscustomobject]@{ Key = '5'; Text = 'Update mit vorhandener Konfiguration' }
    [pscustomobject]@{ Key = '6'; Text = 'Nur Kunden-/Parameterdateien erzeugen' }
    [pscustomobject]@{ Key = '0'; Text = 'Beenden' }
)

while ($true) {
    $choice = Show-SingleChoiceMenuSmooth -Title 'Stammmenue' -Items $menuItems -DefaultKey '1'

    switch ($choice) {
        '1' {
            Show-MenuMessage -Message 'Aktion 1 ausgewaehlt' -MenuItemCount $menuItems.Count
        }

        '2' {
            Show-MenuMessage -Message 'Aktion 2 ausgewaehlt' -MenuItemCount $menuItems.Count
        }

        '3' {
            Show-MenuMessage -Message 'Aktion 3 ausgewaehlt' -MenuItemCount $menuItems.Count
        }

        '4' {
            Show-MenuMessage -Message 'Aktion 4 ausgewaehlt' -MenuItemCount $menuItems.Count
        }

        '5' {
            Show-MenuMessage -Message 'Aktion 5 ausgewaehlt' -MenuItemCount $menuItems.Count
        }

        '6' {
            Show-MenuMessage -Message 'Aktion 6 ausgewaehlt' -MenuItemCount $menuItems.Count
        }

        '0' {
            [System.Console]::Clear()
            exit 0
        }

        default {
            [System.Console]::Clear()
            exit 1
        }
    }
}