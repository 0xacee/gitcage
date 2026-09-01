# Support

Use GitHub Issues for reproducible GitCage bugs and focused feature proposals.

Before filing an issue, collect these non-secret diagnostics:

```powershell
wsl.exe --version
.\gitcage.ps1 status <name>
.\gitcage.ps1 audit <name> -Json
```

Remove usernames, Windows paths, repository names, tokens, device codes, and IDE
passwords before posting output. Never paste `hosts.yml` or cage virtual disks.

General WSL installation failures may be better suited to the
[Microsoft WSL repository](https://github.com/microsoft/WSL). code-server package
or extension failures may belong in the
[code-server repository](https://github.com/coder/code-server).
