Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:ServiceName = 'gitcage-ide.service'
$script:SchemaVersion = 1

function Assert-GitCageHost {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'GitCage requires Windows with WSL2 installed.'
    }
}

function ConvertFrom-GitCageNativeOutput {
    param([object[]]$Value)

    @(
        $Value |
            ForEach-Object { (([string]$_) -replace "`0", '').Trim() } |
            Where-Object { $_ }
    )
}

function Get-GitCageStateRoot {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is not available. GitCage must run in a Windows user session.'
    }

    Join-Path $env:LOCALAPPDATA 'GitCage'
}

function Initialize-GitCageState {
    $root = Get-GitCageStateRoot
    New-Item -ItemType Directory -Path (Join-Path $root 'cages') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'distros') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'runtime') -Force | Out-Null
    $root
}

function Get-GitCageMetadataPath {
    param([Parameter(Mandatory = $true)][string]$Name)

    Join-Path (Join-Path (Get-GitCageStateRoot) 'cages') "$Name.json"
}

function Read-GitCageMetadata {
    param([Parameter(Mandatory = $true)][string]$Name)

    $path = Get-GitCageMetadataPath -Name $Name
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }

    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Write-GitCageMetadata {
    param([Parameter(Mandatory = $true)][object]$Metadata)

    Initialize-GitCageState | Out-Null
    $path = Get-GitCageMetadataPath -Name $Metadata.name
    $Metadata.updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $Metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-GitCageWslDistribution {
    $raw = & wsl.exe --list --quiet
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not read the WSL distribution list.'
    }
    ConvertFrom-GitCageNativeOutput -Value $raw
}

function Get-GitCageWslText {
    param(
        [Parameter(Mandatory = $true)][string]$Distribution,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [string]$User
    )

    $wslArguments = @('--distribution', $Distribution)
    if ($User) {
        $wslArguments += @('--user', $User)
    }
    $wslArguments += '--exec'
    $wslArguments += $ArgumentList

    $output = & wsl.exe @wslArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command in WSL distribution '$Distribution' failed with exit code $LASTEXITCODE."
    }

    ((ConvertFrom-GitCageNativeOutput -Value $output) -join "`n").Trim()
}

function Get-GitCageRunningDistribution {
    $raw = & wsl.exe --list --running --quiet
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not read the running WSL distribution list.'
    }
    ConvertFrom-GitCageNativeOutput -Value $raw
}

function Invoke-GitCageWsl {
    param(
        [Parameter(Mandatory = $true)][string]$Distribution,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [string]$User
    )

    $wslArguments = @('--distribution', $Distribution)
    if ($User) {
        $wslArguments += @('--user', $User)
    }
    $wslArguments += '--exec'
    $wslArguments += $ArgumentList

    & wsl.exe @wslArguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Command in WSL distribution '$Distribution' failed with exit code $exitCode."
    }
}

function Get-GitCageAvailablePort {
    $usedPorts = @{}
    $cageRoot = Join-Path (Get-GitCageStateRoot) 'cages'
    if (Test-Path -LiteralPath $cageRoot) {
        Get-ChildItem -LiteralPath $cageRoot -Filter '*.json' -File | ForEach-Object {
            $item = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            $usedPorts[[int]$item.port] = $true
        }
    }

    foreach ($candidate in 18100..18999) {
        if ($usedPorts.ContainsKey($candidate)) {
            continue
        }

        $listener = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $candidate)
        try {
            $listener.Start()
            return $candidate
        } catch [System.Net.Sockets.SocketException] {
            continue
        } finally {
            $listener.Stop()
        }
    }

    throw 'No free GitCage IDE port was found in the range 18100-18999.'
}

function Initialize-GitCageKeepAlive {
    param([Parameter(Mandatory = $true)][object]$Metadata)

    $runtimeRoot = Join-Path (Initialize-GitCageState) 'runtime'
    $pidPath = Join-Path $runtimeRoot "$($Metadata.name).pid"

    if (Test-Path -LiteralPath $pidPath) {
        $savedPid = 0
        if ([int]::TryParse((Get-Content -LiteralPath $pidPath -Raw).Trim(), [ref]$savedPid)) {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid" -ErrorAction SilentlyContinue
            if ($null -ne $process -and
                $process.Name -eq 'wsl.exe' -and
                $process.CommandLine -like "*--distribution $($Metadata.distroName)*sleep infinity*") {
                return
            }
        }
        Remove-Item -LiteralPath $pidPath -Force
    }

    $arguments = "--distribution $($Metadata.distroName) --user $($Metadata.linuxUser) --exec sleep infinity"
    $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wsl.exe') `
        -ArgumentList $arguments -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $pidPath -Value $process.Id -Encoding Ascii
}

function Wait-GitCagePort {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutSeconds = 45
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $result = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
            if ($result.AsyncWaitHandle.WaitOne(400)) {
                $client.EndConnect($result)
                return
            }
        } catch [System.Net.Sockets.SocketException] {
            $null = $_.Exception
        } finally {
            $client.Close()
        }
        Start-Sleep -Milliseconds 250
    }

    throw "The GitCage IDE did not become ready on port $Port within $TimeoutSeconds seconds."
}

function Get-GitCage {
    [CmdletBinding()]
    param(
        [ValidatePattern('^[a-z][a-z0-9-]{1,31}$')]
        [string]$Name
    )

    Assert-GitCageHost
    $knownDistributions = @(Get-GitCageWslDistribution)
    $runningDistributions = @(Get-GitCageRunningDistribution)

    if ($Name) {
        $metadata = Read-GitCageMetadata -Name $Name
        if ($null -eq $metadata) {
            throw "GitCage '$Name' does not exist."
        }
        $metadataList = @($metadata)
    } else {
        $cageRoot = Join-Path (Get-GitCageStateRoot) 'cages'
        if (-not (Test-Path -LiteralPath $cageRoot)) {
            return @()
        }
        $metadataList = @(Get-ChildItem -LiteralPath $cageRoot -Filter '*.json' -File |
            Sort-Object Name |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
    }

    foreach ($item in $metadataList) {
        $state = if ($item.distroName -in $runningDistributions) {
            'Running'
        } elseif ($item.distroName -in $knownDistributions) {
            'Stopped'
        } else {
            'Missing'
        }

        [pscustomobject]@{
            Name = $item.name
            State = $state
            Distro = $item.distroName
            LinuxUser = $item.linuxUser
            Port = [int]$item.port
            IDE = "http://127.0.0.1:$($item.port)"
            GitHub = $item.expectedGitHub
            Stage = $item.stage
            CreatedAt = $item.createdAt
        }
    }
}

function New-GitCage {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z][a-z0-9-]{1,31}$')]
        [string]$Name,

        [ValidateRange(0, 65535)]
        [int]$Port = 0,

        [ValidatePattern('^[a-z_][a-z0-9_-]*$')]
        [string]$LinuxUser = 'coder'
    )

    Assert-GitCageHost
    if ($Port -ne 0 -and $Port -lt 1024) {
        throw 'Custom IDE ports must be between 1024 and 65535.'
    }
    if (-not $PSCmdlet.ShouldProcess($Name, 'Create and provision a GitCage WSL2 distribution')) {
        return
    }
    $stateRoot = Initialize-GitCageState
    $distroName = "GitCage-$Name"
    $existingMetadata = Read-GitCageMetadata -Name $Name
    $knownDistributions = @(Get-GitCageWslDistribution)

    if ($null -eq $existingMetadata -and $distroName -in $knownDistributions) {
        throw "WSL distribution '$distroName' exists but is not managed by GitCage."
    }

    if ($null -ne $existingMetadata) {
        if ($existingMetadata.distroName -notin $knownDistributions) {
            throw "GitCage metadata exists for '$Name', but its WSL distribution is missing."
        }
        $metadata = $existingMetadata
        $Port = [int]$metadata.port
        $LinuxUser = [string]$metadata.linuxUser
    } else {
        if ($Port -eq 0) {
            $Port = Get-GitCageAvailablePort
        }

        $installRoot = Join-Path (Join-Path $stateRoot 'distros') $distroName
        Write-Information "Creating Debian WSL2 distribution '$distroName'..." -InformationAction Continue
        & wsl.exe --install Debian --name $distroName --location $installRoot --version 2 --no-launch --web-download
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create WSL distribution '$distroName'."
        }

        $now = [DateTimeOffset]::UtcNow.ToString('o')
        $metadata = [pscustomobject]@{
            schemaVersion = $script:SchemaVersion
            name = $Name
            distroName = $distroName
            linuxUser = $LinuxUser
            port = $Port
            installRoot = $installRoot
            expectedGitHub = $null
            stage = 'Created'
            createdAt = $now
            updatedAt = $now
        }
        Write-GitCageMetadata -Metadata $metadata
    }

    $provisionPath = Join-Path $script:ProjectRoot 'assets\provision.sh'
    $provisionScript = Get-Content -LiteralPath $provisionPath -Raw
    Write-Information "Provisioning '$Name' with Git, GitHub CLI, and code-server..." -InformationAction Continue
    $provisionScript | & wsl.exe --distribution $distroName --user root --exec bash -s -- $LinuxUser ([string]$Port)
    if ($LASTEXITCODE -ne 0) {
        throw "Provisioning failed for GitCage '$Name'."
    }

    $metadata.stage = 'Ready'
    Write-GitCageMetadata -Metadata $metadata

    & wsl.exe --terminate $distroName
    if ($LASTEXITCODE -ne 0) {
        throw "Could not restart WSL distribution '$distroName'."
    }

    Initialize-GitCageKeepAlive -Metadata $metadata
    Invoke-GitCageWsl -Distribution $distroName -User root `
        -ArgumentList @('systemctl', 'start', $script:ServiceName) | Out-Null
    Wait-GitCagePort -Port $Port

    Get-GitCage -Name $Name
}

function Open-GitCage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z][a-z0-9-]{1,31}$')]
        [string]$Name,

        [switch]$NoBrowser
    )

    $metadata = Read-GitCageMetadata -Name $Name
    if ($null -eq $metadata) {
        throw "GitCage '$Name' does not exist."
    }

    Initialize-GitCageKeepAlive -Metadata $metadata
    Invoke-GitCageWsl -Distribution $metadata.distroName -User root `
        -ArgumentList @('systemctl', 'start', $script:ServiceName) | Out-Null
    Wait-GitCagePort -Port ([int]$metadata.port)

    $password = & wsl.exe --distribution $metadata.distroName --user $metadata.linuxUser `
        --exec sh -lc "sed -n 's/^password: //p' ~/.config/code-server/config.yaml | head -n 1"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read the IDE password for GitCage '$Name'."
    }
    $password = (([string]$password) -replace "`0", '').Trim()
    $uri = "http://127.0.0.1:$($metadata.port)"

    if (-not $NoBrowser) {
        Start-Process $uri
    }

    [pscustomobject]@{
        Name = $Name
        IDE = $uri
        Password = $password
        Workspace = "/home/$($metadata.linuxUser)/workspace"
    }
}

function Connect-GitCage {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z][a-z0-9-]{1,31}$')]
        [string]$Name,

        [string]$GitName,

        [ValidatePattern('^[^@\s]+@[^@\s]+$')]
        [string]$GitEmail,

        [switch]$NoBrowser
    )

    $metadata = Read-GitCageMetadata -Name $Name
    if ($null -eq $metadata) {
        throw "GitCage '$Name' does not exist."
    }
    if (-not $PSCmdlet.ShouldProcess($Name, 'Authenticate and bind a GitHub identity')) {
        return
    }

    Initialize-GitCageKeepAlive -Metadata $metadata
    Invoke-GitCageWsl -Distribution $metadata.distroName -User root -ArgumentList @(
        'install', '-d', '-m', '0700',
        '-o', $metadata.linuxUser, '-g', $metadata.linuxUser,
        "/home/$($metadata.linuxUser)/.config",
        "/home/$($metadata.linuxUser)/.config/gh"
    )

    if (-not $NoBrowser) {
        Start-Process 'https://github.com/login/device'
    }

    Write-Warning 'Complete the GitHub device flow using the account dedicated to this cage.'
    Invoke-GitCageWsl -Distribution $metadata.distroName -User $metadata.linuxUser -ArgumentList @(
        'env', 'BROWSER=/bin/true', 'gh', 'auth', 'login',
        '--hostname', 'github.com',
        '--git-protocol', 'https',
        '--web'
    )
    Invoke-GitCageWsl -Distribution $metadata.distroName -User $metadata.linuxUser `
        -ArgumentList @('gh', 'auth', 'setup-git')

    $login = Get-GitCageWslText -Distribution $metadata.distroName -User $metadata.linuxUser `
        -ArgumentList @('gh', 'api', 'user', '--jq', '.login')

    if ([string]::IsNullOrWhiteSpace($GitName)) {
        $GitName = $login
    }
    if ([string]::IsNullOrWhiteSpace($GitEmail)) {
        $GitEmail = "$login@users.noreply.github.com"
    }

    Invoke-GitCageWsl -Distribution $metadata.distroName -User $metadata.linuxUser `
        -ArgumentList @('git', 'config', '--global', 'user.name', $GitName)
    Invoke-GitCageWsl -Distribution $metadata.distroName -User $metadata.linuxUser `
        -ArgumentList @('git', 'config', '--global', 'user.email', $GitEmail)

    $metadata.expectedGitHub = $login
    $metadata.stage = 'Authenticated'
    Write-GitCageMetadata -Metadata $metadata

    [pscustomobject]@{
        Name = $Name
        GitHub = $login
        GitName = $GitName
        GitEmail = $GitEmail
        CredentialStore = "/home/$($metadata.linuxUser)/.config/gh/hosts.yml"
    }
}

function Copy-GitCageRepository {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z][a-z0-9-]{1,31}$')]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^(https://github\.com/)?[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?/?$')]
        [string]$Repository
    )

    $metadata = Read-GitCageMetadata -Name $Name
    if ($null -eq $metadata) {
        throw "GitCage '$Name' does not exist."
    }
    if ([string]::IsNullOrWhiteSpace($metadata.expectedGitHub)) {
        throw "GitCage '$Name' is not connected to GitHub. Run the login command first."
    }
    if (-not $PSCmdlet.ShouldProcess($Name, "Clone GitHub repository '$Repository'")) {
        return
    }

    $trimmedRepository = $Repository.TrimEnd('/')
    $repositoryName = ($trimmedRepository -split '/')[-1] -replace '\.git$', ''
    $target = "/home/$($metadata.linuxUser)/workspace/$repositoryName"
    Initialize-GitCageKeepAlive -Metadata $metadata

    & wsl.exe --distribution $metadata.distroName --user $metadata.linuxUser `
        --exec test -e $target
    if ($LASTEXITCODE -eq 0) {
        throw "Target '$target' already exists inside GitCage '$Name'."
    }
    if ($LASTEXITCODE -ne 1) {
        throw "Could not inspect '$target' inside GitCage '$Name'."
    }

    Invoke-GitCageWsl -Distribution $metadata.distroName -User $metadata.linuxUser `
        -ArgumentList @('gh', 'repo', 'clone', $Repository, $target)

    [pscustomobject]@{
        Name = $Name
        Repository = $Repository
        Path = $target
        GitHub = $metadata.expectedGitHub
    }
}

function Test-GitCageIsolation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z][a-z0-9-]{1,31}$')]
        [string]$Name
    )

    $metadata = Read-GitCageMetadata -Name $Name
    if ($null -eq $metadata) {
        throw "GitCage '$Name' does not exist."
    }

    Initialize-GitCageKeepAlive -Metadata $metadata
    $auditPath = Join-Path $script:ProjectRoot 'assets\audit.sh'
    $auditScript = Get-Content -LiteralPath $auditPath -Raw
    $expectedGitHub = if ($null -eq $metadata.expectedGitHub) { '' } else { [string]$metadata.expectedGitHub }

    $raw = $auditScript | & wsl.exe --distribution $metadata.distroName `
        --user $metadata.linuxUser --exec bash -s -- `
        $metadata.linuxUser ([string]$metadata.port) $expectedGitHub
    if ($LASTEXITCODE -ne 0) {
        throw "Isolation audit could not run inside GitCage '$Name'."
    }

    $results = @(
        ConvertFrom-GitCageNativeOutput -Value $raw | ForEach-Object {
            $parts = $_ -split "`t", 3
            if ($parts.Count -ne 3) {
                throw "Isolation audit returned malformed output: $_"
            }
            [pscustomobject]@{
                Check = $parts[0]
                Status = $parts[1]
                Detail = $parts[2]
            }
        }
    )
    $failureCount = @($results | Where-Object Status -eq 'FAIL').Count

    [pscustomobject]@{
        Name = $Name
        Passed = $failureCount -eq 0
        CheckCount = $results.Count
        FailureCount = $failureCount
        ExpectedGitHub = $expectedGitHub
        Results = $results
    }
}

function Stop-GitCage {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z][a-z0-9-]{1,31}$')]
        [string]$Name
    )

    $metadata = Read-GitCageMetadata -Name $Name
    if ($null -eq $metadata) {
        throw "GitCage '$Name' does not exist."
    }
    if (-not $PSCmdlet.ShouldProcess($Name, 'Stop the WSL2 distribution')) {
        return
    }

    & wsl.exe --terminate $metadata.distroName
    if ($LASTEXITCODE -ne 0) {
        throw "Could not stop GitCage '$Name'."
    }

    $pidPath = Join-Path (Join-Path (Get-GitCageStateRoot) 'runtime') "$Name.pid"
    if (Test-Path -LiteralPath $pidPath) {
        Remove-Item -LiteralPath $pidPath -Force
    }

    Write-Information "Stopped GitCage '$Name'." -InformationAction Continue
}

function Invoke-GitCage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z][a-z0-9-]{1,31}$')]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ArgumentList
    )

    $metadata = Read-GitCageMetadata -Name $Name
    if ($null -eq $metadata) {
        throw "GitCage '$Name' does not exist."
    }

    Initialize-GitCageKeepAlive -Metadata $metadata
    Invoke-GitCageWsl -Distribution $metadata.distroName -User $metadata.linuxUser `
        -ArgumentList $ArgumentList
}

Export-ModuleMember -Function @(
    'Connect-GitCage',
    'Copy-GitCageRepository',
    'Get-GitCage',
    'Invoke-GitCage',
    'New-GitCage',
    'Open-GitCage',
    'Stop-GitCage',
    'Test-GitCageIsolation'
)
