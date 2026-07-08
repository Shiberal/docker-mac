import AppKit
import Foundation
import NativeStackClient
import NativeStackCore

enum MenuBarQuickActions {
    static func openShell(for container: ContainerRecord, binaryPath: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapeForAppleScript(binaryPath)) exec -it \(escapeForAppleScript(container.id)) sh -c 'exec sh || exec bash'"
        end tell
        """
        run(script)
    }

    static func copyComposeProjectPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    static func revealLogsInConsole(for container: ContainerRecord, service: ContainerService) {
        Task {
            let text = (try? await service.logs(for: container.id, tail: 2000)) ?? "No logs available."
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("NativeStack", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent("\(container.displayName).log")
            try? text.write(to: fileURL, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Console", fileURL.path]
            try? process.run()
        }
    }

    private static func escapeForAppleScript(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func run(_ script: String) {
        guard let appleScript = NSAppleScript(source: script) else { return }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}
