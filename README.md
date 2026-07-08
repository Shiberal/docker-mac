# NativeStack

**NativeStack** is an OrbStack-style macOS container manager built on [Apple's native `container` tool](https://github.com/apple/container) and the [Containerization](https://github.com/apple/containerization) framework.

It provides:

- **React Native macOS GUI** — containers, images, logs, and activity monitor
- **`nativestack` CLI** — Docker-familiar commands wrapping Apple's container tool
- **Local HTTP API** — powers the GUI via `nativestack serve`
- **Onboarding** — guides installation of Apple's container CLI

## Requirements

| Requirement | Details |
|-------------|---------|
| Hardware | Apple Silicon Mac |
| macOS | 26+ (Tahoe) recommended for full networking |
| Backend | [Apple `container` CLI](https://github.com/apple/container/releases) |
| GUI | Node.js 20+, CocoaPods |

## Install Apple container (automatic)

NativeStack auto-installs the toolkit on launch if missing:

1. **Homebrew** (`brew install container`) when available
2. Otherwise downloads Apple's signed `.pkg` from GitHub (admin password required)

Manual install:

```bash
nativestack system install
# or
brew install container
container system start
```

## Docker & Compose compatibility (Socktainer)

NativeStack can enable **Docker CLI** and **Docker Compose** via [Socktainer](https://github.com/socktainer/socktainer):

```bash
nativestack docker enable
eval "$(nativestack docker env)"

# Then use standard docker / compose commands:
docker run --rm hello-world
nativestack compose up -d
docker compose down
```

Socktainer exposes a partial Docker Engine API over a Unix socket. When run via `brew services`, the socket is at `$HOMEBREW_PREFIX/var/run/socktainer/.socktainer/container.sock`; when run manually it uses `~/.socktainer/container.sock`. NativeStack auto-detects the active socket. Compatibility is good for common dev workflows but not 100% identical to Docker Desktop.

`nativestack docker enable` installs Socktainer, the Docker CLI, Compose, and Buildx, and wires CLI plugins into `~/.docker/cli-plugins`.

### Compose build fails with `GRPCCore.RPCError`

Image builds go through Apple's container builder (gRPC), not Docker BuildKit. If a build fails mid-way with `GRPCCore.RPCError error 1`:

1. **Install Buildx** (Compose v5 expects it): `brew install docker-buildx` then re-run `nativestack docker enable`
2. **Restart the container runtime**: `container system stop && container system start`
3. **Retry the build** — first builds after restart can fail transiently ([apple/container#857](https://github.com/apple/container/issues/857))
4. **Watch logs** while building: `container system logs --debug --follow`
5. **Shrink the build context** — add a `.dockerignore` (your log showed ~35 MB sent)
6. **Avoid Desktop/Documents** — Apple's `vmnet` has a known bug when projects live under those folders on macOS 26

For a clearer error message, try building the service directly:

```bash
eval "$(nativestack docker env)"
container build --tag web_mattatoio-php --file Dockerfile .
```

### Compose service DNS (`getaddrinfo failed`)

OrbStack and Colima register Compose service names (e.g. `mysql`) in an embedded DNS server. **Socktainer 1.0.0 often does not**, which breaks apps using `MYSQL_HOST=mysql`.

**`nativestack compose` fixes this automatically** (on by default):

1. Parses your compose file and detects cross-service references (`depends_on`, `MYSQL_HOST`, etc.)
2. After `up` / `start` / `restart`, patches `/etc/hosts` inside consumer containers (Socktainer does not register Compose DNS and ignores `extra_hosts` at create time)
3. Remembers your compose files so `nativestack compose up` and `down` work without repeating `-f`

```bash
nativestack compose -f docker-compose.local.yml up -d
# NativeStack: injected Compose host mappings (...)
# NativeStack: reconciled Compose service host mappings in running containers
```

Disable with `NATIVESTACK_COMPOSE_HOSTS=0`. After `eval "$(nativestack docker env)"`, plain `docker compose` is also routed through NativeStack (via a PATH shim) so service DNS is patched automatically.

### `compose down` only stops one service

This happens when **up and down use different compose files**. Example: you start with `-f docker-compose.local.yml` (php + mysql), then run plain `docker compose down`, which reads the default `docker-compose.yml` (php only) and leaves mysql running.

**`nativestack compose down` fixes this** by remembering the compose files from your last `nativestack compose up` in the same directory and reusing them automatically. The saved files **stay remembered after down**, so a later `nativestack compose up -d` in the same folder brings mysql back without repeating `-f`. It also removes any leftover containers for that project.

If no session exists yet, NativeStack auto-detects common local files (`docker-compose.yml` + `docker-compose.local.yml` / `docker-compose.override.yml`) in the current directory.

```bash
nativestack compose -f docker-compose.local.yml up -d
nativestack compose down    # reuses saved -f files; stops php + mysql
nativestack compose up -d   # still uses docker-compose.local.yml; patches mysql host again
```

If you use plain `docker compose`, pass the same `-f` flags for both up and down.

## Install with Homebrew

NativeStack ships a Homebrew formula in `Formula/nativestack.rb`.

### From GitHub (recommended once published)

Replace `YOUR_GITHUB_USER` with your GitHub username or org, then update the `homepage`, `url`, `head`, and `sha256` fields in `Formula/nativestack.rb` to match your repository.

```bash
brew tap YOUR_GITHUB_USER/nativestack https://github.com/YOUR_GITHUB_USER/nativestack
brew install nativestack
```

Apple's container runtime is recommended but optional at install time:

```bash
brew install container
container system start
```

### From a local checkout (development)

Commit `Formula/nativestack.rb` first — `brew tap` clones from git and only sees committed files.

```bash
cd /path/to/nativestack
brew tap nativestack/tap "$(pwd)"
brew install --build-from-source nativestack/tap/nativestack
```

The formula builds the `nativestack` CLI from source on your machine (Swift ABI). After install:

```bash
nativestack system start
nativestack serve          # API for the React Native GUI
```

### Publishing a stable release

When tagging a release, refresh the tarball checksum in the formula:

```bash
git tag v0.2.0
git archive --format=tar.gz --prefix=nativestack-0.2.0/ -o nativestack-0.2.0.tar.gz v0.2.0
shasum -a 256 nativestack-0.2.0.tar.gz
# Paste the sha256 into Formula/nativestack.rb
```

Push the tag to GitHub, then users can `brew install nativestack` without `--build-from-source`.

## Build NativeStack

```bash
cd "cartella senza nome 4"
swift build -c release
```

Binaries:

- `.build/release/nativestack` — CLI + API server

## Run the React Native GUI

One command (builds backend, starts API, launches macOS app):

```bash
./scripts/run-gui.sh
```

If the API is already running on port 7842, restart it after rebuilding so compose host fixes take effect:

```bash
pkill -f 'nativestack serve' || true
./scripts/run-gui.sh
```

Manual steps:

```bash
# Terminal 1 — API backend
swift build -c release
.build/release/nativestack serve

# Terminal 2 — React Native app
cd gui
npm install
RCT_NEW_ARCH_ENABLED=1 pod install --project-directory=macos
npm run start

# Terminal 3
cd gui
RCT_NEW_ARCH_ENABLED=1 npm run macos
```

The GUI talks to `http://127.0.0.1:7842` by default.

## CLI usage

```bash
nativestack system start
nativestack system status
nativestack image pull nginx:latest
nativestack run -p 8080:80 nginx:latest
nativestack ps
nativestack logs <container-id>
nativestack stop <container-id>
nativestack serve --port 7842
```

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full system design.

### Current implementation (Phase 1)

NativeStack Phase 1 wraps Apple's `container` CLI via `NativeStackClient`. The React Native GUI consumes a local JSON HTTP API exposed by `nativestack serve`.

## Project structure

```
Sources/
├── NativeStackCore/         # Models, errors
├── NativeStackClient/       # container CLI wrapper + ContainerService
├── NativeStackAPIServer/    # HTTP API for the GUI
├── NativeStackCLI/          # nativestack command-line tool
└── NativeStackApp/          # legacy SwiftUI app (not built by default)

gui/                         # React Native macOS app
Formula/nativestack.rb       # Homebrew formula
scripts/run-gui.sh           # start API + launch GUI
```

## Comparison with OrbStack

| Feature | OrbStack | NativeStack (v0.2) |
|---------|----------|-------------------|
| Runtime | Custom Linux VM + Docker | Apple container (per-container VM) |
| GUI | Native Swift | React Native macOS |
| Menu bar | ✅ | Planned |
| Container list | ✅ | ✅ |
| Compose projects | ✅ | ✅ (via Docker/Socktainer) |
| Images | ✅ | ✅ |
| Volumes | ✅ | ✅ |
| Networks | ✅ | ✅ |
| Logs + filter | ✅ | ✅ |
| Per-container stats | ✅ | ✅ |
| Batch actions | ✅ | ✅ |
| Settings UI | ✅ | ✅ |
| Activity monitor | ✅ | ✅ (system + Docker tabs) |
| K8s / Machines | ✅ | Planned |
| Docker Compose | ✅ | ✅ via Socktainer |
| `.local` DNS | `*.orb.local` | `*.<dnsDomain>` (configurable) |

## License

Apache 2.0 (compatible with Apple's container projects)
