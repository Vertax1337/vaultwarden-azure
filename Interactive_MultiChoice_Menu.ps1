function Show-MultiSelectMenuSmooth {
    param(
        [string]$Title = "Bitte auswaehlen",
        [string[]]$Items
    )

    if (-not $Items -or $Items.Count -eq 0) {
        throw "Keine Eintraege vorhanden."
    }

    if ([System.Console]::IsInputRedirected -or [System.Console]::IsOutputRedirected) {
        throw "Dieses Menue braucht eine echte Konsole mit Tastatureingabe."
    }

    $selected = New-Object 'bool[]' $Items.Count
    $index = 0
    $startTop = [System.Console]::CursorTop
    $lineCount = 4 + $Items.Count
    $oldCursorVisible = $true

    function Write-PaddedLine {
        param(
            [int]$Row,
            [string]$Text
        )

        $width = [System.Console]::WindowWidth
        if ($width -lt 1) {
            $width = 80
        }

        $out = $Text
        if ($out.Length -gt ($width - 1)) {
            $out = $out.Substring(0, $width - 1)
        }
        else {
            $out = $out.PadRight($width - 1)
        }

        [System.Console]::SetCursorPosition(0, $Row)
        [System.Console]::Write($out)
    }

    function Render-Menu {
        Write-PaddedLine -Row $startTop -Text $Title
        Write-PaddedLine -Row ($startTop + 1) -Text ""
        Write-PaddedLine -Row ($startTop + 2) -Text "Pfeile = bewegen, Leertaste = umschalten, Enter = fertig, Esc = abbrechen"
        Write-PaddedLine -Row ($startTop + 3) -Text ""

        for ($i = 0; $i -lt $Items.Count; $i++) {
            $cursor = " "
            if ($i -eq $index) {
                $cursor = ">"
            }

            $mark = "[ ]"
            if ($selected[$i]) {
                $mark = "[x]"
            }

            $line = $cursor + " " + $mark + " " + $Items[$i]
            Write-PaddedLine -Row ($startTop + 4 + $i) -Text $line
        }
    }

    try {
        try {
            $oldCursorVisible = [System.Console]::CursorVisible
            [System.Console]::CursorVisible = $false
        }
        catch {
        }

        Render-Menu

        while ($true) {
            $key = [System.Console]::ReadKey($true)

            switch ($key.Key) {
                'UpArrow' {
                    if ($index -gt 0) {
                        $index = $index - 1
                    }
                    else {
                        $index = $Items.Count - 1
                    }
                    Render-Menu
                    continue
                }

                'DownArrow' {
                    if ($index -lt ($Items.Count - 1)) {
                        $index = $index + 1
                    }
                    else {
                        $index = 0
                    }
                    Render-Menu
                    continue
                }

                'Spacebar' {
                    $selected[$index] = -not $selected[$index]
                    Render-Menu
                    continue
                }

                'Enter' {
                    $result = @()

                    for ($j = 0; $j -lt $Items.Count; $j++) {
                        if ($selected[$j]) {
                            $result += $Items[$j]
                        }
                    }

                    [System.Console]::SetCursorPosition(0, $startTop + $lineCount)
                    return $result
                }

                'Escape' {
                    [System.Console]::SetCursorPosition(0, $startTop + $lineCount)
                    return $null
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

$wahl = Show-MultiSelectMenuSmooth -Title "Dienste auswaehlen" -Items @(
    "Apache",
    "MySQL",
    "Redis",
    "RabbitMQ",
    "Elasticsearch"
)

Write-Host ""
Write-Host "Gewaehlt:"
$wahl
