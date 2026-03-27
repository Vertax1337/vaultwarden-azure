Set-StrictMode -Version Latest

function New-ConsoleMenuItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][ValidateSet('submenu', 'action', 'back', 'exit')][string]$ItemType,
        [string]$TargetMenuId,
        [string]$ActionId,
        [bool]$Enabled = $true
    )

    if ($ItemType -eq 'submenu' -and [string]::IsNullOrWhiteSpace($TargetMenuId)) {
        throw 'TargetMenuId ist fuer ItemType=submenu erforderlich.'
    }

    if ($ItemType -eq 'action' -and [string]::IsNullOrWhiteSpace($ActionId)) {
        throw 'ActionId ist fuer ItemType=action erforderlich.'
    }

    [pscustomobject]@{
        PSTypeName   = 'ConsoleMenu.Item'
        Key          = $Key
        Text         = $Text
        ItemType     = $ItemType
        TargetMenuId = $TargetMenuId
        ActionId     = $ActionId
        Enabled      = $Enabled
    }
}

function New-ConsoleMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$DefaultKey,
        [Parameter(Mandatory)][object[]]$Items
    )

    if ($Items.Count -eq 0) {
        throw 'Ein Menue muss mindestens einen Eintrag haben.'
    }

    [pscustomobject]@{
        PSTypeName = 'ConsoleMenu.Definition'
        Id         = $Id
        Title      = $Title
        DefaultKey = $DefaultKey
        Items      = $Items
    }
}

function Write-ConsoleMenuLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Row,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
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

function Enter-ConsoleScreen {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Title = ''
    )

    [System.Console]::Clear()

    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        Write-ConsoleMenuLine -Row 0 -Text $Title
        Write-ConsoleMenuLine -Row 1 -Text ''
    }
}

function Show-ConsoleScreenMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message
    )

    Enter-ConsoleScreen -Title $Title
    Write-ConsoleMenuLine -Row 3 -Text $Message
    Write-ConsoleMenuLine -Row 5 -Text 'Taste druecken zum Fortfahren...'
    [void][System.Console]::ReadKey($true)
}

function Get-ConsoleMenuEnabledIndices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Items
    )

    $indices = New-Object System.Collections.Generic.List[int]

    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($Items[$i].Enabled) {
            [void]$indices.Add($i)
        }
    }

    return ,$indices.ToArray()
}

function Get-ConsoleMenuDefaultIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][string]$DefaultKey
    )

    $enabledIndices = Get-ConsoleMenuEnabledIndices -Items $Items
    if ($enabledIndices.Count -eq 0) {
        throw 'Es gibt keine aktivierten Menueeintraege.'
    }

    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($Items[$i].Enabled -and ([string]$Items[$i].Key -eq $DefaultKey)) {
            return $i
        }
    }

    return $enabledIndices[0]
}

function Get-ConsoleMenuNextIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][int]$CurrentIndex,
        [Parameter(Mandatory)][ValidateSet(-1, 1)][int]$Step
    )

    $enabledIndices = Get-ConsoleMenuEnabledIndices -Items $Items
    if ($enabledIndices.Count -eq 0) {
        throw 'Es gibt keine aktivierten Menueeintraege.'
    }

    $position = [Array]::IndexOf([int[]]$enabledIndices, $CurrentIndex)
    if ($position -lt 0) {
        return $enabledIndices[0]
    }

    $position += $Step

    if ($position -lt 0) {
        $position = $enabledIndices.Count - 1
    }
    elseif ($position -ge $enabledIndices.Count) {
        $position = 0
    }

    return $enabledIndices[$position]
}

function Draw-ConsoleMenuItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$TopRow,
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][int]$SelectedIndex
    )

    $item = $Items[$Index]

    $prefix = ' '
    if ($Index -eq $SelectedIndex) {
        $prefix = '>'
    }

    $statePrefix = ' '
    if (-not $item.Enabled) {
        $statePrefix = '-'
    }

    $line = '{0} [{1}] {2}{3}' -f $prefix, $item.Key, $statePrefix, $item.Text
    Write-ConsoleMenuLine -Row ($TopRow + $Index) -Text $line
}

function Invoke-ConsoleMenuFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Menu,
        [string]$InitialSelectedKey
    )

    $promptDefault = $Menu.DefaultKey
    if (-not [string]::IsNullOrWhiteSpace($InitialSelectedKey)) {
        $promptDefault = $InitialSelectedKey
    }

    while ($true) {
        Write-Host ''
        Write-Host $Menu.Title
        Write-Host ''

        foreach ($item in $Menu.Items) {
            $prefix = if ($item.Enabled) { ' ' } else { '-' }
            Write-Host ('[{0}] {1}{2}' -f $item.Key, $prefix, $item.Text)
        }

        Write-Host ''
        $inputValue = Read-Host ('Auswahl [{0}]' -f $promptDefault)

        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            $inputValue = $promptDefault
        }

        $inputValue = $inputValue.Trim()

        foreach ($item in $Menu.Items) {
            if ($item.Enabled -and ([string]$item.Key -eq $inputValue)) {
                return $item
            }
        }

        Write-Warning 'Ungueltige Auswahl.'
    }
}

function Show-ConsoleMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Menu,
        [switch]$ClearScreenOnOpen,
        [string]$InitialSelectedKey
    )

    if (-not $Menu.Items -or $Menu.Items.Count -eq 0) {
        throw 'Keine Menueeintraege vorhanden.'
    }

    $effectiveSelectedKey = $Menu.DefaultKey
    if (-not [string]::IsNullOrWhiteSpace($InitialSelectedKey)) {
        $effectiveSelectedKey = $InitialSelectedKey
    }

    $selectedIndex = Get-ConsoleMenuDefaultIndex -Items $Menu.Items -DefaultKey $effectiveSelectedKey

    if ([System.Console]::IsInputRedirected -or [System.Console]::IsOutputRedirected) {
        return Invoke-ConsoleMenuFallback -Menu $Menu -InitialSelectedKey $effectiveSelectedKey
    }

    $titleRow = 0
    $helpRow = 2
    $menuTopRow = 4
    $oldCursorVisible = $true

    try {
        if ($ClearScreenOnOpen) {
            Enter-ConsoleScreen -Title $Menu.Title
        }

        try {
            $oldCursorVisible = [System.Console]::CursorVisible
            [System.Console]::CursorVisible = $false
        }
        catch {
        }

        Write-ConsoleMenuLine -Row $titleRow -Text $Menu.Title
        Write-ConsoleMenuLine -Row ($titleRow + 1) -Text ''
        Write-ConsoleMenuLine -Row $helpRow -Text 'Pfeile = bewegen, Enter = waehlen, Zahl = direkt waehlen, Esc = Default/Back'
        Write-ConsoleMenuLine -Row ($helpRow + 1) -Text ''

        for ($i = 0; $i -lt $Menu.Items.Count; $i++) {
            Draw-ConsoleMenuItem -TopRow $menuTopRow -Items $Menu.Items -Index $i -SelectedIndex $selectedIndex
        }

        while ($true) {
            $keyInfo = [System.Console]::ReadKey($true)

            switch ($keyInfo.Key) {
                'UpArrow' {
                    $oldIndex = $selectedIndex
                    $selectedIndex = Get-ConsoleMenuNextIndex -Items $Menu.Items -CurrentIndex $selectedIndex -Step -1
                    Draw-ConsoleMenuItem -TopRow $menuTopRow -Items $Menu.Items -Index $oldIndex -SelectedIndex $selectedIndex
                    Draw-ConsoleMenuItem -TopRow $menuTopRow -Items $Menu.Items -Index $selectedIndex -SelectedIndex $selectedIndex
                    continue
                }

                'DownArrow' {
                    $oldIndex = $selectedIndex
                    $selectedIndex = Get-ConsoleMenuNextIndex -Items $Menu.Items -CurrentIndex $selectedIndex -Step 1
                    Draw-ConsoleMenuItem -TopRow $menuTopRow -Items $Menu.Items -Index $oldIndex -SelectedIndex $selectedIndex
                    Draw-ConsoleMenuItem -TopRow $menuTopRow -Items $Menu.Items -Index $selectedIndex -SelectedIndex $selectedIndex
                    continue
                }

                'Enter' {
                    return $Menu.Items[$selectedIndex]
                }

                'Escape' {
                    return $Menu.Items[(Get-ConsoleMenuDefaultIndex -Items $Menu.Items -DefaultKey $Menu.DefaultKey)]
                }

                default {
                    $typed = [string]$keyInfo.KeyChar

                    if ($typed -match '^\S+$') {
                        foreach ($item in $Menu.Items) {
                            if ($item.Enabled -and ([string]$item.Key -eq $typed)) {
                                return $item
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

function Get-ConsoleMenuById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$MenuRegistry,
        [Parameter(Mandatory)][string]$MenuId
    )

    if (-not $MenuRegistry.ContainsKey($MenuId)) {
        throw ('Menue-ID nicht gefunden: {0}' -f $MenuId)
    }

    return $MenuRegistry[$MenuId]
}

function Start-ConsoleMenuApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$MenuRegistry,
        [Parameter(Mandatory)][string]$RootMenuId,
        [scriptblock]$ActionHandler
    )

    $menuStack = New-Object System.Collections.Generic.List[string]
    [void]$menuStack.Add($RootMenuId)

    $menuState = @{}
    $clearOnOpen = $true

    while ($true) {
        $currentMenuId = $menuStack[$menuStack.Count - 1]
        $currentMenu = Get-ConsoleMenuById -MenuRegistry $MenuRegistry -MenuId $currentMenuId

        $initialSelectedKey = $currentMenu.DefaultKey
        if ($menuState.ContainsKey($currentMenuId)) {
            $initialSelectedKey = [string]$menuState[$currentMenuId]
        }

        $selectedItem = Show-ConsoleMenu `
            -Menu $currentMenu `
            -ClearScreenOnOpen:$clearOnOpen `
            -InitialSelectedKey $initialSelectedKey

        $menuState[$currentMenuId] = [string]$selectedItem.Key

        $clearOnOpen = $false

        switch ($selectedItem.ItemType) {
            'submenu' {
                if (-not $MenuRegistry.ContainsKey($selectedItem.TargetMenuId)) {
                    throw ('Zielmenue nicht gefunden: {0}' -f $selectedItem.TargetMenuId)
                }

                [void]$menuStack.Add($selectedItem.TargetMenuId)
                $clearOnOpen = $true
                continue
            }

            'back' {
                if ($menuStack.Count -gt 1) {
                    $menuStack.RemoveAt($menuStack.Count - 1)
                }
                $clearOnOpen = $true
                continue
            }

            'action' {
                if ($ActionHandler) {
                    & $ActionHandler $selectedItem $currentMenu $MenuRegistry $menuStack $menuState
                }
                $clearOnOpen = $true
                continue
            }

            'exit' {
                [System.Console]::Clear()
                return [pscustomobject]@{
                    ExitRequested = $true
                    SelectedItem  = $selectedItem
                    MenuState     = $menuState
                }
            }

            default {
                throw ('Unbekannter ItemType: {0}' -f $selectedItem.ItemType)
            }
        }
    }
}

Export-ModuleMember -Function `
    New-ConsoleMenuItem, `
    New-ConsoleMenu, `
    Show-ConsoleMenu, `
    Show-ConsoleScreenMessage, `
    Enter-ConsoleScreen, `
    Write-ConsoleMenuLine, `
    Get-ConsoleMenuDefaultIndex, `
    Get-ConsoleMenuNextIndex, `
    Get-ConsoleMenuById, `
    Start-ConsoleMenuApplication
