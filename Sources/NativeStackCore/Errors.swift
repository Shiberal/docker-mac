import Foundation

public enum NativeStackError: LocalizedError, Sendable {
    case containerCLINotFound
    case commandFailed(command: String, exitCode: Int32, output: String)
    case parseFailed(context: String)
    case engineNotRunning
    case unsupportedPlatform
    case installFailed(reason: String)
    case installRequiresAdmin
    case brewRequired
    case dockerCompatibilityUnavailable(reason: String)
    case notFound(context: String)

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
        case let .installFailed(reason):
            return "Failed to install container toolkit: \(reason)"
        case .installRequiresAdmin:
            return "Installing the container toolkit requires administrator approval."
        case .brewRequired:
            return "Homebrew is required to install Socktainer and Docker compatibility tools."
        case let .dockerCompatibilityUnavailable(reason):
            return reason
        case let .notFound(context):
            return "\(context) not found."
        }
    }
}
