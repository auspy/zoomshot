import AppKit
import QuartzCore

/// Circular magnifier that follows the cursor and shows an 8x crop of the
/// frozen screenshot with a 1px crosshair on the center pixel. Auto-flips
/// to the opposite side of the cursor when near screen edges.
final class LoupeView: NSView {
    private let frozen: FrozenScreen
    private let diameter: CGFloat = 140
    private let zoom: CGFloat
    private let cursorOffset: CGFloat = 28  // distance from cursor to loupe edge

    private let imageLayer = CALayer()
    private let ringLayer = CAShapeLayer()
    private let crosshairLayer = CAShapeLayer()

    // Cache the last source-pixel rect so we skip CGImage.cropping + the
    // CATransaction commit when the cursor moves sub-pixel and the magnified
    // tile is identical to the previous frame.
    private var lastClamped: CGRect = .null

    init(frozen: FrozenScreen) {
        self.frozen = frozen
        self.zoom = PreferencesStore.shared.zoomLevel
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))

        wantsLayer = true
        layer?.masksToBounds = false

        // Circular clip mask
        let mask = CAShapeLayer()
        mask.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        mask.path = CGPath(ellipseIn: mask.frame, transform: nil)

        imageLayer.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        imageLayer.magnificationFilter = .nearest
        imageLayer.minificationFilter = .nearest
        imageLayer.mask = mask
        imageLayer.backgroundColor = NSColor.black.cgColor
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(imageLayer)

        ringLayer.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        ringLayer.path = CGPath(ellipseIn: ringLayer.frame.insetBy(dx: 1, dy: 1), transform: nil)
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        ringLayer.lineWidth = 2
        ringLayer.shadowColor = NSColor.black.cgColor
        ringLayer.shadowOpacity = 0.6
        ringLayer.shadowRadius = 6
        ringLayer.shadowOffset = .zero
        layer?.addSublayer(ringLayer)

        // White halo behind the crosshair for contrast on dark pixels
        let crosshairHalo = CAShapeLayer()
        crosshairHalo.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        crosshairHalo.fillColor = NSColor.clear.cgColor
        crosshairHalo.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        crosshairHalo.lineWidth = 3
        crosshairHalo.lineCap = .round
        crosshairHalo.path = makeCrosshairPath()
        layer?.addSublayer(crosshairHalo)

        crosshairLayer.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        crosshairLayer.fillColor = NSColor.clear.cgColor
        crosshairLayer.strokeColor = NSColor.black.cgColor
        crosshairLayer.lineWidth = 1.5
        crosshairLayer.lineCap = .round
        crosshairLayer.path = makeCrosshairPath()
        crosshairLayer.actions = ["path": NSNull()]
        layer?.addSublayer(crosshairLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    /// `centerPoint` is the cursor position in the parent view's coordinate
    /// space (top-left origin, points). `viewBounds` is the parent's bounds
    /// so we can flip the loupe near edges.
    func update(centerPoint: CGPoint, viewBounds: CGRect) {
        // Source rect (in pixels) around the cursor inside the frozen image
        let sidePoints = diameter / zoom
        let sidePixels = sidePoints * frozen.scale
        let cursorPixel = CGPoint(x: centerPoint.x * frozen.scale,
                                  y: centerPoint.y * frozen.scale)
        let pixelRect = CGRect(
            x: cursorPixel.x - sidePixels / 2,
            y: cursorPixel.y - sidePixels / 2,
            width: sidePixels,
            height: sidePixels
        ).integral

        let imageBounds = CGRect(x: 0, y: 0,
                                 width: frozen.image.width,
                                 height: frozen.image.height)
        let clamped = pixelRect.intersection(imageBounds)
        if clamped != lastClamped {
            lastClamped = clamped
            if let cropped = frozen.image.cropping(to: clamped) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                imageLayer.contents = cropped
                CATransaction.commit()
            }
        }

        // Position: prefer down-right of cursor, flip on edge collisions
        let half = diameter / 2
        var cx = centerPoint.x + cursorOffset + half
        var cy = centerPoint.y + cursorOffset + half

        if cx + half > viewBounds.maxX {
            cx = centerPoint.x - cursorOffset - half
        }
        if cy + half > viewBounds.maxY {
            cy = centerPoint.y - cursorOffset - half
        }
        // Clamp inside view if cursor is in a corner that flips both ways but still overflows
        cx = min(max(cx, half), viewBounds.maxX - half)
        cy = min(max(cy, half), viewBounds.maxY - half)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = NSRect(x: cx - half, y: cy - half, width: diameter, height: diameter)
        CATransaction.commit()
    }

    private func makeCrosshairPath() -> CGPath {
        let path = CGMutablePath()
        let c = diameter / 2
        let gap: CGFloat = 5
        let arm: CGFloat = 14
        // horizontal
        path.move(to: CGPoint(x: c - gap - arm, y: c))
        path.addLine(to: CGPoint(x: c - gap, y: c))
        path.move(to: CGPoint(x: c + gap, y: c))
        path.addLine(to: CGPoint(x: c + gap + arm, y: c))
        // vertical
        path.move(to: CGPoint(x: c, y: c - gap - arm))
        path.addLine(to: CGPoint(x: c, y: c - gap))
        path.move(to: CGPoint(x: c, y: c + gap))
        path.addLine(to: CGPoint(x: c, y: c + gap + arm))
        return path
    }
}
