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
            return parsePSLine(trimmed, includeStopped: includeStopped)
        }
    }

    private static func parsePSLine(_ line: String, includeStopped: Bool) -> ContainerRecord? {
        // container ps columns: ID  IMAGE  STATE  ADDR  PORTS  COMMAND
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3 else { return nil }

        let id = parts[0]
        let image = parts[1]
        let stateToken = parts[2].lowercased()
        let state = mapState(stateToken)

        if !includeStopped, !state.isActive, state != .created {
            return nil
        }

        var ports: [String] = []
        var ipAddress: String?
        if parts.count > 3 {
            let addr = parts[3]
            if addr.contains(".") { ipAddress = addr }
        }
        if parts.count > 4 {
            ports = parts[4].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        return ContainerRecord(
            id: id,
            image: image,
            state: state,
            status: stateToken,
            ports: ports,
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
            guard parts.count >= 3 else { return nil }

            let id = parts[0]
            let repository = parts[1]
            let tag = parts[2]
            let size = parts.count > 3 ? parseSize(parts[3]) : nil

            return ImageRecord(id: id, repository: repository, tag: tag, sizeBytes: size)
        }
    }

    static func parseSystemStatus(stdout: String, stderr: String, containers: [ContainerRecord]) -> SystemStatus {
        let combined = (stdout + stderr).lowercased()
        let running = containers.filter(\.state.isActive).count

        if combined.contains("not running") || combined.contains("stopped") {
            return SystemStatus(
                engineState: .stopped,
                runningContainers: running,
                totalContainers: containers.count,
                message: stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        var version: String?
        for line in stdout.split(separator: "\n") {
            let s = String(line)
            if s.lowercased().contains("version") {
                version = s.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
            }
        }

        return SystemStatus(
            engineState: .running,
            version: version,
            runningContainers: running,
            totalContainers: containers.count,
            message: stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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
}
