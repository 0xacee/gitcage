<div align="center">
  <img src="docs/gitcage.svg" width="128" alt="GitCage logo">
  <h1>GitCage</h1>
  <p><strong>One Windows machine. Many GitHub identities. Zero accidental crossover.</strong></p>

  [![CI](https://github.com/0xacee/gitcage/actions/workflows/ci.yml/badge.svg)](https://github.com/0xacee/gitcage/actions/workflows/ci.yml)
  [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
</div>

GitCage creates a dedicated WSL2 distribution for each GitHub identity. Every
cage gets its own Linux filesystem, Git configuration, GitHub CLI token, IDE,
and process environment. Windows drives and Windows process interop are disabled.

The unusual part is not creating a workspace. It is the `audit` command: GitCage
checks the running environment and reports whether its isolation claims are
actually true.

## What problem does it solve?

Git profiles and credential-manager entries are easy to misconfigure. A terminal
can show the right commit email while `git push` silently uses a different cached
account. Browser profiles do not protect Git, SSH agents, extensions, or files.

GitCage moves the identity boundary below those settings:

```text
Windows
  ├─ GitCage-personal  → personal token, personal Git config, private VHD
  ├─ GitCage-work      → work token, work Git config, private VHD
  └─ Host credentials  → unavailable inside either cage
```

This is narrower than a general devcontainer manager. Tools such as
[DevPod](https://github.com/loft-sh/devpod) focus on reproducible development
environments; GitCage focuses on verifiable account separation.

## Requirements

- Windows 10 or Windows 11
- A current WSL2 installation with `systemd`, named distributions, and custom
  install locations
- PowerShell 5.1 or PowerShell 7
- Hardware virtualization enabled
- Internet access during provisioning and GitHub device login

Check WSL before starting:

```powershell
wsl.exe --version
wsl.exe --status
```

## Quick start

```powershell
git clone https://github.com/0xacee/gitcage.git
cd gitcage

# Create a cage. GitCage chooses a free IDE port from 18100-18999.
.\gitcage.ps1 new personal

# Bind exactly one GitHub account through GitHub's device flow.
.\gitcage.ps1 login personal

# Verify the boundary before cloning anything.
.\gitcage.ps1 audit personal

# Clone and open the isolated workspace.
.\gitcage.ps1 clone personal -Repository owner/project
.\gitcage.ps1 open personal
```

If local PowerShell policy blocks scripts, use a process-scoped invocation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\gitcage.ps1 audit personal
```

## Commands

| Command | Purpose |
|---|---|
| `new <name>` | Create or idempotently reprovision a cage |
| `login <name>` | Authenticate `gh`, configure Git, and bind the expected account |
| `audit <name>` | Verify mounts, interop, IDE binding, permissions, Git, and GitHub identity |
| `clone <name> -Repository owner/repo` | Clone with the cage's own GitHub credential |
| `open <name>` | Start the cage and open its loopback-only code-server IDE |
| `run <name> <command...>` | Execute a command directly without a Windows shell bridge |
| `status <name>` | Show cage state and its bound account |
| `list` | List all locally managed cages |
| `stop <name>` | Terminate the cage's WSL distribution |

Use lowercase names containing letters, digits, and hyphens. Names are mapped to
WSL distributions as `GitCage-<name>`.

## What `audit` verifies

- WSL automount is disabled.
- Windows executable interop and Windows PATH injection are disabled.
- No Windows drive is mounted below `/mnt`.
- `WSL_INTEROP` is absent from the cage process.
- code-server binds only to `127.0.0.1` and requires a password.
- IDE and GitHub credential files have restrictive ownership and permissions.
- No Windows credential helper is configured.
- The live GitHub login matches the account recorded during `login`.

An unauthenticated cage reports account checks as `SKIP`; any violated isolation
control reports `FAIL` and makes the command exit non-zero.

## Storage and lifecycle

Metadata and WSL virtual disks live under:

```text
%LOCALAPPDATA%\GitCage\
  cages\       # non-secret metadata
  distros\     # WSL virtual disks, source, and credentials
  runtime\     # keepalive process IDs
```

GitCage intentionally has no `destroy` command in v0.1. Unregistering a WSL
distribution irreversibly deletes its Linux filesystem and credentials. Read
[the lifecycle section](docs/ARCHITECTURE.md#destruction) before doing that.

## Security boundary

GitCage protects against accidental cross-account use and routine credential
leakage between development environments. It does **not** protect a cage from the
Windows user who owns it, a compromised Windows host, kernel-level attacks, or
unrestricted network egress. WSL administrators can inspect or unregister every
cage.

Read [THREAT_MODEL.md](docs/THREAT_MODEL.md) before using GitCage for sensitive
work. Security reports should follow [SECURITY.md](SECURITY.md).

## Development

```powershell
.\scripts\bootstrap-dev.ps1
.\scripts\verify.ps1
```

CI tests Windows PowerShell 5.1, PowerShell 7, Bash syntax, module metadata,
PSScriptAnalyzer, Pester, and committed credential patterns.

## Status

GitCage is an early public preview. The command and metadata formats may change
before v1.0. See the [roadmap](docs/ROADMAP.md) and
[contribution guide](CONTRIBUTING.md).

## License

[MIT](LICENSE)
