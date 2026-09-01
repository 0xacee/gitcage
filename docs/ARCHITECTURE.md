# Architecture

GitCage has a thin Windows control plane and one Linux data plane per identity.

## Control plane

`gitcage.ps1` is the CLI entry point. It imports `GitCage.psd1`, which exposes the
public functions implemented by `src/GitCage.psm1`.

The control plane is responsible for:

- validating cage names and ports;
- creating named WSL2 distributions;
- writing non-secret metadata below `%LOCALAPPDATA%\GitCage\cages`;
- starting and stopping distributions;
- opening the loopback IDE in Windows;
- routing argument arrays directly to `wsl.exe` without constructing shell text.

## Data plane

`assets/provision.sh` runs as root inside a new Debian distribution. It creates an
unprivileged development user, installs Git, GitHub CLI, and code-server, writes
the WSL isolation configuration, and registers the IDE as a systemd service.

Persistent source and credentials remain in the distribution's virtual disk:

```text
/home/coder/
  .config/gh/hosts.yml
  .config/code-server/config.yaml
  .gitconfig
  workspace/
```

No Windows filesystem path is needed for normal work.

## Identity binding

`login` authenticates with GitHub's device flow inside the cage, configures the
GitHub CLI credential helper, sets commit identity, and records the returned
GitHub login in cage metadata. The OAuth token itself is never copied to Windows
metadata.

## Audit path

`assets/audit.sh` runs inside the target distribution and emits tab-separated,
machine-readable check records. PowerShell parses those records into objects and
returns a non-zero CLI exit when any check has status `FAIL`.

`SKIP` is reserved for checks that cannot apply yet, such as GitHub identity
before first login. It never hides a violated isolation setting.

## Process lifetime

WSL may stop a distribution when its last process exits. GitCage starts one hidden
`sleep infinity` process per running cage and records its Windows PID below the
runtime state directory. The IDE itself is managed by systemd and can restart on
failure.

## Destruction

GitCage does not automate deletion in v0.1. To destroy a cage, first back up or
push all source code, confirm the exact mapped distribution with `list`, stop it,
and then explicitly unregister that distribution:

```powershell
.\gitcage.ps1 list
.\gitcage.ps1 stop personal
wsl.exe --unregister GitCage-personal
```

`wsl.exe --unregister` is irreversible. After unregistering, remove only the
matching metadata JSON and distro directory under `%LOCALAPPDATA%\GitCage`.
