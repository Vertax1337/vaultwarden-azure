# Menu integration layer for the Vaultwarden deployment wizard.
# Loads the vendored ConsoleMenu module and exposes a facade for future menu integration.
#
# NOTE: This file is intentionally minimal. The active menu implementation is not yet
# switched. This file only prepares the integration structure.

# Resolve vendored module path to a normalized absolute path so comparisons are deterministic.
$script:ConsoleMenuModulePath = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\modules\ConsoleMenu\ConsoleMenu.psd1')
)

# Check whether a ConsoleMenu module is already loaded and, if so, whether it comes from
# the expected vendored path.  If a module with the same name exists but was loaded from a
# different location, remove only that conflicting instance before importing the repo-local
# version.  Unrelated modules are never touched.
$script:_loadedConsoleMenu = Get-Module -Name 'ConsoleMenu'
if ($script:_loadedConsoleMenu) {
    $script:_loadedPath = [System.IO.Path]::GetFullPath($script:_loadedConsoleMenu.Path)
    if ($script:_loadedPath -ne $script:ConsoleMenuModulePath) {
        Remove-Module -Name 'ConsoleMenu' -Force -ErrorAction Stop
        Import-Module $script:ConsoleMenuModulePath -Force -ErrorAction Stop
    }
    # else: already loaded from the correct vendored path – nothing to do.
} else {
    Import-Module $script:ConsoleMenuModulePath -Force -ErrorAction Stop
}

# Placeholder for the future deployment main menu facade.
# Will be implemented in a follow-up issue.
function Show-DeploymentMainMenu {
    [CmdletBinding()]
    param()
    # TODO: Implement deployment wizard main menu using ConsoleMenu module.
}
