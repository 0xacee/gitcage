# GitCage

Hermetic GitHub identity workspaces for Windows, powered by WSL2.

GitCage gives every GitHub account its own Linux filesystem, Git configuration,
GitHub CLI credentials, IDE, and process namespace. It is designed for people
who contribute through multiple identities and want a machine-checkable answer
to a simple question: **can this terminal accidentally use the wrong account?**

The first public release is under active development.

## Principles

- Identity isolation is the product, not an optional profile setting.
- Windows drives and Windows process interop are disabled inside each cage.
- Credentials stay inside the cage's WSL virtual disk.
- The IDE binds to loopback and uses a generated password.
- Isolation claims are verified by an audit command.

## License

MIT
