import CoreGraphics
import Foundation

enum PixelCropper {
    /// Crop the frozen image to `rectInPoints`, where the rect is expressed in the
    /// overlay view's coordinate space (origin top-left, points). Returns a CGImage
    /// in native pixels.
    static func crop(_ frozen: FrozenScreen, rectInPoints: CGRect) -> CGImage? {
        let scale = frozen.scale
        var pixelRect = CGRect(
            x: rectInPoints.origin.x * scale,
            y: rectInPoints.origin.y * scale,
            width: rectInPoints.width * scale,
            height: rectInPoints.height * scale
        ).integral

        let imageBounds = CGRect(x: 0, y: 0,
                                 width: frozen.image.width,
                                 height: frozen.image.height)
        pixelRect = pixelRect.intersection(imageBounds)
        guard !pixelRect.isEmpty else { return nil }
        return frozen.image.cropping(to: pixelRect)
    }
}
