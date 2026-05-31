import AppKit

final class PreferencesWindowController: NSWindowController {
    private let store = PreferencesStore.shared
    private let pathLabel = NSTextField(labelWithString: "")
    private let zoomControl = NSSegmentedControl(labels: ["4×", "8×"],
                                                 trackingMode: .selectOne,
                                                 target: nil,
                                                 action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ZoomShot Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        buildLayout()
        refreshValues()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Layout

    private func buildLayout() {
        guard let content = window?.contentView else { return }

        let pathTitle = NSTextField(labelWithString: "Save location")
        pathTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle

        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearFolder))
        clearButton.bezelStyle = .rounded

        let pathHint = NSTextField(labelWithString:
            "When set, every capture is auto-saved here as a timestamped PNG. " +
            "Captures are always also copied to the clipboard.")
        pathHint.font = .systemFont(ofSize: 11)
        pathHint.textColor = .tertiaryLabelColor
        pathHint.lineBreakMode = .byWordWrapping
        pathHint.maximumNumberOfLines = 0
        pathHint.preferredMaxLayoutWidth = 420

        let zoomTitle = NSTextField(labelWithString: "Loupe zoom")
        zoomTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        zoomControl.target = self
        zoomControl.action = #selector(zoomChanged)
        zoomControl.translatesAutoresizingMaskIntoConstraints = false

        let pathRow = NSStackView(views: [pathLabel, chooseButton, clearButton])
        pathRow.orientation = .horizontal
        pathRow.spacing = 8
        pathRow.alignment = .centerY
        pathRow.setHuggingPriority(.defaultLow, for: .horizontal)
        pathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [pathTitle, pathRow, pathHint, zoomTitle, zoomControl])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            pathRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            pathRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    private func refreshValues() {
        if let dir = store.saveDirectory {
            pathLabel.stringValue = dir.path
        } else {
            pathLabel.stringValue = "(not set — saves to clipboard only)"
        }
        zoomControl.selectedSegment = store.zoomLevel == 4 ? 0 : 1
    }

    // MARK: Actions

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick a folder where ZoomShot will save screenshots."
        if let current = store.saveDirectory { panel.directoryURL = current }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.store.saveDirectory = url
            self?.refreshValues()
        }
    }

    @objc private func clearFolder() {
        store.saveDirectory = nil
        refreshValues()
    }

    @objc private func zoomChanged() {
        store.zoomLevel = zoomControl.selectedSegment == 0 ? 4 : 8
    }
}
