# Interactive flow functions for the Vaultwarden deployment wizard.
# Each Start-*Flow function encapsulates one interactive action branch from the
# main action selector (Get-InteractiveAction). Functions return a hashtable with
# the values that the calling script must apply to its local state.
#
# NOTE: These functions depend on helper functions defined in
# Invoke-CustomerDeployment.ps1 (Select-CustomerCodeInteractive,
# New-CustomerConfigInteractive) and in VaultwardenDeployment.Common.ps1
# (Get-CustomerPaths, ConvertTo-HashtableDeep, Read-JsonFile). They are
# intended to be dot-sourced only from Invoke-CustomerDeployment.ps1.
#
# Do not activate Show-DeploymentMainMenu here; that belongs to a follow-up issue.

function Start-NewDeploymentFlow {
    [CmdletBinding()]
    param()
    $config = New-CustomerConfigInteractive
    return @{ Config = $config }
}

function Start-DeployExistingFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot,
        [Parameter(Mandatory)][string]$RepoRoot
    )
    $customerCode = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
    $pathsForLoad = Get-CustomerPaths -RepoRoot $RepoRoot -CustomersRoot $CustomersRoot -CustomerCode $customerCode
    $config = ConvertTo-HashtableDeep -InputObject (Read-JsonFile -Path $pathsForLoad.ConfigPath)
    return @{ Config = $config }
}

function Start-EditAndDeployFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot,
        [Parameter(Mandatory)][string]$RepoRoot
    )
    $customerCode = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
    $pathsForLoad = Get-CustomerPaths -RepoRoot $RepoRoot -CustomersRoot $CustomersRoot -CustomerCode $customerCode
    $loaded = ConvertTo-HashtableDeep -InputObject (Read-JsonFile -Path $pathsForLoad.ConfigPath)
    $config = New-CustomerConfigInteractive -ExistingConfig $loaded
    return @{ Config = $config }
}

function Start-RepairFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot
    )
    $customerCode = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
    return @{ CustomerNumber = $customerCode; Repair = $true }
}

function Start-UpdateFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot
    )
    $customerCode = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
    return @{ CustomerNumber = $customerCode; Update = $true }
}

function Start-GenerateOnlyFlow {
    [CmdletBinding()]
    param()
    $config = New-CustomerConfigInteractive
    return @{ Config = $config; GenerateOnly = $true }
}
