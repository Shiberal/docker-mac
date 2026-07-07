import Foundation
import NativeStackCore

@Observable
@MainActor
public final class ContainerService {
    private let cli: ContainerCLI

    public private(set) var systemStatus: SystemStatus
    public private(set) var containers: [ContainerRecord] = []
    public private(set) var images: [ImageRecord] = []
    public private(set) var volumes: [VolumeRecord] = []
    public private(set) var networks: [NetworkRecord] = []
    public private(set) var composeProjects: [ComposeProjectRecord] = []
    public private(set) var settings: AppSettings = AppSettingsStore.load()
    public private(set) var lastError: String?
    public private(set) var isRefreshing = false

    public var isInstalled: Bool { _isInstalled }
    private var _isInstalled: Bool = false

    public private(set) var installPhase: ToolkitInstallPhase = .idle
    public private(set) var isInstallingToolkit = false

    public var autoInstallToolkit: Bool

    public init(cli: ContainerCLI = ContainerCLI(), autoInstallToolkit: Bool = true) {
        self.cli = cli
        self.autoInstallToolkit = autoInstallToolkit
        self.systemStatus = SystemStatus(engineState: .notInstalled)
        self.settings = AppSettingsStore.load()
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        await checkInstallation()
        if !_isInstalled, autoInstallToolkit {
            try? await installToolkit()
        }
    }

    public func installToolkit(startEngineAfterInstall: Bool = false) async throws {
        guard !isInstallingToolkit else { return }
        isInstallingToolkit = true
        defer { isInstallingToolkit = false }

        let installer = ContainerToolkitInstaller.shared
        try await installer.install { [weak self] phase in
            Task { @MainActor in
                self?.installPhase = phase
            }
        }

        await checkInstallation()
        if startEngineAfterInstall, _isInstalled {
            try? await startEngine()
        }
    }

    public func checkInstallation() async {
        _isInstalled = await cli.isInstalled()
        if !_isInstalled {
            systemStatus = SystemStatus(
                engineState: .notInstalled,
                message: "Install Apple's container tool from github.com/apple/container"
            )
        } else if systemStatus.engineState == .notInstalled {
            systemStatus = SystemStatus(engineState: .stopped)
        }
    }

    public func refresh(all: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let snapshot = await Task.detached(priority: .utility) { [cli] in
            await ContainerSnapshotLoader.load(cli: cli, all: all)
        }.value

        _isInstalled = await cli.isInstalled()
        if !_isInstalled {
            systemStatus = SystemStatus(
                engineState: .notInstalled,
                message: "Install Apple's container tool from github.com/apple/container"
            )
            return
        }

        systemStatus = snapshot.systemStatus
        containers = snapshot.containers
        images = snapshot.images
        volumes = snapshot.volumes
        networks = snapshot.networks
        composeProjects = snapshot.composeProjects
        lastError = snapshot.error
    }

    public func startEngine() async throws {
        _ = try await cli.runOrThrow(
            ["system", "start", "--enable-kernel-install"],
            inheritIO: true
        )
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

    public func restartContainer(id: String) async throws {
        _ = try? await cli.runOrThrow(["stop", id])
        _ = try await cli.runOrThrow(["start", id])
        await refresh(all: true)
    }

    public func batchStartContainers(ids: [String]) async throws {
        for id in ids {
            try? await cli.runOrThrow(["start", id])
        }
        await refresh(all: true)
    }

    public func batchStopContainers(ids: [String]) async throws {
        for id in ids {
            try? await cli.runOrThrow(["stop", id])
        }
        await refresh(all: true)
    }

    public func batchRemoveContainers(ids: [String], force: Bool = true) async throws {
        for id in ids {
            var args = ["rm"]
            if force { args.append("-f") }
            args.append(id)
            try? await cli.runOrThrow(args)
        }
        await refresh(all: true)
    }

    public func containerStats(id: String) async throws -> ResourceStats {
        try await ActivityStatsLoader.loadContainerStats(cli: cli, id: id)
    }

    public func activityStats() async -> ActivityStats {
        await ActivityStatsLoader.load(
            cli: cli,
            containers: containers,
            images: images
        )
    }

    public func createVolume(name: String) async throws {
        _ = try await cli.runOrThrow(["volume", "create", name])
        await refresh(all: true)
    }

    public func removeVolume(name: String, force: Bool = false) async throws {
        var args = ["volume", "rm"]
        if force { args.append("-f") }
        args.append(name)
        if (try? await cli.runOrThrow(args)) != nil {
            await refresh(all: true)
            return
        }
        if await DockerResourceService.canQueryDocker() {
            try await DockerResourceService.removeDockerVolume(name: name)
            await refresh(all: true)
            return
        }
        _ = try await cli.runOrThrow(args)
        await refresh(all: true)
    }

    public func createNetwork(name: String) async throws {
        _ = try await cli.runOrThrow(["network", "create", name])
        await refresh(all: true)
    }

    public func removeNetwork(name: String) async throws {
        _ = try await cli.runOrThrow(["network", "rm", name])
        await refresh(all: true)
    }

    public func updateSettings(_ newSettings: AppSettings) throws {
        settings = newSettings
        try AppSettingsStore.save(newSettings)
    }

    public func reloadSettings() {
        settings = AppSettingsStore.load()
    }

    public var filesBasePath: String {
        AppSettingsStore.dataDirectoryURL.path
    }

    public func openPathHint(for container: ContainerRecord) -> String {
        let name = container.displayName
        return "\(filesBasePath)/containers/\(name)"
    }

    public func pullImage(_ reference: String) async throws {
        _ = try await cli.runOrThrow(["image", "pull", reference])
        await refresh(all: true)
    }

    public func removeImage(id: String) async throws {
        let image = images.first { $0.id == id }
        var candidates: [String] = []
        if let image {
            candidates.append(image.reference)
            if image.tag != "<none>" {
                candidates.append("\(image.repository):\(image.tag)")
            }
            candidates.append(image.id)
        } else {
            candidates.append(id)
        }

        var seen = Set<String>()
        let uniqueCandidates = candidates.filter { candidate in
            guard !candidate.isEmpty else { return false }
            return seen.insert(candidate).inserted
        }

        var lastError: Error?
        for candidate in uniqueCandidates {
            if (try? await cli.runOrThrow(["image", "rm", candidate])) != nil {
                await refresh(all: true)
                return
            }
            if await DockerResourceService.canQueryDocker() {
                do {
                    try await DockerResourceService.removeDockerImage(reference: candidate)
                    await refresh(all: true)
                    return
                } catch {
                    lastError = error
                }
            }
        }

        if let lastError {
            throw lastError
        }
        throw NativeStackError.commandFailed(
            command: "image rm \(id)",
            exitCode: 1,
            output: "Could not remove image. Tried: \(uniqueCandidates.joined(separator: ", "))"
        )
    }

    public func logs(for id: String, tail: Int = 200) async throws -> String {
        try await cli.runOrThrow(["logs", "--tail", String(tail), id])
    }

    public func runQuick(
        image: String,
        ports: [String] = [],
        detach: Bool = true,
        remove: Bool = false,
        command: [String] = [],
        interactive: Bool = false,
        tty: Bool = false
    ) async throws {
        var args = ["run"]
        let useInteractive = ContainerCLIExec.shouldRunInteractively(
            command: command,
            interactive: interactive,
            tty: tty,
            detach: detach
        )

        if useInteractive {
            args.append("-i")
            args.append("-t")
        }
        if remove { args.append("--rm") }
        if detach { args.append("-d") }
        for port in ports {
            args.append(contentsOf: ["-p", port])
        }
        args.append(image)
        args.append(contentsOf: command)

        if useInteractive {
            try ContainerCLIExec.exec(arguments: args)
        }

        let result = try await cli.run(args, inheritIO: false)
        if !detach {
            if !result.stderr.isEmpty {
                FileHandle.standardError.write(Data(result.stderr.utf8))
            }
            if !result.stdout.isEmpty {
                FileHandle.standardOutput.write(Data(result.stdout.utf8))
            }
        }
        guard result.exitCode == 0 else {
            let output = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            throw NativeStackError.commandFailed(
                command: "container " + args.joined(separator: " "),
                exitCode: result.exitCode,
                output: output
            )
        }
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

    // MARK: - Docker compatibility (Socktainer)

    public private(set) var dockerPhase: DockerCompatibilityPhase = .idle
    public private(set) var isEnablingDocker = false

    public var dockerStatus: DockerCompatibilityStatus {
        get async { await DockerCompatibilityService.shared.status() }
    }

    public func enableDockerCompatibility() async throws {
        guard !isEnablingDocker else { return }
        isEnablingDocker = true
        defer { isEnablingDocker = false }

        try await DockerCompatibilityService.shared.enable { [weak self] phase in
            Task { @MainActor in
                self?.dockerPhase = phase
            }
        }
    }

    public func runDocker(arguments: [String]) async throws {
        try await DockerCompatibilityService.shared.runDocker(arguments: arguments)
    }

    public func runCompose(arguments: [String]) async throws {
        try await DockerCompatibilityService.shared.runCompose(arguments: arguments)
    }

    public func startComposeStack(projectName: String) async throws {
        try await runComposeStackAction(projectName: projectName, action: ComposeStackService.startProject)
    }

    public func stopComposeStack(projectName: String) async throws {
        try await runComposeStackAction(projectName: projectName, action: ComposeStackService.stopProject)
    }

    private func runComposeStackAction(
        projectName: String,
        action: (
            String,
            [String],
            [ContainerRecord],
            ContainerCLI
        ) async throws -> Void
    ) async throws {
        let project = composeProjects.first { $0.name == projectName || $0.id == projectName }
        let configFiles = project?.configFiles ?? []
        try await action(
            project?.name ?? projectName,
            configFiles,
            containers,
            cli
        )
        await refresh(all: true)
    }
}
