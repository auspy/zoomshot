import AppKit
import QuartzCore

/// Full-screen overlay view that paints the frozen screenshot, lets the user
/// drag a selection rectangle, and hosts the magnifier loupe.
///
/// Coordinate space: this view is flipped (top-left origin) so the math lines
/// up with the underlying CGImage. Rects emitted via `onCommit` are in this
/// same top-left point space, ready for PixelCropper.
final class OverlayView: NSView {
    var onCommit: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let frozen: FrozenScreen
    private let backgroundLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()
    private let loupe: LoupeView

    private var dragOrigin: CGPoint?
    private var currentMouse: CGPoint = .zero
    private var selectionRect: CGRect = .zero

    init(frame: NSRect, frozen: FrozenScreen) {
        self.frozen = frozen
        self.loupe = LoupeView(frozen: frozen)
        super.init(frame: frame)

        wantsLayer = true
        layer?.masksToBounds = true

        backgroundLayer.frame = bounds
        backgroundLayer.contents = frozen.image
        backgroundLayer.contentsGravity = .resize
        backgroundLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(backgroundLayer)

        dimLayer.frame = bounds
        dimLayer.fillColor = NSColor(white: 0, alpha: 0.45).cgColor
        dimLayer.fillRule = .evenOdd
        dimLayer.actions = ["path": NSNull(), "frame": NSNull()]
        layer?.addSublayer(dimLayer)

        selectionLayer.frame = bounds
        selectionLayer.fillColor = NSColor.clear.cgColor
        selectionLayer.strokeColor = NSColor.white.cgColor
        selectionLayer.lineWidth = 1.0
        selectionLayer.actions = ["path": NSNull(), "frame": NSNull()]
        layer?.addSublayer(selectionLayer)

        addSubview(loupe)
        loupe.isHidden = true

        refreshDim()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        window.makeFirstResponder(self)
    }

    // MARK: Mouse

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        loupe.isHidden = false
        NSCursor.crosshair.set()
        updateLoupe()
    }

    override func mouseExited(with event: NSEvent) {
        loupe.isHidden = true
    }

    override func mouseMoved(with event: NSEvent) {
        currentMouse = convert(event.locationInWindow, from: nil)
        updateLoupe()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragOrigin = p
        currentMouse = p
        selectionRect = CGRect(origin: p, size: .zero)
        refreshDim()
        updateLoupe()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        currentMouse = convert(event.locationInWindow, from: nil)
        selectionRect = CGRect(
            x: min(origin.x, currentMouse.x),
            y: min(origin.y, currentMouse.y),
            width: abs(currentMouse.x - origin.x),
            height: abs(currentMouse.y - origin.y)
        )
        refreshDim()
        updateLoupe()
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil }
        guard !selectionRect.isEmpty,
              selectionRect.width >= 2,
              selectionRect.height >= 2 else {
            onCancel?()
            return
        }
        onCommit?(selectionRect)
    }

    // MARK: Drawing

    private func refreshDim() {
        let full = CGMutablePath()
        full.addRect(bounds)
        if !selectionRect.isEmpty {
            full.addRect(selectionRect)
            selectionLayer.path = CGPath(rect: selectionRect, transform: nil)
        } else {
            selectionLayer.path = nil
        }
        dimLayer.path = full
    }

    private func updateLoupe() {
        loupe.update(centerPoint: currentMouse, viewBounds: bounds)
    }
}
