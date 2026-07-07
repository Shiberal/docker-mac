import Foundation
import NativeStackCore

public enum ExternalCommandRunner {
    public static func brewExecutable() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    public static func homebrewEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        return env
    }

    public static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        inheritIO: Bool = false
    ) async throws -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        if let environment {
            for (key, value) in environment {
                env[key] = value
            }
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let drainer: PipeDrainer?
        if inheritIO {
            process.standardOutput = nil
            process.standardError = nil
            process.standardInput = nil
            drainer = nil
        } else {
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            drainer = PipeDrainer(stdout: stdoutPipe, stderr: stderrPipe)
        }

        try process.run()

        let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
        }

        if inheritIO {
            return CLIResult(stdout: "", stderr: "", exitCode: exitCode)
        }

        let (stdout, stderr) = drainer?.collect() ?? ("", "")
        return CLIResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }

    public static func runOrThrow(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        inheritIO: Bool = false
    ) async throws -> String {
        let result = try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            inheritIO: inheritIO
        )
        guard result.exitCode == 0 else {
            let output = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            throw NativeStackError.commandFailed(
                command: ([executable] + arguments).joined(separator: " "),
                exitCode: result.exitCode,
                output: output
            )
        }
        return result.stdout
    }
}
