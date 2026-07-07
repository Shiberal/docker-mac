import Foundation
import NativeStackCore

public actor ContainerToolkitInstaller {
    public static let shared = ContainerToolkitInstaller()

    private static let releaseAPI = "https://api.github.com/repos/apple/container/releases/latest"
    private static let pkgAssetSuffix = "installer-signed.pkg"

    public init() {}

    public func isPlatformSupported() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    public func install(
        progress: @Sendable @escaping (ToolkitInstallPhase) -> Void = { _ in }
    ) async throws {
        guard isPlatformSupported() else {
            throw NativeStackError.unsupportedPlatform
        }

        progress(.checking)

        if ContainerCLIConfiguration().resolvedInstalledPath() != nil {
            progress(.succeeded)
            return
        }

        if let brew = ExternalCommandRunner.brewExecutable() {
            progress(.installingViaHomebrew)
            let result = try await ExternalCommandRunner.run(
                executable: brew,
                arguments: ["install", "container"],
                environment: ExternalCommandRunner.homebrewEnvironment(),
                inheritIO: true
            )
            guard result.exitCode == 0 else {
                let message = "Homebrew install failed with exit code \(result.exitCode)."
                progress(.failed(message))
                throw NativeStackError.installFailed(reason: message)
            }
            try await verifyInstalled(progress: progress)
            return
        }

        progress(.downloadingPackage)
        let pkgURL = try await fetchSignedPackageURL()
        let pkgPath = try await downloadPackage(from: pkgURL)

        progress(.runningInstaller)
        try await installPackage(at: pkgPath)

        try await verifyInstalled(progress: progress)
    }

    private func verifyInstalled(progress: @Sendable (ToolkitInstallPhase) -> Void) async throws {
        progress(.verifying)

        if ContainerCLIConfiguration.resolveBinary(in: ContainerCLIConfiguration.defaultSearchPaths) != nil
            || ContainerCLIConfiguration.which("container") != nil
        {
            progress(.succeeded)
            return
        }

        let message = "Install finished but `container` was not found on PATH."
        progress(.failed(message))
        throw NativeStackError.installFailed(reason: message)
    }

    private func fetchSignedPackageURL() async throws -> URL {
        var request = URLRequest(url: URL(string: Self.releaseAPI)!)
        request.setValue("NativeStack/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NativeStackError.installFailed(reason: "Could not fetch release metadata from GitHub.")
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let assets = json["assets"] as? [[String: Any]]
        else {
            throw NativeStackError.installFailed(reason: "Unexpected GitHub release format.")
        }

        for asset in assets {
            guard
                let name = asset["name"] as? String,
                name.hasSuffix(Self.pkgAssetSuffix),
                let urlString = asset["browser_download_url"] as? String,
                let url = URL(string: urlString)
            else { continue }
            return url
        }

        throw NativeStackError.installFailed(reason: "No signed installer package found in latest release.")
    }

    private func downloadPackage(from url: URL) async throws -> String {
        let (location, _) = try await URLSession.shared.download(from: url)
        let destination = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("container-installer-\(UUID().uuidString).pkg")

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination) {
            try fileManager.removeItem(atPath: destination)
        }
        try fileManager.moveItem(atPath: location.path, toPath: destination)
        return destination
    }

    private func installPackage(at path: String) async throws {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        let shell = "installer -pkg '\(escaped)' -target /"
        let script = "do shell script \"\(shell.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"

        let result = try await ExternalCommandRunner.run(
            executable: "/usr/bin/osascript",
            arguments: ["-e", script]
        )

        guard result.exitCode == 0 else {
            let output = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")

            if output.localizedCaseInsensitiveContains("canceled")
                || output.localizedCaseInsensitiveContains("cancelled")
                || result.exitCode == 1 {
                throw NativeStackError.installRequiresAdmin
            }

            throw NativeStackError.installFailed(
                reason: output.isEmpty ? "Installer exited with code \(result.exitCode)" : output
            )
        }
    }
}
