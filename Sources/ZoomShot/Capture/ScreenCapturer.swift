import AppKit
import ScreenCaptureKit

struct FrozenScreen {
    let image: CGImage          // native-pixel resolution
    let displayBounds: CGRect   // in points (origin in screen coordinate space)
    let scale: CGFloat          // backing scale factor
}

enum CaptureError: Error {
    case noMainDisplay
    case noSCDisplay
    case captureFailed(Error)
}

enum ScreenCapturer {
    /// Snapshot the main display synchronously (blocks the caller until done).
    /// Returns the image in native pixels along with the display's point-space bounds.
    static func snapshotMainDisplay() async throws -> FrozenScreen {
        guard let screen = NSScreen.main else { throw CaptureError.noMainDisplay }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let mainID = (NSScreen.main?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber)?.uint32Value,
              let scDisplay = content.displays.first(where: { $0.displayID == mainID })
                              ?? content.displays.first
        else {
            throw CaptureError.noSCDisplay
        }

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(scDisplay.width) * screen.backingScaleFactor)
        config.height = Int(CGFloat(scDisplay.height) * screen.backingScaleFactor)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false

        do {
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return FrozenScreen(
                image: cgImage,
                displayBounds: screen.frame,
                scale: screen.backingScaleFactor
            )
        } catch {
            throw CaptureError.captureFailed(error)
        }
    }
}
