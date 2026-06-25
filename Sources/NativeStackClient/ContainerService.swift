import Foundation
import NativeStackCore

@Observable
@MainActor
public final class ContainerService {
    private let cli: ContainerCLI

    public private(set) var systemStatus: SystemStatus
    public private(set) var containers: [ContainerRecord] = []
    public private(set) var images: [ImageRecord] = []
    public private(set) var lastError: String?
    public private(set) var isRefreshing = false

    public var isInstalled: Bool { _isInstalled }
    private var _isInstalled: Bool = false

    public init(cli: ContainerCLI = ContainerCLI()) {
        self.cli = cli
        self.systemStatus = SystemStatus(engineState: .notInstalled)
        Task { await checkInstallation() }
    }

    public func checkInstallation() async {
        _isInstalled = await cli.isInstalled()
        if !_isInstalled {
            systemStatus = SystemStatus(
                engineState: .notInstalled,
                message: "Install Apple's container tool from github.com/apple/container"
            )
        }
    }

    public func refresh(all: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await checkInstallation()
        guard _isInstalled else { return }

        do {
            let psArgs = all ? ["ps", "-a"] : ["ps"]
            let psOut = try await cli.runOrThrow(psArgs)
            containers = ContainerOutputParser.parseContainers(from: psOut, includeStopped: all)

            let statusResult = try await cli.run(["system", "status"])
            systemStatus = ContainerOutputParser.parseSystemStatus(
                stdout: statusResult.stdout,
                stderr: statusResult.stderr,
                containers: containers
            )

            if let imagesOut = try? await cli.runOrThrow(["image", "ls"]) {
                images = ContainerOutputParser.parseImages(from: imagesOut)
            }

            lastError = nil
        } catch {
            lastError = error.localizedDescription
            if let nsError = error as? NativeStackError,
               case .containerCLINotFound = nsError {
                systemStatus = SystemStatus(engineState: .notInstalled, message: error.localizedDescription)
            }
        }
    }

    public func startEngine() async throws {
        _ = try await cli.runOrThrow(["system", "start"])
        await refresh(all: true)
    }

    public func stopEngine() async throws {
        _ = try await cli.runOrThrow(["system", "stop"])
        await refresh(all: true)
    }

    public func startContainer(id: String) async throws {
        _ = try await cli.runOrThrow(["start", id])
        await refresh(all: true)
    }

    public func stopContainer(id: String) async throws {
        _ = try await cli.runOrThrow(["stop", id])
        await refresh(all: true)
    }

    public func removeContainer(id: String, force: Bool = false) async throws {
        var args = ["rm"]
        if force { args.append("-f") }
        args.append(id)
        _ = try await cli.runOrThrow(args)
        await refresh(all: true)
    }

    public func pullImage(_ reference: String) async throws {
        _ = try await cli.runOrThrow(["image", "pull", reference])
        await refresh(all: true)
    }

    public func removeImage(id: String) async throws {
        _ = try await cli.runOrThrow(["image", "rm", id])
        await refresh(all: true)
    }

    public func logs(for id: String, tail: Int = 200) async throws -> String {
        try await cli.runOrThrow(["logs", "--tail", String(tail), id])
    }

    public func runQuick(image: String, ports: [String] = [], detach: Bool = true) async throws {
        var args = ["run"]
        if detach { args.append("-d") }
        for port in ports {
            args.append(contentsOf: ["-p", port])
        }
        args.append(image)
        _ = try await cli.runOrThrow(args)
        await refresh(all: true)
    }

    public func streamLogs(for id: String) -> AsyncStream<LogLine> {
        AsyncStream { continuation in
            Task {
                do {
                    let result = try await cli.run(["logs", "-f", "--tail", "100", id])
                    let text = result.stdout + result.stderr
                    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                        continuation.yield(LogLine(text: String(line)))
                    }
                } catch {
                    continuation.yield(LogLine(text: "Error: \(error.localizedDescription)"))
                }
                continuation.finish()
            }
        }
    }
}
