import Foundation
import NativeStackCore

public struct ContainerCLIConfiguration: Sendable {
    public var binaryPath: String
    public var searchPaths: [String]

    public init(
        binaryPath: String? = nil,
        searchPaths: [String] = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(NSHomeDirectory())/.local/bin",
        ]
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

    private static func resolveBinary(in paths: [String]) -> String? {
        for dir in paths {
            let candidate = (dir as NSString).appendingPathComponent("container")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
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

    public func isInstalled() -> Bool {
        if config.binaryPath.contains("/") {
            return FileManager.default.isExecutableFile(atPath: config.binaryPath)
        }
        return Self.which(config.binaryPath) != nil
    }

    public func run(_ arguments: [String], input: String? = nil) async throws -> CLIResult {
        guard isInstalled() else { throw NativeStackError.containerCLINotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedExecutablePath())
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

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
                let stdout = String(
                    data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                continuation.resume(returning: CLIResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: proc.terminationStatus
                ))
            }
        }
    }

    public func runOrThrow(_ arguments: [String]) async throws -> String {
        let result = try await run(arguments)
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

    private func resolvedExecutablePath() -> String {
        if config.binaryPath.contains("/") { return config.binaryPath }
        return Self.which(config.binaryPath) ?? config.binaryPath
    }

    private static func which(_ name: String) -> String? {
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
