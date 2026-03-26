[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ResourceGroupName,
  [string]$Location = 'germanywestcentral',
  [string]$DomainUrl,
  [bool]$SmtpUseAuth = $true,
  [string]$MailRootDomain = '',
  [string]$SmtpFrom = '',
  [string]$SmtpFromName = 'Vaultwarden',
  [string]$SmtpHost = '',
  [string]$SmtpPort = '587',
  [ValidateSet('starttls','force_tls','off')][string]$SmtpSecurity = 'starttls',
  [string]$SmtpUsername = '',
  [securestring]$SmtpPassword,
  [ValidateSet('prod','test','dev')][string]$Environment = 'prod',
  [string]$BsseRef = '',
  [string]$InvitationOrgName = '',
  [string]$SignupsDomainsWhitelist = '',
  [string]$OrgCreationUsers = ''
)

. (Join-Path $PSScriptRoot 'lib/VaultwardenDeployment.Common.ps1')
Ensure-AzCliReady
Ensure-ResourceGroupExists -ResourceGroupName $ResourceGroupName -Location $Location

if ([string]::IsNullOrWhiteSpace($DomainUrl)) {
  $DomainUrl = Read-Host 'Domain URL (z.B. https://vault.example.com)'
}
$hostname = Get-HostnameFromUrl -Url $DomainUrl
if ([string]::IsNullOrWhiteSpace($MailRootDomain)) {
  $MailRootDomain = Get-DefaultZoneFromHostname -Hostname $hostname
}
if ([string]::IsNullOrWhiteSpace($InvitationOrgName)) {
  $InvitationOrgName = Get-SuggestedInvitationOrgName -ZoneName $MailRootDomain
}
if ([string]::IsNullOrWhiteSpace($SignupsDomainsWhitelist)) {
  $SignupsDomainsWhitelist = Get-SuggestedSignupsDomainsWhitelist -ZoneName $MailRootDomain
}
if ([string]::IsNullOrWhiteSpace($SmtpFrom)) {
  $SmtpFrom = 'vaultwarden@' + $MailRootDomain
}
if ($SmtpUseAuth) {
  if ([string]::IsNullOrWhiteSpace($SmtpHost)) { $SmtpHost = 'smtp.office365.com' }
  if ([string]::IsNullOrWhiteSpace($SmtpUsername)) { $SmtpUsername = $SmtpFrom }
  if (-not $SmtpPassword) { $SmtpPassword = Read-Host -AsSecureString 'SMTP Password' }
}

$repoRoot = Get-RepoRoot -StartPath $PSScriptRoot
$templatePath = Join-Path $repoRoot 'main.json'
$paramFile = Join-Path ([System.IO.Path]::GetTempPath()) ('vaultwarden.parameters.{0}.json' -f ([guid]::NewGuid().ToString('N')))
try {
  $params = [ordered]@{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = [ordered]@{
      location = @{ value = $Location }
      environment = @{ value = $Environment }
      bsseRef = @{ value = $BsseRef }
      domainUrl = @{ value = $DomainUrl }
      customHostname = @{ value = $hostname }
      mailRootDomain = @{ value = $MailRootDomain }
      smtpUseAuth = @{ value = $SmtpUseAuth }
      smtpFrom = @{ value = $SmtpFrom }
      smtpFromName = @{ value = $SmtpFromName }
      invitationOrgName = @{ value = $InvitationOrgName }
      signupsDomainsWhitelist = @{ value = $SignupsDomainsWhitelist }
      orgCreationUsers = @{ value = $OrgCreationUsers }
    }
  }
  if ($SmtpUseAuth) {
    $params.parameters.smtpHost = @{ value = $SmtpHost }
    $params.parameters.smtpPort = @{ value = $SmtpPort }
    $params.parameters.smtpSecurity = @{ value = $SmtpSecurity }
    $params.parameters.smtpUsername = @{ value = $SmtpUsername }
    $params.parameters.smtpPassword = @{ value = (ConvertFrom-SecureStringPlain -SecureString $SmtpPassword) }
  }
  Save-JsonUtf8 -Data $params -Path $paramFile
  az deployment group create --resource-group $ResourceGroupName --template-file $templatePath --parameters @$paramFile
}
finally {
  if (Test-Path -LiteralPath $paramFile) { Remove-Item -LiteralPath $paramFile -Force -ErrorAction SilentlyContinue }
}
