# Menu integration layer for the Vaultwarden deployment wizard.
# Loads the vendored ConsoleMenu module and exposes a facade for future menu integration.
#
# NOTE: This file is intentionally minimal. The active menu implementation is not yet
# switched. This file only prepares the integration structure.

$script:ConsoleMenuModulePath = Join-Path $PSScriptRoot '..\modules\ConsoleMenu\ConsoleMenu.psd1'

if (-not (Get-Module -Name 'ConsoleMenu')) {
    Import-Module $script:ConsoleMenuModulePath -Force -ErrorAction Stop
}

# Placeholder for the future deployment main menu facade.
# Will be implemented in a follow-up issue.
function Show-DeploymentMainMenu {
    [CmdletBinding()]
    param()
    # TODO: Implement deployment wizard main menu using ConsoleMenu module.
}
