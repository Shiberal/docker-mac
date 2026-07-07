import Foundation
import NativeStackCore

public enum AppSettingsStore {
    public static var settingsURL: URL {
        let base = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/NativeStack", isDirectory: true)
        return base.appendingPathComponent("settings.json")
    }

    public static var dataDirectoryURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/NativeStack", isDirectory: true)
    }

    public static func load() -> AppSettings {
        let url = settingsURL
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    public static func save(_ settings: AppSettings) throws {
        let url = settingsURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(settings)
        try data.write(to: url, options: .atomic)
    }
}
