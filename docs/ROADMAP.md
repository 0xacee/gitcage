# Roadmap

## v0.1 — verifiable identity isolation

- [x] Named WSL2 cage lifecycle
- [x] Per-cage GitHub device authentication
- [x] Loopback-only code-server IDE
- [x] Direct command execution and repository cloning
- [x] Machine-readable isolation audit
- [x] PowerShell 5.1 and PowerShell 7 CI

## v0.2 — reproducibility and recovery

- [ ] Pin code-server versions and verify download checksums
- [ ] Export non-secret cage manifests
- [ ] Backup and restore guidance with credential redaction
- [ ] Detect WSL features before creation and explain missing prerequisites
- [ ] Optional SSH mode without importing the Windows SSH agent

## v0.3 — policy

- [ ] Declarative allowed GitHub owners and organizations
- [ ] Pre-push identity guard generated per clone
- [ ] Optional network egress policy with an explicit threat model
- [ ] Signed release artifacts and installation bootstrap

## v1.0

- Stable CLI and metadata schema
- Migration support between schema versions
- Destructive operations with typed confirmation and backup checks
- End-to-end tests on supported Windows releases

Roadmap items describe direction, not a promise or deadline. Issues proposing a
smaller, testable step are welcome.
