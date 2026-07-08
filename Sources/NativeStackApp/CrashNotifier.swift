import Foundation
import NativeStackClient
import NativeStackCore

/// Posts macOS notifications via `osascript`. NativeStack isn't packaged as a
/// signed `.app` bundle (it's a plain SPM executable), and `UNUserNotificationCenter`
/// hard-crashes in that case (`bundleProxyForCurrentProcess is nil`). `osascript`
/// posts through Notification Center without needing an owning app bundle.
enum CrashNotifier {
    @MainActor
    static func notify(container: ContainerRecord) {
        let title = escape(container.displayName)
        let body = escape("It stopped without being asked to — check its logs if that's unexpected.")
        let script = "display notification \"\(body)\" with title \"\(title) stopped\" sound name \"Basso\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
