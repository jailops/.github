**Built for FreeBSD. Sentenced to simplicity.**

JailOps is a ZFS-native management platform for FreeBSD jails, written in Go: a REST API, a CLI, a Go SDK, optional web consoles, encrypted backups and fleets declared in git. Every jail can have its own public IPv6 address, on any cloud that gives you a /64.

| | |
|---|---|
| [**JailOps**](https://github.com/jailops/jailops) | Jails, ZFS storage, VNET and PF networking, IPv6 routed and switched, backups, `jailops-sync` |
| [**PkgOps**](https://github.com/jailops/jailops-pkgops) | Build native FreeBSD packages from Go on Linux or macOS, signed `pkg` repositories, an optional registry. No FreeBSD builder |
| [**Packages**](https://github.com/jailops/jailops-packages) | The signed package repository at `pkg.jailops.net`: JailOps and PkgOps for FreeBSD 15.1 and later, amd64 and arm64 |

Documentation, examples and the roadmap: [jailops.net](https://jailops.net)

DevOps. SecOps. JailOps.
