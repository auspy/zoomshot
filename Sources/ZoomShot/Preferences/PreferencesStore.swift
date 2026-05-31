import Foundation

/// UserDefaults-backed preferences. Singleton because everything reads from it.
final class PreferencesStore {
    static let shared = PreferencesStore()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let saveDirectoryPath = "saveDirectoryPath"
        static let zoomLevel = "zoomLevel"
    }

    static let didChangeNotification = Notification.Name("ZoomShotPreferencesDidChange")

    /// Where new captures are auto-saved. `nil` means "don't auto-save to disk"
    /// (the screenshot still lands on the clipboard and a temp file is created
    /// to support drag-and-drop).
    var saveDirectory: URL? {
        get {
            guard let path = defaults.string(forKey: Key.saveDirectoryPath),
                  !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            defaults.set(newValue?.path, forKey: Key.saveDirectoryPath)
            notify()
        }
    }

    /// Loupe magnification factor. Supported: 4 or 8.
    var zoomLevel: CGFloat {
        get {
            let raw = defaults.integer(forKey: Key.zoomLevel)
            return raw == 4 ? 4 : 8
        }
        set {
            defaults.set(Int(newValue), forKey: Key.zoomLevel)
            notify()
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
