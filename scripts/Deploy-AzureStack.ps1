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

# Write az output to a temp file instead of returning it through the job pipeline.
# PS 5.1 Start-Job uses CliXml serialization; large JSON payloads can silently fail
# deserialization, causing Receive-Job to return $null even though the job succeeded.
$_azJsonFile = Join-Path ([System.IO.Path]::GetTempPath()) ('az-deploy-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    $null = Invoke-WithSpinner -Message ('Azure-Deployment laeuft: {0}' -f $DeploymentName) -ScriptBlock {
        # $using: references pass captured variables into the thread job.
        $args_capture = $using:deployArgs
        $tmpFile      = $using:_azJsonFile
        $output = az @args_capture
        if ($LASTEXITCODE -ne 0) { throw 'Azure deployment failed.' }
        # Persist to file – bypasses Start-Job CliXml serialisation for large payloads.
        if ($null -ne $output) {
            $text = if ($output -is [array]) { $output -join [System.Environment]::NewLine } else { [string]$output }
            [System.IO.File]::WriteAllText($tmpFile, $text, [System.Text.UTF8Encoding]::new($false))
        }
    }
    if (-not (Test-Path -LiteralPath $_azJsonFile)) {
        throw 'Azure-Deployment: az CLI hat keine JSON-Ausgabe geliefert.'
    }
    $json = [System.IO.File]::ReadAllText($_azJsonFile, [System.Text.UTF8Encoding]::new($false))
} finally {
    if (Test-Path -LiteralPath $_azJsonFile) {
        Remove-Item -LiteralPath $_azJsonFile -Force -ErrorAction SilentlyContinue
    }
}
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $result = $json | ConvertFrom-Json -Depth 100
} else {
    $result = $json | ConvertFrom-Json
}
if ($null -eq $result) {
    throw 'Azure-Deployment: JSON-Ausgabe konnte nicht geparst werden (null-Ergebnis).'
}
if ($OutputPath) {
    Save-JsonUtf8 -Data $result -Path $OutputPath
}
$result
