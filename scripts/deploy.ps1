param(
  [Parameter(Mandatory=$true)]
  [string]$ResourceGroupName,

  # Public URL of Vaultwarden, e.g. https://vault.example.com
  [Parameter(Mandatory=$false)]
  [string]$DomainUrl,

  # SMTP mode
  # - $false (Default): Direct Send ohne Auth (Port 25, STARTTLS, MX Lookup anhand der Domain aus DomainUrl)
  # - $true: SMTP Submission mit Auth (z.B. smtp.office365.com:587)
  [Parameter(Mandatory=$false)]
  [bool]$SmtpUseAuth = $false,

  # Optional: Absender-Override (z.B. vault@kundendomain.tld).
  # Leer lassen = Template setzt default auf vault@<BaseDomain aus DomainUrl>
  [Parameter(Mandatory=$false)]
  [string]$SmtpFrom,

  [Parameter(Mandatory=$false)]
  [string]$SmtpFromName = "Vaultwarden",

  # Optional: HELO/EHLO Name. Leer lassen = Hostname aus DomainUrl wird verwendet.
  [Parameter(Mandatory=$false)]
  [string]$HeloName,

  # Optional: SMTP Auth Mechanism (nur bei Auth), z.B. "Login" / "Plain" / "Xoauth2"
  [Parameter(Mandatory=$false)]
  [string]$SmtpAuthMechanism,

  # Optional: SMTP Host Override
  # - Direct Send: leer = MX Lookup anhand BaseDomain aus DomainUrl
  # - Auth-Mode: leer = smtp.office365.com
  [Parameter(Mandatory=$false)]
  [string]$SmtpHost,

  [Parameter(Mandatory=$false)]
  [int]$SmtpPort,

  [Parameter(Mandatory=$false)]
  [ValidateSet("starttls","force_tls","off")]
  [string]$SmtpSecurity,

  [ValidateSet("custom", "acsSmtp")]
  [string]$SmtpAuthPreset = "custom",

  # ACS SMTP (nur bei $SmtpUseAuth = $true und $SmtpAuthPreset = "acsSmtp")
  [string]$AcsDataLocation = "Germany",
  [string]$AcsDomainName = "",
  [ValidateSet("CustomerManaged", "CustomerManagedInExchangeOnline")]
  [string]$AcsDomainManagement = "CustomerManaged",
  [string]$AcsEntraApplicationId = "",
  [string]$AcsEntraTenantId = "",
  [string]$AcsEntraServicePrincipalObjectId = "",

  # SMTP Auth (nur bei $SmtpUseAuth = $true)
  [Parameter(Mandatory=$false)]
  [string]$SmtpUsername,

  [Parameter(Mandatory=$false)]
  [securestring]$SmtpPassword,

  # Optional: SSO (OIDC) für Web Vault Login (Vaultwarden >= 1.35)
  [Parameter(Mandatory=$false)]
  [bool]$SsoEnabled = $false,

  [Parameter(Mandatory=$false)]
  [bool]$SsoOnly = $false,

  [Parameter(Mandatory=$false)]
  [string]$SsoAuthority = "",

  [Parameter(Mandatory=$false)]
  [string]$SsoClientId = "",

  [Parameter(Mandatory=$false)]
  [securestring]$SsoClientSecret,

  [Parameter(Mandatory=$false)]
  [string]$SsoScopes = "openid profile email offline_access User.Read",

  # Optional: Push Notifications (Mobile Clients) via Bitwarden Push Relay
  [Parameter(Mandatory=$false)]
  [bool]$PushEnabled = $false,

  [Parameter(Mandatory=$false)]
  [string]$PushInstallationId = "",

  [Parameter(Mandatory=$false)]
  [securestring]$PushInstallationKey,

  [Parameter(Mandatory=$false)]
  [bool]$PushUseEuServers = $false,

  # Optional: Restrict who can create Organizations (Directory Connector / Governance)
  [Parameter(Mandatory=$false)]
  [string]$OrgCreationUsers = "",


  [ValidateSet("prod","test","dev")]
  [string]$Environment = "prod",

  [string]$BsseRef = ""
)

# Requires: Azure CLI (az) and (optionally) git
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw "Azure CLI (az) wurde nicht gefunden. Bitte Azure CLI installieren und 'az login' ausführen."
}

if ([string]::IsNullOrWhiteSpace($BsseRef)) {
  if (Get-Command git -ErrorAction SilentlyContinue) {
    try {
      $BsseRef = (git describe --tags --always --dirty 2>$null).Trim()
      if ([string]::IsNullOrWhiteSpace($BsseRef)) {
        $BsseRef = (git rev-parse --short HEAD 2>$null).Trim()
      }
    } catch { }
  }
}

Write-Host "Deploying with tags: Environment=$Environment, bsse:ref=$BsseRef"
Write-Host "SMTP mode: " -NoNewline
if ($SmtpUseAuth) {
  if ($SmtpAuthPreset -eq "acsSmtp") { Write-Host "AUTH (acsSmtp / smtp.azurecomm.net:587)" }
  else { Write-Host "AUTH (custom)" }
} else { Write-Host "DIRECT SEND (no-auth / Port 25)" }

# ACS SMTP Zusatzparameter (nur wenn aktiviert)
if ($SmtpUseAuth -and $SmtpAuthPreset -eq "acsSmtp") {
  if (-not $AcsEntraApplicationId) { $AcsEntraApplicationId = Read-Host "Entra App (Client) ID (acsEntraApplicationId)" }
  if (-not $AcsEntraServicePrincipalObjectId) { $AcsEntraServicePrincipalObjectId = Read-Host "Service Principal Object ID (acsEntraServicePrincipalObjectId) (Tipp: az ad sp show --id <APPID> --query id -o tsv)" }
  if (-not $AcsEntraTenantId) { $AcsEntraTenantId = "" }
  if (-not $AcsDomainName) { $AcsDomainName = "" }
  if (-not $SmtpUsername) { $SmtpUsername = Read-Host "ACS SMTP Username (smtpUsername) (frei oder email@domain)" }
  if (-not $SmtpPassword) { $SmtpPassword = Read-Host -AsSecureString "ACS Entra App Client Secret (smtpPassword)" }
}

if ([string]::IsNullOrWhiteSpace($DomainUrl)) {
  $DomainUrl = Read-Host "Domain URL (e.g. https://vault.example.com)"
}

# --- SMTP Eingaben abhängig vom Modus ---
if (-not $SmtpUseAuth) {
  # Direct Send: Keine Pflichtangaben außer DomainUrl.
  # - SmtpHost leer lassen = Template macht MX Lookup.
  # - SmtpFrom leer lassen = Template baut vault@<base-domain aus DomainUrl>.
  if ([string]::IsNullOrWhiteSpace($SmtpFrom)) { $SmtpFrom = "" }
  if ([string]::IsNullOrWhiteSpace($SmtpHost)) { $SmtpHost = "" }
}
else {
  # Auth-Mode: SMTP Host/Port/Security können optional übergeben werden
  if ([string]::IsNullOrWhiteSpace($SmtpHost)) {
    $SmtpHost = Read-Host "SMTP Host (leer = smtp.office365.com)"
  }
  if (-not $SmtpPort) {
    $SmtpPort = [int](Read-Host "SMTP Port (e.g. 587)")
  }
  if ([string]::IsNullOrWhiteSpace($SmtpSecurity)) {
    $SmtpSecurity = Read-Host "SMTP Security (starttls|force_tls|off)"
  }
  if ([string]::IsNullOrWhiteSpace($SmtpFrom)) {
    $SmtpFrom = Read-Host "SMTP From (e.g. vault@yourdomain.tld)"
  }
  if ([string]::IsNullOrWhiteSpace($SmtpUsername)) {
    $SmtpUsername = Read-Host "SMTP Username"
  }
  if (-not $SmtpPassword) {
    $SmtpPassword = Read-Host "SMTP Password" -AsSecureString
  }
}


# --- Optional: SSO (OIDC) Eingaben ---
if ($SsoEnabled) {
  if ([string]::IsNullOrWhiteSpace($SsoAuthority)) {
    $SsoAuthority = Read-Host "SSO Authority (OIDC) (z.B. https://login.microsoftonline.com/<TENANT_ID>/v2.0)"
  }
  if ([string]::IsNullOrWhiteSpace($SsoClientId)) {
    $SsoClientId = Read-Host "SSO Client ID (Application (client) ID)"
  }
  if (-not $SsoClientSecret) {
    $SsoClientSecret = Read-Host "SSO Client Secret" -AsSecureString
  }
  if ([string]::IsNullOrWhiteSpace($SsoScopes)) {
    $SsoScopes = "openid profile email offline_access User.Read"
  }
}

# --- Optional: Push Notifications Eingaben ---
if ($PushEnabled) {
  if ([string]::IsNullOrWhiteSpace($PushInstallationId)) {
    $PushInstallationId = Read-Host "Push Installation ID (von https://bitwarden.com/host/)"
  }
  if (-not $PushInstallationKey) {
    $PushInstallationKey = Read-Host "Push Installation Key (von https://bitwarden.com/host/)" -AsSecureString
  }
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TemplatePath = Join-Path $RepoRoot "main.json"

if (-not (Test-Path $TemplatePath)) {
  throw "Template nicht gefunden: $TemplatePath"
}

$smtpPasswordPlain = $null
$paramFile = Join-Path ([System.IO.Path]::GetTempPath()) ("vaultwarden.parameters.{0}.json" -f ([System.Guid]::NewGuid().ToString("N")))

try {
  $params = @{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = @{
      environment = @{ value = $Environment }
      bsseRef     = @{ value = $BsseRef }
      domainUrl   = @{ value = $DomainUrl }
      smtpUseAuth = @{ value = $SmtpUseAuth }
      smtpFromName      = @{ value = $SmtpFromName }
      heloName          = @{ value = $HeloName }
      smtpAuthMechanism = @{ value = $SmtpAuthMechanism }
      ssoEnabled       = @{ value = $SsoEnabled }
      ssoOnly          = @{ value = $SsoOnly }
      ssoAuthority     = @{ value = $SsoAuthority }
      ssoClientId      = @{ value = $SsoClientId }
      ssoScopes        = @{ value = $SsoScopes }
      pushEnabled      = @{ value = $PushEnabled }
      pushInstallationId = @{ value = $PushInstallationId }
      pushUseEuServers = @{ value = $PushUseEuServers }
      orgCreationUsers = @{ value = $OrgCreationUsers }
    smtpAuthPreset = @{ value = $SmtpAuthPreset }
    acsDataLocation = @{ value = $AcsDataLocation }
    acsDomainName = @{ value = $AcsDomainName }
    acsDomainManagement = @{ value = $AcsDomainManagement }
    acsEntraApplicationId = @{ value = $AcsEntraApplicationId }
    acsEntraTenantId = @{ value = $AcsEntraTenantId }
    acsEntraServicePrincipalObjectId = @{ value = $AcsEntraServicePrincipalObjectId }

      smtpFrom          = @{ value = $SmtpFrom }
      smtpHost          = @{ value = $SmtpHost }
      smtpPort          = @{ value = $SmtpPort }
      smtpSecurity      = @{ value = $SmtpSecurity }
      smtpUsername      = @{ value = $SmtpUsername }
      # smtpPassword wird nur gesetzt, wenn Auth-Mode aktiv ist
    }
  }

  if ($SmtpUseAuth -and $SmtpPassword) {
    # Convert securestring to plain only for the temporary parameters file (file will be deleted).
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SmtpPassword)
    try {
      $smtpPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $params.parameters.smtpPassword = @{ value = $smtpPasswordPlain }

  if ($SsoEnabled -and $SsoClientSecret) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SsoClientSecret)
    try {
      $ssoClientSecretPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $params.parameters.ssoClientSecret = @{ value = $ssoClientSecretPlain }
  }

  if ($PushEnabled -and $PushInstallationKey) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($PushInstallationKey)
    try {
      $pushInstallationKeyPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $params.parameters.pushInstallationKey = @{ value = $pushInstallationKeyPlain }
  }

  }

  $params | ConvertTo-Json -Depth 15 | Set-Content -Path $paramFile -Encoding UTF8

  az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file $TemplatePath `
    --parameters @$paramFile
}
finally {
  if (Test-Path $paramFile) {
    Remove-Item $paramFile -Force -ErrorAction SilentlyContinue
  }
  $smtpPasswordPlain = $null
  $ssoClientSecretPlain = $null
  $pushInstallationKeyPlain = $null
}