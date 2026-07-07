import ArgumentParser
import Foundation
import NativeStackAPIServer
import NativeStackClient
import NativeStackCore

@main
struct NativeStackCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nativestack",
        abstract: "OrbStack-like container manager for Apple's native container tool",
        subcommands: [
            System.self,
            Ps.self,
            Start.self,
            Stop.self,
            Rm.self,
            Logs.self,
            Image.self,
            Run.self,
            Docker.self,
            Compose.self,
            Serve.self,
        ],
        defaultSubcommand: Ps.self
    )
}

struct System: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [StartEngine.self, StopEngine.self, Status.self, InstallToolkit.self])
}

struct InstallToolkit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install")

    mutating func run() async throws {
        let service = await makeService(autoInstall: false)
        print("Installing Apple container toolkit…")
        try await service.installToolkit(startEngineAfterInstall: true)
        print("Container toolkit installed.")
        try? await service.startEngine()
        print("Container engine started.")
    }
}

struct StartEngine: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "start")

    mutating func run() async throws {
        let service = await makeService()
        try await service.startEngine()
        print("NativeStack engine started.")
    }
}

struct StopEngine: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stop")

    mutating func run() async throws {
        let service = await makeService()
        try await service.stopEngine()
        print("NativeStack engine stopped.")
    }
}

struct Status: AsyncParsableCommand {
    mutating func run() async throws {
        let service = await makeService()
        await service.refresh(all: true)
        let status = await service.systemStatus
        print("Engine: \(status.engineState.rawValue)")
        if let version = status.version { print("Version: \(version)") }
        print("Containers: \(status.runningContainers) running / \(status.totalContainers) total")
        if let message = status.message, !message.isEmpty {
            print(message)
        }
    }
}

struct Ps: AsyncParsableCommand {
    @Flag(name: .shortAndLong, help: "Show all containers")
    var all = false

    mutating func run() async throws {
        let service = await makeService()
        await service.refresh(all: all)
        let containers = await service.containers
        if containers.isEmpty {
            print("No containers.")
            return
        }
        print("ID\tIMAGE\tSTATE")
        for c in containers {
            let id = String(c.id.prefix(12))
            print("\(id)\t\(c.image)\t\(c.state.rawValue)")
        }
    }
}

struct Start: AsyncParsableCommand {
    @Argument(help: "Container ID or name")
    var id: String

    mutating func run() async throws {
        let service = await makeService()
        try await service.startContainer(id: id)
        print("Started \(id)")
    }
}

struct Stop: AsyncParsableCommand {
    @Argument(help: "Container ID or name")
    var id: String

    mutating func run() async throws {
        let service = await makeService()
        try await service.stopContainer(id: id)
        print("Stopped \(id)")
    }
}

struct Rm: AsyncParsableCommand {
    @Flag(name: .shortAndLong, help: "Force removal")
    var force = false

    @Argument(help: "Container ID or name")
    var id: String

    mutating func run() async throws {
        let service = await makeService()
        try await service.removeContainer(id: id, force: force)
        print("Removed \(id)")
    }
}

struct Logs: AsyncParsableCommand {
    @Option(name: .shortAndLong, help: "Number of lines")
    var tail = 200

    @Argument(help: "Container ID or name")
    var id: String

    mutating func run() async throws {
        let service = await makeService()
        let output = try await service.logs(for: id, tail: tail)
        print(output, terminator: output.hasSuffix("\n") ? "" : "\n")
    }
}

struct Image: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [Pull.self, Ls.self, RmImage.self])
}

struct Pull: AsyncParsableCommand {
    @Argument(help: "Image reference")
    var reference: String

    mutating func run() async throws {
        let service = await makeService()
        try await service.pullImage(reference)
        print("Pulled \(reference)")
    }
}

struct Ls: AsyncParsableCommand {
    mutating func run() async throws {
        let service = await makeService()
        await service.refresh(all: true)
        let images = await service.images
        if images.isEmpty {
            print("No images.")
            return
        }
        print("ID\tREPOSITORY:TAG\tSIZE")
        for image in images {
            let id = String(image.id.prefix(12))
            let size = image.sizeBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "-"
            print("\(id)\t\(image.reference)\t\(size)")
        }
    }
}

struct RmImage: AsyncParsableCommand {
    @Argument(help: "Image ID")
    var id: String

    mutating func run() async throws {
        let service = await makeService()
        try await service.removeImage(id: id)
        print("Removed image \(id)")
    }
}

struct Run: AsyncParsableCommand {
    @Option(name: .shortAndLong, help: "Publish a port (host:container). Repeat -p for multiple ports.")
    var publish: [String] = []

    @Flag(name: .long, help: "Remove the container when it exits")
    var rm = false

    @Flag(name: .shortAndLong, help: "Run in background")
    var detach = false

    @Flag(name: .shortAndLong, help: "Keep STDIN open (required for interactive shells)")
    var interactive = false

    @Flag(name: .shortAndLong, help: "Allocate a pseudo-TTY (required for interactive shells)")
    var tty = false

    @Argument(help: "Image reference")
    var image: String

    @Argument(parsing: .remaining, help: "Command to run inside the container")
    var command: [String] = []

    mutating func run() async throws {
        let service = await makeService()
        let runDetached = command.isEmpty ? true : detach
        try await service.runQuick(
            image: image,
            ports: publish,
            detach: runDetached,
            remove: rm,
            command: command,
            interactive: interactive,
            tty: tty
        )
        if runDetached {
            print("Started \(image)")
        }
    }
}

@MainActor
private func makeService(autoInstall: Bool = true) -> ContainerService {
    ContainerService(autoInstallToolkit: autoInstall)
}

struct Docker: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "docker",
        abstract: "Docker CLI via Socktainer compatibility layer"
    )

    @Argument(parsing: .allUnrecognized, help: "Arguments passed to docker, or: enable | status | env")
    var arguments: [String] = []

    mutating func run() async throws {
        let service = await makeService(autoInstall: false)

        guard let first = arguments.first else {
            printDockerHelp()
            return
        }

        switch first {
        case "enable":
            print("Enabling Docker compatibility (Socktainer)…")
            try await service.enableDockerCompatibility()
            let status = await service.dockerStatus
            print("Docker compatibility enabled.")
            print("DOCKER_HOST=\(status.dockerHost)")
            print("Run: eval \"$(nativestack docker env)\"")
        case "status":
            let status = await service.dockerStatus
            print("Socktainer installed: \(status.socktainerInstalled)")
            print("Socktainer running:  \(status.socktainerRunning)")
            print("Docker CLI:          \(status.dockerCLIInstalled)")
            print("Compose:             \(status.composeInstalled)")
            print("Buildx:              \(status.buildxInstalled)")
            print("Socket:              \(status.socketPath)")
            print("DOCKER_HOST:         \(status.dockerHost)")
            print("Ready:               \(status.isReady)")
        case "env":
            print(await DockerCompatibilityService.shared.shellSetupSnippet())
        default:
            try await service.runDocker(arguments: arguments)
        }
    }

    private func printDockerHelp() {
        print("""
        Usage:
          nativestack docker enable          Install/start Socktainer + Docker CLI
          nativestack docker status          Show compatibility status
          nativestack docker env             Print DOCKER_HOST export for your shell
          nativestack docker <args...>       Passthrough to docker (via Socktainer)

        Examples:
          nativestack docker run --rm hello-world
          eval "$(nativestack docker env)"
          docker compose up
        """)
    }
}

struct Compose: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compose",
        abstract: "Docker Compose via Socktainer compatibility layer"
    )

    @Argument(parsing: .allUnrecognized, help: "Arguments passed to docker compose")
    var arguments: [String] = []

    mutating func run() async throws {
        let service = await makeService(autoInstall: false)
        if arguments.isEmpty {
            print("Usage: nativestack compose up -d")
            return
        }
        try await service.runCompose(arguments: arguments)
    }
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the HTTP API for the React Native GUI"
    )

    @Option(name: .shortAndLong, help: "TCP port for the local API")
    var port: UInt16 = 7842

    @MainActor
    mutating func run() async throws {
        let service = makeService()
        let router = APIRouter(service: service)
        let server = APIServer(router: router, port: port)
        try server.start()

        while !Task.isCancelled {
            try await Task.sleep(for: .seconds(3600))
        }
    }
}
