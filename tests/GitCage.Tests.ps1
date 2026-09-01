BeforeAll {
    $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:RepositoryRoot 'GitCage.psd1'
    $script:OriginalLocalAppData = $env:LOCALAPPDATA
    $env:GITCAGE_TEST_STATE = $TestDrive
    Import-Module $script:ManifestPath -Force
    $script:GitCageModule = Get-Module GitCage
}

AfterAll {
    $env:LOCALAPPDATA = $script:OriginalLocalAppData
    Remove-Item Env:GITCAGE_TEST_STATE -ErrorAction SilentlyContinue
    Remove-Module GitCage -ErrorAction SilentlyContinue
}

Describe 'GitCage module contract' {
    It 'has a valid module manifest' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $manifest.Name | Should -Be 'GitCage'
        $manifest.Version.ToString() | Should -Be '0.1.0'
        $manifest.PowerShellVersion.ToString() | Should -Be '5.1'
    }

    It 'exports the public command surface' {
        $expected = @(
            'Connect-GitCage',
            'Copy-GitCageRepository',
            'Get-GitCage',
            'Invoke-GitCage',
            'New-GitCage',
            'Open-GitCage',
            'Stop-GitCage',
            'Test-GitCageIsolation'
        )
        $actual = @(Get-Command -Module GitCage | Select-Object -ExpandProperty Name | Sort-Object)
        $actual | Should -Be $expected
    }

    It 'parses every PowerShell source file without syntax errors' {
        $sourceFiles = Get-ChildItem -LiteralPath $script:RepositoryRoot -Recurse -File |
            Where-Object Extension -in @('.ps1', '.psd1', '.psm1')

        foreach ($sourceFile in $sourceFiles) {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $sourceFile.FullName,
                [ref]$tokens,
                [ref]$errors
            ) | Out-Null
            $errors | Should -BeNullOrEmpty -Because $sourceFile.FullName
        }
    }

    It 'rejects invalid cage names before invoking WSL' {
        { Get-GitCage -Name 'Work_Account' } | Should -Throw
    }
}

Describe 'GitCage state and native output helpers' {
    BeforeEach {
        $env:LOCALAPPDATA = $env:GITCAGE_TEST_STATE
    }

    It 'normalizes NUL-padded WSL output' {
        $values = @("Debian`0 ", '', " GitCage-work`0")
        $actual = @(& $script:GitCageModule {
            param($InputValues)
            ConvertFrom-GitCageNativeOutput -Value $InputValues
        } $values)
        $actual | Should -Be @('Debian', 'GitCage-work')
    }

    It 'round-trips cage metadata' {
        $now = [DateTimeOffset]::UtcNow.ToString('o')
        $metadata = [pscustomobject]@{
            schemaVersion = 1
            name = 'work'
            distroName = 'GitCage-work'
            linuxUser = 'coder'
            port = 18100
            installRoot = 'C:\state\GitCage-work'
            expectedGitHub = 'octocat'
            stage = 'Authenticated'
            createdAt = $now
            updatedAt = $now
        }

        & $script:GitCageModule { param($Value) Write-GitCageMetadata -Metadata $Value } $metadata
        $actual = & $script:GitCageModule { Read-GitCageMetadata -Name 'work' }

        $actual.distroName | Should -Be 'GitCage-work'
        $actual.expectedGitHub | Should -Be 'octocat'
        $actual.port | Should -Be 18100
    }

    It 'does not allocate a port reserved by cage metadata' {
        $now = [DateTimeOffset]::UtcNow.ToString('o')
        $metadata = [pscustomobject]@{
            schemaVersion = 1
            name = 'reserved'
            distroName = 'GitCage-reserved'
            linuxUser = 'coder'
            port = 18100
            installRoot = 'C:\state\GitCage-reserved'
            expectedGitHub = $null
            stage = 'Ready'
            createdAt = $now
            updatedAt = $now
        }
        & $script:GitCageModule { param($Value) Write-GitCageMetadata -Metadata $Value } $metadata

        (& $script:GitCageModule { Get-GitCageAvailablePort }) | Should -Not -Be 18100
    }
}

Describe 'Isolation assets' {
    It 'disables host mounts and Windows interop in the provisioner' {
        $provisioner = Get-Content -LiteralPath (
            Join-Path $script:RepositoryRoot 'assets\provision.sh'
        ) -Raw

        $provisioner | Should -Match '\[automount\][\s\S]*enabled=false'
        $provisioner | Should -Match '\[interop\][\s\S]*enabled=false'
        $provisioner | Should -Match 'appendWindowsPath=false'
        $provisioner | Should -Match 'bind-addr: 127\.0\.0\.1:'
    }

    It 'contains no committed GitHub token' {
        $files = Get-ChildItem -LiteralPath $script:RepositoryRoot -Recurse -File |
            Where-Object FullName -NotMatch '[\\/]\.git[\\/]'
        $content = $files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
        ($content -join "`n") | Should -Not -Match '(gho_|github_pat_)[A-Za-z0-9_]+'
    }
}
