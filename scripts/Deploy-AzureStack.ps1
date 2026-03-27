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

# Native-process spinner: runs cmd.exe /c az with a live [~]/[OK]/[FEHLER] display.
# stdout/stderr are drained via .NET Tasks to prevent pipe-buffer deadlock.
# The spinner runs on the main thread (no background jobs).
$_spinMsg   = 'Azure-Deployment laeuft: {0}' -f $DeploymentName
$_spinChars = @('|', '/', '-', '\')
$_spinIdx   = 0
$_lineWidth = 82
$_quotedArgs = $deployArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
$_pinfo = [System.Diagnostics.ProcessStartInfo]::new()
$_pinfo.FileName               = 'cmd.exe'
$_pinfo.Arguments              = '/c az ' + ($_quotedArgs -join ' ')
$_pinfo.RedirectStandardOutput = $true
$_pinfo.RedirectStandardError  = $true
$_pinfo.UseShellExecute        = $false
$_proc = [System.Diagnostics.Process]::new()
$_proc.StartInfo = $_pinfo
$_sw = [System.Diagnostics.Stopwatch]::StartNew()
$json = ''; $_azStderr = ''; $_azExit = -1
try {
    $null = $_proc.Start()
    $_stdoutTask = $_proc.StandardOutput.ReadToEndAsync()
    $_stderrTask = $_proc.StandardError.ReadToEndAsync()
    try {
        while (-not $_proc.HasExited) {
            [Console]::Write("`r{0,-$_lineWidth}" -f ('[~] {0} {1} {2:mm\:ss}' -f $_spinMsg, $_spinChars[$_spinIdx++ % 4], $_sw.Elapsed))
            Start-Sleep -Milliseconds 120
        }
    } finally { [Console]::Write("`r{0}`r" -f (' ' * $_lineWidth)) }
    $_proc.WaitForExit()
    [System.Threading.Tasks.Task]::WhenAll($_stdoutTask, $_stderrTask).GetAwaiter().GetResult()
    $json       = $_stdoutTask.Result
    $_azStderr  = $_stderrTask.Result
    $_azExit    = $_proc.ExitCode
} finally { $_proc.Dispose() }
$_sw.Stop()
$_elapsed = $_sw.Elapsed.ToString('mm\:ss')
if ($_azExit -ne 0) {
    if ($_azStderr.Trim()) { Write-Host $_azStderr.Trim() -ForegroundColor Red }
    Write-Host ('[FEHLER] {0} ({1})' -f $_spinMsg, $_elapsed) -ForegroundColor Red
    throw ('Azure-Deployment fehlgeschlagen (ExitCode {0}).' -f $_azExit)
}
Write-Host ('[OK] {0} ({1})' -f $_spinMsg, $_elapsed) -ForegroundColor Green
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $result = $json | ConvertFrom-Json -Depth 100
} else {
    $result = $json | ConvertFrom-Json
}
if ($OutputPath) {
    Save-JsonUtf8 -Data $result -Path $OutputPath
}
$result
