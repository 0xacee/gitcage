# Security policy

## Supported versions

GitCage is currently a pre-1.0 project. Security fixes are applied to the latest
release and the `main` branch.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository. Do not
open a public issue containing a working exploit, token, password, personal path,
or private repository name.

Include:

- affected GitCage version or commit;
- Windows and WSL versions;
- the violated security invariant;
- minimal reproduction steps with all credentials removed;
- realistic impact and any known mitigation.

If private reporting is unavailable, open a public issue containing no sensitive
details and ask the maintainer for a private contact channel.

## Scope

Reports are especially useful when they demonstrate:

- access to a Windows drive despite a passing audit;
- Windows command execution despite a passing audit;
- use of a GitHub account different from the bound identity without audit failure;
- IDE exposure beyond loopback under default configuration;
- committed or copied credentials produced by GitCage itself;
- command injection through a supported CLI parameter.

The limitations documented in `docs/THREAT_MODEL.md` are not vulnerabilities by
themselves, but bypasses of a stated invariant are.
