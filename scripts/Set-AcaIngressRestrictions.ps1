[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CustomerConfigPath,
    [switch]$Redeploy,
    [string]$TemplateFile,
    [string]$OutputPath
)

. (Join-Path $PSScriptRoot 'lib/VaultwardenDeployment.Common.ps1')
$repoRoot = Get-RepoRoot -StartPath $PSScriptRoot
$configObj = Read-JsonFile -Path $CustomerConfigPath
$config = ConvertTo-HashtableDeep -InputObject $configObj
$customerRoot = Split-Path -Parent $CustomerConfigPath
$paths = @{
    CustomerRoot = $customerRoot
    ConfigPath = $CustomerConfigPath
    AzureParametersPath = Join-Path $customerRoot 'azure.parameters.json'
    CustomerReadmePath = Join-Path $customerRoot 'README.md'
    ArtifactsRoot = Join-Path $customerRoot 'artifacts'
    DeployOutputPath = Join-Path (Join-Path $customerRoot 'artifacts') 'last-deploy-output.json'
    CloudflareStatePath = Join-Path (Join-Path $customerRoot 'artifacts') 'cloudflare-state.json'
}

$cidrs = @(& (Join-Path $PSScriptRoot 'cloudflare/Get-CloudflareIpRanges.ps1'))
$config.azure.ingressAllowedCidrs = @($cidrs)
$config.azure.enableIngressIpRestrictions = $true
$config.metadata.updatedAt = (Get-Date).ToString('o')
Save-JsonUtf8 -Data $config -Path $paths.ConfigPath

if (-not (Test-Path -LiteralPath $paths.AzureParametersPath)) {
    throw "Azure-Parameterdatei nicht gefunden: $($paths.AzureParametersPath)"
}
$paramsDoc = ConvertTo-HashtableDeep -InputObject (Read-JsonFile -Path $paths.AzureParametersPath)
$paramsDoc.parameters.enableIngressIpRestrictions = @{ value = $true }
$paramsDoc.parameters.ingressAllowedCidrs = @{ value = @(Convert-CidrsToIngressRestrictions -Cidrs @($cidrs)) }
Save-JsonUtf8 -Data $paramsDoc -Path $paths.AzureParametersPath

if ($Redeploy) {
    if (-not $TemplateFile) { $TemplateFile = Join-Path $repoRoot 'main.json' }
    & (Join-Path $PSScriptRoot 'Deploy-AzureStack.ps1') -ResourceGroupName $config.azure.resourceGroupName -TemplateFile $TemplateFile -ParametersFile $paths.AzureParametersPath -OutputPath $OutputPath
}
