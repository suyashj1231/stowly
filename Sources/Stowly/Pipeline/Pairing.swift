import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import StowlyShared

extension Pairing {
    /// Render `string` as a QR code, black on white with a quiet zone (so it scans even when the
    /// surrounding UI is dark). Nearest-neighbour scaling keeps the modules crisp.
    static func qrImage(for string: String, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let quietZone: CGFloat = 4   // modules of white border, per the QR spec
        let modules = output.extent.width + quietZone * 2
        let scale = max(1, (size / modules).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        let side = modules * scale
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSGraphicsContext.current?.cgContext.draw(
            cg,
            in: CGRect(x: quietZone * scale, y: quietZone * scale, width: scaled.extent.width, height: scaled.extent.height)
        )
        image.unlockFocus()
        return image
    }
}
