# Menu layer for the Vaultwarden deployment wizard.
# Loads the vendored ConsoleMenu module and implements the interactive root menu.
# Contains only menu structure and navigation – no deployment or business logic.

# Resolve vendored module path to a normalized absolute path so comparisons are deterministic.
$script:ConsoleMenuModulePath = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\modules\ConsoleMenu\ConsoleMenu.psd1')
)

# Check whether ConsoleMenu module instances are already loaded and, for each one,
# whether it comes from the expected vendored path.  Only conflicting instances (loaded
# from a different path) are removed individually via -ModuleInfo.  The vendored instance
# (correct path) and all unrelated modules are left untouched.
$script:_vendoredAlreadyLoaded = $false
foreach ($_mod in @(Get-Module -Name 'ConsoleMenu' -All)) {
    $_modPath = [System.IO.Path]::GetFullPath($_mod.Path)
    if ($_modPath -eq $script:ConsoleMenuModulePath) {
        $script:_vendoredAlreadyLoaded = $true
    } else {
        Remove-Module -ModuleInfo $_mod -Force -ErrorAction Stop
    }
}

if (-not $script:_vendoredAlreadyLoaded) {
    Import-Module $script:ConsoleMenuModulePath -Force -ErrorAction Stop
}

# Interactive root menu for the Vaultwarden deployment wizard.
# Uses the vendored ConsoleMenu module to present a navigable menu with submenus.
#
# Accepts optional MenuState (hashtable) and MenuStack (List[string]) to preserve
# selection memory between invocations, enabling a persistent interactive loop.
# Returns a pscustomobject with:
#   ActionId  – one of: DeployExisting | EditConfig | DeleteConfig |
#                       CreateOnly | Repair | Update | Exit
#   MenuState – updated selection-memory hashtable (pass back on next call)
#   MenuStack – updated navigation stack (pass back on next call)
#
# The menu layer contains no deployment or business logic.
# Action execution belongs exclusively to the Start-*Flow functions.
function Show-DeploymentMainMenu {
    [CmdletBinding()]
    param(
        [hashtable]$MenuState,
        [System.Collections.Generic.List[string]]$MenuStack
    )

    $menuRegistry = @{
        'root' = New-ConsoleMenu `
            -Id 'root' `
            -Title 'Vaultwarden Azure – Deployment-Wizard' `
            -DefaultKey '1' `
            -Items @(
                New-ConsoleMenuItem -Key '1' -Text 'Kundenkonfiguration deployen' -ItemType 'action' -ActionId 'DeployExisting'
                New-ConsoleMenuItem -Key '2' -Text 'Kundenkonfigurationen bearbeiten' -ItemType 'submenu' -TargetMenuId 'edit'
                New-ConsoleMenuItem -Key '3' -Text 'Kundenkonfiguration anlegen' -ItemType 'action' -ActionId 'CreateOnly'
                New-ConsoleMenuItem -Key '4' -Text 'Wartung' -ItemType 'submenu' -TargetMenuId 'maintenance'
                New-ConsoleMenuItem -Key '0' -Text 'Beenden' -ItemType 'exit'
            )
        'edit' = New-ConsoleMenu `
            -Id 'edit' `
            -Title 'Vaultwarden Azure – Kundenkonfigurationen bearbeiten' `
            -DefaultKey '1' `
            -Items @(
                New-ConsoleMenuItem -Key '1' -Text 'Vorhandene Konfiguration deployen' -ItemType 'action' -ActionId 'DeployExisting'
                New-ConsoleMenuItem -Key '2' -Text 'Vorhandene Konfiguration bearbeiten' -ItemType 'action' -ActionId 'EditConfig'
                New-ConsoleMenuItem -Key '3' -Text 'Vorhandene Konfiguration löschen' -ItemType 'action' -ActionId 'DeleteConfig'
                New-ConsoleMenuItem -Key '0' -Text 'Zurück' -ItemType 'back'
            )
        'maintenance' = New-ConsoleMenu `
            -Id 'maintenance' `
            -Title 'Vaultwarden Azure – Wartung' `
            -DefaultKey '1' `
            -Items @(
                New-ConsoleMenuItem -Key '1' -Text 'Repair mit vorhandener Konfiguration' -ItemType 'action' -ActionId 'Repair'
                New-ConsoleMenuItem -Key '2' -Text 'Update mit vorhandener Konfiguration' -ItemType 'action' -ActionId 'Update'
                New-ConsoleMenuItem -Key '0' -Text 'Zurück' -ItemType 'back'
            )
    }

    if ($null -eq $MenuState) { $MenuState = @{} }
    if ($null -eq $MenuStack) {
        $MenuStack = New-Object System.Collections.Generic.List[string]
        [void]$MenuStack.Add('root')
    }

    $clearOnOpen = $true

    while ($MenuStack.Count -gt 0) {
        $currentMenuId = $MenuStack[$MenuStack.Count - 1]
        $currentMenu   = $menuRegistry[$currentMenuId]

        $initialKey = if ($MenuState.ContainsKey($currentMenuId)) {
            [string]$MenuState[$currentMenuId]
        } else {
            $currentMenu.DefaultKey
        }

        $selectedItem = Show-ConsoleMenu `
            -Menu $currentMenu `
            -ClearScreenOnOpen:$clearOnOpen `
            -InitialSelectedKey $initialKey

        $clearOnOpen = $false

        # Esc returns $null – treat as Back.
        if ($null -eq $selectedItem) {
            if ($MenuStack.Count -gt 1) {
                $MenuStack.RemoveAt($MenuStack.Count - 1)
            }
            $clearOnOpen = $true
            continue
        }

        switch ($selectedItem.ItemType) {
            'action' {
                # Save the last meaningful selection so it is pre-selected on re-entry.
                $MenuState[$currentMenuId] = [string]$selectedItem.Key
                return [pscustomobject]@{
                    ActionId  = $selectedItem.ActionId
                    MenuState = $MenuState
                    MenuStack = $MenuStack
                }
            }
            'submenu' {
                # Save the submenu-entry position in the parent menu.
                $MenuState[$currentMenuId] = [string]$selectedItem.Key
                [void]$MenuStack.Add($selectedItem.TargetMenuId)
                $clearOnOpen = $true
            }
            'back' {
                # Do NOT update MenuState: preserve the last meaningful position
                # so the submenu pre-selects it on re-entry instead of "Zurück".
                if ($MenuStack.Count -gt 1) {
                    $MenuStack.RemoveAt($MenuStack.Count - 1)
                }
                $clearOnOpen = $true
            }
            'exit' {
                $MenuState[$currentMenuId] = [string]$selectedItem.Key
                [System.Console]::Clear()
                return [pscustomobject]@{
                    ActionId  = 'Exit'
                    MenuState = $MenuState
                    MenuStack = $MenuStack
                }
            }
        }
    }

    # Fallback: stack unexpectedly empty – treat as Exit.
    return [pscustomobject]@{
        ActionId  = 'Exit'
        MenuState = $MenuState
        MenuStack = $MenuStack
    }
}
