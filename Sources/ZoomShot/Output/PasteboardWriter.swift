import AppKit

enum PasteboardWriter {
    static func writePNG(_ image: CGImage) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return writePNGData(data)
    }

    @discardableResult
    static func writePNGData(_ data: Data) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setData(data, forType: .png)
    }
}
