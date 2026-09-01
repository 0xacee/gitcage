# Contributing

Thanks for helping improve GitCage. Security and predictable failure behavior
matter more than adding commands quickly.

## Before opening a change

1. Search open issues and pull requests for overlap.
2. For security-sensitive behavior, open an issue describing the intended
   invariant before implementation. Do not publish an exploitable vulnerability;
   follow `SECURITY.md` instead.
3. Keep changes focused. Avoid unrelated formatting or refactoring.

## Development setup

On Windows PowerShell 5.1 or PowerShell 7:

```powershell
.\scripts\bootstrap-dev.ps1
.\scripts\verify.ps1
```

Shell assets must also pass:

```bash
bash -n assets/*.sh
```

## Pull requests

Every pull request should include:

- the observed problem or invariant being strengthened;
- why the change belongs in GitCage rather than user configuration;
- validation commands and results;
- security-boundary impact;
- documentation changes when CLI behavior changes.

Never commit tokens, IDE passwords, virtual disks, cage metadata, or copied user
configuration. Tests must use synthetic identities such as `octocat`.

## Design rules

- Pass argument arrays to native commands; do not concatenate untrusted shell
  strings.
- Prefer explicit failure over silent recovery for isolation controls.
- Destructive behavior requires `ShouldProcess`, exact targets, and prominent
  documentation.
- Keep Windows metadata free of credentials.
- Treat audit regressions as release blockers.
