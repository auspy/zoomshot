import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onCapture: () -> Void
    private let onPreferences: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onQuit: () -> Void

    init(onCapture: @escaping () -> Void,
         onPreferences: @escaping () -> Void,
         onCheckForUpdates: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onCapture = onCapture
        self.onPreferences = onPreferences
        self.onCheckForUpdates = onCheckForUpdates
        self.onQuit = onQuit
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dot.viewfinder",
                                   accessibilityDescription: "ZoomShot")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(makeItem(title: "Capture Area",
                              key: "5",
                              modifiers: [.command, .shift],
                              action: #selector(captureClicked)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Preferences…",
                              key: ",",
                              modifiers: [.command],
                              action: #selector(preferencesClicked)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Check for Updates…",
                              key: "",
                              modifiers: [],
                              action: #selector(checkForUpdatesClicked)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit ZoomShot",
                              key: "q",
                              modifiers: [.command],
                              action: #selector(quitClicked)))
        statusItem.menu = menu
    }

    private func makeItem(title: String,
                          key: String,
                          modifiers: NSEvent.ModifierFlags,
                          action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func captureClicked() { onCapture() }
    @objc private func preferencesClicked() { onPreferences() }
    @objc private func checkForUpdatesClicked() { onCheckForUpdates() }
    @objc private func quitClicked() { onQuit() }
}
