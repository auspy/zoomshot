import AppKit

final class OverlayController {
    private var window: OverlayWindow?
    private var view: OverlayView?
    private var keyMonitor: Any?
    private var completion: ((CGRect?) -> Void)?

    /// Present the overlay with `frozen` and call `completion` with the selected
    /// rect (in OverlayView point coordinates, top-left origin) or nil if cancelled.
    func present(frozen: FrozenScreen, completion: @escaping (CGRect?) -> Void) {
        guard let screen = NSScreen.main else {
            completion(nil); return
        }
        self.completion = completion

        let window = OverlayWindow(screen: screen)
        let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size),
                               frozen: frozen)
        view.onCommit = { [weak self] rect in self?.finish(with: rect) }
        view.onCancel = { [weak self] in self?.finish(with: nil) }

        window.contentView = view
        window.makeFirstResponder(view)
        self.window = window
        self.view = view

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 53 = Escape
            if event.keyCode == 53 {
                self?.finish(with: nil)
                return nil
            }
            return event
        }
    }

    private func finish(with rect: CGRect?) {
        let cb = completion
        completion = nil

        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil

        NSCursor.pop()
        window?.orderOut(nil)
        window = nil
        view = nil

        cb?(rect)
    }
}
