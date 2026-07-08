import Foundation
import NativeStackCore

struct ComposePreparedCommand {
    var arguments: [String]
    var subcommand: String?
    var projectName: String?
    var shouldReconcileHosts: Bool
    var shouldCleanupProject: Bool
    var messages: [String]
}

enum ComposeProjectSupport {
    private static let hostSubcommands: Set<String> = ["up", "run", "create", "start", "restart"]
    private static let lifecycleSubcommands: Set<String> = ["up", "run", "create", "start", "restart", "down", "stop", "rm", "kill"]

    private static let composeSubcommands: Set<String> = [
        "attach", "bridge", "build", "commit", "config", "cp", "create", "down", "events", "exec",
        "export", "images", "kill", "logs", "ls", "pause", "port", "ps", "publish", "pull", "push",
        "restart", "rm", "run", "scale", "start", "stats", "stop", "top", "unpause", "up", "version",
        "volumes", "wait", "watch",
    ]

    static func prepare(
        arguments: [String],
        dockerExecutable: String,
        environment: [String: String]
    ) async throws -> ComposePreparedCommand {
        var split = splitComposeArguments(arguments)
        var messages: [String] = []
        var projectName: String?

        if let subcommand = split.subcommand,
           lifecycleSubcommands.contains(subcommand),
           extractComposeFiles(from: split.globalArguments).isEmpty {
            if let session = loadSession(for: FileManager.default.currentDirectoryPath) {
                let userFiles = userComposeFiles(session.composeFiles)
                split = SplitArguments(
                    globalArguments: composeFileArguments(userFiles),
                    subcommand: subcommand,
                    subcommandArguments: split.subcommandArguments
                )
                projectName = session.projectName
                messages.append(
                    "NativeStack: using saved compose files from last nativestack compose up (\(userFiles.count) file(s))"
                )
            } else if let detected = detectLocalComposeFiles(in: FileManager.default.currentDirectoryPath) {
                split = SplitArguments(
                    globalArguments: composeFileArguments(detected),
                    subcommand: subcommand,
                    subcommandArguments: split.subcommandArguments
                )
                messages.append(
                    "NativeStack: using detected compose files (\(detected.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")))"
                )
            }
        }

        var resolvedArguments = split.globalArguments
        if let subcommand = split.subcommand {
            resolvedArguments.append(subcommand)
        }
        resolvedArguments.append(contentsOf: split.subcommandArguments)

        var shouldReconcileHosts = false
        if let subcommand = split.subcommand, hostSubcommands.contains(subcommand),
           DockerCompatibilityConfiguration.composeHostsInjectionEnabled,
           try await ComposeHostsInjector.hasHostMappings(
               arguments: resolvedArguments,
               dockerExecutable: dockerExecutable,
               environment: environment
           ) {
            shouldReconcileHosts = true
            messages.append("NativeStack: will reconcile Compose service host mappings after \(subcommand)")
        }

        let finalSplit = splitComposeArguments(resolvedArguments)
        let composeFiles = userComposeFiles(extractComposeFiles(from: finalSplit.globalArguments))
        if let subcommand = finalSplit.subcommand, hostSubcommands.contains(subcommand), !composeFiles.isEmpty {
            projectName = try await ComposeHostsInjector.fetchComposeProjectName(
                dockerExecutable: dockerExecutable,
                globalArguments: finalSplit.globalArguments,
                environment: environment
            )
            saveSession(
                ComposeSession(
                    workingDirectory: FileManager.default.currentDirectoryPath,
                    projectName: projectName ?? "compose",
                    composeFiles: composeFiles
                )
            )
        }

        return ComposePreparedCommand(
            arguments: resolvedArguments,
            subcommand: finalSplit.subcommand,
            projectName: projectName,
            shouldReconcileHosts: shouldReconcileHosts,
            shouldCleanupProject: finalSplit.subcommand == "down",
            messages: messages
        )
    }

    static func finalize(
        prepared: ComposePreparedCommand,
        dockerExecutable: String,
        environment: [String: String]
    ) async throws {
        if prepared.shouldReconcileHosts {
            try await ComposeHostsInjector.reconcileAfterCompose(
                arguments: prepared.arguments,
                dockerExecutable: dockerExecutable,
                environment: environment
            )
        }

        if prepared.shouldCleanupProject {
            let project = prepared.projectName
                ?? loadSession(for: FileManager.default.currentDirectoryPath)?.projectName
            if let project {
                let removed = try await cleanupProject(
                    projectName: project,
                    dockerExecutable: dockerExecutable,
                    environment: environment
                )
                if removed > 0 {
                    fputs("NativeStack: removed \(removed) leftover compose container(s) for project '\(project)'\n", stderr)
                }
            }
        }
    }

    static func reconcileSavedProject(
        composeArguments: [String],
        dockerExecutable: String,
        environment: [String: String]
    ) async throws {
        guard DockerCompatibilityConfiguration.composeHostsInjectionEnabled else { return }
        try await ComposeHostsInjector.reconcileAfterCompose(
            arguments: composeArguments,
            dockerExecutable: dockerExecutable,
            environment: environment
        )
    }

    /// Looks up the remembered working directory for a Compose project name, if any
    /// `nativestack compose up` session was recorded for it.
    static func workingDirectory(forProject projectName: String) -> String? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: sessionsDirectory) else {
            return nil
        }
        for name in names where name.hasSuffix(".json") {
            let path = (sessionsDirectory as NSString).appendingPathComponent(name)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let session = try? JSONDecoder().decode(ComposeSession.self, from: data),
                  session.projectName == projectName else {
                continue
            }
            return session.workingDirectory
        }
        return nil
    }

    // MARK: - Session

    private struct ComposeSession: Codable {
        var workingDirectory: String
        var projectName: String
        var composeFiles: [String]
    }

    private static var sessionsDirectory: String {
        let base = "\(NSHomeDirectory())/Library/Application Support/NativeStack"
        return "\(base)/compose-projects"
    }

    private static func sessionPath(for workingDirectory: String) -> String {
        let slug = stablePathHash(workingDirectory)
        return (sessionsDirectory as NSString).appendingPathComponent("\(slug).json")
    }

    private static func stablePathHash(_ value: String) -> String {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private static func userComposeFiles(_ files: [String]) -> [String] {
        files.filter { !$0.contains(".hosts.override.yml") && !$0.contains("/compose-overrides/") }
    }

    private static func saveSession(_ session: ComposeSession) {
        try? FileManager.default.createDirectory(atPath: sessionsDirectory, withIntermediateDirectories: true)
        let path = sessionPath(for: session.workingDirectory)
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func loadSession(for workingDirectory: String) -> ComposeSession? {
        let path = sessionPath(for: workingDirectory)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let session = try? JSONDecoder().decode(ComposeSession.self, from: data),
              session.workingDirectory == workingDirectory else {
            return nil
        }
        return session
    }

    private static func clearSession(for workingDirectory: String) {
        try? FileManager.default.removeItem(atPath: sessionPath(for: workingDirectory))
    }

    // MARK: - Cleanup

    private static func cleanupProject(
        projectName: String,
        dockerExecutable: String,
        environment: [String: String]
    ) async throws -> Int {
        let listArgs = [
            "ps", "-aq",
            "--filter", "label=com.docker.compose.project=\(projectName)",
        ]
        let listed = try await ExternalCommandRunner.run(
            executable: dockerExecutable,
            arguments: listArgs,
            environment: environment
        )
        guard listed.exitCode == 0 else { return 0 }

        let ids = listed.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !ids.isEmpty else { return 0 }

        for id in ids {
            _ = try await ExternalCommandRunner.run(
                executable: dockerExecutable,
                arguments: ["rm", "-f", id],
                environment: environment
            )
        }

        _ = try? await ExternalCommandRunner.run(
            executable: dockerExecutable,
            arguments: ["network", "rm", "\(projectName)_default"],
            environment: environment
        )
        return ids.count
    }

    // MARK: - Argument parsing

    private struct SplitArguments {
        var globalArguments: [String]
        var subcommand: String?
        var subcommandArguments: [String]
    }

    private static func splitComposeArguments(_ arguments: [String]) -> SplitArguments {
        var global: [String] = []
        var index = 0

        while index < arguments.count {
            let arg = arguments[index]
            if composeSubcommands.contains(arg), !arg.hasPrefix("-") {
                return SplitArguments(
                    globalArguments: global,
                    subcommand: arg,
                    subcommandArguments: Array(arguments[(index + 1)...])
                )
            }
            global.append(arg)
            if takesOptionValue(arg), index + 1 < arguments.count {
                index += 1
                global.append(arguments[index])
            }
            index += 1
        }
        return SplitArguments(globalArguments: global, subcommand: nil, subcommandArguments: [])
    }

    private static func takesOptionValue(_ argument: String) -> Bool {
        switch argument {
        case "-f", "--file", "--project-directory", "-p", "--project-name", "--profile", "--env-file",
             "--ansi", "--compatibility", "--context":
            return true
        default:
            return false
        }
    }

    private static func extractComposeFiles(from globalArguments: [String]) -> [String] {
        var files: [String] = []
        var index = 0
        while index < globalArguments.count {
            let arg = globalArguments[index]
            if (arg == "-f" || arg == "--file"), index + 1 < globalArguments.count {
                files.append(globalArguments[index + 1])
                index += 2
                continue
            }
            index += 1
        }
        return files
    }

    private static func composeFileArguments(_ files: [String]) -> [String] {
        files.flatMap { ["-f", $0] }
    }

    private static func detectLocalComposeFiles(in workingDirectory: String) -> [String]? {
        let candidates = [
            "docker-compose.yml",
            "docker-compose.override.yml",
            "docker-compose.local.yml",
        ]
        let existing = candidates.compactMap { name -> String? in
            let path = (workingDirectory as NSString).appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
        guard !existing.isEmpty else { return nil }

        var files: [String] = []
        if let base = existing.first(where: { ($0 as NSString).lastPathComponent == "docker-compose.yml" }) {
            files.append(base)
        }
        for name in ["docker-compose.override.yml", "docker-compose.local.yml"] {
            if let path = existing.first(where: { ($0 as NSString).lastPathComponent == name }) {
                files.append(path)
            }
        }
        if files.isEmpty {
            files = existing
        }
        return files
    }
}
