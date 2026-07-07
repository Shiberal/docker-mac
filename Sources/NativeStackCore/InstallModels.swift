import Foundation

public enum ToolkitInstallPhase: Sendable, Equatable {
    case idle
    case checking
    case installingViaHomebrew
    case downloadingPackage
    case runningInstaller
    case verifying
    case succeeded
    case failed(String)

    public var isActive: Bool {
        switch self {
        case .checking, .installingViaHomebrew, .downloadingPackage, .runningInstaller, .verifying:
            return true
        default:
            return false
        }
    }

    public var label: String {
        switch self {
        case .idle: return "Ready"
        case .checking: return "Checking for container toolkit…"
        case .installingViaHomebrew: return "Installing via Homebrew…"
        case .downloadingPackage: return "Downloading Apple container installer…"
        case .runningInstaller: return "Running system installer (admin password required)…"
        case .verifying: return "Verifying installation…"
        case .succeeded: return "Container toolkit installed"
        case let .failed(message): return message
        }
    }
}

public struct DockerCompatibilityStatus: Codable, Sendable, Equatable {
    public var socktainerInstalled: Bool
    public var socktainerRunning: Bool
    public var dockerCLIInstalled: Bool
    public var composeInstalled: Bool
    public var buildxInstalled: Bool
    public var socketPath: String
    public var dockerHost: String

    public init(
        socktainerInstalled: Bool = false,
        socktainerRunning: Bool = false,
        dockerCLIInstalled: Bool = false,
        composeInstalled: Bool = false,
        buildxInstalled: Bool = false,
        socketPath: String = DockerCompatibilityConfiguration.defaultSocketPath,
        dockerHost: String = DockerCompatibilityConfiguration.defaultDockerHost
    ) {
        self.socktainerInstalled = socktainerInstalled
        self.socktainerRunning = socktainerRunning
        self.dockerCLIInstalled = dockerCLIInstalled
        self.composeInstalled = composeInstalled
        self.buildxInstalled = buildxInstalled
        self.socketPath = socketPath
        self.dockerHost = dockerHost
    }

    public var isReady: Bool {
        socktainerRunning && dockerCLIInstalled && composeInstalled && buildxInstalled
    }
}

public enum DockerCompatibilityPhase: Sendable, Equatable {
    case idle
    case checking
    case installingDependencies
    case startingSocktainer
    case verifying
    case succeeded
    case failed(String)

    public var isActive: Bool {
        switch self {
        case .checking, .installingDependencies, .startingSocktainer, .verifying:
            return true
        default:
            return false
        }
    }

    public var label: String {
        switch self {
        case .idle: return "Ready"
        case .checking: return "Checking Docker compatibility layer…"
        case .installingDependencies: return "Installing Socktainer, Docker CLI, Compose, and Buildx…"
        case .startingSocktainer: return "Starting Socktainer…"
        case .verifying: return "Verifying Docker socket…"
        case .succeeded: return "Docker compatibility enabled"
        case let .failed(message): return message
        }
    }
}

public struct DockerCompatibilityConfiguration: Sendable {
    public static var userSocketPath: String {
        "\(NSHomeDirectory())/.socktainer/container.sock"
    }

    public static var homebrewPrefix: String {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew"
        }
        if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            return "/usr/local"
        }
        return "/opt/homebrew"
    }

    /// Socket used when Socktainer runs as a Homebrew service (`brew services start socktainer`).
    public static var homebrewServiceSocketPath: String {
        "\(homebrewPrefix)/var/run/socktainer/.socktainer/container.sock"
    }

    public static var candidateSocketPaths: [String] {
        [homebrewServiceSocketPath, userSocketPath]
    }

    public static func resolvedSocketPath() -> String? {
        candidateSocketPaths.first { UnixSocket.canConnect(to: $0) }
    }

    public static var defaultSocketPath: String {
        resolvedSocketPath() ?? userSocketPath
    }

    public static var defaultDockerHost: String {
        "unix://\(defaultSocketPath)"
    }

    public static var envFilePath: String {
        let base = "\(NSHomeDirectory())/Library/Application Support/NativeStack"
        return "\(base)/docker-env.sh"
    }

    public static var composeOverridesDirectory: String {
        let base = "\(NSHomeDirectory())/Library/Application Support/NativeStack"
        return "\(base)/compose-overrides"
    }

    public static var shimBinDirectory: String {
        let base = "\(NSHomeDirectory())/Library/Application Support/NativeStack"
        return "\(base)/bin"
    }

    public static var dockerShimPath: String {
        (shimBinDirectory as NSString).appendingPathComponent("docker")
    }

    /// When true (default), `nativestack compose` injects a generated override for service DNS.
    public static var composeHostsInjectionEnabled: Bool {
        let raw = ProcessInfo.processInfo.environment["NATIVESTACK_COMPOSE_HOSTS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let raw, !raw.isEmpty else { return true }
        return !["0", "false", "no", "off"].contains(raw)
    }
}
