import AppKit
import CoreGraphics

/// Orchestrates: capture → present overlay → crop → copy + persist + show floater.
@MainActor
final class CaptureCoordinator {
    private var overlay: OverlayController?
    private var capturing = false

    func beginCapture() {
        guard !capturing else { return }

        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            showRelaunchPrompt()
            return
        }

        capturing = true
        Task { @MainActor in
            do {
                let frozen = try await ScreenCapturer.snapshotMainDisplay()
                presentOverlay(with: frozen)
            } catch {
                NSLog("ZoomShot: capture failed: \(error)")
                capturing = false
                showRelaunchPrompt()
            }
        }
    }

    private func presentOverlay(with frozen: FrozenScreen) {
        let controller = OverlayController()
        self.overlay = controller
        controller.present(frozen: frozen) { [weak self] rect in
            defer {
                self?.overlay = nil
                self?.capturing = false
            }
            guard let rect, let cropped = PixelCropper.crop(frozen, rectInPoints: rect) else {
                return
            }
            self?.handleCapturedImage(cropped)
        }
    }

    private func handleCapturedImage(_ image: CGImage) {
        guard let pngData = Self.pngData(from: image) else { return }
        _ = PasteboardWriter.writePNG(image)

        let filename = Self.timestampFilename()

        // Always write a temp copy so drag-and-drop has a real file URL.
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do { try pngData.write(to: tempURL) } catch {
            NSLog("ZoomShot: failed to write temp PNG: \(error)")
        }

        // If a save directory is configured, persist a second copy there.
        var persistedURL: URL? = nil
        if let dir = PreferencesStore.shared.saveDirectory {
            let target = dir.appendingPathComponent(filename)
            do {
                try FileManager.default.createDirectory(at: dir,
                                                        withIntermediateDirectories: true)
                try pngData.write(to: target)
                persistedURL = target
            } catch {
                NSLog("ZoomShot: failed to write to save directory: \(error)")
            }
        }

        let primaryURL = persistedURL ?? tempURL
        ThumbnailFloater.show(image: image, pngData: pngData, fileURL: primaryURL)
    }

    private static func pngData(from image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    private static func timestampFilename() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "ZoomShot \(fmt.string(from: Date())).png"
    }

    private func showRelaunchPrompt() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ZoomShot needs to be restarted"
        alert.informativeText = """
        macOS only applies new Screen Recording permission after the app is fully relaunched.

        1. Make sure ZoomShot is enabled in System Settings → Privacy & Security → Screen & System Audio Recording.
        2. Quit ZoomShot below, then launch it again.

        If the system still doesn't trust the app (this can happen after a rebuild), reset its permission by running this in Terminal:

            tccutil reset ScreenCapture com.zoomshot.app

        Then relaunch and grant again.
        """
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Quit ZoomShot")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
    }
}
