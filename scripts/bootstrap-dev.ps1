[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

foreach ($module in @(
    @{ Name = 'Pester'; MinimumVersion = '5.7.1' },
    @{ Name = 'PSScriptAnalyzer'; MinimumVersion = '1.24.0' }
)) {
    if ($PSCmdlet.ShouldProcess($module.Name, 'Install development PowerShell module')) {
        Install-Module @module -Scope CurrentUser -Force -SkipPublisherCheck
    }
}
