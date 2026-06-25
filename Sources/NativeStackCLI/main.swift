import ArgumentParser
import Foundation
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
        ],
        defaultSubcommand: Ps.self
    )
}

struct System: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [StartEngine.self, StopEngine.self, Status.self])
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
    @Option(name: .shortAndLong, parsing: .upToNextOption, help: "Publish ports (host:container)")
    var publish: [String] = []

    @Flag(name: .shortAndLong, help: "Run in background")
    var detach = true

    @Argument(help: "Image reference")
    var image: String

    mutating func run() async throws {
        let service = await makeService()
        try await service.runQuick(image: image, ports: publish, detach: detach)
        print("Started \(image)")
    }
}

@MainActor
private func makeService() -> ContainerService {
    ContainerService()
}
