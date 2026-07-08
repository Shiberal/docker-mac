import Foundation

/// Remembers which containers (by display name) should be started automatically
/// whenever NativeStack launches, so a personal Postgres/Redis you keep around
/// comes back up without a manual click.
public enum AutoStartStore {
    private static var storeURL: URL {
        AppSettingsStore.dataDirectoryURL.appendingPathComponent("autostart.json")
    }

    public static func load() -> Set<String> {
        guard let data = try? Data(contentsOf: storeURL),
              let names = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }
        return names
    }

    public static func setEnabled(_ enabled: Bool, for name: String) {
        var names = load()
        if enabled {
            names.insert(name)
        } else {
            names.remove(name)
        }
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(names) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    public static func isEnabled(_ name: String) -> Bool {
        load().contains(name)
    }
}
