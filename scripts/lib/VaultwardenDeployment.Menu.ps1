# Menu integration layer for the Vaultwarden deployment wizard.
# Loads the vendored ConsoleMenu module and exposes a facade for future menu integration.
#
# NOTE: This file is intentionally minimal. The active menu implementation is not yet
# switched. This file only prepares the integration structure.

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

# Placeholder for the future deployment main menu facade.
# Will be implemented in a follow-up issue.
function Show-DeploymentMainMenu {
    [CmdletBinding()]
    param()
    # TODO: Implement deployment wizard main menu using ConsoleMenu module.
}
