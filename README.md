# NativeStack

**NativeStack** is an OrbStack-style macOS container manager built on [Apple's native `container` tool](https://github.com/apple/container) and the [Containerization](https://github.com/apple/containerization) framework.

It provides:

- **SwiftUI menu bar app** — quick start/stop, status at a glance
- **Container IDE window** — containers, images, logs, activity monitor
- **`nativestack` CLI** — Docker-familiar commands wrapping Apple's container tool
- **Onboarding** — guides installation of Apple's container CLI

## Requirements

| Requirement | Details |
|-------------|---------|
| Hardware | Apple Silicon Mac |
| macOS | 26+ (Tahoe) recommended for full networking |
| Backend | [Apple `container` CLI](https://github.com/apple/container/releases) |

## Install Apple container (prerequisite)

```bash
# Download and install from GitHub releases, then:
container system start
container image pull alpine:latest
container run -t -i alpine:latest sh
```

## Build NativeStack

```bash
cd "cartella senza nome 4"
swift build -c release
```

Binaries:

- `.build/release/nativestack` — CLI
- `.build/release/NativeStack` — menu bar + dashboard app

Run the GUI:

```bash
.build/release/NativeStack
```

## CLI usage

```bash
nativestack system start
nativestack system status
nativestack image pull nginx:latest
nativestack run -p 8080:80 nginx:latest
nativestack ps
nativestack logs <container-id>
nativestack stop <container-id>
```

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full system design synthesized from five parallel research agents:

1. **OrbStack feature research** — prioritized feature parity matrix
2. **Apple Containerization research** — APIs, limitations, integration paths
3. **System architecture** — daemon/XPC/module structure
4. **Backend runtime plan** — ContainerManager, LinuxContainer, persistence
5. **UI/UX plan** — SwiftUI views, navigation, keyboard shortcuts

### Current implementation (Phase 1)

NativeStack Phase 1 wraps Apple's `container` CLI via `NativeStackClient`. Future phases will embed the Containerization Swift package directly for XPC daemon control, DNS (`*.nativestack.local`), and container machines.

## Project structure

```
Sources/
├── NativeStackCore/       # Models, errors
├── NativeStackClient/     # container CLI wrapper + ContainerService
├── NativeStackCLI/        # nativestack command-line tool
└── NativeStackApp/        # SwiftUI MenuBarExtra + dashboard
```

## Comparison with OrbStack

| Feature | OrbStack | NativeStack (v0.1) |
|---------|----------|-------------------|
| Runtime | Custom Linux VM + Docker | Apple container (per-container VM) |
| GUI | Native Swift | Native SwiftUI |
| Menu bar | ✅ | ✅ |
| Container list | ✅ | ✅ |
| Images | ✅ | ✅ |
| Logs | ✅ | ✅ |
| K8s / Machines | ✅ | Planned |
| Docker Compose | ✅ | Planned |
| `.local` DNS | `*.orb.local` | `*.nativestack.local` (planned) |

## License

Apache 2.0 (compatible with Apple's container projects)
