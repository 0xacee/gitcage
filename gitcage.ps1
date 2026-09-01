[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'list', 'new', 'open', 'run', 'status', 'stop')]
    [string]$Command = 'help',

    [Parameter(Position = 1)]
    [string]$Name,

    [ValidateRange(0, 65535)]
    [int]$Port = 0,

    [ValidatePattern('^[a-z_][a-z0-9_-]*$')]
    [string]$LinuxUser = 'coder',

    [switch]$NoBrowser,

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
  .\gitcage.ps1 open <name> [-NoBrowser]
  .\gitcage.ps1 status <name>
  .\gitcage.ps1 list
  .\gitcage.ps1 run <name> <command> [arguments...]
  .\gitcage.ps1 stop <name>

Examples:
  .\gitcage.ps1 new personal
  .\gitcage.ps1 run personal git status
  .\gitcage.ps1 open personal
'@
}

if ($Command -notin @('help', 'list') -and [string]::IsNullOrWhiteSpace($Name)) {
    throw "The '$Command' command requires a cage name."
}

switch ($Command) {
    'help' {
        Show-GitCageHelp
    }
    'list' {
        Get-GitCage | Format-Table -AutoSize
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
