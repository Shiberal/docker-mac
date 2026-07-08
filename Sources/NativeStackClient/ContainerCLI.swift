import Foundation
import NativeStackCore

public struct ContainerCLIConfiguration: Sendable {
    public var binaryPath: String
    public var searchPaths: [String]

    public init(
        binaryPath: String? = nil,
        searchPaths: [String] = ContainerCLIConfiguration.defaultSearchPaths
    ) {
        if let binaryPath {
            self.binaryPath = binaryPath
        } else if let env = ProcessInfo.processInfo.environment["CONTAINER_BIN"] {
            self.binaryPath = env
        } else {
            self.binaryPath = Self.resolveBinary(in: searchPaths) ?? "container"
        }
        self.searchPaths = searchPaths
    }

    public static let defaultSearchPaths: [String] = [
        "/opt/homebrew/bin",
        "/opt/homebrew/opt/container/bin",
        "/usr/local/bin",
        "/usr/local/opt/container/bin",
        "\(NSHomeDirectory())/.local/bin",
    ]

    public func resolvedInstalledPath() -> String? {
        if binaryPath.contains("/"), FileManager.default.isExecutableFile(atPath: binaryPath) {
            return binaryPath
        }
        if let found = Self.resolveBinary(in: searchPaths) {
            return found
        }
        return Self.which("container")
    }

    public static func resolveBinary(in paths: [String]) -> String? {
        for dir in paths {
            let candidate = (dir as NSString).appendingPathComponent("container")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public static func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path?.isEmpty == false ? path : nil
        } catch {
            return nil
        }
    }
}

public struct CLIResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

public actor ContainerCLI {
    private let config: ContainerCLIConfiguration

    public init(config: ContainerCLIConfiguration = ContainerCLIConfiguration()) {
        self.config = config
    }

    public var binaryPath: String { config.binaryPath }

    public nonisolated func resolvedBinaryPath() -> String {
        config.resolvedInstalledPath() ?? config.binaryPath
    }

    public func isInstalled() -> Bool {
        config.resolvedInstalledPath() != nil
    }

    public func run(
        _ arguments: [String],
        input: String? = nil,
        inheritIO: Bool = false
    ) async throws -> CLIResult {
        guard isInstalled() else { throw NativeStackError.containerCLINotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedExecutablePath())
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        if inheritIO {
            process.standardOutput = nil
            process.standardError = nil
            process.standardInput = nil
        } else {
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
        }

        let drainer = inheritIO ? nil : PipeDrainer(stdout: stdoutPipe, stderr: stderrPipe)

        if let input {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            try process.run()
            if let data = input.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            stdinPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                if let drainer {
                    let (stdout, stderr) = drainer.collect()
                    continuation.resume(returning: CLIResult(
                        stdout: stdout,
                        stderr: stderr,
                        exitCode: proc.terminationStatus
                    ))
                } else {
                    continuation.resume(returning: CLIResult(
                        stdout: "",
                        stderr: "",
                        exitCode: proc.terminationStatus
                    ))
                }
            }
        }
    }

    public func runOrThrow(
        _ arguments: [String],
        inheritIO: Bool = false
    ) async throws -> String {
        let result = try await run(arguments, inheritIO: inheritIO)
        guard result.exitCode == 0 else {
            let output = [result.stdout, result.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw NativeStackError.commandFailed(
                command: ([resolvedExecutablePath()] + arguments).joined(separator: " "),
                exitCode: result.exitCode,
                output: output
            )
        }
        return result.stdout
    }

    /// Runs a long-lived, non-terminating command (e.g. `logs -f`) and yields complete
    /// lines incrementally as they're produced, instead of buffering until exit.
    public func stream(_ arguments: [String]) -> AsyncStream<String> {
        let executable = resolvedExecutablePath()
        return AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let buffer = LineBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    if let remainder = buffer.flush() {
                        continuation.yield(remainder)
                    }
                    continuation.finish()
                    return
                }
                for line in buffer.append(data) {
                    continuation.yield(line)
                }
            }

            continuation.onTermination = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.yield("Error: \(error.localizedDescription)")
                continuation.finish()
            }
        }
    }

    private func resolvedExecutablePath() -> String {
        config.resolvedInstalledPath() ?? config.binaryPath
    }
}

/// Accumulates raw byte chunks and hands back only complete, newline-terminated lines.
private final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        var lines: [String] = []
        while let range = pending.range(of: Data("\n".utf8)) {
            let lineData = pending.subdata(in: pending.startIndex..<range.lowerBound)
            pending.removeSubrange(pending.startIndex..<range.upperBound)
            lines.append(String(data: lineData, encoding: .utf8) ?? "")
        }
        return lines
    }

    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else { return nil }
        let text = String(data: pending, encoding: .utf8)
        pending.removeAll()
        return text
    }
}
