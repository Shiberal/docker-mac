import Foundation
import NativeStackCore

public actor DockerCompatibilityService {
    public static let shared = DockerCompatibilityService()

    private let containerInstaller = ContainerToolkitInstaller.shared

    public init() {}

    public func status() -> DockerCompatibilityStatus {
        let socketPath = DockerCompatibilityConfiguration.resolvedSocketPath()
            ?? DockerCompatibilityConfiguration.userSocketPath
        return DockerCompatibilityStatus(
            socktainerInstalled: resolveExecutable("socktainer") != nil,
            socktainerRunning: DockerCompatibilityConfiguration.resolvedSocketPath() != nil,
            dockerCLIInstalled: resolveExecutable("docker") != nil,
            composeInstalled: resolveComposeExecutable() != nil,
            buildxInstalled: resolveBuildxExecutable() != nil,
            socketPath: socketPath,
            dockerHost: "unix://\(socketPath)"
        )
    }

    public func enable(
        progress: @Sendable @escaping (DockerCompatibilityPhase) -> Void = { _ in }
    ) async throws {
        progress(.checking)

        guard await containerInstaller.isPlatformSupported() else {
            throw NativeStackError.unsupportedPlatform
        }

        if ContainerCLIConfiguration().resolvedInstalledPath() == nil {
            try await containerInstaller.install()
        }

        guard let brew = ExternalCommandRunner.brewExecutable() else {
            throw NativeStackError.brewRequired
        }

        let current = status()
        if current.isReady {
            try ensureDockerCLIPlugins()
            try writeEnvironmentFile()
            progress(.succeeded)
            return
        }

        progress(.installingDependencies)

        var packages = ["socktainer"]
        if !current.dockerCLIInstalled { packages.append("docker") }
        if !current.composeInstalled { packages.append("docker-compose") }
        if !current.buildxInstalled { packages.append("docker-buildx") }

        _ = try await ExternalCommandRunner.runOrThrow(
            executable: brew,
            arguments: ["install"] + packages,
            environment: ExternalCommandRunner.homebrewEnvironment(),
            inheritIO: true
        )

        try ensureDockerCLIPlugins()

        progress(.startingSocktainer)
        let brewEnv = ExternalCommandRunner.homebrewEnvironment()
        _ = try? await ExternalCommandRunner.runOrThrow(
            executable: brew,
            arguments: ["services", "restart", "socktainer"],
            environment: brewEnv
        )
        _ = try? await ExternalCommandRunner.runOrThrow(
            executable: brew,
            arguments: ["services", "start", "socktainer"],
            environment: brewEnv
        )

        progress(.verifying)
        try await waitForSocket()

        try writeEnvironmentFile()
        progress(.succeeded)
    }

    public func runDocker(arguments: [String]) async throws {
        if arguments.first == "compose" {
            try await runCompose(arguments: Array(arguments.dropFirst()))
            return
        }

        try await ensureReady()
        guard let docker = resolveExecutable("docker") else {
            throw NativeStackError.dockerCompatibilityUnavailable(reason: "Docker CLI not found. Run `nativestack docker enable`.")
        }
        let code = try await ExternalCommandRunner.run(
            executable: docker,
            arguments: arguments,
            environment: dockerEnvironment(),
            inheritIO: true
        ).exitCode
        if code != 0 {
            throw NativeStackError.commandFailed(
                command: "docker " + arguments.joined(separator: " "),
                exitCode: code,
                output: ""
            )
        }
    }

    public func captureDocker(arguments: [String]) async throws -> String {
        try await ensureReady()
        guard let docker = resolveExecutable("docker") else {
            throw NativeStackError.dockerCompatibilityUnavailable(reason: "Docker CLI not found. Run `nativestack docker enable`.")
        }
        let result = try await ExternalCommandRunner.run(
            executable: docker,
            arguments: arguments,
            environment: dockerEnvironment(),
            inheritIO: false
        )
        guard result.exitCode == 0 else {
            let output = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            throw NativeStackError.commandFailed(
                command: "docker " + arguments.joined(separator: " "),
                exitCode: result.exitCode,
                output: output
            )
        }
        return result.stdout
    }

    public func runCompose(arguments: [String]) async throws {
        try await ensureReady()
        guard let compose = resolveComposeExecutable() else {
            throw NativeStackError.dockerCompatibilityUnavailable(
                reason: "docker compose not found. Run `nativestack docker enable`."
            )
        }

        let isPluginStyle = compose.hasSuffix("docker")
        let prepared = try await ComposeProjectSupport.prepare(
            arguments: arguments,
            dockerExecutable: compose,
            environment: dockerEnvironment()
        )

        for message in prepared.messages {
            fputs("\(message)\n", stderr)
        }

        var args: [String]
        if isPluginStyle {
            args = ["compose"] + prepared.arguments
        } else {
            args = prepared.arguments
        }

        let code = try await ExternalCommandRunner.run(
            executable: compose,
            arguments: args,
            environment: dockerEnvironment(),
            inheritIO: true
        ).exitCode
        if code != 0 {
            throw NativeStackError.commandFailed(
                command: "docker compose " + arguments.joined(separator: " "),
                exitCode: code,
                output: ""
            )
        }

        try await ComposeProjectSupport.finalize(
            prepared: prepared,
            dockerExecutable: compose,
            environment: dockerEnvironment()
        )

        if prepared.shouldReconcileHosts {
            fputs("NativeStack: reconciled Compose service host mappings in running containers\n", stderr)
        }
    }

    public func reconcileComposeHosts(composeArguments: [String]) async throws {
        try await ensureReady()
        guard let compose = resolveComposeExecutable() else { return }
        try await ComposeProjectSupport.reconcileSavedProject(
            composeArguments: composeArguments,
            dockerExecutable: compose,
            environment: dockerEnvironment()
        )
    }

    public func shellSetupSnippet() -> String {
        """
        export DOCKER_HOST=\(DockerCompatibilityConfiguration.defaultDockerHost)
        export PATH="\(DockerCompatibilityConfiguration.shimBinDirectory):$PATH"
        """
    }

    public func environmentFileContents() -> String {
        """
        # Generated by NativeStack — Docker compatibility via Socktainer
        export DOCKER_HOST=\(DockerCompatibilityConfiguration.defaultDockerHost)
        export PATH="\(DockerCompatibilityConfiguration.shimBinDirectory):$PATH"
        """
    }

    private func ensureReady() async throws {
        let current = status()
        if current.isReady { return }
        try await enable()
        guard status().isReady else {
            throw NativeStackError.dockerCompatibilityUnavailable(
                reason: "Socktainer is not running. Try `nativestack docker enable`."
            )
        }
    }

    private func dockerEnvironment() -> [String: String] {
        ["DOCKER_HOST": DockerCompatibilityConfiguration.defaultDockerHost]
    }

    private func writeEnvironmentFile() throws {
        let path = DockerCompatibilityConfiguration.envFilePath
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try writeDockerShim()
        try environmentFileContents().write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Routes plain `docker compose` through NativeStack host reconciliation for Socktainer.
    private func writeDockerShim() throws {
        guard let realDocker = resolveExecutable("docker") else { return }

        let shimDir = DockerCompatibilityConfiguration.shimBinDirectory
        try FileManager.default.createDirectory(atPath: shimDir, withIntermediateDirectories: true)

        let shimPath = DockerCompatibilityConfiguration.dockerShimPath
        let shim = """
        #!/bin/sh
        # Generated by NativeStack — routes `docker compose` through host reconciliation.
        if [ "$1" = "compose" ]; then
          shift
          NATIVESTACK_BIN="${NATIVESTACK_BIN:-$(command -v nativestack 2>/dev/null)}"
          if [ -n "$NATIVESTACK_BIN" ]; then
            exec "$NATIVESTACK_BIN" compose "$@"
          fi
          echo "NativeStack: nativestack not found; falling back to plain docker compose (Compose DNS may fail on Socktainer)" >&2
        fi
        exec "\(realDocker)" "$@"
        """

        try shim.write(toFile: shimPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimPath)
    }

    private func waitForSocket(timeout: TimeInterval = 20) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if DockerCompatibilityConfiguration.resolvedSocketPath() != nil {
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        let candidates = DockerCompatibilityConfiguration.candidateSocketPaths.joined(separator: ", ")
        throw NativeStackError.dockerCompatibilityUnavailable(
            reason: "Timed out waiting for Socktainer socket. Checked: \(candidates)"
        )
    }

    private func resolveExecutable(_ name: String) -> String? {
        let shimDir = DockerCompatibilityConfiguration.shimBinDirectory
        for dir in ContainerCLIConfiguration.defaultSearchPaths where dir != shimDir {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        if let path = ContainerCLIConfiguration.which(name),
           !path.hasPrefix(shimDir + "/") {
            return path
        }
        return nil
    }

    private func resolveComposeExecutable() -> String? {
        if let docker = resolveExecutable("docker") {
            for base in ["/opt/homebrew", "/usr/local"] {
                let plugin = "\(base)/lib/docker/cli-plugins/docker-compose"
                if FileManager.default.isExecutableFile(atPath: plugin) {
                    return docker
                }
            }
            let userPlugin = "\(NSHomeDirectory())/.docker/cli-plugins/docker-compose"
            if FileManager.default.isExecutableFile(atPath: userPlugin) {
                return docker
            }
        }
        return resolveExecutable("docker-compose")
    }

    private func resolveBuildxExecutable() -> String? {
        for base in ["/opt/homebrew", "/usr/local"] {
            let plugin = "\(base)/lib/docker/cli-plugins/docker-buildx"
            if FileManager.default.isExecutableFile(atPath: plugin) {
                return plugin
            }
        }
        let userPlugin = "\(NSHomeDirectory())/.docker/cli-plugins/docker-buildx"
        if FileManager.default.isExecutableFile(atPath: userPlugin) {
            return userPlugin
        }
        return nil
    }

    /// Symlink Homebrew Docker CLI plugins into `~/.docker/cli-plugins` so `docker compose` and `docker buildx` work.
    private func ensureDockerCLIPlugins() throws {
        let pluginDir = "\(NSHomeDirectory())/.docker/cli-plugins"
        try FileManager.default.createDirectory(atPath: pluginDir, withIntermediateDirectories: true)

        let prefix = DockerCompatibilityConfiguration.homebrewPrefix
        for name in ["docker-compose", "docker-buildx"] {
            let source = "\(prefix)/lib/docker/cli-plugins/\(name)"
            let destination = "\(pluginDir)/\(name)"
            guard FileManager.default.isExecutableFile(atPath: source) else { continue }

            if FileManager.default.fileExists(atPath: destination) {
                try? FileManager.default.removeItem(atPath: destination)
            }
            try FileManager.default.createSymbolicLink(atPath: destination, withDestinationPath: source)
        }
    }
}
