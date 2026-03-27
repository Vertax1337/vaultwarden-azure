@{
    RootModule        = 'ConsoleMenu.psm1'
    ModuleVersion     = '2.1.0'
    GUID              = '7f0f8b64-cd73-47f6-bc31-7c6f8b1d99bf'
    Author            = 'OpenAI'
    CompanyName       = 'OpenAI'
    Copyright         = '(c) OpenAI'
    Description       = 'Generisches Konsolenmenue fuer PowerShell mit Menue-Registry, Stack-Navigation und Auswahlspeicher pro Menue.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'New-ConsoleMenuItem',
        'New-ConsoleMenu',
        'Show-ConsoleMenu',
        'Show-ConsoleScreenMessage',
        'Enter-ConsoleScreen',
        'Write-ConsoleMenuLine',
        'Get-ConsoleMenuDefaultIndex',
        'Get-ConsoleMenuNextIndex',
        'Get-ConsoleMenuById',
        'Start-ConsoleMenuApplication'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
