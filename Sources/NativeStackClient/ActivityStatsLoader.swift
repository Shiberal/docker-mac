import Foundation
import NativeStackCore

enum ActivityStatsLoader {
    static func load(
        cli: ContainerCLI,
        containers: [ContainerRecord],
        images: [ImageRecord]
    ) async -> ActivityStats {
        guard await cli.isInstalled() else {
            return ActivityStats()
        }

        var containerStats: [ContainerResourceStat] = []
        var cpuTotal: Double = 0
        var memoryUsed: UInt64 = 0
        var memoryLimit: UInt64 = 0

        if let jsonOutput = try? await cli.runOrThrow(["stats", "--no-stream", "--format", "json"]) {
            containerStats = ContainerOutputParser.parseStatsJSONArray(jsonOutput)
        }

        if containerStats.isEmpty, let tableOutput = try? await cli.runOrThrow(["stats", "--no-stream"]) {
            containerStats = ContainerOutputParser.parseStatsTableRows(tableOutput)
        }

        if !containerStats.isEmpty {
            let cpuFromTable = await loadCPUPercentages(cli: cli)
            if !cpuFromTable.isEmpty {
                containerStats = containerStats.map { stat in
                    var updated = stat
                    if let cpu = cpuFromTable[stat.id] {
                        updated.cpuPercent = cpu
                    }
                    return updated
                }
            }
        }

        let names = Dictionary(uniqueKeysWithValues: containers.map { ($0.id, $0.name ?? $0.displayName) })
        containerStats = containerStats.map { stat in
            var updated = stat
            if updated.name == nil {
                updated.name = names[stat.id]
            }
            return updated
        }

        for stat in containerStats {
            cpuTotal += stat.cpuPercent ?? 0
            memoryUsed += stat.memoryUsedBytes ?? 0
            memoryLimit += stat.memoryLimitBytes ?? 0
        }

        let storagePath = await resolveStoragePath(cli: cli)
        let engineStorage = await directorySize(at: storagePath)
        let imageStorage = images.compactMap(\.sizeBytes).reduce(0, +)
        let storageUsed = max(engineStorage, imageStorage > 0 ? imageStorage : engineStorage)

        return ActivityStats(
            cpuPercent: containerStats.isEmpty ? nil : cpuTotal,
            memoryUsedBytes: memoryUsed > 0 ? memoryUsed : nil,
            memoryLimitBytes: memoryLimit > 0 ? memoryLimit : nil,
            storageUsedBytes: storageUsed > 0 ? storageUsed : nil,
            storagePath: storagePath,
            containers: containerStats.sorted {
                ($0.name ?? $0.id).localizedCaseInsensitiveCompare($1.name ?? $1.id) == .orderedAscending
            }
        )
    }

    static func loadContainerStats(cli: ContainerCLI, id: String) async throws -> ResourceStats {
        if let jsonOutput = try? await cli.runOrThrow(["stats", "--no-stream", "--format", "json", id]) {
            let parsed = ContainerOutputParser.parseStatsJSONArray(jsonOutput)
            if let first = parsed.first {
                var stats = ResourceStats(
                    cpuPercent: first.cpuPercent,
                    memoryUsedBytes: first.memoryUsedBytes,
                    memoryLimitBytes: first.memoryLimitBytes,
                    diskReadBytes: first.diskReadBytes,
                    diskWriteBytes: first.diskWriteBytes
                )
                if stats.cpuPercent == nil, let table = try? await cli.runOrThrow(["stats", "--no-stream", id]) {
                    let tableStats = ContainerOutputParser.parseStatsTableRows(table)
                    stats.cpuPercent = tableStats.first?.cpuPercent
                }
                return stats
            }
        }

        if let tableOutput = try? await cli.runOrThrow(["stats", "--no-stream", id]) {
            let tableStats = ContainerOutputParser.parseStatsTableRows(tableOutput)
            if let first = tableStats.first {
                return ResourceStats(
                    cpuPercent: first.cpuPercent,
                    memoryUsedBytes: first.memoryUsedBytes,
                    memoryLimitBytes: first.memoryLimitBytes,
                    diskReadBytes: first.diskReadBytes,
                    diskWriteBytes: first.diskWriteBytes
                )
            }
            return ContainerOutputParser.parseStats(from: tableOutput)
        }

        if await DockerCompatibilityService.shared.status().isReady {
            let output = try await DockerCompatibilityService.shared.captureDocker(
                arguments: ["stats", "--no-stream", "--format", "{{.CPUPerc}}\t{{.MemUsage}}\t{{.BlockIO}}", id]
            )
            return ContainerOutputParser.parseStats(from: output)
        }

        return ResourceStats()
    }

    private static func loadCPUPercentages(cli: ContainerCLI) async -> [String: Double] {
        guard let tableOutput = try? await cli.runOrThrow(["stats", "--no-stream"]) else {
            return [:]
        }
        var map: [String: Double] = [:]
        for stat in ContainerOutputParser.parseStatsTableRows(tableOutput) {
            if let cpu = stat.cpuPercent {
                map[stat.id] = cpu
            }
        }
        return map
    }

    private static func resolveStoragePath(cli: ContainerCLI) async -> String? {
        if let status = try? await cli.runOrThrow(["system", "status"]) {
            return parseAppRoot(from: status)
        }
        return "\(NSHomeDirectory())/Library/Application Support/com.apple.container"
    }

    private static func parseAppRoot(from statusOutput: String) -> String? {
        for line in statusOutput.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("approot") {
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                if parts.count >= 2 {
                    return parts[1]
                }
            }
        }
        return "\(NSHomeDirectory())/Library/Application Support/com.apple.container"
    }

    private static func directorySize(at path: String?) async -> UInt64 {
        guard let path, !path.isEmpty else { return 0 }
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        guard let du = resolveExecutable("du") else { return 0 }
        do {
            let result = try await ExternalCommandRunner.run(
                executable: du,
                arguments: ["-sk", path]
            )
            let token = result.stdout.split(separator: "\t").first ?? Substring("")
            if let kilobytes = UInt64(token.trimmingCharacters(in: .whitespaces)) {
                return kilobytes * 1024
            }
        } catch {
            return 0
        }
        return 0
    }

    private static func resolveExecutable(_ name: String) -> String? {
        for dir in ContainerCLIConfiguration.defaultSearchPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return ContainerCLIConfiguration.which(name)
    }
}
