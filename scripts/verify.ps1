[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot

$findings = @(Invoke-ScriptAnalyzer -Path $repositoryRoot -Recurse -Severity Warning,Error)
if ($findings.Count -gt 0) {
    $findings | Format-Table -Wrap -AutoSize
    throw "PSScriptAnalyzer found $($findings.Count) blocking issue(s)."
}

Test-ModuleManifest -Path (Join-Path $repositoryRoot 'GitCage.psd1') | Out-Null
Invoke-Pester -Path (Join-Path $repositoryRoot 'tests') -Output Detailed
