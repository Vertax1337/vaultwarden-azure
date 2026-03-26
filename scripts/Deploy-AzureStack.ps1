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

$json = az @deployArgs
if ($LASTEXITCODE -ne 0) {
    throw 'Azure deployment failed.'
}
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $result = $json | ConvertFrom-Json -Depth 100
} else {
    $result = $json | ConvertFrom-Json
}
if ($OutputPath) {
    Save-JsonUtf8 -Data $result -Path $OutputPath
}
$result
