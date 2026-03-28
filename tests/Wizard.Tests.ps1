# Pester 5 unit tests for the Vaultwarden wizard and menu logic.
#
# Covers:
#   - ConsoleMenu pure logic (New-ConsoleMenuItem, New-ConsoleMenu,
#     Get-ConsoleMenuDefaultIndex, Get-ConsoleMenuNextIndex)
#   - Show-SingleChoiceMenuSmooth / Show-MultiSelectMenuSmooth (non-interactive fallback)
#   - Read-WizardChoiceWithDefault (mail-mode key mapping + Esc)
#   - Select-CustomerCodeInteractive flow contracts
#   - Start-DeleteConfigFlow flow contracts
#   - New-CustomerConfigInteractive Esc propagation
#   - Start-*Flow back contracts
#
# Run manually:  Invoke-Pester -Path tests/Wizard.Tests.ps1 -Output Detailed
#
# Requires Pester >= 5.0.  Install via:
#   Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck

BeforeAll {
    $script:RepoRoot   = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts' 'modules' 'ConsoleMenu' 'ConsoleMenu.psd1'
    $script:FlowsPath  = Join-Path $script:RepoRoot 'scripts' 'lib' 'VaultwardenDeployment.Flows.ps1'

    Import-Module $script:ModulePath -Force -ErrorAction Stop

    # -----------------------------------------------------------------------
    # Stub functions – normally provided by VaultwardenDeployment.Common.ps1 /
    # Invoke-CustomerDeployment.ps1.  Defined here so Flows.ps1 can be
    # dot-sourced without the full deployment environment.
    # -----------------------------------------------------------------------
    function Get-AvailableCustomerCodes        { param($CustomersRoot); @() }
    function Read-JsonFile                     { param($Path); @{} }
    function Write-Section                     { param($Title) }
    function ConvertTo-HashtableDeep           { param($InputObject); $InputObject }
    function New-EmptyAdvancedArmParameters {
        [hashtable]@{
            adminPanelEnabled            = $true
            diagnosticsEnabled           = $true
            ssoEnabled                   = $false
            pushEnabled                  = $false
            acsDeployFoundation          = $false
            storageAccountSku            = 'Standard_LRS'
            postgresSkuName              = 'Standard_B1ms'
            postgresStorageGB            = 32
            postgresBackupRetentionDays  = 14
            allowInsecureHttp            = $true
            allowAzureServicesToPostgres = $true
            invitationOrgName            = ''
            signupsDomainsWhitelist      = ''
            orgCreationUsers             = ''
            ssoOnly                      = $false
            ssoAuthority                 = ''
            ssoClientId                  = ''
            ssoScopes                    = 'openid profile email offline_access User.Read'
            pushInstallationId           = ''
            pushUseEuServers             = $false
            acsDataLocation              = 'Germany'
            acsDomainName                = ''
        }
    }
    function Get-AdvancedParameterValue            { param($Advanced, $Name, $Default); $Default }
    function Get-DefaultZoneFromHostname           { param($Hostname); 'example.com' }
    function Test-ValidHostnameInZone              { $true }
    function Convert-DomainToSlug                  { param($Domain); ($Domain -replace '[^a-z0-9]', '-') }
    function Get-DefaultResourceGroupName          { 'rg-test' }
    function Get-SuggestedInvitationOrgName        { 'TestOrg' }
    function Get-SuggestedSignupsDomainsWhitelist  { 'example.com' }
    function New-CustomerConfigObject              { [pscustomobject]@{ customerNumber = 'test' } }
    function Get-MailModeFromConfig                { 'smtp_auth' }
    function Get-CustomerPaths                     { @{ ConfigPath = '/tmp/dummy.json' } }
    function Read-BooleanWithDefault               { }
    function Read-TextWithDefault                  { }

    . $script:FlowsPath
}

# ===========================================================================
# ConsoleMenu – New-ConsoleMenuItem
# ===========================================================================
Describe 'New-ConsoleMenuItem' {
    It 'creates an action item with correct properties' {
        $item = New-ConsoleMenuItem -Key '1' -Text 'Deploy' -ItemType 'action' -ActionId 'deploy'
        $item.Key      | Should -Be '1'
        $item.Text     | Should -Be 'Deploy'
        $item.ItemType | Should -Be 'action'
        $item.ActionId | Should -Be 'deploy'
        $item.Enabled  | Should -BeTrue
    }

    It 'creates a back item' {
        $item = New-ConsoleMenuItem -Key '0' -Text 'Zurück' -ItemType 'back'
        $item.ItemType | Should -Be 'back'
    }

    It 'creates a submenu item' {
        $item = New-ConsoleMenuItem -Key '2' -Text 'Sub' -ItemType 'submenu' -TargetMenuId 'sub1'
        $item.ItemType     | Should -Be 'submenu'
        $item.TargetMenuId | Should -Be 'sub1'
    }

    It 'throws when action item lacks ActionId' {
        { New-ConsoleMenuItem -Key '1' -Text 'X' -ItemType 'action' } | Should -Throw
    }

    It 'throws when submenu item lacks TargetMenuId' {
        { New-ConsoleMenuItem -Key '1' -Text 'X' -ItemType 'submenu' } | Should -Throw
    }

    It 'respects Enabled=$false' {
        $item = New-ConsoleMenuItem -Key '1' -Text 'X' -ItemType 'back' -Enabled $false
        $item.Enabled | Should -BeFalse
    }
}

# ===========================================================================
# ConsoleMenu – New-ConsoleMenu
# ===========================================================================
Describe 'New-ConsoleMenu' {
    It 'creates a menu with correct properties' {
        $items = @(New-ConsoleMenuItem -Key '1' -Text 'Item' -ItemType 'action' -ActionId 'act')
        $menu = New-ConsoleMenu -Id 'test' -Title 'Test' -DefaultKey '1' -Items $items
        $menu.Id          | Should -Be 'test'
        $menu.Title       | Should -Be 'Test'
        $menu.DefaultKey  | Should -Be '1'
        $menu.Items.Count | Should -Be 1
    }

    It 'throws when Items array is empty' {
        { New-ConsoleMenu -Id 'x' -Title 'x' -DefaultKey '1' -Items @() } | Should -Throw
    }
}

# ===========================================================================
# ConsoleMenu – Get-ConsoleMenuDefaultIndex
# ===========================================================================
Describe 'Get-ConsoleMenuDefaultIndex' {
    It 'returns index of the DefaultKey item' {
        $items = @(
            (New-ConsoleMenuItem -Key '1' -Text 'A' -ItemType 'action' -ActionId 'a')
            (New-ConsoleMenuItem -Key '2' -Text 'B' -ItemType 'action' -ActionId 'b')
            (New-ConsoleMenuItem -Key '3' -Text 'C' -ItemType 'action' -ActionId 'c')
        )
        Get-ConsoleMenuDefaultIndex -Items $items -DefaultKey '2' | Should -Be 1
    }

    It 'returns first enabled index when DefaultKey not found' {
        $items = @(
            (New-ConsoleMenuItem -Key '1' -Text 'A' -ItemType 'action' -ActionId 'a' -Enabled $false)
            (New-ConsoleMenuItem -Key '2' -Text 'B' -ItemType 'action' -ActionId 'b')
        )
        Get-ConsoleMenuDefaultIndex -Items $items -DefaultKey 'X' | Should -Be 1
    }

    It 'throws when no items are enabled' {
        $items = @(New-ConsoleMenuItem -Key '1' -Text 'A' -ItemType 'back' -Enabled $false)
        { Get-ConsoleMenuDefaultIndex -Items $items -DefaultKey '1' } | Should -Throw
    }
}

# ===========================================================================
# ConsoleMenu – Get-ConsoleMenuNextIndex
# ===========================================================================
Describe 'Get-ConsoleMenuNextIndex' {
    BeforeAll {
        $script:threeItems = @(
            (New-ConsoleMenuItem -Key '1' -Text 'A' -ItemType 'action' -ActionId 'a')
            (New-ConsoleMenuItem -Key '2' -Text 'B' -ItemType 'action' -ActionId 'b')
            (New-ConsoleMenuItem -Key '3' -Text 'C' -ItemType 'action' -ActionId 'c')
        )
    }

    It 'moves forward by 1' {
        Get-ConsoleMenuNextIndex -Items $script:threeItems -CurrentIndex 0 -Step 1 | Should -Be 1
    }

    It 'wraps forward at the last item' {
        Get-ConsoleMenuNextIndex -Items $script:threeItems -CurrentIndex 2 -Step 1 | Should -Be 0
    }

    It 'moves backward by 1' {
        Get-ConsoleMenuNextIndex -Items $script:threeItems -CurrentIndex 2 -Step -1 | Should -Be 1
    }

    It 'wraps backward at the first item' {
        Get-ConsoleMenuNextIndex -Items $script:threeItems -CurrentIndex 0 -Step -1 | Should -Be 2
    }

    It 'skips disabled items when moving forward' {
        $items = @(
            (New-ConsoleMenuItem -Key '1' -Text 'A' -ItemType 'action' -ActionId 'a')
            (New-ConsoleMenuItem -Key '2' -Text 'B' -ItemType 'action' -ActionId 'b' -Enabled $false)
            (New-ConsoleMenuItem -Key '3' -Text 'C' -ItemType 'action' -ActionId 'c')
        )
        Get-ConsoleMenuNextIndex -Items $items -CurrentIndex 0 -Step 1 | Should -Be 2
    }
}

# ===========================================================================
# Show-SingleChoiceMenuSmooth – Non-interactive fallback
# ===========================================================================
Describe 'Show-SingleChoiceMenuSmooth – NonInteractive Fallback' {
    BeforeEach { $Script:_ForceNonInteractive = $true }
    AfterEach  { $Script:_ForceNonInteractive = $false }

    It 'returns the default item on empty input (Enter on default)' {
        Mock Read-Host { '' }
        Show-SingleChoiceMenuSmooth -Items @('Alpha', 'Beta', 'Gamma') -InitialIndex 1 |
            Should -Be 'Beta'
    }

    It 'returns first item when InitialIndex=0 and input is empty' {
        Mock Read-Host { '' }
        Show-SingleChoiceMenuSmooth -Items @('Alpha', 'Beta') -InitialIndex 0 |
            Should -Be 'Alpha'
    }

    It 'returns item by 1-based numeric input' {
        Mock Read-Host { '3' }
        Show-SingleChoiceMenuSmooth -Items @('Alpha', 'Beta', 'Gamma') -InitialIndex 0 |
            Should -Be 'Gamma'
    }

    It 'falls back to default when number is out of range' {
        Mock Read-Host { '99' }
        Show-SingleChoiceMenuSmooth -Items @('Alpha', 'Beta') -InitialIndex 0 |
            Should -Be 'Alpha'
    }

    It 'clamps an over-range InitialIndex to the last item' {
        Mock Read-Host { '' }
        Show-SingleChoiceMenuSmooth -Items @('Alpha', 'Beta') -InitialIndex 99 |
            Should -Be 'Beta'
    }

    It 'throws when Items list is empty' {
        { Show-SingleChoiceMenuSmooth -Items @() } | Should -Throw
    }
}

# ===========================================================================
# Show-MultiSelectMenuSmooth – Non-interactive fallback
# ===========================================================================
Describe 'Show-MultiSelectMenuSmooth – NonInteractive Fallback' {
    BeforeEach { $Script:_ForceNonInteractive = $true }
    AfterEach  { $Script:_ForceNonInteractive = $false }

    It 'returns pre-selected items on empty input' {
        Mock Read-Host { '' }
        $result = Show-MultiSelectMenuSmooth -Items @('Alpha', 'Beta', 'Gamma') -PreSelected @{ Beta = $true }
        $result | Should -Contain 'Beta'
        $result | Should -Not -Contain 'Alpha'
        $result | Should -Not -Contain 'Gamma'
    }

    It 'returns empty array when nothing pre-selected and input is empty' {
        Mock Read-Host { '' }
        @(Show-MultiSelectMenuSmooth -Items @('Alpha', 'Beta') -PreSelected @{}).Count | Should -Be 0
    }

    It 'toggles a single item on by number' {
        $script:msCall = 0
        Mock Read-Host { $script:msCall++; if ($script:msCall -eq 1) { '1' } else { '' } }
        $result = Show-MultiSelectMenuSmooth -Items @('Alpha', 'Beta') -PreSelected @{}
        $result | Should -Contain 'Alpha'
    }

    It 'toggles a pre-selected item off then back on' {
        $script:msCall2 = 0
        Mock Read-Host {
            $script:msCall2++
            switch ($script:msCall2) { 1 { '1' } 2 { '1' } default { '' } }
        }
        $result = Show-MultiSelectMenuSmooth -Items @('Alpha') -PreSelected @{ Alpha = $true }
        $result | Should -Contain 'Alpha'
    }

    It 'throws when Items list is empty' {
        { Show-MultiSelectMenuSmooth -Items @() } | Should -Throw
    }
}

# ===========================================================================
# Read-WizardChoiceWithDefault
# ===========================================================================
Describe 'Read-WizardChoiceWithDefault' {
    It 'returns acs_smtp key when that display item is selected' {
        Mock Show-SingleChoiceMenuSmooth { 'ACS SMTP (Azure Communication Services SMTP Relay) (acs_smtp)' }
        $choices = [ordered]@{
            acs_smtp    = 'ACS SMTP (Azure Communication Services SMTP Relay)'
            direct_send = 'Direct Send (kein Auth, MX-Endpunkt direkt kontaktieren)'
            smtp_auth   = 'SMTP Auth (klassisches SMTP Relay mit User/Passwort)'
        }
        Read-WizardChoiceWithDefault -Label 'Mail-Modus' -Choices $choices -DefaultKey 'direct_send' |
            Should -Be 'acs_smtp'
    }

    It 'returns direct_send key when that display item is selected' {
        Mock Show-SingleChoiceMenuSmooth { 'Direct Send (kein Auth, MX-Endpunkt direkt kontaktieren) (direct_send)' }
        $choices = [ordered]@{
            acs_smtp    = 'ACS SMTP (Azure Communication Services SMTP Relay)'
            direct_send = 'Direct Send (kein Auth, MX-Endpunkt direkt kontaktieren)'
            smtp_auth   = 'SMTP Auth (klassisches SMTP Relay mit User/Passwort)'
        }
        Read-WizardChoiceWithDefault -Label 'Mail-Modus' -Choices $choices -DefaultKey 'smtp_auth' |
            Should -Be 'direct_send'
    }

    It 'returns smtp_auth key when that display item is selected' {
        Mock Show-SingleChoiceMenuSmooth { 'SMTP Auth (klassisches SMTP Relay mit User/Passwort) (smtp_auth)' }
        $choices = [ordered]@{
            acs_smtp    = 'ACS SMTP (Azure Communication Services SMTP Relay)'
            direct_send = 'Direct Send (kein Auth, MX-Endpunkt direkt kontaktieren)'
            smtp_auth   = 'SMTP Auth (klassisches SMTP Relay mit User/Passwort)'
        }
        Read-WizardChoiceWithDefault -Label 'Mail-Modus' -Choices $choices -DefaultKey 'acs_smtp' |
            Should -Be 'smtp_auth'
    }

    It 'returns null when Show-SingleChoiceMenuSmooth returns null (Esc)' {
        Mock Show-SingleChoiceMenuSmooth { $null }
        $choices = [ordered]@{ a = 'Option A' }
        Read-WizardChoiceWithDefault -Label 'Test' -Choices $choices -DefaultKey 'a' |
            Should -BeNullOrEmpty
    }
}

# ===========================================================================
# Select-CustomerCodeInteractive – Flow Contracts
# ===========================================================================
Describe 'Select-CustomerCodeInteractive – Flow Contracts' {
    It 'returns back when Show-ConsoleMenu returns null (Esc)' {
        Mock Get-AvailableCustomerCodes { @('vault-kunde-de') }
        Mock Read-JsonFile { @{} }
        Mock Show-ConsoleMenu { $null }
        (Select-CustomerCodeInteractive -CustomersRoot '/tmp').SelectionType | Should -Be 'back'
    }

    It 'returns back when back item is selected' {
        Mock Get-AvailableCustomerCodes { @('vault-kunde-de') }
        Mock Read-JsonFile { @{} }
        $back = New-ConsoleMenuItem -Key '0' -Text 'Zurück' -ItemType 'back'
        Mock Show-ConsoleMenu { $back }
        (Select-CustomerCodeInteractive -CustomersRoot '/tmp').SelectionType | Should -Be 'back'
    }

    It 'returns new when +Neue Konfiguration is selected' {
        Mock Get-AvailableCustomerCodes { @('vault-kunde-de') }
        Mock Read-JsonFile { @{} }
        $newItem = New-ConsoleMenuItem -Key 'N' -Text '+Neue Konfiguration' -ItemType 'action' -ActionId 'new'
        Mock Show-ConsoleMenu { $newItem }
        $result = Select-CustomerCodeInteractive -CustomersRoot '/tmp' -IncludeNewConfig
        $result.SelectionType | Should -Be 'new'
    }

    It 'returns existing with CustomerCode when a customer item is selected' {
        Mock Get-AvailableCustomerCodes { @('vault-kunde-de') }
        Mock Read-JsonFile { @{} }
        $pick = New-ConsoleMenuItem -Key '1' -Text 'vault-kunde-de' -ItemType 'action' -ActionId 'pick:1'
        Mock Show-ConsoleMenu { $pick }
        $result = Select-CustomerCodeInteractive -CustomersRoot '/tmp'
        $result.SelectionType | Should -Be 'existing'
        $result.CustomerCode  | Should -Be 'vault-kunde-de'
    }

    It 'immediately returns new when no customers exist and IncludeNewConfig is set' {
        Mock Get-AvailableCustomerCodes { @() }
        (Select-CustomerCodeInteractive -CustomersRoot '/tmp' -IncludeNewConfig).SelectionType |
            Should -Be 'new'
    }

    It 'throws when no customers exist and IncludeNewConfig is not set' {
        Mock Get-AvailableCustomerCodes { @() }
        { Select-CustomerCodeInteractive -CustomersRoot '/tmp' } | Should -Throw
    }
}

# ===========================================================================
# Start-DeleteConfigFlow – Flow Contracts
# ===========================================================================
Describe 'Start-DeleteConfigFlow – Flow Contracts' {
    It 'returns Back=true when selection is null' {
        Mock Select-CustomerCodesInteractive { $null }
        (Start-DeleteConfigFlow -CustomersRoot '/tmp').Back | Should -BeTrue
    }

    It 'returns Back=true when selection is empty' {
        Mock Select-CustomerCodesInteractive { @() }
        (Start-DeleteConfigFlow -CustomersRoot '/tmp').Back | Should -BeTrue
    }

    It 'returns Back=true when confirmation is not "ja"' {
        Mock Select-CustomerCodesInteractive { @('vault-test-de') }
        Mock Read-Host { 'nein' }
        (Start-DeleteConfigFlow -CustomersRoot '/tmp').Back | Should -BeTrue
    }

    It 'returns Back=true when confirmation is empty' {
        Mock Select-CustomerCodesInteractive { @('vault-test-de') }
        Mock Read-Host { '' }
        (Start-DeleteConfigFlow -CustomersRoot '/tmp').Back | Should -BeTrue
    }

    It 'deletes customer directory and returns Back=true when confirmation is "ja"' {
        $tmpRoot   = Join-Path ([System.IO.Path]::GetTempPath()) ('wiz-del-' + [System.Guid]::NewGuid().ToString('N'))
        $targetDir = Join-Path $tmpRoot 'vault-test-de'
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        try {
            Mock Select-CustomerCodesInteractive { @('vault-test-de') }
            Mock Read-Host { 'ja' }
            $result = Start-DeleteConfigFlow -CustomersRoot $tmpRoot
            $result.Back         | Should -BeTrue
            Test-Path $targetDir | Should -BeFalse
        } finally {
            Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ===========================================================================
# New-CustomerConfigInteractive – Esc / null propagation
# ===========================================================================
Describe 'New-CustomerConfigInteractive – Esc Propagation' {
    It 'returns null when Esc at Kunden-Nr. (first field)' {
        Mock Read-WizardTextWithDefault { $null }
        New-CustomerConfigInteractive | Should -BeNullOrEmpty
    }

    It 'returns null when Esc at domain field (second prompt)' {
        $script:ncCall = 0
        Mock Read-WizardTextWithDefault {
            $script:ncCall++
            if ($script:ncCall -eq 1) { '9999' } else { $null }
        }
        Mock Show-MultiSelectMenuSmooth { @() }
        New-CustomerConfigInteractive | Should -BeNullOrEmpty
    }

    It 'returns null when mail-mode selection is cancelled (Esc)' {
        $script:ncCall2 = 0
        Mock Read-WizardTextWithDefault {
            $script:ncCall2++
            switch ($script:ncCall2) {
                1  { '9999' }               # customerNumber
                2  { 'vault.example.com' }  # domain
                3  { 'germanywestcentral' }  # location
                4  { 'prod' }               # environment
                5  { 'rg-test' }            # resourceGroup
                6  { 'Standard_LRS' }       # storageAccountSku
                7  { 'Standard_B1ms' }      # postgresSkuName
                8  { '32' }                 # postgresStorageGB
                9  { '14' }                 # postgresBackupRetentionDays
                10 { 'example.com' }        # mailRootDomain
                default { 'dummy' }
            }
        }
        Mock Show-MultiSelectMenuSmooth { @() }
        Mock Read-WizardChoiceWithDefault { $null }
        New-CustomerConfigInteractive | Should -BeNullOrEmpty
    }
}

# ===========================================================================
# Start-DeployExistingFlow – Back Contract
# ===========================================================================
Describe 'Start-DeployExistingFlow – Back Contract' {
    It 'returns Back=true when customer selection returns back' {
        Mock Select-CustomerCodeInteractive { [pscustomobject]@{ SelectionType = 'back' } }
        (Start-DeployExistingFlow -CustomersRoot '/tmp' -RepoRoot '/tmp').Back | Should -BeTrue
    }
}

# ===========================================================================
# Start-EditConfigFlow – Back Contract
# ===========================================================================
Describe 'Start-EditConfigFlow – Back Contract' {
    It 'returns Back=true when customer selection returns back' {
        Mock Select-CustomerCodeInteractive { [pscustomobject]@{ SelectionType = 'back' } }
        (Start-EditConfigFlow -CustomersRoot '/tmp' -RepoRoot '/tmp').Back | Should -BeTrue
    }
}

# ===========================================================================
# Start-CreateOnlyFlow – Back Contract
# ===========================================================================
Describe 'Start-CreateOnlyFlow – Back Contract' {
    It 'returns Back=true when wizard is cancelled (Esc)' {
        Mock New-CustomerConfigInteractive { $null }
        (Start-CreateOnlyFlow).Back | Should -BeTrue
    }

    It 'returns Config and GenerateOnly=true when wizard completes' {
        Mock New-CustomerConfigInteractive { [pscustomobject]@{ customerNumber = '42' } }
        $result = Start-CreateOnlyFlow
        $result['Back']         | Should -BeNullOrEmpty
        $result['GenerateOnly'] | Should -BeTrue
        $result['Config']       | Should -Not -BeNullOrEmpty
    }
}

# ===========================================================================
# Start-RepairFlow – Back Contract
# ===========================================================================
Describe 'Start-RepairFlow – Back Contract' {
    It 'returns Back=true when customer selection returns back' {
        Mock Select-CustomerCodeInteractive { [pscustomobject]@{ SelectionType = 'back' } }
        (Start-RepairFlow -CustomersRoot '/tmp').Back | Should -BeTrue
    }
}

# ===========================================================================
# Start-UpdateFlow – Back Contract
# ===========================================================================
Describe 'Start-UpdateFlow – Back Contract' {
    It 'returns Back=true when customer selection returns back' {
        Mock Select-CustomerCodeInteractive { [pscustomobject]@{ SelectionType = 'back' } }
        (Start-UpdateFlow -CustomersRoot '/tmp').Back | Should -BeTrue
    }
}
