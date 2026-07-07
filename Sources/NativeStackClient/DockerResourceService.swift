import Foundation
import NativeStackCore

enum DockerResourceService {
    static func canQueryDocker() async -> Bool {
        let status = await DockerCompatibilityService.shared.status()
        return status.socktainerRunning && status.dockerCLIInstalled
    }

    static func listComposeProjects() async -> [ComposeProjectRecord] {
        guard await canQueryDocker() else { return [] }
        do {
            let output = try await DockerCompatibilityService.shared.captureDocker(
                arguments: ["compose", "ls", "--format", "json"]
            )
            return parseComposeProjectsJSON(output)
        } catch {
            return []
        }
    }

    static func enrichContainers(_ containers: [ContainerRecord]) async -> [ContainerRecord] {
        guard await canQueryDocker(), !containers.isEmpty else {
            return containers
        }

        let composeLabels = await loadComposeLabelsByName()
        var enriched = containers

        for index in enriched.indices {
            let id = enriched[index].id
            let displayName = enriched[index].displayName

            if let labels = composeLabels[displayName] ?? composeLabels[id] {
                enriched[index].composeProject = labels.project
                enriched[index].composeService = labels.service
            }

            guard let details = try? await inspectContainer(id: id) else { continue }
            if let project = details.composeProject {
                enriched[index].composeProject = project
            }
            if let service = details.composeService {
                enriched[index].composeService = service
            }
            if !details.ports.isEmpty {
                enriched[index].ports = details.ports
            }
            if let name = details.name, enriched[index].name == nil {
                enriched[index].name = name
            }
            if !details.mounts.isEmpty {
                enriched[index].mounts = details.mounts
            }
            if let platform = details.platform {
                enriched[index].platform = platform
            }
        }
        return enriched
    }

    static func listDockerVolumes() async -> [VolumeRecord] {
        guard await canQueryDocker() else { return [] }
        do {
            let output = try await DockerCompatibilityService.shared.captureDocker(
                arguments: ["volume", "ls", "--format", "{{.Name}}\t{{.Driver}}"]
            )
            return ContainerOutputParser.parseDockerVolumes(from: output)
        } catch {
            return []
        }
    }

    static func listDockerNetworks() async -> [NetworkRecord] {
        guard await canQueryDocker() else { return [] }
        do {
            let output = try await DockerCompatibilityService.shared.captureDocker(
                arguments: ["network", "ls", "--format", "{{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}"]
            )
            return parseTabularNetworks(output)
        } catch {
            return []
        }
    }

    static func listDockerImages() async -> [ImageRecord] {
        guard await canQueryDocker() else { return [] }
        do {
            let output = try await DockerCompatibilityService.shared.captureDocker(
                arguments: [
                    "images", "--format", "{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}",
                ]
            )
            return ContainerOutputParser.parseDockerImages(from: output)
        } catch {
            return []
        }
    }

    static func removeDockerImage(reference: String) async throws {
        try await DockerCompatibilityService.shared.runDocker(arguments: ["rmi", "-f", reference])
    }

    static func removeDockerVolume(name: String) async throws {
        try await DockerCompatibilityService.shared.runDocker(arguments: ["volume", "rm", "-f", name])
    }

    private static func loadComposeLabelsByName() async -> [String: (project: String, service: String)] {
        guard await canQueryDocker() else { return [:] }
        guard let output = try? await DockerCompatibilityService.shared.captureDocker(
            arguments: [
                "ps", "-a",
                "--format", "{{.Names}}\t{{.Label \"com.docker.compose.project\"}}\t{{.Label \"com.docker.compose.service\"}}",
            ]
        ) else {
            return [:]
        }

        var labels: [String: (project: String, service: String)] = [:]
        for line in output.split(separator: "\n") {
            let parts = String(line).split(separator: "\t").map(String.init)
            guard parts.count >= 3 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let project = parts[1].trimmingCharacters(in: .whitespaces)
            let service = parts[2].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !project.isEmpty else { continue }
            labels[name] = (project, service)
        }
        return labels
    }

    private struct InspectDetails {
        var name: String?
        var composeProject: String?
        var composeService: String?
        var ports: [String]
        var mounts: [String]
        var platform: String?
    }

    private static func inspectContainer(id: String) async throws -> InspectDetails {
        let output = try await DockerCompatibilityService.shared.captureDocker(
            arguments: ["inspect", id, "--format", "{{json .}}"]
        )
        guard let data = output.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeStackError.parseFailed(context: "docker inspect")
        }

        let labels = root["Config"] as? [String: Any]
        let labelMap = labels?["Labels"] as? [String: String] ?? [:]
        let name = (root["Name"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let project = labelMap["com.docker.compose.project"]
        let service = labelMap["com.docker.compose.service"]

        var ports: [String] = []
        if let portMap = root["NetworkSettings"] as? [String: Any],
           let bindings = portMap["Ports"] as? [String: Any] {
            for (containerPort, value) in bindings {
                if let hosts = value as? [[String: Any]],
                   let hostPort = hosts.first?["HostPort"] as? String {
                    ports.append("\(hostPort):\(containerPort)")
                }
            }
        }

        var mounts: [String] = []
        if let mountList = root["Mounts"] as? [[String: Any]] {
            for mount in mountList {
                let source = mount["Source"] as? String ?? ""
                let destination = mount["Destination"] as? String ?? ""
                if !destination.isEmpty {
                    mounts.append("\(source) → \(destination)")
                }
            }
        }

        let platform = root["Platform"] as? String

        return InspectDetails(
            name: name,
            composeProject: project,
            composeService: service,
            ports: ports,
            mounts: mounts,
            platform: platform
        )
    }

    private static func parseComposeProjectsJSON(_ output: String) -> [ComposeProjectRecord] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.hasPrefix("[") {
            guard let data = trimmed.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return array.compactMap { item in
                guard let name = item["Name"] as? String else { return nil }
                let status = item["Status"] as? String
                let config = item["ConfigFiles"] as? String
                let files = config?
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces) } ?? []
                let running = jsonInt(item["Running"])
                let total = jsonInt(item["Containers"])
                let counts = parseComposeStatus(status, running: running, total: total)
                return ComposeProjectRecord(
                    id: name,
                    name: name,
                    status: status,
                    configFiles: files,
                    containerCount: counts.total,
                    runningCount: counts.running
                )
            }
        }

        return trimmed
            .split(separator: "\n")
            .compactMap { line -> ComposeProjectRecord? in
                let parts = line.split(separator: "\t").map(String.init)
                guard let name = parts.first else { return nil }
                let status = parts.count > 1 ? parts[1] : nil
                let counts = parseComposeStatus(status, running: 0, total: 0)
                return ComposeProjectRecord(
                    id: name,
                    name: name,
                    status: status,
                    configFiles: parts.count > 2 ? [parts[2]] : [],
                    containerCount: counts.total,
                    runningCount: counts.running
                )
            }
    }

    private static func parseComposeStatus(
        _ status: String?,
        running: Int,
        total: Int
    ) -> (running: Int, total: Int) {
        if running > 0 || total > 0 {
            return (running, total)
        }
        guard let status else { return (0, 0) }

        let pattern = #"running\((\d+)\)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: status, range: NSRange(status.startIndex..., in: status)),
           let range = Range(match.range(at: 1), in: status),
           let count = Int(status[range]) {
            return (count, count)
        }

        if status.lowercased().contains("running") {
            return (1, 1)
        }
        return (0, 0)
    }

    private static func parseTabularNetworks(_ output: String) -> [NetworkRecord] {
        output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line in
                let parts = line.split(separator: "\t").map(String.init)
                guard parts.count >= 2 else { return nil }
                return NetworkRecord(
                    id: parts[0],
                    name: parts[1],
                    driver: parts.count > 2 ? parts[2] : nil,
                    scope: parts.count > 3 ? parts[3] : nil
                )
            }
    }

    private static func jsonInt(_ value: Any?) -> Int {
        if let intValue = value as? Int { return intValue }
        if let stringValue = value as? String, let intValue = Int(stringValue) { return intValue }
        return 0
    }

    static func composeCountsFromDocker() async -> [String: (running: Int, total: Int)] {
        guard await canQueryDocker() else { return [:] }
        guard let output = try? await DockerCompatibilityService.shared.captureDocker(
            arguments: [
                "ps", "-a",
                "--format", "{{.Label \"com.docker.compose.project\"}}\t{{.Status}}",
            ]
        ) else {
            return [:]
        }

        var counts: [String: (running: Int, total: Int)] = [:]
        for line in output.split(separator: "\n") {
            let parts = String(line).split(separator: "\t").map(String.init)
            guard parts.count >= 2 else { continue }
            let project = parts[0].trimmingCharacters(in: .whitespaces)
            guard !project.isEmpty else { continue }
            let status = parts[1].lowercased()
            var entry = counts[project] ?? (0, 0)
            entry.total += 1
            if status.hasPrefix("up") || status.contains("running") {
                entry.running += 1
            }
            counts[project] = entry
        }
        return counts
    }

    static func mergeVolumes(_ primary: [VolumeRecord], _ secondary: [VolumeRecord]) -> [VolumeRecord] {
        var merged: [String: VolumeRecord] = [:]
        for volume in primary + secondary {
            merged[volume.name] = volume
        }
        return merged.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func mergeImages(_ primary: [ImageRecord], _ secondary: [ImageRecord]) -> [ImageRecord] {
        var merged: [String: ImageRecord] = [:]
        for image in primary + secondary {
            let key = "\(image.repository):\(image.tag)"
            merged[key] = image
        }
        return merged.values.sorted {
            $0.reference.localizedCaseInsensitiveCompare($1.reference) == .orderedAscending
        }
    }
}
