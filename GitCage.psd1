@{
    RootModule = 'src/GitCage.psm1'
    ModuleVersion = '0.1.0'
    GUID = '665c9c70-15dc-4a47-9640-c25da226a25c'
    Author = 'GitCage contributors'
    CompanyName = 'Community'
    Copyright = '(c) 2026 GitCage contributors. MIT License.'
    Description = 'Hermetic GitHub identity workspaces for Windows, powered by WSL2.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-GitCage',
        'Invoke-GitCage',
        'New-GitCage',
        'Open-GitCage',
        'Stop-GitCage'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('GitHub', 'WSL2', 'Isolation', 'DeveloperTools')
            LicenseUri = 'https://github.com/0xacee/gitcage/blob/main/LICENSE'
            ProjectUri = 'https://github.com/0xacee/gitcage'
        }
    }
}
