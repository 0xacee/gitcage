[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('audit', 'clone', 'help', 'list', 'login', 'new', 'open', 'run', 'status', 'stop')]
    [string]$Command = 'help',

    [Parameter(Position = 1)]
    [string]$Name,

    [ValidateRange(0, 65535)]
    [int]$Port = 0,

    [ValidatePattern('^[a-z_][a-z0-9_-]*$')]
    [string]$LinuxUser = 'coder',

    [string]$Repository,

    [string]$GitName,

    [string]$GitEmail,

    [switch]$NoBrowser,

    [switch]$Json,

    [Parameter(Position = 2, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'GitCage.psd1') -Force

function Show-GitCageHelp {
    @'
GitCage - hermetic GitHub identity workspaces for Windows

Usage:
  .\gitcage.ps1 new <name> [-Port 18100] [-LinuxUser coder]
  .\gitcage.ps1 login <name> [-GitName name] [-GitEmail address]
  .\gitcage.ps1 clone <name> -Repository owner/repo
  .\gitcage.ps1 open <name> [-NoBrowser]
  .\gitcage.ps1 audit <name> [-Json]
  .\gitcage.ps1 status <name>
  .\gitcage.ps1 list
  .\gitcage.ps1 run <name> <command> [arguments...]
  .\gitcage.ps1 stop <name>

Examples:
  .\gitcage.ps1 new personal
  .\gitcage.ps1 login personal
  .\gitcage.ps1 clone personal -Repository owner/project
  .\gitcage.ps1 audit personal
  .\gitcage.ps1 run personal git status
  .\gitcage.ps1 open personal
'@
}

if ($Command -notin @('help', 'list') -and [string]::IsNullOrWhiteSpace($Name)) {
    throw "The '$Command' command requires a cage name."
}

switch ($Command) {
    'audit' {
        $audit = Test-GitCageIsolation -Name $Name
        if ($Json) {
            $audit | ConvertTo-Json -Depth 6
        } else {
            $audit.Results | Format-Table -AutoSize
            Write-Output ''
            Write-Output ("Isolation: {0} ({1} checks, {2} failures)" -f `
                $(if ($audit.Passed) { 'PASS' } else { 'FAIL' }),
                $audit.CheckCount,
                $audit.FailureCount)
        }
        if (-not $audit.Passed) {
            exit 1
        }
    }
    'clone' {
        if ([string]::IsNullOrWhiteSpace($Repository)) {
            throw "The 'clone' command requires -Repository owner/repo."
        }
        Copy-GitCageRepository -Name $Name -Repository $Repository | Format-List
    }
    'help' {
        Show-GitCageHelp
    }
    'list' {
        Get-GitCage | Format-Table -AutoSize
    }
    'login' {
        Connect-GitCage -Name $Name -GitName $GitName -GitEmail $GitEmail `
            -NoBrowser:$NoBrowser | Format-List
    }
    'new' {
        New-GitCage -Name $Name -Port $Port -LinuxUser $LinuxUser | Format-List
    }
    'open' {
        Open-GitCage -Name $Name -NoBrowser:$NoBrowser | Format-List
    }
    'run' {
        if ($null -eq $Arguments -or $Arguments.Count -eq 0) {
            throw "The 'run' command requires a command to execute inside the cage."
        }
        Invoke-GitCage -Name $Name -ArgumentList $Arguments
    }
    'status' {
        Get-GitCage -Name $Name | Format-List
    }
    'stop' {
        Stop-GitCage -Name $Name
    }
}
