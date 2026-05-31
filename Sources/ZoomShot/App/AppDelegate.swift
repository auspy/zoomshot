import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotKey: HotKeyManager?
    private var coordinator: CaptureCoordinator?
    private var preferences: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = CaptureCoordinator()
        self.coordinator = coordinator

        self.menuBar = MenuBarController(
            onCapture: { [weak coordinator] in coordinator?.beginCapture() },
            onPreferences: { [weak self] in self?.showPreferences() },
            onQuit: { NSApp.terminate(nil) }
        )

        self.hotKey = HotKeyManager()
        self.hotKey?.register(keyCode: UInt32(kVK_ANSI_5),
                              modifiers: UInt32(cmdKey | shiftKey)) { [weak coordinator] in
            coordinator?.beginCapture()
        }
    }

    private func showPreferences() {
        if preferences == nil {
            preferences = PreferencesWindowController()
        }
        preferences?.show()
    }
}
