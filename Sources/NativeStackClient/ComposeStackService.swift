import Foundation
import NativeStackCore

enum ComposeStackService {
    static func startProject(
        name: String,
        configFiles: [String],
        containers: [ContainerRecord],
        cli: ContainerCLI
    ) async throws {
        if await DockerResourceService.canQueryDocker() {
            do {
                try await runComposeCommand(name: name, configFiles: configFiles, subcommand: "start")
                return
            } catch {
                if !configFiles.isEmpty {
                    do {
                        try await runComposeCommand(
                            name: name,
                            configFiles: configFiles,
                            subcommand: "up",
                            subcommandArgs: ["-d"]
                        )
                        return
                    } catch {
                        // Fall through to per-container start.
                    }
                }
            }
        }

        let projectContainers = containers.filter { $0.composeProject == name }
        guard !projectContainers.isEmpty else {
            throw NativeStackError.commandFailed(
                command: "compose start \(name)",
                exitCode: 1,
                output: "No containers found for Compose project '\(name)'. Run compose up from the project directory first."
            )
        }

        for container in projectContainers where !container.state.isActive {
            try? await cli.runOrThrow(["start", container.id])
        }

        if await DockerResourceService.canQueryDocker() {
            for container in projectContainers where !container.state.isActive {
                let target = container.name ?? container.displayName
                try? await DockerCompatibilityService.shared.runDocker(arguments: ["start", target])
            }
            try await reconcileHosts(name: name, configFiles: configFiles)
        }
    }

    static func stopProject(
        name: String,
        configFiles: [String],
        containers: [ContainerRecord],
        cli: ContainerCLI
    ) async throws {
        if await DockerResourceService.canQueryDocker() {
            do {
                try await runComposeCommand(name: name, configFiles: configFiles, subcommand: "stop")
                return
            } catch {
                // Fall through to per-container stop.
            }
        }

        let projectContainers = containers.filter { $0.composeProject == name }
        guard !projectContainers.isEmpty else {
            throw NativeStackError.commandFailed(
                command: "compose stop \(name)",
                exitCode: 1,
                output: "No containers found for Compose project '\(name)'"
            )
        }

        for container in projectContainers {
            try? await cli.runOrThrow(["stop", container.id])
        }

        if await DockerResourceService.canQueryDocker() {
            for container in projectContainers {
                let target = container.name ?? container.displayName
                try? await DockerCompatibilityService.shared.runDocker(arguments: ["stop", target])
            }
        }
    }

    private static func runComposeCommand(
        name: String,
        configFiles: [String],
        subcommand: String,
        subcommandArgs: [String] = []
    ) async throws {
        var args = buildComposeArguments(name: name, configFiles: configFiles)
        args.append(subcommand)
        args.append(contentsOf: subcommandArgs)
        try await DockerCompatibilityService.shared.runCompose(arguments: args)
    }

    private static func reconcileHosts(name: String, configFiles: [String]) async throws {
        var args = buildComposeArguments(name: name, configFiles: configFiles)
        args.append("up")
        try await DockerCompatibilityService.shared.reconcileComposeHosts(composeArguments: args)
    }

    private static func buildComposeArguments(name: String, configFiles: [String]) -> [String] {
        var args: [String] = []

        let composeFiles = configFiles.filter { FileManager.default.fileExists(atPath: $0) }
        for file in composeFiles {
            args += ["-f", file]
        }

        args += ["-p", name]

        if let directory = projectDirectory(from: composeFiles.isEmpty ? configFiles : composeFiles) {
            args += ["--project-directory", directory]
        }

        return args
    }

    private static func projectDirectory(from configFiles: [String]) -> String? {
        let primary = configFiles.first { file in
            !file.contains("/compose-overrides/")
        } ?? configFiles.first
        guard let primary else { return nil }
        let directory = (primary as NSString).deletingLastPathComponent
        guard !directory.isEmpty, FileManager.default.fileExists(atPath: directory) else {
            return nil
        }
        return directory
    }
}
