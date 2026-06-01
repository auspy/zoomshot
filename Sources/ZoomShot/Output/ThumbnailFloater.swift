import AppKit
import UniformTypeIdentifiers

/// Borderless floating window anchored bottom-right showing the captured
/// thumbnail. Stays on screen until dismissed via the hover-revealed Close
/// button. The card can also be dragged out as a PNG file.
final class ThumbnailFloater {
    private static var active: ThumbnailFloater?

    private let window: NSWindow
    private let host: FloaterHostView

    static func show(image: CGImage, pngData: Data, fileURL: URL) {
        active?.dismissNow()
        let f = ThumbnailFloater(image: image, pngData: pngData, fileURL: fileURL)
        active = f
        f.present()
    }

    private init(image: CGImage, pngData: Data, fileURL: URL) {
        let thumbMaxSide: CGFloat = 240
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let aspect = imgW / imgH
        let (w, h): (CGFloat, CGFloat) = aspect >= 1
            ? (thumbMaxSide, thumbMaxSide / aspect)
            : (thumbMaxSide * aspect, thumbMaxSide)

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let pad: CGFloat = 24
        let frame = NSRect(
            x: screen.visibleFrame.maxX - w - pad,
            y: screen.visibleFrame.minY + pad,
            width: w,
            height: h
        )

        window = NSWindow(contentRect: frame,
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        host = FloaterHostView(frame: NSRect(origin: .zero, size: frame.size),
                               image: image,
                               pngData: pngData,
                               fileURL: fileURL)
        window.contentView = host
        host.onClose = { [weak self] in self?.dismissNow() }
    }

    private func present() {
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 1
        }
    }

    private func dismissNow() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.window.orderOut(nil)
            if ThumbnailFloater.active === self { ThumbnailFloater.active = nil }
        })
    }
}

// MARK: - Card view

private final class FloaterHostView: NSView, NSDraggingSource {
    var onClose: (() -> Void)?

    private let image: CGImage
    private let pngData: Data
    private let fileURL: URL

    private let imageLayer = CALayer()
    private let dimLayer = CALayer()
    private let toolbar: HoverToolbar
    private let closeButton = CircleIconButton(symbol: "xmark")

    private var trackingArea: NSTrackingArea?
    private var mouseDownLocation: NSPoint?
    private var dragging = false
    private let dragThreshold: CGFloat = 4

    init(frame: NSRect, image: CGImage, pngData: Data, fileURL: URL) {
        self.image = image
        self.pngData = pngData
        self.fileURL = fileURL
        self.toolbar = HoverToolbar(frame: .zero)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1

        imageLayer.frame = bounds
        imageLayer.contents = image
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(imageLayer)

        dimLayer.frame = bounds
        dimLayer.backgroundColor = NSColor(white: 0, alpha: 0.45).cgColor
        dimLayer.opacity = 0
        layer?.addSublayer(dimLayer)

        toolbar.frame = bounds
        toolbar.alphaValue = 0
        toolbar.onCopy = { [weak self] in self?.copyToClipboard() }
        toolbar.onSave = { [weak self] in self?.saveAs() }
        addSubview(toolbar)

        let btnSize: CGFloat = 24
        let margin: CGFloat = 8
        closeButton.frame = NSRect(x: margin, y: bounds.maxY - btnSize - margin,
                                   width: btnSize, height: btnSize)
        closeButton.alphaValue = 0
        closeButton.onClick = { [weak self] in self?.onClose?() }
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent)  { setHovered(false) }

    private func setHovered(_ on: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            toolbar.animator().alphaValue = on ? 1 : 0
            closeButton.animator().alphaValue = on ? 1 : 0
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        dimLayer.opacity = on ? 1 : 0
        CATransaction.commit()
    }

    // MARK: Drag-out

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let start = mouseDownLocation else { return }
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - start.x
        let dy = p.y - start.y
        if dx * dx + dy * dy < dragThreshold * dragThreshold { return }

        dragging = true
        beginFileDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownLocation = nil }
        // Only treat this as a click on the card itself if we actually saw
        // the matching mouseDown here. Without this guard, a click on a
        // subview (e.g. the close button) that doesn't override mouseUp
        // bubbles up the responder chain and re-fires the file-open here.
        guard mouseDownLocation != nil, !dragging else { return }
        NSWorkspace.shared.open(fileURL)
    }

    private func beginFileDrag(with event: NSEvent) {
        let pbItem = NSPasteboardItem()
        pbItem.setString(fileURL.absoluteString, forType: .fileURL)
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)

        // Drag image: a scaled-down thumbnail of the capture
        let thumbnail = NSImage(cgImage: image, size: bounds.size)
        let dragSize = NSSize(width: min(bounds.width, 180), height: min(bounds.height, 180))
        let originInView = convert(event.locationInWindow, from: nil)
        let dragOrigin = NSPoint(x: originInView.x - dragSize.width / 2,
                                 y: originInView.y - dragSize.height / 2)
        dragItem.setDraggingFrame(NSRect(origin: dragOrigin, size: dragSize),
                                  contents: thumbnail)

        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    // NSDraggingSource
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .generic]
    }

    // MARK: Toolbar actions

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(pngData, forType: .png)
        flash("Copied")
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png]
        panel.nameFieldStringValue = fileURL.lastPathComponent
        panel.canCreateDirectories = true
        if let dir = PreferencesStore.shared.saveDirectory {
            panel.directoryURL = dir
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try self.pngData.write(to: url)
                self.flash("Saved")
            } catch {
                NSLog("ZoomShot: save-as failed: \(error)")
            }
        }
    }

    private func flash(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.drawsBackground = true
        label.backgroundColor = NSColor(white: 0, alpha: 0.7)
        label.wantsLayer = true
        label.layer?.cornerRadius = 8
        label.layer?.masksToBounds = true
        label.sizeToFit()
        var f = label.frame
        f.size.width += 16
        f.size.height += 6
        f.origin = NSPoint(x: (bounds.width - f.width) / 2, y: 12)
        label.frame = f
        addSubview(label)

        label.alphaValue = 0
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            label.animator().alphaValue = 1
        }, completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.25
                    label.animator().alphaValue = 0
                }, completionHandler: {
                    label.removeFromSuperview()
                })
            }
        })
    }
}

// MARK: - Hover toolbar

private final class HoverToolbar: NSView {
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

    private let copyButton = PillButton(title: "Copy")
    private let saveButton = PillButton(title: "Save")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        copyButton.onClick = { [weak self] in self?.onCopy?() }
        saveButton.onClick = { [weak self] in self?.onSave?() }
        addSubview(copyButton)
        addSubview(saveButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let pillWidth: CGFloat = 84
        let pillHeight: CGFloat = 32
        let gap: CGFloat = 8
        let totalH = pillHeight * 2 + gap
        let originY = (bounds.height - totalH) / 2
        let originX = (bounds.width - pillWidth) / 2
        copyButton.frame = NSRect(x: originX, y: originY + pillHeight + gap,
                                  width: pillWidth, height: pillHeight)
        saveButton.frame = NSRect(x: originX, y: originY,
                                  width: pillWidth, height: pillHeight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass clicks outside the buttons through to the underlying card so
        // the user can still drag from the empty area.
        let local = convert(point, from: superview)
        if copyButton.frame.contains(local) || saveButton.frame.contains(local) {
            return super.hitTest(point)
        }
        return nil
    }
}

// MARK: - Buttons

private final class PillButton: NSView {
    var onClick: (() -> Void)?

    private let label: NSTextField
    private let bg = CALayer()
    private var trackingArea: NSTrackingArea?
    private var hovered = false
    private var pressed = false

    init(title: String) {
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = NSColor(white: 0.1, alpha: 1)
        l.alignment = .center
        self.label = l
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        bg.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        bg.cornerRadius = 14
        bg.shadowColor = NSColor.black.cgColor
        bg.shadowOpacity = 0.25
        bg.shadowRadius = 8
        bg.shadowOffset = NSSize(width: 0, height: -1)
        layer?.addSublayer(bg)

        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        bg.frame = bounds
        bg.cornerRadius = bounds.height / 2
        label.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; refresh() }
    override func mouseExited(with event: NSEvent)  { hovered = false; pressed = false; refresh() }
    override func mouseDown(with event: NSEvent)    { pressed = true; refresh() }
    override func mouseUp(with event: NSEvent) {
        defer { pressed = false; refresh() }
        if hovered { onClick?() }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        let white: CGFloat = pressed ? 0.85 : (hovered ? 1.0 : 0.96)
        bg.backgroundColor = NSColor(white: white, alpha: 1).cgColor
        CATransaction.commit()
    }
}

private final class CircleIconButton: NSView {
    var onClick: (() -> Void)?

    private let bg = CAShapeLayer()
    private let symbolLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var hovered = false

    init(symbol: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        bg.fillColor = NSColor(white: 0, alpha: 0.7).cgColor
        bg.strokeColor = NSColor.white.withAlphaComponent(0.4).cgColor
        bg.lineWidth = 1
        layer?.addSublayer(bg)

        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            // Tint white by rendering into a bitmap
            let tinted = NSImage(size: img.size, flipped: false) { rect in
                NSColor.white.set()
                img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                rect.fill(using: .sourceIn)
                return true
            }
            symbolLayer.contents = tinted
            symbolLayer.contentsGravity = .resizeAspect
        }
        layer?.addSublayer(symbolLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        bg.frame = bounds
        bg.path = CGPath(ellipseIn: bounds, transform: nil)
        let inset = bounds.width * 0.28
        symbolLayer.frame = bounds.insetBy(dx: inset, dy: inset)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        bg.fillColor = NSColor(white: 0, alpha: 0.92).cgColor
        CATransaction.commit()
    }
    override func mouseExited(with event: NSEvent) {
        hovered = false
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        bg.fillColor = NSColor(white: 0, alpha: 0.7).cgColor
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    // Explicitly consume mouseUp so it doesn't bubble to the parent card,
    // which would re-fire the file-open action on top of the close.
    override func mouseUp(with event: NSEvent) {}

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
