# Threat model

GitCage is an identity-isolation tool, not a hardened hostile-code sandbox. This
document defines the boundary precisely so users can decide whether it fits their
risk.

## Assets

- GitHub CLI OAuth tokens
- Git commit identity and credential-helper configuration
- Source code cloned for one identity
- IDE extensions, settings, terminals, and command history
- The association between a cage and its expected GitHub account

## Trusted components

- The Windows user creating the cage
- Windows, WSL2, and the Linux kernel supplied through WSL
- Debian package repositories used during provisioning
- GitHub CLI and GitHub's device authentication flow
- The official code-server installer and package repository

GitCage cannot provide stronger guarantees than these components.

## Threats in scope

### Accidental credential reuse

A contributor signs commits as account A but pushes with a cached token for
account B. GitCage stores GitHub CLI state inside a dedicated Linux virtual disk,
removes inherited credential helpers, and compares the live account to metadata
recorded at login.

### Accidental host filesystem access

A command or coding agent reads repositories, SSH keys, or configuration from a
Windows drive. GitCage disables WSL automount, checks for manual drive mounts,
disables Windows PATH injection, and makes the audit fail when a drive appears.

### Accidental Windows command execution

Linux tooling invokes a Windows executable through WSL interop. GitCage disables
interop in `/etc/wsl.conf` and checks that the `WSL_INTEROP` socket is absent.

### IDE exposure on the LAN

The web IDE unintentionally listens on all interfaces. GitCage writes and audits
a loopback-only `127.0.0.1` binding with password authentication.

### Permissive credential files

Credential or IDE configuration becomes readable by other Linux users. GitCage
checks file owner and mode for code-server configuration and `gh`'s `hosts.yml`.

## Threats out of scope

- A malicious or compromised Windows account that owns the WSL distributions
- Windows administrator, hypervisor, kernel, or WSL vulnerabilities
- Malicious root processes inside the cage
- Network isolation, domain allowlists, or data-loss prevention
- GitHub account compromise, malicious OAuth applications, or browser compromise
- Supply-chain compromise of Debian, GitHub CLI, code-server, or downloaded tools
- Denial of service and resource exhaustion across WSL distributions

## Residual risks

Windows can access WSL files through supported host mechanisms even when drives
are not mounted inside Linux. A user with control of the host can also change
`/etc/wsl.conf`, modify the virtual disk, replace `wsl.exe`, or attach a debugger.

The code-server installer is downloaded over HTTPS during provisioning. A future
release should replace this bootstrap path with a version-pinned package and
checksum verification.

The audit is point-in-time evidence. A privileged process can change the cage
after an audit, so high-sensitivity workflows should audit immediately before
authentication and push operations.

## Security invariants

The following conditions are treated as release-blocking invariants:

1. Windows drive automount remains disabled.
2. Windows executable interop remains disabled.
3. The IDE never binds beyond loopback by default.
4. A cage never imports a host Git credential helper.
5. A recorded GitHub identity mismatch is a failing audit result.
6. Repository code never contains a token or generated IDE password.
