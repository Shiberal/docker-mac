import Foundation
import NativeStackCore

/// Injects `extra_hosts` for Compose service DNS when Socktainer does not register names.
enum ComposeHostsInjector {
    private static let injectableSubcommands: Set<String> = [
        "up", "run", "create", "start", "restart",
    ]

    private static let composeSubcommands: Set<String> = [
        "attach", "bridge", "build", "commit", "config", "cp", "create", "down", "events", "exec",
        "export", "images", "kill", "logs", "ls", "pause", "port", "ps", "publish", "pull", "push",
        "restart", "rm", "run", "scale", "start", "stats", "stop", "top", "unpause", "up", "version",
        "volumes", "wait", "watch",
    ]

    static func shouldInject(arguments: [String]) -> Bool {
        guard DockerCompatibilityConfiguration.composeHostsInjectionEnabled else { return false }
        let split = splitComposeArguments(arguments)
        guard let subcommand = split.subcommand else { return false }
        return injectableSubcommands.contains(subcommand)
    }

    static func hasHostMappings(
        arguments: [String],
        dockerExecutable: String,
        environment: [String: String]
    ) async throws -> Bool {
        guard shouldInject(arguments: arguments) else { return false }
        let split = splitComposeArguments(arguments)
        let config = try await fetchComposeConfig(
            dockerExecutable: dockerExecutable,
            globalArguments: split.globalArguments,
            environment: environment
        )
        guard let plan = try await resolvedPlan(
            config: config,
            dockerExecutable: dockerExecutable,
            globalArguments: split.globalArguments,
            environment: environment
        ) else { return false }
        return !plan.entries.isEmpty
    }

    static func argumentsWithHostsOverride(
        arguments: [String],
        dockerExecutable: String,
        environment: [String: String]
    ) async throws -> (arguments: [String], overridePath: String?)? {
        guard shouldInject(arguments: arguments) else { return nil }

        let split = splitComposeArguments(arguments)
        guard let subcommand = split.subcommand else { return nil }

        let config = try await fetchComposeConfig(
            dockerExecutable: dockerExecutable,
            globalArguments: split.globalArguments,
            environment: environment
        )

        guard let plan = try await resolvedPlan(
            config: config,
            dockerExecutable: dockerExecutable,
            globalArguments: split.globalArguments,
            environment: environment
        ) else { return nil }

        let grouped = Dictionary(grouping: plan.entries.filter { !$0.hostValue.isEmpty }, by: \.consumerService)
        guard !grouped.isEmpty else { return nil }

        let yaml = renderOverrideYAML(grouped)
        let overridePath = try writeOverrideFile(
            yaml: yaml,
            projectName: plan.projectName,
            fingerprint: split.globalArguments.joined(separator: "|")
        )

        let updated = insertOverrideFile(overridePath, into: arguments, subcommand: subcommand)
        return (updated, overridePath)
    }

    static func fetchComposeProjectName(
        dockerExecutable: String,
        globalArguments: [String],
        environment: [String: String]
    ) async throws -> String {
        let config = try await fetchComposeConfig(
            dockerExecutable: dockerExecutable,
            globalArguments: globalArguments,
            environment: environment
        )
        return config.projectName
    }

    static func reconcileAfterCompose(
        arguments: [String],
        dockerExecutable: String,
        environment: [String: String]
    ) async throws {
        guard shouldInject(arguments: arguments) else { return }

        let split = splitComposeArguments(arguments)
        let config = try await fetchComposeConfig(
            dockerExecutable: dockerExecutable,
            globalArguments: split.globalArguments,
            environment: environment
        )
        guard let plan = try await resolvedPlan(
            config: config,
            dockerExecutable: dockerExecutable,
            globalArguments: split.globalArguments,
            environment: environment
        ) else { return }

        try await reconcileHosts(
            plan: plan,
            services: config.services,
            dockerExecutable: dockerExecutable,
            environment: environment
        )
    }

    /// Socktainer currently ignores `extra_hosts` at create time; patch `/etc/hosts` after compose succeeds.
    private static func reconcileHosts(
        plan: InjectionPlan,
        services: [String: ComposeService],
        dockerExecutable: String,
        environment: [String: String]
    ) async throws {
        guard !plan.entries.isEmpty else { return }

        let gateway = try await lookupNetworkGateway(
            dockerExecutable: dockerExecutable,
            environment: environment,
            projectName: plan.projectName
        )

        let ipMap = try await lookupServiceIPsWithRetry(
            dockerExecutable: dockerExecutable,
            environment: environment,
            projectName: plan.projectName,
            services: services
        )

        for entry in plan.entries {
            let hostValue: String?
            if entry.hostValue == "host-gateway" {
                hostValue = gateway
            } else if !entry.hostValue.isEmpty {
                hostValue = entry.hostValue
            } else if let ip = ipMap[entry.targetService] {
                hostValue = ip
            } else {
                hostValue = nil
            }
            guard let hostValue else { continue }

            guard let container = try await resolveRunningContainer(
                dockerExecutable: dockerExecutable,
                environment: environment,
                projectName: plan.projectName,
                serviceName: entry.consumerService,
                services: services
            ) else { continue }

            try await appendHostEntry(
                dockerExecutable: dockerExecutable,
                environment: environment,
                container: container,
                hostname: entry.targetService,
                ip: hostValue
            )
        }
    }

    // MARK: - Types

    private struct ComposeConfig {
        var projectName: String
        var services: [String: ComposeService]
    }

    private struct ComposeService {
        var containerName: String?
        var publishedPorts: [String]
        var environment: [String: String]
        var dependsOn: [String]
    }

    private struct InjectionEntry {
        var consumerService: String
        var targetService: String
        var hostValue: String
        var targetHasPublishedPorts: Bool
    }

    private struct InjectionPlan {
        var projectName: String
        var entries: [InjectionEntry]
        var services: [String: ComposeService]
    }

    private struct SplitArguments {
        var globalArguments: [String]
        var subcommand: String?
        var subcommandArguments: [String]
    }

    // MARK: - Compose config

    private static func splitComposeArguments(_ arguments: [String]) -> SplitArguments {
        var global: [String] = []
        var index = 0

        while index < arguments.count {
            let arg = arguments[index]
            if composeSubcommands.contains(arg), !arg.hasPrefix("-") {
                let rest = Array(arguments[(index + 1)...])
                return SplitArguments(
                    globalArguments: global,
                    subcommand: arg,
                    subcommandArguments: rest
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

    private static func fetchComposeConfig(
        dockerExecutable: String,
        globalArguments: [String],
        environment: [String: String]
    ) async throws -> ComposeConfig {
        let args = ["compose"] + globalArguments + ["config", "--format", "json"]
        let result = try await ExternalCommandRunner.run(
            executable: dockerExecutable,
            arguments: args,
            environment: environment
        )
        guard result.exitCode == 0 else {
            let output = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            throw NativeStackError.commandFailed(
                command: ([dockerExecutable] + args).joined(separator: " "),
                exitCode: result.exitCode,
                output: output
            )
        }
        return try parseComposeConfigJSON(result.stdout)
    }

    private static func parseComposeConfigJSON(_ json: String) throws -> ComposeConfig {
        guard let data = json.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeStackError.parseFailed(context: "compose config JSON")
        }

        let projectName = root["name"] as? String ?? "compose"
        guard let servicesObject = root["services"] as? [String: Any] else {
            return ComposeConfig(projectName: projectName, services: [:])
        }

        var services: [String: ComposeService] = [:]
        for (name, value) in servicesObject {
            guard let service = value as? [String: Any] else { continue }
            services[name] = ComposeService(
                containerName: service["container_name"] as? String,
                publishedPorts: parsePublishedPorts(service["ports"]),
                environment: parseEnvironment(service["environment"]),
                dependsOn: parseDependsOn(service["depends_on"])
            )
        }
        return ComposeConfig(projectName: projectName, services: services)
    }

    private static func parsePublishedPorts(_ value: Any?) -> [String] {
        guard let ports = value as? [Any] else { return [] }
        var published: [String] = []
        for entry in ports {
            if let text = entry as? String {
                let parts = text.split(separator: ":")
                if let last = parts.last, Int(last) != nil {
                    published.append(String(last))
                }
                continue
            }
            guard let object = entry as? [String: Any] else { continue }
            if let p = object["published"] as? String, !p.isEmpty {
                published.append(p)
            } else if let p = object["published"] as? Int {
                published.append(String(p))
            }
        }
        return published
    }

    private static func parseEnvironment(_ value: Any?) -> [String: String] {
        if let object = value as? [String: Any] {
            return object.compactMapValues { item in
                if let text = item as? String { return text }
                if let number = item as? NSNumber { return number.stringValue }
                return nil
            }
        }
        guard let array = value as? [String] else { return [:] }
        var env: [String: String] = [:]
        for item in array {
            let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            env[parts[0]] = parts[1]
        }
        return env
    }

    private static func parseDependsOn(_ value: Any?) -> [String] {
        if let array = value as? [String] { return array }
        if let object = value as? [String: Any] { return Array(object.keys).sorted() }
        return []
    }

    // MARK: - Injection plan

    private static func resolvedPlan(
        config: ComposeConfig,
        dockerExecutable: String,
        globalArguments: [String],
        environment: [String: String]
    ) async throws -> InjectionPlan? {
        var plan = buildInjectionPlan(from: config)
        guard !plan.entries.isEmpty else { return nil }

        let internalTargets = Set(plan.entries.map(\.targetService))
        if !internalTargets.isEmpty {
            try await ensureDependencyServicesRunning(
                dockerExecutable: dockerExecutable,
                globalArguments: globalArguments,
                environment: environment,
                services: Array(internalTargets)
            )
            let ipMap = try await lookupServiceIPs(
                dockerExecutable: dockerExecutable,
                environment: environment,
                projectName: plan.projectName,
                services: config.services
            )
            plan.entries = plan.entries.map { entry in
                guard entry.hostValue.isEmpty,
                      let ip = ipMap[entry.targetService] else { return entry }
                return InjectionEntry(
                    consumerService: entry.consumerService,
                    targetService: entry.targetService,
                    hostValue: ip,
                    targetHasPublishedPorts: entry.targetHasPublishedPorts
                )
            }
        }
        return plan
    }

    private static func buildInjectionPlan(from config: ComposeConfig) -> InjectionPlan {
        let serviceNames = config.services.keys.sorted()
        var entries: [InjectionEntry] = []

        // Mirror Docker Compose embedded DNS: every service can resolve every peer
        // service name (and explicit container_name aliases) in the project.
        for consumer in serviceNames {
            for target in serviceNames where target != consumer {
                guard let targetService = config.services[target] else { continue }
                let hasPorts = !targetService.publishedPorts.isEmpty
                for hostname in hostnames(for: target, service: targetService) {
                    entries.append(
                        InjectionEntry(
                            consumerService: consumer,
                            targetService: hostname,
                            hostValue: "",
                            targetHasPublishedPorts: hasPorts
                        )
                    )
                }
            }
        }

        return InjectionPlan(
            projectName: config.projectName,
            entries: deduplicated(entries),
            services: config.services
        )
    }

    private static func hostnames(for serviceName: String, service: ComposeService) -> [String] {
        var names = [serviceName]
        if let containerName = service.containerName,
           !containerName.isEmpty,
           containerName != serviceName {
            names.append(containerName)
        }
        return names
    }

    private static func deduplicated(_ entries: [InjectionEntry]) -> [InjectionEntry] {
        var seen = Set<String>()
        var result: [InjectionEntry] = []
        for entry in entries {
            let key = "\(entry.consumerService)|\(entry.targetService)"
            guard seen.insert(key).inserted else { continue }
            result.append(entry)
        }
        return result
    }

    // MARK: - Network lookup

    private static func lookupNetworkGateway(
        dockerExecutable: String,
        environment: [String: String],
        projectName: String
    ) async throws -> String? {
        let networkName = "\(projectName)_default"
        let args = ["network", "inspect", networkName, "--format", "{{json .Gateway}}"]
        let result = try await ExternalCommandRunner.run(
            executable: dockerExecutable,
            arguments: args,
            environment: environment
        )
        guard result.exitCode == 0 else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private static func resolveRunningContainer(
        dockerExecutable: String,
        environment: [String: String],
        projectName: String,
        serviceName: String,
        services: [String: ComposeService]
    ) async throws -> String? {
        if let containerName = services[serviceName]?.containerName {
            let args = ["inspect", "-f", "{{.State.Running}}", containerName]
            let result = try await ExternalCommandRunner.run(
                executable: dockerExecutable,
                arguments: args,
                environment: environment
            )
            if result.exitCode == 0, result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" {
                return containerName
            }
        }

        let args = [
            "ps",
            "--filter", "label=com.docker.compose.project=\(projectName)",
            "--filter", "label=com.docker.compose.service=\(serviceName)",
            "--format", "{{.Names}}",
        ]
        let result = try await ExternalCommandRunner.run(
            executable: dockerExecutable,
            arguments: args,
            environment: environment
        )
        guard result.exitCode == 0 else { return nil }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { !$0.isEmpty }
    }

    private static func appendHostEntry(
        dockerExecutable: String,
        environment: [String: String],
        container: String,
        hostname: String,
        ip: String
    ) async throws {
        let script = """
        grep -qE '[[:space:]]\(hostname)$' /etc/hosts 2>/dev/null || echo '\(ip) \(hostname)' >> /etc/hosts
        """
        let args = ["exec", container, "sh", "-c", script]
        _ = try await ExternalCommandRunner.run(
            executable: dockerExecutable,
            arguments: args,
            environment: environment
        )
    }

    private static func ensureDependencyServicesRunning(
        dockerExecutable: String,
        globalArguments: [String],
        environment: [String: String],
        services: [String]
    ) async throws {
        guard !services.isEmpty else { return }
        let args = ["compose"] + globalArguments + ["up", "-d"] + services
        _ = try await ExternalCommandRunner.run(
            executable: dockerExecutable,
            arguments: args,
            environment: environment,
            inheritIO: false
        )
    }

    private static func lookupServiceIPsWithRetry(
        dockerExecutable: String,
        environment: [String: String],
        projectName: String,
        services: [String: ComposeService]
    ) async throws -> [String: String] {
        let expectedCount = services.count
        let maxAttempts = 12

        for attempt in 0..<maxAttempts {
            let ipMap = try await lookupServiceIPs(
                dockerExecutable: dockerExecutable,
                environment: environment,
                projectName: projectName,
                services: services
            )
            if ipMap.count >= expectedCount || (expectedCount <= 1 && !ipMap.isEmpty) {
                return ipMap
            }
            if attempt + 1 < maxAttempts {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        return try await lookupServiceIPs(
            dockerExecutable: dockerExecutable,
            environment: environment,
            projectName: projectName,
            services: services
        )
    }

    private static func lookupServiceIPs(
        dockerExecutable: String,
        environment: [String: String],
        projectName: String,
        services: [String: ComposeService]
    ) async throws -> [String: String] {
        let networkName = "\(projectName)_default"
        let psArgs = [
            "ps", "-q",
            "--filter", "label=com.docker.compose.project=\(projectName)",
        ]
        let psResult = try await ExternalCommandRunner.run(
            executable: dockerExecutable,
            arguments: psArgs,
            environment: environment
        )

        var serviceIPs: [String: String] = [:]
        if psResult.exitCode == 0 {
            let ids = psResult.stdout
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for id in ids {
                let inspectArgs = ["inspect", id, "--format", "{{json .}}"]
                let inspectResult = try await ExternalCommandRunner.run(
                    executable: dockerExecutable,
                    arguments: inspectArgs,
                    environment: environment
                )
                guard inspectResult.exitCode == 0,
                      let data = inspectResult.stdout.data(using: .utf8),
                      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let ip = ipAddress(
                          from: root["NetworkSettings"] as? [String: Any],
                          preferredNetwork: networkName
                      ) else {
                    continue
                }

                let config = root["Config"] as? [String: Any]
                let labels = config?["Labels"] as? [String: String] ?? [:]
                if let composeService = labels["com.docker.compose.service"], !composeService.isEmpty {
                    serviceIPs[composeService] = ip
                }
                if let containerName = (root["Name"] as? String)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                   !containerName.isEmpty {
                    serviceIPs[containerName] = ip
                }
            }
        }

        for (serviceName, service) in services where serviceIPs[serviceName] == nil {
            if let containerName = service.containerName, let ip = serviceIPs[containerName] {
                serviceIPs[serviceName] = ip
            }
        }

        if !serviceIPs.isEmpty {
            return serviceIPs
        }

        return try await lookupServiceIPsFromNetworkInspect(
            dockerExecutable: dockerExecutable,
            environment: environment,
            projectName: projectName,
            networkName: networkName,
            services: services
        )
    }

    private static func lookupServiceIPsFromNetworkInspect(
        dockerExecutable: String,
        environment: [String: String],
        projectName: String,
        networkName: String,
        services: [String: ComposeService]
    ) async throws -> [String: String] {
        let args = ["network", "inspect", networkName, "--format", "{{json .}}"]
        let result = try await ExternalCommandRunner.run(
            executable: dockerExecutable,
            arguments: args,
            environment: environment
        )
        guard result.exitCode == 0,
              let data = result.stdout.data(using: .utf8),
              let network = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let containers = network["Containers"] as? [String: Any] else {
            return [:]
        }

        var containerIPs: [String: String] = [:]
        for (_, value) in containers {
            guard let endpoint = value as? [String: Any],
                  let address = endpoint["IPv4Address"] as? String else { continue }
            let ip = address.split(separator: "/").first.map(String.init) ?? address
            if let name = endpoint["Name"] as? String, !name.isEmpty {
                containerIPs[name] = ip
            }
        }

        let labelArgs = [
            "ps", "-a",
            "--filter", "label=com.docker.compose.project=\(projectName)",
            "--format", "{{.Names}}\t{{.Label \"com.docker.compose.service\"}}",
        ]
        let labelResult = try await ExternalCommandRunner.run(
            executable: dockerExecutable,
            arguments: labelArgs,
            environment: environment
        )

        var serviceIPs: [String: String] = [:]
        if labelResult.exitCode == 0 {
            for line in labelResult.stdout.split(whereSeparator: \.isNewline) {
                let parts = String(line).split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let containerName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let composeService = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !containerName.isEmpty, !composeService.isEmpty,
                      let ip = containerIPs[containerName] else { continue }
                serviceIPs[composeService] = ip
                serviceIPs[containerName] = ip
            }
        }

        for (serviceName, service) in services where serviceIPs[serviceName] == nil {
            if let containerName = service.containerName, let ip = serviceIPs[containerName] ?? containerIPs[serviceName] {
                serviceIPs[serviceName] = ip
                continue
            }
            if let match = containerIPs.first(where: { $0.key.contains(serviceName) }) {
                serviceIPs[serviceName] = match.value
            }
        }
        return serviceIPs
    }

    private static func ipAddress(
        from networkSettings: [String: Any]?,
        preferredNetwork: String
    ) -> String? {
        guard let networks = networkSettings?["Networks"] as? [String: [String: Any]] else {
            return nil
        }
        if let endpoint = networks[preferredNetwork],
           let ip = endpoint["IPAddress"] as? String,
           !ip.isEmpty {
            return ip
        }
        for (_, endpoint) in networks {
            guard let ip = endpoint["IPAddress"] as? String, !ip.isEmpty else { continue }
            return ip
        }
        return nil
    }

    // MARK: - Override file

    private static func renderOverrideYAML(_ grouped: [String: [InjectionEntry]]) -> String {
        var lines = [
            "# Generated by NativeStack — Compose service host mappings for Socktainer",
            "# Set NATIVESTACK_COMPOSE_HOSTS=0 to disable.",
            "services:",
        ]
        for service in grouped.keys.sorted() {
            guard let entries = grouped[service], !entries.isEmpty else { continue }
            lines.append("  \(yamlKey(service)):")
            lines.append("    extra_hosts:")
            for entry in entries.sorted(by: { $0.targetService < $1.targetService }) {
                lines.append("      - \"\(entry.targetService):\(entry.hostValue)\"")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func yamlKey(_ value: String) -> String {
        if value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func writeOverrideFile(
        yaml: String,
        projectName: String,
        fingerprint: String
    ) throws -> String {
        let directory = DockerCompatibilityConfiguration.composeOverridesDirectory
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let projectSlug = projectName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let fingerprintSlug = stablePathHash(fingerprint)
        let fileName = "\(projectSlug.isEmpty ? "compose" : projectSlug)-\(fingerprintSlug).hosts.override.yml"
        let path = (directory as NSString).appendingPathComponent(fileName)
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    static func insertOverrideFile(_ path: String, into arguments: [String], subcommand: String) -> [String] {
        var result: [String] = []
        var inserted = false
        var index = 0

        while index < arguments.count {
            let arg = arguments[index]
            if !inserted, arg == subcommand {
                result.append(contentsOf: ["-f", path])
                inserted = true
            }
            result.append(arg)
            if takesOptionValue(arg), index + 1 < arguments.count {
                index += 1
                result.append(arguments[index])
            }
            index += 1
        }

        if !inserted {
            result.insert(contentsOf: ["-f", path], at: 0)
        }
        return result
    }

    private static func stablePathHash(_ value: String) -> String {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}
