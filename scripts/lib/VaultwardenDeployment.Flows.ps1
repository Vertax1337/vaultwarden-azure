# Interactive flow functions for the Vaultwarden deployment wizard.
# Contains all interactive wizard helpers (config input, customer picker, ARM parameters)
# and the Start-*Flow action functions routed from Show-DeploymentMainMenu.
# All functions depend on helpers from VaultwardenDeployment.Common.ps1.
# Intended to be dot-sourced only from Invoke-CustomerDeployment.ps1.

# Testability hook: set to $true in unit tests to force the non-interactive
# fallback in Show-MultiSelectMenuSmooth and Show-SingleChoiceMenuSmooth.
$Script:_ForceNonInteractive = $false

# Interactive multi-select menu using arrow keys, spacebar and Enter.
# Supports pre-selected items via -PreSelected hashtable (item label → $true/$false).
# Falls back to a text-based prompt when the console I/O is redirected.
# Returns an array of selected item labels, or $null when Escape is pressed.
function Show-MultiSelectMenuSmooth {
    param(
        [string]$Title = 'Bitte auswählen',
        [Parameter(Mandatory)][string[]]$Items,
        [hashtable]$PreSelected = @{}
    )

    if (-not $Items -or $Items.Count -eq 0) {
        throw 'Keine Eintraege vorhanden.'
    }

    if ($Script:_ForceNonInteractive -or [System.Console]::IsInputRedirected -or [System.Console]::IsOutputRedirected) {
        Write-Host ''
        Write-Host $Title
        $selected = New-Object 'bool[]' $Items.Count
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if ($PreSelected -and $PreSelected.ContainsKey($Items[$i]) -and $PreSelected[$Items[$i]]) {
                $selected[$i] = $true
            }
        }
        while ($true) {
            Write-Host ''
            for ($i = 0; $i -lt $Items.Count; $i++) {
                $mark = if ($selected[$i]) { '[x]' } else { '[ ]' }
                Write-Host ('  {0} {1} {2}' -f ($i + 1), $mark, $Items[$i])
            }
            Write-Host '  (Komma-getrennte Nummern umschalten, leere Eingabe = fertig)'
            $raw = Read-Host 'Auswahl'
            if ([string]::IsNullOrWhiteSpace($raw)) { break }
            foreach ($tok in ($raw -split '[,\s]+')) {
                if ($tok -match '^\d+$') {
                    $idx = [int]$tok - 1
                    if ($idx -ge 0 -and $idx -lt $Items.Count) { $selected[$idx] = -not $selected[$idx] }
                }
            }
        }
        $result = @()
        for ($j = 0; $j -lt $Items.Count; $j++) {
            if ($selected[$j]) { $result += $Items[$j] }
        }
        return $result
    }

    $selected  = New-Object 'bool[]' $Items.Count
    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($PreSelected -and $PreSelected.ContainsKey($Items[$i]) -and $PreSelected[$Items[$i]]) {
            $selected[$i] = $true
        }
    }
    $index     = 0
    $startTop  = [System.Console]::CursorTop
    $lineCount = 4 + $Items.Count
    $oldCursorVisible = $true

    function Write-PaddedLine {
        param([int]$Row, [string]$Text)
        $width = [System.Console]::WindowWidth
        if ($width -lt 1) { $width = 80 }
        $out = if ($Text.Length -gt ($width - 1)) { $Text.Substring(0, $width - 1) } else { $Text.PadRight($width - 1) }
        try { if ([System.Console]::BufferHeight -lt ($Row + 2)) { [System.Console]::BufferHeight = $Row + 2 } } catch { }
        [System.Console]::SetCursorPosition(0, $Row)
        [System.Console]::Write($out)
    }

    function Render-Menu {
        Write-PaddedLine -Row $startTop       -Text $Title
        Write-PaddedLine -Row ($startTop + 1) -Text ''
        Write-PaddedLine -Row ($startTop + 2) -Text 'Pfeile = bewegen, Leertaste = umschalten, Enter = fertig, Esc = abbrechen'
        Write-PaddedLine -Row ($startTop + 3) -Text ''
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $cursor = if ($i -eq $index) { '>' } else { ' ' }
            $mark   = if ($selected[$i])  { '[x]' } else { '[ ]' }
            Write-PaddedLine -Row ($startTop + 4 + $i) -Text "$cursor $mark $($Items[$i])"
        }
    }

    try {
        try { $oldCursorVisible = [System.Console]::CursorVisible; [System.Console]::CursorVisible = $false } catch { }
        Render-Menu
        while ($true) {
            $key = [System.Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $index = if ($index -gt 0) { $index - 1 } else { $Items.Count - 1 }; Render-Menu; continue }
                'DownArrow' { $index = if ($index -lt ($Items.Count - 1)) { $index + 1 } else { 0 }; Render-Menu; continue }
                'Spacebar'  { $selected[$index] = -not $selected[$index]; Render-Menu; continue }
                'Enter' {
                    $result = @()
                    for ($j = 0; $j -lt $Items.Count; $j++) { if ($selected[$j]) { $result += $Items[$j] } }
                    [System.Console]::SetCursorPosition(0, $startTop + $lineCount)
                    return $result
                }
                'Escape' {
                    [System.Console]::SetCursorPosition(0, $startTop + $lineCount)
                    return $null
                }
            }
        }
    }
    finally {
        try { [System.Console]::CursorVisible = $oldCursorVisible } catch { }
    }
}

# Interactive single-choice (radio-button) menu.
# Shows exactly one item marked as active [x], all others as [ ].
# Arrow keys navigate, Enter accepts the current selection, Esc cancels.
# After Enter the screen is cleared.
# Falls back to a number-prompt when console I/O is redirected.
# Returns the selected item label, or $null when Escape is pressed.
function Show-SingleChoiceMenuSmooth {
    param(
        [string]$Title = 'Bitte auswählen',
        [Parameter(Mandatory)][string[]]$Items,
        [int]$InitialIndex = 0
    )

    if (-not $Items -or $Items.Count -eq 0) {
        throw 'Keine Eintraege vorhanden.'
    }

    # Clamp initial index to valid bounds [0, Count-1].
    $index = [Math]::Max(0, [Math]::Min($InitialIndex, $Items.Count - 1))

    if ($Script:_ForceNonInteractive -or [System.Console]::IsInputRedirected -or [System.Console]::IsOutputRedirected) {
        Write-Host ''
        Write-Host $Title
        Write-Host ''
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $mark = if ($i -eq $index) { '[x]' } else { '[ ]' }
            Write-Host ('  {0} {1}' -f $mark, $Items[$i])
        }
        $raw = Read-Host ('Auswahl [1-{0}], Standard {1}' -f $Items.Count, ($index + 1))
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Items[$index] }
        if ($raw -match '^\d+$') {
            $idx = [int]$raw - 1
            if ($idx -ge 0 -and $idx -lt $Items.Count) { return $Items[$idx] }
        }
        return $Items[$index]
    }

    $startTop  = 0
    $lineCount = 4 + $Items.Count
    $oldCursorVisible = $true

    function Write-SCPaddedLine {
        param([int]$Row, [string]$Text)
        $width = [System.Console]::WindowWidth
        if ($width -lt 1) { $width = 80 }
        $maxLen = $width - 1
        $out = if ($Text.Length -gt $maxLen) { $Text.Substring(0, $maxLen) } else { $Text.PadRight($maxLen) }
        try { if ([System.Console]::BufferHeight -lt ($Row + 2)) { [System.Console]::BufferHeight = $Row + 2 } } catch { }
        [System.Console]::SetCursorPosition(0, $Row)
        [System.Console]::Write($out)
    }

    function Render-SCMenu {
        Write-SCPaddedLine -Row $startTop       -Text $Title
        Write-SCPaddedLine -Row ($startTop + 1) -Text ''
        Write-SCPaddedLine -Row ($startTop + 2) -Text 'Pfeile = bewegen, Enter = waehlen, Zahl = direkt waehlen, Esc = abbrechen'
        Write-SCPaddedLine -Row ($startTop + 3) -Text ''
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $cursor = if ($i -eq $index) { '>' } else { ' ' }
            $mark   = if ($i -eq $index) { '[x]' } else { '[ ]' }
            Write-SCPaddedLine -Row ($startTop + 4 + $i) -Text "$cursor $mark $($Items[$i])"
        }
    }

    try {
        try { $oldCursorVisible = [System.Console]::CursorVisible; [System.Console]::CursorVisible = $false } catch { }
        [System.Console]::Clear()
        Render-SCMenu
        while ($true) {
            $key = [System.Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $index = if ($index -gt 0) { $index - 1 } else { $Items.Count - 1 }; Render-SCMenu; continue }
                'DownArrow' { $index = if ($index -lt ($Items.Count - 1)) { $index + 1 } else { 0 }; Render-SCMenu; continue }
                'Enter' {
                    [System.Console]::SetCursorPosition(0, $startTop + $lineCount)
                    [System.Console]::Clear()
                    return $Items[$index]
                }
                'Escape' {
                    [System.Console]::SetCursorPosition(0, $startTop + $lineCount)
                    return $null
                }
                default {
                    if ($key.KeyChar -ge '1' -and $key.KeyChar -le '9') {
                        $digit = [int][string]$key.KeyChar - 1
                        if ($digit -lt $Items.Count) { $index = $digit; Render-SCMenu }
                    }
                }
            }
        }
    }
    finally {
        try { [System.Console]::CursorVisible = $oldCursorVisible } catch { }
    }
}

function Read-WizardTextWithDefault {
    param(
        [Parameter(Mandatory)][string]$Label,
        [string]$Default = '',
        [switch]$Required
    )

    while ($true) {
        $prompt = if ([string]::IsNullOrWhiteSpace($Default)) { $Label } else { '{0} [{1}]' -f $Label, $Default }
        if ([System.Console]::IsInputRedirected -or [System.Console]::IsOutputRedirected) {
            $value = Read-Host $prompt
        }
        else {
            Write-Host ('{0}: ' -f $prompt) -NoNewline
            $buffer = New-Object System.Collections.Generic.List[char]
            $done = $false
            while (-not $done) {
                $keyInfo = [System.Console]::ReadKey($true)
                switch ($keyInfo.Key) {
                    'Escape' {
                        Write-Host ''
                        return $null
                    }
                    'Enter' {
                        Write-Host ''
                        $done = $true
                    }
                    'Backspace' {
                        if ($buffer.Count -gt 0) {
                            $buffer.RemoveAt($buffer.Count - 1)
                            [System.Console]::Write("`b `b")
                        }
                    }
                    default {
                        if (-not [char]::IsControl($keyInfo.KeyChar)) {
                            $buffer.Add($keyInfo.KeyChar)
                            [System.Console]::Write($keyInfo.KeyChar)
                        }
                    }
                }
            }
            $value = -join $buffer.ToArray()
        }

        if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
        if ($Required -and [string]::IsNullOrWhiteSpace($value)) {
            Write-Warning ('{0} darf nicht leer sein.' -f $Label)
            continue
        }
        return $value
    }
}

function Read-WizardBooleanWithDefault {
    param(
        [Parameter(Mandatory)][string]$Label,
        [bool]$Default = $true
    )

    $defaultToken = if ($Default) { 'Y/n' } else { 'y/N' }
    while ($true) {
        $raw = Read-WizardTextWithDefault -Label ('{0} [{1}]' -f $Label, $defaultToken)
        if ($null -eq $raw) { return $null }
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        switch -Regex ($raw.Trim()) {
            '^(y|yes|j|ja|1|true)$' { return $true }
            '^(n|no|nein|0|false)$' { return $false }
            default { Write-Warning 'Bitte ja/nein eingeben.' }
        }
    }
}

function Read-WizardChoiceWithDefault {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][hashtable]$Choices,
        [Parameter(Mandatory)][string]$DefaultKey
    )

    $displayItems = @()
    $keyByDisplay = @{}
    $defaultIndex = 0
    $i = 0

    foreach ($entry in $Choices.GetEnumerator()) {
        $disp = '{0} ({1})' -f $entry.Value, $entry.Key
        $displayItems += $disp
        $keyByDisplay[$disp] = [string]$entry.Key
        if ([string]$entry.Key -eq $DefaultKey) { $defaultIndex = $i }
        $i++
    }

    $selected = Show-SingleChoiceMenuSmooth -Title $Label -Items $displayItems -InitialIndex $defaultIndex
    if ($null -eq $selected) { return $null }
    return $keyByDisplay[$selected]
}

function Select-CustomerCodeInteractive {
    param(
        [Parameter(Mandatory)][string]$CustomersRoot,
        [switch]$IncludeNewConfig,
        [string]$Title = 'Vorhandene Kundenkonfigurationen'
    )

    $customers = @(Get-AvailableCustomerCodes -CustomersRoot $CustomersRoot)
    if ($customers.Count -eq 0) {
        if ($IncludeNewConfig) {
            return [pscustomobject]@{ SelectionType = 'new' }
        }
        throw 'Keine vorhandenen Kundenkonfigurationen gefunden.'
    }

    $items = @()
    $codeByKey = @{}
    $keyIndex = 1
    foreach ($customer in $customers) {
        $key = [string]$keyIndex
        $keyIndex++
        $cfgPath = Join-Path (Join-Path $CustomersRoot $customer) 'deployment.config.json'
        $display = $customer
        if (Test-Path -LiteralPath $cfgPath) {
            try {
                $cfg = Read-JsonFile -Path $cfgPath
                $display = '{0,-8}  {1,-40}  {2}' -f $cfg.customerNumber, $cfg.domain.hostname, $customer
            } catch { }
        }
        $items += New-ConsoleMenuItem -Key $key -Text $display -ItemType 'action' -ActionId ('pick:' + $key)
        $codeByKey[$key] = $customer
    }

    if ($IncludeNewConfig) {
        $items += New-ConsoleMenuItem -Key 'N' -Text '+Neue Konfiguration' -ItemType 'action' -ActionId 'new'
    }

    $items += New-ConsoleMenuItem -Key '0' -Text 'Zurück' -ItemType 'back'
    $menu = New-ConsoleMenu -Id 'customerSelection' -Title $Title -DefaultKey '1' -Items $items
    $selectedItem = Show-ConsoleMenu -Menu $menu -ClearScreenOnOpen

    if ($null -eq $selectedItem -or $selectedItem.ItemType -eq 'back') {
        return [pscustomobject]@{ SelectionType = 'back' }
    }
    if ($selectedItem.ActionId -eq 'new') {
        return [pscustomobject]@{ SelectionType = 'new' }
    }

    return [pscustomobject]@{
        SelectionType = 'existing'
        CustomerCode  = $codeByKey[[string]$selectedItem.Key]
    }
}

# Wizard function – called by Start-NewDeploymentFlow, Start-EditAndDeployFlow, and Start-GenerateOnlyFlow.
# Collects all deployment configuration interactively from the operator.
# Flow:
#   1. Kunden-Nr. → clear screen
#   2. Multi-choice feature selection (CloudFlare, SSO, Push, ACS Foundation, Admin Panel, Diagnostics)
#   3. Vaultwarden-Domäne, (Cloudflare Zone only if CF selected), Azure Region, Environment, Resource Group
#   4. Storage Account SKU, PostgreSQL SKU/Storage/Backup
#   5. Mail-Konfiguration section (Mail Root Domain, Mail-Modus selection, SMTP From/FromName/Host)
#   6. CloudFlare detail questions (only if CF selected)
#   7. SSO / Push / ACS Foundation detail questions (only if selected in multi-choice)
# Mail-Modus (3 exklusive Zielzustände): direct_send / smtp_auth / acs_smtp.
# Stale-Felder des vorherigen Modus werden durch explizite Initialisierung bereinigt.
function New-CustomerConfigInteractive {
    param([hashtable]$ExistingConfig)

    Write-Section 'Vaultwarden Customer Deployment Setup'

    # --- 1. Kunden-Nr. ---
    $customerNumber = Read-WizardTextWithDefault -Label 'Kunden-Nr.' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.customerNumber } else { '' })) -Required
    if ($null -eq $customerNumber) { return $null }

    # --- 2. Clear screen, then show multi-choice feature menu ---
    try { [System.Console]::Clear() } catch { }

    $advancedArm = if ($ExistingConfig) { ConvertTo-HashtableDeep -InputObject $ExistingConfig.azure.advancedArmParameters } else { New-EmptyAdvancedArmParameters }

    $featureItems = @(
        'CloudFlare aktivieren'
        'SSO aktivieren'
        'Push aktivieren'
        'ACS Foundation deployen'
        'Admin Panel für Bootstrap aktivieren'
        'Diagnostics aktivieren'
    )
    $featureDefaults = @{
        'CloudFlare aktivieren'              = [bool]($ExistingConfig -and ($ExistingConfig.edge.mode -eq 'cloudflare-managed'))
        'SSO aktivieren'                     = [bool](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'ssoEnabled'          -Default $false)
        'Push aktivieren'                    = [bool](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'pushEnabled'         -Default $false)
        'ACS Foundation deployen'            = [bool](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'acsDeployFoundation' -Default $false)
        'Admin Panel für Bootstrap aktivieren' = [bool](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'adminPanelEnabled' -Default $true)
        'Diagnostics aktivieren'             = [bool](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'diagnosticsEnabled'  -Default $true)
    }

    $selectedFeatures = Show-MultiSelectMenuSmooth -Title 'Optionen auswählen' -Items $featureItems -PreSelected $featureDefaults
    if ($null -eq $selectedFeatures) { $selectedFeatures = @() }

    $useCloudflare       = $selectedFeatures -contains 'CloudFlare aktivieren'
    $ssoEnabled          = $selectedFeatures -contains 'SSO aktivieren'
    $pushEnabled         = $selectedFeatures -contains 'Push aktivieren'
    $acsDeployFoundation = $selectedFeatures -contains 'ACS Foundation deployen'
    $adminPanelEnabled   = $selectedFeatures -contains 'Admin Panel für Bootstrap aktivieren'
    $diagnosticsEnabled  = $selectedFeatures -contains 'Diagnostics aktivieren'

    # --- 3. Domain, (zone), location, environment, resource group ---
    $defaultDomain = if ($ExistingConfig) { $ExistingConfig.domain.hostname } else { 'vault.example.com' }
    $vaultwardenDomainInput = Read-WizardTextWithDefault -Label 'Vaultwarden-Domäne' -Default $defaultDomain -Required
    if ($null -eq $vaultwardenDomainInput) { return $null }
    $vaultwardenDomain = $vaultwardenDomainInput.Trim().ToLowerInvariant()

    if ($useCloudflare) {
        $zoneNameInput = Read-WizardTextWithDefault -Label 'Cloudflare Zone' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.domain.zoneName } else { Get-DefaultZoneFromHostname -Hostname $vaultwardenDomain })) -Required
        if ($null -eq $zoneNameInput) { return $null }
        $zoneName = $zoneNameInput.Trim().ToLowerInvariant()
    } else {
        $zoneName = (Get-DefaultZoneFromHostname -Hostname $vaultwardenDomain).ToLowerInvariant()
    }

    if (-not (Test-ValidHostnameInZone -Hostname $vaultwardenDomain -ZoneName $zoneName)) {
        throw "Vaultwarden-Domäne '$vaultwardenDomain' passt nicht zur Zone '$zoneName'."
    }
    $customerCode = Convert-DomainToSlug -Domain $vaultwardenDomain

    $location    = Read-WizardTextWithDefault -Label 'Azure Region' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.azure.location } else { 'germanywestcentral' })) -Required
    if ($null -eq $location) { return $null }
    $environment = Read-WizardTextWithDefault -Label 'Environment (prod/test/dev)' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.azure.environment } else { 'prod' })) -Required
    if ($null -eq $environment) { return $null }
    $resourceGroupDefault = if ($ExistingConfig) { $ExistingConfig.azure.resourceGroupName } else { Get-DefaultResourceGroupName -Environment $environment -Location $location -VaultwardenDomain $vaultwardenDomain }
    $resourceGroupName = Read-WizardTextWithDefault -Label 'Resource Group' -Default ([string]$resourceGroupDefault) -Required
    if ($null -eq $resourceGroupName) { return $null }

    # --- 4. Storage & PostgreSQL parameters ---
    $storageAccountSku           = Read-WizardTextWithDefault -Label 'Storage Account SKU'              -Default ([string](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'storageAccountSku'           -Default 'Standard_LRS'))  -Required
    if ($null -eq $storageAccountSku) { return $null }
    $postgresSkuName             = Read-WizardTextWithDefault -Label 'PostgreSQL SKU'                   -Default ([string](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'postgresSkuName'             -Default 'Standard_B1ms')) -Required
    if ($null -eq $postgresSkuName) { return $null }
    $postgresStorageGBRaw        = Read-WizardTextWithDefault -Label 'PostgreSQL Storage GB'      -Default ([string](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'postgresStorageGB'           -Default '32'))            -Required
    if ($null -eq $postgresStorageGBRaw) { return $null }
    $postgresStorageGB = [int]$postgresStorageGBRaw
    $postgresBackupRetentionDaysRaw = Read-WizardTextWithDefault -Label 'PostgreSQL Backup Retention Days' -Default ([string](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'postgresBackupRetentionDays' -Default '14'))     -Required
    if ($null -eq $postgresBackupRetentionDaysRaw) { return $null }
    $postgresBackupRetentionDays = [int]$postgresBackupRetentionDaysRaw

    # --- 5. Mail-Konfiguration (opens directly after PostgreSQL Backup Retention Days) ---
    Write-Section 'Mail-Konfiguration'

    $mailRootDomainInput = Read-WizardTextWithDefault -Label 'Mail Root Domain' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.mailRootDomain } else { $zoneName })) -Required
    if ($null -eq $mailRootDomainInput) { return $null }
    $mailRootDomain = $mailRootDomainInput.Trim().ToLowerInvariant()

    # Mail-Modus wählen (3 exklusive Zielzustände) – ordered to match spec: acs_smtp, direct_send, smtp_auth
    $mailModeChoices = [ordered]@{
        'acs_smtp'    = 'ACS SMTP (Azure Communication Services SMTP Relay)'
        'direct_send' = 'Direct Send (kein Auth, MX-Endpunkt direkt kontaktieren)'
        'smtp_auth'   = 'SMTP Auth (klassisches SMTP Relay mit User/Passwort)'
    }
    $existingMailMode = if ($ExistingConfig) { Get-MailModeFromConfig -Config $ExistingConfig } else { 'smtp_auth' }
    $mailModeValue = Read-WizardChoiceWithDefault -Label 'Mail-Modus' -Choices $mailModeChoices -DefaultKey $existingMailMode
    if ($null -eq $mailModeValue) { return $null }

    $smtpFrom          = Read-WizardTextWithDefault -Label 'SMTP From'      -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.from }     else { 'noreply@' + $mailRootDomain }))
    if ($null -eq $smtpFrom) { return $null }
    $smtpFromNameValue = Read-WizardTextWithDefault -Label 'SMTP From Name' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.fromName } else { 'Vaultwarden' }))
    if ($null -eq $smtpFromNameValue) { return $null }

    # SMTP host prompting depends on mail mode:
    #   smtp_auth:    prompts with default smtp.office365.com (or existing host if editing)
    #   acs_smtp:     smtp.azurecomm.net is auto-set (no prompt)
    #   direct_send:  MX endpoint is always prompted explicitly (no sensible default)
    $smtpHostValue     = ''
    $smtpPortValue     = ''
    $smtpSecurityValue = 'starttls'
    $smtpUsernameValue = ''

    if ($mailModeValue -eq 'direct_send') {
        # Direct Send: MX lookup is not supported at deployment time (Azure DeploymentScript lacks dig/nslookup).
        # The MX endpoint (MX-Endpunkt) must be provided explicitly here and will be written directly to the parameter file.
        $smtpHostValue = Read-WizardTextWithDefault -Label 'SMTP Host (MX-Endpunkt für Direct Send, z. B. mx01.example-com.mail.protection.outlook.com)' -Default ([string]$(if ($ExistingConfig) { $ExistingConfig.smtp.host } else { '' })) -Required
        if ($null -eq $smtpHostValue) { return $null }
    }
    elseif ($mailModeValue -eq 'smtp_auth') {
        # SMTP Auth: prompt for SMTP host with default smtp.office365.com.
        # If an existing smtp_auth config already has a custom host, use that as the default.
        # The operator can override it to use any SMTP relay.
        $existingSmtpHost = if ($ExistingConfig -and (Get-MailModeFromConfig -Config $ExistingConfig) -eq 'smtp_auth') { [string]$ExistingConfig.smtp.host } else { '' }
        $smtpHostDefault  = if (-not [string]::IsNullOrWhiteSpace($existingSmtpHost)) { $existingSmtpHost } else { 'smtp.office365.com' }
        $smtpHostValue     = Read-WizardTextWithDefault -Label 'SMTP Host (smtp_auth-Relay, z.B. smtp.office365.com)' -Default $smtpHostDefault -Required
        if ($null -eq $smtpHostValue) { return $null }
        $smtpPortValue     = Read-WizardTextWithDefault -Label 'SMTP Port'     -Default ([string]$(if ($ExistingConfig -and (Get-MailModeFromConfig -Config $ExistingConfig) -eq 'smtp_auth') { $ExistingConfig.smtp.port }     else { '587' }))       -Required
        if ($null -eq $smtpPortValue) { return $null }
        $smtpSecurityValue = Read-WizardTextWithDefault -Label 'SMTP Security' -Default ([string]$(if ($ExistingConfig -and (Get-MailModeFromConfig -Config $ExistingConfig) -eq 'smtp_auth') { $ExistingConfig.smtp.security } else { 'starttls' })) -Required
        if ($null -eq $smtpSecurityValue) { return $null }
        $smtpUsernameValue = Read-WizardTextWithDefault -Label 'SMTP Username' -Default ([string]$(if ($ExistingConfig -and (Get-MailModeFromConfig -Config $ExistingConfig) -eq 'smtp_auth') { $ExistingConfig.smtp.username } else { $smtpFrom }))   -Required
        if ($null -eq $smtpUsernameValue) { return $null }
    }
    else {
        # acs_smtp: smtp.azurecomm.net is auto-set; acsDeployFoundation=true is implied.
        # Prompt only for the ACS-specific username (connection string / access key user).
        $smtpHostValue     = 'smtp.azurecomm.net'
        $smtpPortValue     = '587'
        $smtpSecurityValue = 'starttls'
        $smtpUsernameValue = Read-WizardTextWithDefault -Label 'ACS SMTP Username (Azure Communication Services Verbindungszeichenfolge)' -Default ([string]$(if ($ExistingConfig -and (Get-MailModeFromConfig -Config $ExistingConfig) -eq 'acs_smtp') { $ExistingConfig.smtp.username } else { '' })) -Required
        if ($null -eq $smtpUsernameValue) { return $null }
    }

    # --- 6. CloudFlare detail questions (only if CloudFlare selected) ---
    $mode = if ($useCloudflare) { 'cloudflare-managed' } else { 'basic' }
    $enableWafValue       = if ($ExistingConfig) { [bool]$ExistingConfig.edge.enableWaf }       else { $true }
    $enableRateLimitValue = if ($ExistingConfig) { [bool]$ExistingConfig.edge.enableRateLimit }  else { $true }
    if ($useCloudflare) {
        $enableWafValue       = Read-WizardBooleanWithDefault -Label 'Cloudflare WAF-Regel für /admin aktivieren?'             -Default $enableWafValue
        if ($null -eq $enableWafValue) { return $null }
        $enableRateLimitValue = Read-WizardBooleanWithDefault -Label 'Cloudflare Rate Limit für Login-Endpunkte aktivieren?' -Default $enableRateLimitValue
        if ($null -eq $enableRateLimitValue) { return $null }
    }

    # ACS Foundation: auto-enable when acs_smtp mail mode is chosen, regardless of multi-choice selection.
    if ($mailModeValue -eq 'acs_smtp') { $acsDeployFoundation = $true }

    # Populate advanced ARM parameters from collected values.
    $advancedArm.adminPanelEnabled           = $adminPanelEnabled
    $advancedArm.diagnosticsEnabled          = $diagnosticsEnabled
    $advancedArm.ssoEnabled                  = $ssoEnabled
    $advancedArm.pushEnabled                 = $pushEnabled
    $advancedArm.acsDeployFoundation         = $acsDeployFoundation
    $advancedArm.storageAccountSku           = $storageAccountSku
    $advancedArm.postgresSkuName             = $postgresSkuName
    $advancedArm.postgresStorageGB           = $postgresStorageGB
    $advancedArm.postgresBackupRetentionDays = $postgresBackupRetentionDays
    # allowInsecureHttp is always true (ACA handles TLS at the edge)
    $advancedArm.allowInsecureHttp           = $true
    # allowAzureServicesToPostgres is always true in the standard path (no VNet/NAT)
    $advancedArm.allowAzureServicesToPostgres = $true
    # Preserve or derive defaults for non-prompted text fields
    if ([string]::IsNullOrWhiteSpace([string]$advancedArm.invitationOrgName))    { $advancedArm.invitationOrgName    = Get-SuggestedInvitationOrgName    -ZoneName $zoneName }
    if ([string]::IsNullOrWhiteSpace([string]$advancedArm.signupsDomainsWhitelist)) { $advancedArm.signupsDomainsWhitelist = Get-SuggestedSignupsDomainsWhitelist -ZoneName $zoneName }

    # --- 7. SSO detail questions (only if SSO selected) ---
    if ($ssoEnabled) {
        $advancedArm.ssoOnly      = Read-WizardBooleanWithDefault -Label 'SSO Only aktivieren?'  -Default ([bool](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'ssoOnly'      -Default $false))
        if ($null -eq $advancedArm.ssoOnly) { return $null }
        $advancedArm.ssoAuthority = Read-WizardTextWithDefault    -Label 'SSO Authority'          -Default ([string](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'ssoAuthority' -Default ''))                                           -Required
        if ($null -eq $advancedArm.ssoAuthority) { return $null }
        $advancedArm.ssoClientId  = Read-WizardTextWithDefault    -Label 'SSO Client ID'          -Default ([string](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'ssoClientId'  -Default ''))                                           -Required
        if ($null -eq $advancedArm.ssoClientId) { return $null }
        $advancedArm.ssoScopes    = Read-WizardTextWithDefault    -Label 'SSO Scopes'             -Default ([string](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'ssoScopes'    -Default 'openid profile email offline_access User.Read')) -Required
        if ($null -eq $advancedArm.ssoScopes) { return $null }
    }
    else {
        $advancedArm.ssoOnly      = $false
        $advancedArm.ssoAuthority = ''
        $advancedArm.ssoClientId  = ''
        $advancedArm.ssoScopes    = 'openid profile email offline_access User.Read'
    }

    # --- Push detail questions (only if Push selected) ---
    if ($pushEnabled) {
        $advancedArm.pushInstallationId = Read-WizardTextWithDefault    -Label 'Push Installation ID'   -Default ([string](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'pushInstallationId' -Default ''))    -Required
        if ($null -eq $advancedArm.pushInstallationId) { return $null }
        $advancedArm.pushUseEuServers   = Read-WizardBooleanWithDefault -Label 'EU Push Server verwenden?' -Default ([bool](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'pushUseEuServers'   -Default $false))
        if ($null -eq $advancedArm.pushUseEuServers) { return $null }
    }
    else {
        $advancedArm.pushInstallationId = ''
        $advancedArm.pushUseEuServers   = $false
    }

    # --- ACS Foundation detail questions (only if ACS Foundation selected or implied by acs_smtp) ---
    if ($acsDeployFoundation) {
        $advancedArm.acsDataLocation = Read-WizardTextWithDefault -Label 'ACS Data Location' -Default ([string](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'acsDataLocation' -Default 'Germany')) -Required
        if ($null -eq $advancedArm.acsDataLocation) { return $null }
        $advancedArm.acsDomainName   = Read-WizardTextWithDefault -Label 'ACS Domain Name'   -Default ([string](Get-AdvancedParameterValue -Advanced $advancedArm -Name 'acsDomainName'   -Default ''))
        if ($null -eq $advancedArm.acsDomainName) { return $null }
    }
    else {
        $advancedArm.acsDomainName   = ''
        $advancedArm.acsDataLocation = 'Germany'
    }

    $secrets = @{}
    if ($ssoEnabled)  { $secrets.ssoClientSecretSource    = 'prompt' }
    if ($pushEnabled) { $secrets.pushInstallationKeySource = 'prompt' }

    return New-CustomerConfigObject -CustomerNumber $customerNumber -VaultwardenDomain $vaultwardenDomain -ZoneName $zoneName -ResourceGroupName $resourceGroupName -Environment $environment -Location $location -Mode $mode -MailRootDomain $mailRootDomain -MailMode $mailModeValue -SmtpFrom $smtpFrom -SmtpFromName $smtpFromNameValue -SmtpHost $smtpHostValue -SmtpPort $smtpPortValue -SmtpSecurity $smtpSecurityValue -SmtpUsername $smtpUsernameValue -EnableWaf:$enableWafValue -EnableRateLimit:$enableRateLimitValue -AdvancedArmParameters $advancedArm -Secrets $secrets
}

# Kept for backward compatibility and direct invocation outside the main wizard flow.
# The main New-CustomerConfigInteractive no longer calls this function;
# advanced parameters are collected inline in that function's step 7.
function New-AdvancedArmParametersInteractive {
    param(
        [hashtable]$ExistingAdvanced,
        [Parameter(Mandatory)][string]$ZoneName
    )
    $advancedInput = if ($ExistingAdvanced) { $ExistingAdvanced } else { New-EmptyAdvancedArmParameters }
    $advanced = ConvertTo-HashtableDeep -InputObject $advancedInput

    $advanced.adminPanelEnabled = Read-BooleanWithDefault -Label 'Admin Panel für Bootstrap aktiv?' -Default ([bool](Get-AdvancedParameterValue -Advanced $advanced -Name 'adminPanelEnabled' -Default $true))
    $advanced.invitationOrgName = Read-TextWithDefault -Label 'Invitation Org Name' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'invitationOrgName' -Default (Get-SuggestedInvitationOrgName -ZoneName $ZoneName)))
    $advanced.signupsDomainsWhitelist = Read-TextWithDefault -Label 'Signups Domains Whitelist' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'signupsDomainsWhitelist' -Default (Get-SuggestedSignupsDomainsWhitelist -ZoneName $ZoneName)))
    $advanced.orgCreationUsers = Read-TextWithDefault -Label 'Org Creation Users' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'orgCreationUsers' -Default ''))
    $advanced.diagnosticsEnabled = Read-BooleanWithDefault -Label 'Diagnostics aktiv?' -Default ([bool](Get-AdvancedParameterValue -Advanced $advanced -Name 'diagnosticsEnabled' -Default $true))
    $advanced.allowInsecureHttp = $true
    $advanced.storageAccountSku = Read-TextWithDefault -Label 'Storage Account SKU' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'storageAccountSku' -Default 'Standard_LRS')) -Required
    $advanced.postgresSkuName = Read-TextWithDefault -Label 'PostgreSQL SKU' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'postgresSkuName' -Default 'Standard_B1ms')) -Required
    $advanced.postgresStorageGB = [int](Read-TextWithDefault -Label 'PostgreSQL Storage GB' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'postgresStorageGB' -Default '32')) -Required)
    $advanced.postgresBackupRetentionDays = [int](Read-TextWithDefault -Label 'PostgreSQL Backup Retention Days' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'postgresBackupRetentionDays' -Default '14')) -Required)
    $advanced.allowAzureServicesToPostgres = $true

    if ($advanced.ssoEnabled) {
        $advanced.ssoOnly = Read-BooleanWithDefault -Label 'SSO Only aktivieren?' -Default ([bool](Get-AdvancedParameterValue -Advanced $advanced -Name 'ssoOnly' -Default $false))
        $advanced.ssoAuthority = Read-TextWithDefault -Label 'SSO Authority' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'ssoAuthority' -Default '')) -Required
        $advanced.ssoClientId = Read-TextWithDefault -Label 'SSO Client ID' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'ssoClientId' -Default '')) -Required
        $advanced.ssoScopes = Read-TextWithDefault -Label 'SSO Scopes' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'ssoScopes' -Default 'openid profile email offline_access User.Read')) -Required
    }
    else {
        $advanced.ssoOnly = $false
        $advanced.ssoAuthority = ''
        $advanced.ssoClientId = ''
        $advanced.ssoScopes = 'openid profile email offline_access User.Read'
    }

    if ($advanced.pushEnabled) {
        $advanced.pushInstallationId = Read-TextWithDefault -Label 'Push Installation ID' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'pushInstallationId' -Default '')) -Required
        $advanced.pushUseEuServers = Read-BooleanWithDefault -Label 'EU Push Server verwenden?' -Default ([bool](Get-AdvancedParameterValue -Advanced $advanced -Name 'pushUseEuServers' -Default $false))
    }
    else {
        $advanced.pushInstallationId = ''
        $advanced.pushUseEuServers = $false
    }

    if ($advanced.acsDeployFoundation) {
        $advanced.acsDataLocation = Read-TextWithDefault -Label 'ACS Data Location' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'acsDataLocation' -Default 'Germany')) -Required
        $advanced.acsDomainName = Read-TextWithDefault -Label 'ACS Domain Name' -Default ([string](Get-AdvancedParameterValue -Advanced $advanced -Name 'acsDomainName' -Default ''))
    }
    else {
        $advanced.acsDomainName = ''
        $advanced.acsDataLocation = 'Germany'
    }

    return $advanced
}

function Start-DeployExistingFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot,
        [Parameter(Mandatory)][string]$RepoRoot
    )
    try { [System.Console]::Clear() } catch { }
    $selection = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot -IncludeNewConfig -Title 'Vorhandene Kundenkonfigurationen deployen'
    if (($selection.SelectionType) -eq 'back') { return @{ Back = $true } }
    if (($selection.SelectionType) -eq 'new') {
        $config = New-CustomerConfigInteractive
        if ($null -eq $config) { return @{ Back = $true } }
        return @{ Config = $config }
    }
    $customerCode = $selection.CustomerCode
    $pathsForLoad = Get-CustomerPaths -RepoRoot $RepoRoot -CustomersRoot $CustomersRoot -CustomerCode $customerCode
    $config = ConvertTo-HashtableDeep -InputObject (Read-JsonFile -Path $pathsForLoad.ConfigPath)
    return @{ Config = $config }
}

function Start-EditConfigFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot,
        [Parameter(Mandatory)][string]$RepoRoot
    )
    try { [System.Console]::Clear() } catch { }
    $selection = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot -Title 'Vorhandene Kundenkonfigurationen bearbeiten'
    if (($selection.SelectionType) -eq 'back') { return @{ Back = $true } }
    $customerCode = $selection.CustomerCode
    $pathsForLoad = Get-CustomerPaths -RepoRoot $RepoRoot -CustomersRoot $CustomersRoot -CustomerCode $customerCode
    $loaded = ConvertTo-HashtableDeep -InputObject (Read-JsonFile -Path $pathsForLoad.ConfigPath)
    $config = New-CustomerConfigInteractive -ExistingConfig $loaded
    if ($null -eq $config) { return @{ Back = $true } }
    return @{ Config = $config; GenerateOnly = $true }
}

function Select-CustomerCodesInteractive {
    param([Parameter(Mandatory)][string]$CustomersRoot)
    $customers = @(Get-AvailableCustomerCodes -CustomersRoot $CustomersRoot)
    if ($customers.Count -eq 0) {
        Write-Host 'Keine vorhandenen Kundenkonfigurationen gefunden.'
        return $null
    }
    $labels = @()
    $labelToCode = @{}
    foreach ($code in $customers) {
        $cfgPath = Join-Path (Join-Path $CustomersRoot $code) 'deployment.config.json'
        $label = $code
        if (Test-Path -LiteralPath $cfgPath) {
            try {
                $cfg = Read-JsonFile -Path $cfgPath
                $label = '{0,-8}  {1,-40}  {2}' -f $cfg.customerNumber, $cfg.domain.hostname, $code
            } catch { }
        }
        $labels += $label
        $labelToCode[$label] = $code
    }
    $selectedLabels = Show-MultiSelectMenuSmooth -Title 'Konfigurationen zum Löschen auswählen' -Items $labels
    if ($null -eq $selectedLabels -or @($selectedLabels).Count -eq 0) { return $null }
    $result = @()
    foreach ($lbl in @($selectedLabels)) { $result += $labelToCode[$lbl] }
    return $result
}

function Start-DeleteConfigFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot
    )
    try { [System.Console]::Clear() } catch { }
    $selectedCodes = Select-CustomerCodesInteractive -CustomersRoot $CustomersRoot
    if ($null -eq $selectedCodes -or @($selectedCodes).Count -eq 0) { return @{ Back = $true } }
    $selectedCodes = @($selectedCodes)
    Write-Host ''
    Write-Host ('Ausgewählte Konfigurationen ({0}):' -f $selectedCodes.Count)
    foreach ($code in $selectedCodes) { Write-Host "  - $code" }

    Write-Host ''
    $confirm = Read-Host 'Wirklich löschen? Bitte "ja" eingeben zum Bestätigen'
    if ($confirm -ne 'ja') {
        Write-Host 'Abgebrochen.'
        return @{ Back = $true }
    }
    foreach ($code in $selectedCodes) {
        $customerRoot = Join-Path $CustomersRoot $code
        Remove-Item -LiteralPath $customerRoot -Recurse -Force
        Write-Host ("[OK] Konfiguration '{0}' wurde gelöscht." -f $code)
    }
    return @{ Back = $true }
}

function Start-CreateOnlyFlow {
    [CmdletBinding()]
    param()
    $config = New-CustomerConfigInteractive
    if ($null -eq $config) { return @{ Back = $true } }
    return @{ Config = $config; GenerateOnly = $true }
}

function Start-RepairFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot
    )
    $selection = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
    if (($selection.SelectionType) -eq 'back') { return @{ Back = $true } }
    $customerCode = $selection.CustomerCode
    return @{ CustomerNumber = $customerCode; Repair = $true }
}

function Start-UpdateFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CustomersRoot
    )
    $selection = Select-CustomerCodeInteractive -CustomersRoot $CustomersRoot
    if (($selection.SelectionType) -eq 'back') { return @{ Back = $true } }
    $customerCode = $selection.CustomerCode
    return @{ CustomerNumber = $customerCode; Update = $true }
}
