import Foundation
import NativeStackCore

enum ContainerOutputParser {
    static func parseContainers(from output: String, includeStopped: Bool) -> [ContainerRecord] {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return parseListLine(trimmed, includeStopped: includeStopped)
        }
    }

    private static func parseListLine(_ line: String, includeStopped: Bool) -> ContainerRecord? {
        // container list columns: ID IMAGE OS ARCH STATE IP CPUS MEMORY STARTED
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 5 else { return nil }

        let id = parts[0]
        let image = parts[1]
        let stateToken = parts[4].lowercased()
        let state = mapState(stateToken)

        if !includeStopped, !state.isActive, state != .created {
            return nil
        }

        let ipAddress = parts.count > 5 && parts[5].contains(".") ? parts[5] : nil

        return ContainerRecord(
            id: id,
            image: image,
            state: state,
            status: stateToken,
            ipAddress: ipAddress
        )
    }

    static func parseImages(from output: String) -> [ImageRecord] {
        let lines = output.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { return nil }

            let repository = parts[0]
            let tag = parts[1]
            let digest = parts.count > 2 ? parts[2] : repository

            return ImageRecord(id: digest, repository: repository, tag: tag)
        }
    }

    static func parseDockerImages(from output: String) -> [ImageRecord] {
        output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 3 else { return nil }

                let id = parts[0].trimmingCharacters(in: .whitespaces)
                let repository = parts[1].trimmingCharacters(in: .whitespaces)
                let tag = parts[2].trimmingCharacters(in: .whitespaces)
                let size = parts.count > 3 ? parseSize(parts[3].trimmingCharacters(in: .whitespaces)) : nil

                guard !repository.isEmpty, !tag.isEmpty else { return nil }
                return ImageRecord(
                    id: id.isEmpty ? "\(repository):\(tag)" : id,
                    repository: repository,
                    tag: tag,
                    sizeBytes: size
                )
            }
    }

    static func parseSystemStatus(stdout: String, stderr: String, containers: [ContainerRecord]) -> SystemStatus {
        let combined = stdout + stderr
        let running = containers.filter(\.state.isActive).count
        let fields = parseFieldValueTable(combined)

        if let status = fields["status"]?.lowercased() {
            switch status {
            case "running":
                return SystemStatus(
                    engineState: .running,
                    version: fields["apiserver.version"],
                    runningContainers: running,
                    totalContainers: containers.count,
                    message: stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            case "stopped", "not running":
                return SystemStatus(
                    engineState: .stopped,
                    version: fields["apiserver.version"],
                    runningContainers: running,
                    totalContainers: containers.count,
                    message: stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            default:
                break
            }
        }

        let lowered = combined.lowercased()
        if lowered.contains("not running") || lowered.contains("stopped") {
            return SystemStatus(
                engineState: .stopped,
                runningContainers: running,
                totalContainers: containers.count,
                message: stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return SystemStatus(
            engineState: .running,
            version: fields["apiserver.version"],
            runningContainers: running,
            totalContainers: containers.count,
            message: stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func parseFieldValueTable(_ output: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.uppercased().hasPrefix("FIELD") else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                .map(String.init)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            fields[key.lowercased()] = value
        }
        return fields
    }

    private static func mapState(_ token: String) -> ContainerState {
        switch token {
        case "running", "started": return .running
        case "created": return .created
        case "paused": return .paused
        case "stopped": return .stopped
        case "exited", "dead": return .exited
        default: return .unknown
        }
    }

    private static func parseSize(_ token: String) -> UInt64? {
        let lower = token.lowercased()
        let digits = Double(lower.filter { $0.isNumber || $0 == "." }) ?? 0
        if lower.hasSuffix("gib") || lower.hasSuffix("gb") {
            return UInt64(digits * 1024 * 1024 * 1024)
        }
        if lower.hasSuffix("mib") || lower.hasSuffix("mb") {
            return UInt64(digits * 1024 * 1024)
        }
        if lower.hasSuffix("kib") || lower.hasSuffix("kb") {
            return UInt64(digits * 1024)
        }
        return UInt64(digits)
    }

    static func parseVolumes(from output: String) -> [VolumeRecord] {
        parseAppleContainerVolumes(from: output)
    }

    static func parseDockerVolumes(from output: String) -> [VolumeRecord] {
        let lines = output.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            if let tabParts = splitTabColumns(trimmed), tabParts.count >= 2 {
                return VolumeRecord(id: tabParts[0], name: tabParts[0], driver: tabParts[1])
            }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { return nil }

            // `DRIVER VOLUME NAME` table (docker volume ls)
            if parts[0] == "local" || parts[0] == "nfs" || parts[0] == "bind" {
                return VolumeRecord(id: parts[1], name: parts[1], driver: parts[0])
            }

            return VolumeRecord(id: parts[1], name: parts[1], driver: parts[0])
        }
    }

    private static func parseAppleContainerVolumes(from output: String) -> [VolumeRecord] {
        let lines = output.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 3 else { return nil }

            let name = parts[0]
            let driver = parts[2]
            return VolumeRecord(id: name, name: name, driver: driver)
        }
    }

    private static func splitTabColumns(_ line: String) -> [String]? {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return nil }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func parseNetworks(from output: String) -> [NetworkRecord] {
        parseTabularList(output) { parts in
            guard parts.count >= 2 else { return nil }
            return NetworkRecord(
                id: parts[0],
                name: parts[1],
                driver: parts.count > 2 ? parts[2] : nil,
                scope: parts.count > 3 ? parts[3] : nil
            )
        }
    }

    static func parseStatsJSONArray(_ output: String) -> [ContainerResourceStat] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return [] }
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array.compactMap { parseStatsJSONObject($0) }
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return [parseStatsJSONObject(object)].compactMap { $0 }
        }
        return []
    }

    static func parseStatsJSONObject(_ object: [String: Any]) -> ContainerResourceStat? {
        guard let id = object["id"] as? String else { return nil }
        return ContainerResourceStat(
            id: id,
            name: object["name"] as? String,
            memoryUsedBytes: uint64Value(object["memoryUsageBytes"]),
            memoryLimitBytes: uint64Value(object["memoryLimitBytes"]),
            diskReadBytes: uint64Value(object["blockReadBytes"]),
            diskWriteBytes: uint64Value(object["blockWriteBytes"])
        )
    }

    static func parseStatsTableRows(_ output: String) -> [ContainerResourceStat] {
        let lines = output.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            let columns = splitTableColumns(trimmed)
            guard columns.count >= 2 else { return nil }

            let id = columns[0]
            let cpu = parsePercent(columns[1])
            var memoryUsed: UInt64?
            var memoryLimit: UInt64?
            if columns.count > 2, let pair = parseMemoryPair(columns[2]) {
                memoryUsed = pair.used
                memoryLimit = pair.limit
            }
            var diskRead: UInt64?
            var diskWrite: UInt64?
            if columns.count > 4, let pair = parseBlockIOPair(columns[4]) {
                diskRead = pair.read
                diskWrite = pair.write
            }

            return ContainerResourceStat(
                id: id,
                cpuPercent: cpu,
                memoryUsedBytes: memoryUsed,
                memoryLimitBytes: memoryLimit,
                diskReadBytes: diskRead,
                diskWriteBytes: diskWrite
            )
        }
    }

    static func parseStats(from output: String) -> ResourceStats {
        let line = output
            .split(separator: "\n")
            .map(String.init)
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? output

        let parts = line.split(separator: "\t").map(String.init)
        if parts.count >= 3 {
            return ResourceStats(
                cpuPercent: parsePercent(parts[1]),
                memoryUsedBytes: parseMemoryPair(parts[2])?.used,
                memoryLimitBytes: parseMemoryPair(parts[2])?.limit
            )
        }

        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var cpu: Double?
        var memUsed: UInt64?
        var memLimit: UInt64?
        for (index, token) in tokens.enumerated() {
            if token.hasSuffix("%"), cpu == nil {
                cpu = parsePercent(token)
            }
            if token.contains("/"), token.contains("B") || token.contains("i") {
                if let pair = parseMemoryPair(token) {
                    memUsed = pair.used
                    memLimit = pair.limit
                }
            }
            if token.lowercased() == "cpu" && index + 1 < tokens.count {
                cpu = parsePercent(tokens[index + 1])
            }
            if token.lowercased() == "mem" && index + 1 < tokens.count {
                if let pair = parseMemoryPair(tokens[index + 1]) {
                    memUsed = pair.used
                    memLimit = pair.limit
                }
            }
        }
        return ResourceStats(
            cpuPercent: cpu,
            memoryUsedBytes: memUsed,
            memoryLimitBytes: memLimit,
            diskReadBytes: nil,
            diskWriteBytes: nil
        )
    }

    private static func parseTabularList<T>(
        _ output: String,
        map: ([String]) -> T?
    ) -> [T] {
        let lines = output.split(separator: "\n").map(String.init)
        guard lines.count > 1 else {
            return lines.compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                return map(trimmed.split(separator: "\t").map(String.init))
            }
        }
        return lines.dropFirst().compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return map(trimmed.split(separator: "\t").map(String.init))
        }
    }

    private static func parsePercent(_ token: String) -> Double? {
        let digits = token.filter { $0.isNumber || $0 == "." }
        return Double(digits)
    }

    private static func parseMemoryPair(_ token: String) -> (used: UInt64, limit: UInt64)? {
        let parts = token.split(separator: "/").map(String.init)
        guard parts.count == 2,
              let used = parseSize(parts[0]),
              let limit = parseSize(parts[1]) else {
            return nil
        }
        return (used, limit)
    }

    private static func parseBlockIOPair(_ token: String) -> (read: UInt64, write: UInt64)? {
        let parts = token.split(separator: "/").map(String.init)
        guard parts.count == 2,
              let read = parseSize(parts[0]),
              let write = parseSize(parts[1]) else {
            return nil
        }
        return (read, write)
    }

    private static func splitTableColumns(_ line: String) -> [String] {
        let pattern = #"^(\S+)\s+(\S+)\s+([^/]+/\S+)\s+([^/]+/\S+)\s+([^/]+/\S+)\s+(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        }
        return (1 ... 6).compactMap { index in
            guard let range = Range(match.range(at: index), in: line) else { return nil }
            return String(line[range]).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func uint64Value(_ value: Any?) -> UInt64? {
        if let intValue = value as? UInt64 { return intValue }
        if let intValue = value as? Int { return UInt64(max(0, intValue)) }
        if let doubleValue = value as? Double { return UInt64(max(0, doubleValue)) }
        if let stringValue = value as? String, let intValue = UInt64(stringValue) { return intValue }
        return nil
    }
}
