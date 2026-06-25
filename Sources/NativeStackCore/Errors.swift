import Foundation

public enum NativeStackError: LocalizedError, Sendable {
    case containerCLINotFound
    case commandFailed(command: String, exitCode: Int32, output: String)
    case parseFailed(context: String)
    case engineNotRunning
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .containerCLINotFound:
            return """
            Apple's `container` CLI was not found. Install it from \
            https://github.com/apple/container/releases then run `container system start`.
            """
        case let .commandFailed(command, exitCode, output):
            return "`\(command)` failed (exit \(exitCode)): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        case let .parseFailed(context):
            return "Failed to parse \(context)."
        case .engineNotRunning:
            return "Container engine is not running. Run `nativestack system start` or `container system start`."
        case .unsupportedPlatform:
            return "NativeStack requires Apple Silicon and macOS 26+ with Apple's container tool."
        }
    }
}
