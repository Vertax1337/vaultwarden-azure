# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$TemplateFile,
    [Parameter(Mandatory)][string]$ParametersFile,
    [string]$DeploymentName = ('vaultwarden-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [string]$OutputPath
)

. (Join-Path $PSScriptRoot 'lib/VaultwardenDeployment.Common.ps1')
Ensure-AzCliReady

$parameterDocument = Read-JsonFile -Path $ParametersFile
$location = $null
if ($parameterDocument -and $parameterDocument.parameters -and $parameterDocument.parameters.location) {
    $location = [string]$parameterDocument.parameters.location.value
}
if ([string]::IsNullOrWhiteSpace($location)) {
    throw 'ParametersFile enthaelt keinen gueltigen location-Wert.'
}
Ensure-ResourceGroupExists -ResourceGroupName $ResourceGroupName -Location $location

Write-Step ("Azure-Deployment starte: {0}" -f $DeploymentName)
$deployArgs = @(
    'deployment','group','create',
    '--resource-group', $ResourceGroupName,
    '--name', $DeploymentName,
    '--template-file', $TemplateFile,
    '--parameters', ('@' + $ParametersFile),
    '--only-show-errors',
    '-o','json'
)

# Resolve the az executable. On Windows az ships as a .cmd batch wrapper that must be
# invoked via cmd.exe /c; on Linux/macOS az is a direct binary.
$_azSource = (Get-Command az -ErrorAction SilentlyContinue).Source
$_isWin    = -not ($IsLinux -or $IsMacOS)   # $IsLinux/$IsMacOS absent in PS 5.1 → treats as Windows
if ($_isWin -and ($_azSource -like '*.cmd' -or $_azSource -like '*.bat')) {
    $_azExe  = 'cmd.exe'
    $_azArgs = @('/c', $_azSource) + $deployArgs
} else {
    $_azExe  = $_azSource
    $_azArgs = $deployArgs
}

$json = Invoke-NativeProcessWithSpinner `
    -Message      ('Azure-Deployment laeuft: {0}' -f $DeploymentName) `
    -Executable   $_azExe `
    -ArgumentList $_azArgs
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $result = $json | ConvertFrom-Json -Depth 100
} else {
    $result = $json | ConvertFrom-Json
}
if ($OutputPath) {
    Save-JsonUtf8 -Data $result -Path $OutputPath
}
$result
