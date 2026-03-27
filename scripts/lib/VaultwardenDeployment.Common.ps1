Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
function Get-RepoRoot {
    param([string]$StartPath = $PSScriptRoot)
    $current = Resolve-Path $StartPath
    if ($current.Path -and (Test-Path -LiteralPath $current.Path -PathType Leaf)) {
        $current = Split-Path -Parent $current.Path | Resolve-Path
    }
    while ($current) {
        if ((Test-Path -LiteralPath (Join-Path $current.Path 'main.json')) -and (Test-Path -LiteralPath (Join-Path $current.Path 'Readme.md'))) {
            return $current.Path
        }
        $parentPath = Split-Path -Parent $current.Path
        if ([string]::IsNullOrWhiteSpace($parentPath) -or $parentPath -eq $current.Path) { break }
        $current = Resolve-Path $parentPath
    }
    throw 'RepoRoot konnte nicht ermittelt werden.'
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host $Title
    Write-Host ('=' * 72)
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ('[+] {0}' -f $Message)
}

# Runs a ScriptBlock while displaying a live spinner with elapsed time.
# Shows:  [~] <Message> <spinner> <mm:ss>   (updated in-place each tick)
# Prints: [OK] <Message> (<mm:ss>)          on success
# Prints: [FEHLER] <Message> (<mm:ss>)       on error, then re-throws
# Returns the value produced by ScriptBlock.
function Invoke-WithSpinner {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [int]$RefreshMilliseconds = 120
    )

    $spinChars   = @('|', '/', '-', '\')
    $spinIdx     = 0
    $lineWidth   = 82   # wide enough to cover [~] + message + spinner char + mm:ss
    $stopwatch   = [System.Diagnostics.Stopwatch]::StartNew()

    # Run the block on a background thread so the spinner can tick on the main thread.
    $job = Start-ThreadJob -ScriptBlock $ScriptBlock -ErrorAction Stop

    $consoleAvailable = $true
    try { $null = [Console]::CursorVisible } catch { $consoleAvailable = $false }

    try {
        while ($job.State -eq 'Running') {
            $elapsed = $stopwatch.Elapsed
            $display = '[~] {0} {1} {2:mm\:ss}' -f $Message, $spinChars[$spinIdx % $spinChars.Count], $elapsed
            if ($consoleAvailable) {
                [Console]::Write("`r{0,-$lineWidth}" -f $display)
            }
            $spinIdx++
            Start-Sleep -Milliseconds $RefreshMilliseconds
        }
    }
    finally {
        # Ensure the spinner line is cleared before printing the final status.
        if ($consoleAvailable) { [Console]::Write("`r{0}`r" -f (' ' * $lineWidth)) }
    }

    $elapsed = $stopwatch.Elapsed
    $elapsedStr = $elapsed.ToString('mm\:ss')

    # Collect output and check for errors.
    $jobResult = Receive-Job -Job $job -Wait -ErrorAction SilentlyContinue
    $jobError  = $job.Error

    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

    if ($jobError -and $jobError.Count -gt 0) {
        Write-Host ('[FEHLER] {0} ({1})' -f $Message, $elapsedStr) -ForegroundColor Red
        # Re-throw the first error from the job.
        throw $jobError[0].Exception
    }

    Write-Host ('[OK] {0} ({1})' -f $Message, $elapsedStr) -ForegroundColor Green
    return $jobResult
}

function Read-TextWithDefault {
    param(
        [Parameter(Mandatory)][string]$Label,
        [string]$Default = '',
        [switch]$Required
    )
    while ($true) {
        $prompt = if ([string]::IsNullOrWhiteSpace($Default)) { $Label } else { '{0} [{1}]' -f $Label, $Default }
        $value = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
        if ($Required -and [string]::IsNullOrWhiteSpace($value)) {
            Write-Warning ('{0} darf nicht leer sein.' -f $Label)
            continue
        }
        return $value
    }
}

function Read-BooleanWithDefault {
    param(
        [Parameter(Mandatory)][string]$Label,
        [bool]$Default = $true
    )
    $defaultToken = if ($Default) { 'Y/n' } else { 'y/N' }
    while ($true) {
        $raw = Read-Host ('{0} [{1}]' -f $Label, $defaultToken)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        switch -Regex ($raw.Trim()) {
            '^(y|yes|j|ja|1|true)$' { return $true }
            '^(n|no|nein|0|false)$' { return $false }
            default { Write-Warning 'Bitte ja/nein eingeben.' }
        }
    }
}

function Read-ChoiceWithDefault {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][hashtable]$Choices,
        [Parameter(Mandatory)][string]$DefaultKey
    )
    while ($true) {
        Write-Host ''
        Write-Host $Label
        foreach ($key in ($Choices.Keys | Sort-Object)) {
            $marker = if ($key -eq $DefaultKey) { '*' } else { ' ' }
            Write-Host ('  [{0}] {1}{2}' -f $key, $marker, $Choices[$key])
        }
        $selected = Read-Host ('Auswahl [{0}]' -f $DefaultKey)
        if ([string]::IsNullOrWhiteSpace($selected)) { $selected = $DefaultKey }
        $selected = $selected.Trim()
        if ($Choices.ContainsKey($selected)) { return $selected }
        Write-Warning 'Ungültige Auswahl.'
    }
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
function Save-JsonUtf8 {
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][string]$Path,
        [int]$Depth = 20
    )
    $dir = Split-Path -Parent $Path
    if ($dir) { Ensure-Directory -Path $dir | Out-Null }
    $json = $Data | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return $json | ConvertFrom-Json -Depth 50
    }
    return $json | ConvertFrom-Json
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
function ConvertTo-HashtableDeep {
    param([Parameter(Mandatory)]$InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-HashtableDeep -InputObject $InputObject[$key]
        }
        return $hash
    }
    if ($InputObject -is [pscustomobject]) {
        $hash = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $hash[$prop.Name] = ConvertTo-HashtableDeep -InputObject $prop.Value
        }
        return $hash
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = [System.Collections.ArrayList]::new()
        foreach ($item in $InputObject) {
            $list.Add((ConvertTo-HashtableDeep -InputObject $item)) | Out-Null
        }
        return ,$list.ToArray()
    }
    return $InputObject
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
function Convert-DomainToSlug {
    param([Parameter(Mandatory)][string]$Domain)
    $slug = ($Domain.ToLowerInvariant() -replace '[^a-z0-9]+', '-')
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw 'Aus der Vaultwarden-Domäne konnte kein gültiger technischer Slug abgeleitet werden.'
    }
    return $slug
}

function Convert-SlugToAppName {
    param([Parameter(Mandatory)][string]$Slug)
    # appName is intentionally fixed to a stable value. The customer context is
    # already encoded in the resource group, domain, customer folder and current/
    # state. A dynamic, truncated appName produced unreadable values like
    # 'vault50erj' and offered no operational value.
    return 'vault'
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
function Get-DefaultZoneFromHostname {
    param([Parameter(Mandatory)][string]$Hostname)
    $labels = @($Hostname -split '\.')
    if ($labels.Count -le 2) { return $Hostname.ToLowerInvariant() }
    return (($labels | Select-Object -Skip 1) -join '.').ToLowerInvariant()
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
function Get-RegionCode {
    param([Parameter(Mandatory)][string]$Location)
    $normalized = ($Location -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    $known = @{
        germanywestcentral = 'gwc'
        northeurope = 'neu'
        westeurope = 'weu'
        germanynorth = 'gn'
        eastus = 'eus'
        eastus2 = 'eus2'
        westus = 'wus'
        westus2 = 'wus2'
        westus3 = 'wus3'
        centralus = 'cus'
        southcentralus = 'scus'
        uksouth = 'uks'
        ukwest = 'ukw'
        swedencentral = 'swec'
        francecentral = 'frc'
        italynorth = 'itn'
        spaincentral = 'spc'
        polandcentral = 'plc'
        switzerlandnorth = 'chn'
        canadacentral = 'cac'
        austriaeast = 'ate'
    }
    if ($known.ContainsKey($normalized)) { return $known[$normalized] }
    $tokens = [System.Text.RegularExpressions.Regex]::Matches($normalized, '[a-z]+|\d+') | ForEach-Object { $_.Value }
    if ($tokens.Count -eq 0) { return 'loc' }
    $abbr = ($tokens | ForEach-Object {
        if ($_ -match '^\d+$') { $_ }
        elseif ($_.Length -le 3) { $_ }
        else { $_.Substring(0,1) }
    }) -join ''
    if ([string]::IsNullOrWhiteSpace($abbr)) { return 'loc' }
    return $abbr.ToLowerInvariant()
}

function Get-CustomerSlugFromVaultwardenDomain {
    param([Parameter(Mandatory)][string]$VaultwardenDomain)
    $hostname = $VaultwardenDomain.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($hostname)) { return 'vaultwarden' }
    $zoneName = Get-DefaultZoneFromHostname -Hostname $hostname
    $zoneLabels = @($zoneName -split '\.')
    if ($zoneLabels.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($zoneLabels[0])) {
        return Convert-DomainToSlug -Domain $zoneLabels[0]
    }
    return Convert-DomainToSlug -Domain $hostname
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
function Get-DefaultResourceGroupName {
    param(
        [Parameter(Mandatory)][string]$Environment,
        [Parameter(Mandatory)][string]$Location,
        [string]$VaultwardenDomain
    )
    $envPart = ($Environment -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($envPart)) { $envPart = 'prod' }
    $regionPart = Get-RegionCode -Location $Location
    $customerPart = if ([string]::IsNullOrWhiteSpace($VaultwardenDomain)) { 'vaultwarden' } else { Get-CustomerSlugFromVaultwardenDomain -VaultwardenDomain $VaultwardenDomain }
    return ('rg-{0}-vault-{1}-{2}' -f $customerPart, $envPart, $regionPart)
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
function Get-CustomerPaths {
    param(
        [string]$RepoRoot,
        [string]$CustomersRoot,
        [Parameter(Mandatory)][string]$CustomerCode
    )
    if ([string]::IsNullOrWhiteSpace($CustomersRoot)) {
        if ([string]::IsNullOrWhiteSpace($RepoRoot)) { throw 'RepoRoot oder CustomersRoot muss angegeben werden.' }
        $CustomersRoot = Join-Path $RepoRoot 'customers'
    }
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $RepoRoot = Split-Path -Parent $CustomersRoot
    }
    $customerRoot = Join-Path $CustomersRoot $CustomerCode
    $artifactsRoot = Join-Path $customerRoot 'artifacts'
    $currentRoot = Join-Path $RepoRoot 'current'
    return @{
        CustomerRoot = $customerRoot
        ConfigPath = Join-Path $customerRoot 'deployment.config.json'
        AzureParametersPath = Join-Path $customerRoot 'azure.parameters.json'
        CustomerReadmePath = Join-Path $customerRoot 'README.md'
        ArtifactsRoot = $artifactsRoot
        DeployOutputPath = Join-Path $artifactsRoot 'last-deploy-output.json'
        CloudflareStatePath = Join-Path $artifactsRoot 'cloudflare-state.json'
        CurrentRoot = $currentRoot
        CurrentConfigPath = Join-Path $currentRoot 'deployment.config.json'
        CurrentAzureParametersPath = Join-Path $currentRoot 'azure.parameters.json'
        CurrentDeployToAzureTemplatePath = Join-Path $currentRoot 'main.deploytoazure.json'
        CurrentReadmePath = Join-Path $currentRoot 'README.md'
    }
}

function Get-AvailableCustomerCodes {
    param([Parameter(Mandatory)][string]$CustomersRoot)
    if (-not (Test-Path -LiteralPath $CustomersRoot)) { return @() }
    $dirs = Get-ChildItem -LiteralPath $CustomersRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^\.' } |
        Sort-Object Name
    return @($dirs | ForEach-Object { $_.Name })
}

function Get-HostnameFromUrl {
    param([Parameter(Mandatory)][string]$Url)
    $uri = [Uri]$Url
    return $uri.Host
}

function Test-ValidHostnameInZone {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$ZoneName
    )
    if ($Hostname -eq $ZoneName) { return $true }
    $suffix = '.{0}' -f $ZoneName
    return $Hostname.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-RelativeHostLabel {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$ZoneName
    )
    if ($Hostname -eq $ZoneName) { return '@' }
    $suffix = '.{0}' -f $ZoneName
    if (-not (Test-ValidHostnameInZone -Hostname $Hostname -ZoneName $ZoneName)) {
        throw "Hostname '$Hostname' liegt nicht in Zone '$ZoneName'."
    }
    return $Hostname.Substring(0, $Hostname.Length - $suffix.Length)
}

function Get-SubdomainVerificationRecordName {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$ZoneName
    )
    $relative = Get-RelativeHostLabel -Hostname $Hostname -ZoneName $ZoneName
    if ($relative -eq '@') { return 'asuid' }
    return 'asuid.{0}' -f $relative
}

function ConvertFrom-SecureStringPlain {
    param([Parameter(Mandatory)][SecureString]$SecureString)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Convert-CidrsToIngressRestrictions {
    param([Parameter(Mandatory)][string[]]$Cidrs)
    $rules = @()
    foreach ($cidr in $Cidrs) {
        $rules += [ordered]@{
            name = ('allow-' + ($cidr -replace '[:./]', '-'))
            description = ('Allow ' + $cidr)
            ipAddressRange = $cidr
            action = 'Allow'
        }
    }
    return $rules
}

function Normalize-IngressRestrictionParameterValue {
    param([Parameter(Mandatory)]$InputValue)
    $values = @($InputValue)
    if ($values.Count -eq 0) { return @() }
    $first = $values[0]
    if ($first -is [string]) {
        return @(Convert-CidrsToIngressRestrictions -Cidrs @($values))
    }
    return $values
}

function New-RandomPlaintextSecret {
    param([int]$Bytes = 32)
    $buffer = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($buffer)
    }
    finally {
        $rng.Dispose()
    }
    return [Convert]::ToBase64String($buffer).TrimEnd('=').Replace('+','-').Replace('/','_')
}

function Test-AzCliPresent {
    <#
    .SYNOPSIS
        Returns $true if Azure CLI (az) is on PATH, $false otherwise.
    #>
    return [bool](Get-Command az -ErrorAction SilentlyContinue)
}

function Update-PathFromRegistry {
    <#
    .SYNOPSIS
        Refreshes the current session PATH from the Windows registry.
    .DESCRIPTION
        After an MSI/winget install the new PATH entry is only visible to new
        processes. This function re-reads Machine and User PATH from the
        registry and merges them into the current session so that freshly
        installed tools become available without restarting PowerShell.
        On non-Windows platforms this is a no-op.
    #>
    if ($env:OS -ne 'Windows_NT') { return }
    $machinePath = [System.Environment]::GetEnvironmentVariable('PATH', [System.EnvironmentVariableTarget]::Machine)
    $userPath    = [System.Environment]::GetEnvironmentVariable('PATH', [System.EnvironmentVariableTarget]::User)
    $env:PATH    = '{0};{1}' -f $machinePath, $userPath
}

function Install-AzCli {
    <#
    .SYNOPSIS
        Attempts to install Azure CLI automatically.
    .DESCRIPTION
        Platform-aware auto-install:
          Windows  – winget (preferred) or MSI via msiexec
          Linux    – Microsoft install script (curl)
          macOS    – Homebrew
        On Windows the install may require elevation. If the current session
        is not elevated the function will try to spawn an elevated process.
        After installation the session PATH is refreshed so that az is
        immediately available.
    .OUTPUTS
        Returns $true if az became available after install, $false otherwise.
    #>
    [CmdletBinding()]
    param()

    Write-Step 'Azure CLI (az) nicht gefunden. Automatische Installation wird versucht...'

    $isWindows = ($env:OS -eq 'Windows_NT')
    # PS7+ sets $IsLinux / $IsMacOS; PS5.1 on Windows does not, so fall back.
    $isLinux = if (Get-Variable -Name IsLinux -ValueOnly -ErrorAction SilentlyContinue) { $IsLinux } else { $false }
    $isMacOS = if (Get-Variable -Name IsMacOS -ValueOnly -ErrorAction SilentlyContinue) { $IsMacOS } else { $false }

    if ($isWindows) {
        # ---- Windows: prefer winget, fall back to MSI ----
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            Write-Step 'Installiere Azure CLI via winget...'
            $wingetOutput = & winget install -e --id Microsoft.AzureCLI --accept-source-agreements --accept-package-agreements 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning ('winget-Installation fehlgeschlagen (Exit-Code {0}): {1}' -f $LASTEXITCODE, ($wingetOutput | Out-String))
            }
        }
        else {
            Write-Step 'winget nicht verfuegbar. Installiere Azure CLI via MSI...'
            $msiUrl  = 'https://aka.ms/installazurecliwindows'
            $msiPath = Join-Path ([System.IO.Path]::GetTempPath()) 'AzureCLI.msi'
            try {
                # Use .NET WebClient for PS5.1 compat (Invoke-WebRequest on PS5.1 is slow/different)
                $wc = New-Object System.Net.WebClient
                $wc.DownloadFile($msiUrl, $msiPath)
            }
            catch {
                Write-Warning ('Download der Azure CLI MSI fehlgeschlagen: {0}' -f $_)
                return $false
            }
            Write-Step 'MSI-Installation wird gestartet (erfordert ggf. Elevation)...'
            $installArgs = '/i', $msiPath, '/quiet', '/norestart'
            $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs -Wait -PassThru
            if ($proc.ExitCode -ne 0) {
                Write-Warning ('MSI-Installation beendet mit Exit-Code {0}. Versuche erneut mit Elevation...' -f $proc.ExitCode)
                try {
                    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs -Verb RunAs -Wait -PassThru
                }
                catch {
                    Write-Warning ('Elevated MSI-Installation fehlgeschlagen: {0}' -f $_)
                    return $false
                }
                if ($proc.ExitCode -ne 0) {
                    Write-Warning ('Elevated MSI-Installation beendet mit Exit-Code {0}.' -f $proc.ExitCode)
                    return $false
                }
            }
            Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue
        }
        # Refresh PATH so the current session sees the new install
        Update-PathFromRegistry
    }
    elseif ($isLinux) {
        Write-Step 'Installiere Azure CLI via Microsoft-Installskript...'
        $curlCmd = Get-Command curl -ErrorAction SilentlyContinue
        if (-not $curlCmd) {
            Write-Warning 'curl wurde nicht gefunden. Azure CLI kann nicht automatisch installiert werden.'
            return $false
        }
        try {
            $installOutput = & bash -c 'curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash' 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning ('Linux-Installskript beendet mit Exit-Code {0}: {1}' -f $LASTEXITCODE, ($installOutput | Out-String))
                return $false
            }
        }
        catch {
            Write-Warning ('Linux-Installation fehlgeschlagen: {0}' -f $_)
            return $false
        }
    }
    elseif ($isMacOS) {
        Write-Step 'Installiere Azure CLI via Homebrew...'
        $brewCmd = Get-Command brew -ErrorAction SilentlyContinue
        if (-not $brewCmd) {
            Write-Warning 'Homebrew (brew) wurde nicht gefunden. Azure CLI kann nicht automatisch installiert werden.'
            return $false
        }
        try {
            $brewOutput = & brew install azure-cli 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning ('Homebrew-Installation beendet mit Exit-Code {0}: {1}' -f $LASTEXITCODE, ($brewOutput | Out-String))
                return $false
            }
        }
        catch {
            Write-Warning ('Homebrew-Installation fehlgeschlagen: {0}' -f $_)
            return $false
        }
    }
    else {
        Write-Warning 'Unbekannte Plattform. Automatische Azure CLI-Installation nicht moeglich.'
        return $false
    }

    # Verify az is now available
    if (Test-AzCliPresent) {
        Write-Step 'Azure CLI erfolgreich installiert.'
        return $true
    }
    return $false
}


function Invoke-AzCapture {
    <#
    .SYNOPSIS
        Runs an Azure CLI command without surfacing stderr as a PowerShell error.
    .DESCRIPTION
        Start-Process with redirected stdout/stderr is used so the normal CLI state
        'not logged in' can be detected via exit code and stderr text instead of
        becoming a terminating PowerShell error when $ErrorActionPreference='Stop'.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath 'az' -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        return [ordered]@{
            ExitCode = $proc.ExitCode
            StdOut   = ([System.IO.File]::ReadAllText($stdoutFile))
            StdErr   = ([System.IO.File]::ReadAllText($stderrFile))
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-AzCurrentAccount {
    [CmdletBinding()]
    param()
    $result = Invoke-AzCapture -Arguments @('account','show','--only-show-errors','-o','json')
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.StdOut)) {
        return $null
    }
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return ($result.StdOut | ConvertFrom-Json -Depth 10)
    }
    return ($result.StdOut | ConvertFrom-Json)
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
function Ensure-AzCliReady {
    <#
    .SYNOPSIS
        Ensures Azure CLI is installed and the user is logged in.
    .DESCRIPTION
        All local deployment scripts use Azure CLI (az) as the single toolchain.
        1. Checks if az is on PATH.
        2. If missing, attempts automatic installation via Install-AzCli.
        3. If still missing, throws with a clear manual-install message.
        4. Unless -SkipLogin is set, verifies an active Azure login and
           starts az login interactively if needed.
    #>
    [CmdletBinding()]
    param([switch]$SkipLogin)

    if (-not (Test-AzCliPresent)) {
        $installed = Install-AzCli
        if (-not $installed) {
            throw ('Azure CLI (az) konnte nicht automatisch installiert werden. ' +
                   'Bitte manuell installieren: https://learn.microsoft.com/cli/azure/install-azure-cli ' +
                   'und danach eine neue PowerShell-Session starten.')
        }
    }

    if (-not $SkipLogin) {
        $account = Get-AzCurrentAccount
        if ($null -eq $account) {
            Write-Step 'Kein Azure-Login gefunden. Starte az login...'
            & az login
            if ($LASTEXITCODE -ne 0) {
                throw 'Azure-Login fehlgeschlagen. Bitte manuell az login ausfuehren.'
            }

            $account = Get-AzCurrentAccount
            if ($null -eq $account) {
                throw 'Azure-Login konnte nicht verifiziert werden. Bitte manuell az login ausfuehren und erneut starten.'
            }
        }
        Write-Step ('Azure-Login aktiv: {0} (Subscription: {1})' -f $account.user.name, $account.name)
    }
}


# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
function Ensure-ResourceGroupExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$Location
    )

    if ([string]::IsNullOrWhiteSpace($Location)) {
        throw 'Location darf nicht leer sein, wenn die Resource Group erstellt werden soll.'
    }

    $show = Invoke-AzCapture -Arguments @('group','show','--name',$ResourceGroupName,'--only-show-errors','-o','json')
    if ($show.ExitCode -eq 0) {
        return
    }

    Write-Step ("Resource Group '{0}' nicht gefunden. Erstelle sie in '{1}'..." -f $ResourceGroupName, $Location)
    $create = Invoke-AzCapture -Arguments @('group','create','--name',$ResourceGroupName,'--location',$Location,'--only-show-errors','-o','json')
    if ($create.ExitCode -ne 0) {
        $detail = if ($create.StdErr) { $create.StdErr } elseif ($create.StdOut) { $create.StdOut } else { 'Unbekannter Fehler' }
        throw ("Resource Group '{0}' konnte nicht erstellt werden: {1}" -f $ResourceGroupName, $detail.Trim())
    }
    Write-Step ("Resource Group '{0}' ist bereit." -f $ResourceGroupName)
}
function Test-OpenSslPresent {
    if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
        throw 'openssl wurde nicht gefunden.'
    }
}

function Invoke-CloudflareApi {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ApiToken,
        $Body,
        [switch]$AllowNotFound
    )
    $base = 'https://api.cloudflare.com/client/v4'
    $headers = @{ Authorization = 'Bearer ' + $ApiToken }
    if ($null -ne $Body) { $headers['Content-Type'] = 'application/json' }
    try {
        if ($null -ne $Body) {
            $payload = $Body | ConvertTo-Json -Depth 20 -Compress
            $response = Invoke-RestMethod -Method $Method -Uri ($base + $Path) -Headers $headers -Body $payload
        }
        else {
            $response = Invoke-RestMethod -Method $Method -Uri ($base + $Path) -Headers $headers
        }
        if (-not $response.success) {
            $message = ($response.errors | ForEach-Object { $_.message }) -join '; '
            throw "Cloudflare API Fehler: $message"
        }
        return $response.result
    }
    catch {
        $statusCode = $null
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
        if ($AllowNotFound -and $statusCode -eq 404) { return $null }
        throw
    }
}

function Get-AdvancedParameterValue {
    param([hashtable]$Advanced, [string]$Name, $Default = $null)
    if ($Advanced -and $Advanced.ContainsKey($Name)) { return $Advanced[$Name] }
    return $Default
}

function New-EmptyAdvancedArmParameters {
    return [ordered]@{
        adminPanelEnabled = $true
        invitationOrgName = ''
        signupsDomainsWhitelist = ''
        orgCreationUsers = ''
        diagnosticsEnabled = $true
        allowInsecureHttp = $true
        ssoEnabled = $false
        ssoOnly = $false
        ssoAuthority = ''
        ssoClientId = ''
        ssoScopes = 'openid profile email offline_access User.Read'
        pushEnabled = $false
        pushInstallationId = ''
        pushUseEuServers = $false
        acsDeployFoundation = $false
        acsDataLocation = 'Germany'
        acsDomainName = ''
        storageAccountSku = 'Standard_LRS'
        postgresSkuName = 'Standard_B1ms'
        postgresStorageGB = 32
        postgresBackupRetentionDays = 14
        allowAzureServicesToPostgres = $true
    }
}

function Get-SuggestedInvitationOrgName {
    param([Parameter(Mandatory)][string]$ZoneName)
    return $ZoneName
}

function Get-SuggestedSignupsDomainsWhitelist {
    param([Parameter(Mandatory)][string]$ZoneName)
    return $ZoneName
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
# Liest die aktuell an eine ACA-App gebundenen Custom Domains aus der Live-Umgebung.
# Gibt ein (möglicherweise leeres) Array von Custom-Domain-Objekten zurück.
# Gibt @() zurück wenn die Resource Group, die App oder die Custom Domains nicht existieren
# (robuster no-op für Erstdeployments).
function Get-AcaCustomDomains {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$AppName
    )
    try {
        # Temporarily suppress native-command errors so a missing RG or app never
        # throws a terminating error (important when running inside Start-ThreadJob
        # with $ErrorActionPreference = 'Stop').
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        $json = az containerapp show -g $ResourceGroupName -n $AppName `
            --query 'properties.configuration.ingress.customDomains' `
            -o json --only-show-errors 2>$null
        $ErrorActionPreference = $prevEap
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($json) -or $json.Trim() -eq 'null') {
            return @()
        }
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $parsed = $json | ConvertFrom-Json -Depth 20
        } else {
            $parsed = $json | ConvertFrom-Json
        }
        if ($null -eq $parsed) { return @() }
        return @($parsed)
    }
    catch {
        # Any unexpected error (e.g. NativeCommandExitException on PS 7.3+) is
        # treated as "nothing to preserve" so a first deployment is never blocked.
        return @()
    }
}

# SHARED LOGIC: Wird von mehreren Deploy-/Wizard-Pfaden verwendet.
# Änderungen hier können Seiteneffekte in anderen Workflows verursachen.
# Stellt zuvor gespeicherte ACA Custom Domain Bindings nach einem Redeploy wieder her.
# Für jede Custom Domain wird 'az containerapp hostname bind' aufgerufen.
# Ist $CustomDomains leer, passiert nichts (kein Fehler).
function Restore-AcaCustomDomains {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$CustomDomains
    )
    if (-not $CustomDomains -or $CustomDomains.Count -eq 0) {
        return
    }
    Write-Step ("ACA Custom Domain Bindings werden nach Redeploy wiederhergestellt ({0} Einträge)." -f $CustomDomains.Count)
    foreach ($domain in $CustomDomains) {
        $hostname = if ($domain -is [string]) { $domain } else { [string]$domain.name }
        $certId   = if ($domain -is [string]) { $null } else { [string]$domain.certificateId }
        if ([string]::IsNullOrWhiteSpace($hostname)) { continue }
        if ([string]::IsNullOrWhiteSpace($certId)) {
            Write-Step ("  Hostname '{0}' wird ohne Zertifikat hinzugefügt (kein certificateId gespeichert)." -f $hostname)
            az containerapp hostname add -g $ResourceGroupName -n $AppName --hostname $hostname --only-show-errors | Out-Null
        } else {
            Write-Step ("  Hostname '{0}' wird an Zertifikat gebunden." -f $hostname)
            az containerapp hostname bind -g $ResourceGroupName -n $AppName `
                --hostname $hostname --environment $EnvironmentName `
                --certificate $certId --only-show-errors | Out-Null
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Warning ("Warnung: Custom Domain '{0}' konnte nicht wiederhergestellt werden (ExitCode: {1}). Bitte manuell prüfen." -f $hostname, $LASTEXITCODE)
        }
    }
}

function New-CustomerReadmeContent {
    param([Parameter(Mandatory)]$Config)
@"
# $($Config.customerCode)

- Kunden-Nr.: $($Config.customerNumber)
- Vaultwarden-Domäne: $($Config.domain.hostname)
- Resource Group: $($Config.azure.resourceGroupName)
- Location: $($Config.azure.location)
- URL: $($Config.domain.url)
- Edge-Modus: $($Config.edge.mode)
- WAF: $($Config.edge.enableWaf)
- Rate Limit: $($Config.edge.enableRateLimit)
- Origin Lockdown: $($Config.edge.lockOriginToCloudflare)

> ``deployment.config.json`` ist die persistente Kundenkonfiguration.
> ``azure.parameters.json`` wird pro Deployment neu generiert und kann Secrets enthalten. Deshalb ist diese Datei per ``.gitignore`` ausgeschlossen.
> Erweiterte ARM-Parameter stehen unter ``azure.advancedArmParameters`` in der Kundenkonfiguration.
"@
}
