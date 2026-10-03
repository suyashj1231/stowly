import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Phone ↔ Mac pairing. The Mac shows a QR of `stowly://pair?topic=<topic>`; the Stowly iPhone
/// app scans it (or the user pastes the ntfy address) to learn which relay topic to POST to.
/// The topic is the only thing exchanged — no accounts, no server.
enum Pairing {
    static let scheme = "stowly"
    static let host = "pair"

    /// The payload encoded in the pairing QR.
    static func url(topic: String) -> URL {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host
        comps.queryItems = [URLQueryItem(name: "topic", value: topic)]
        return comps.url!
    }

    /// Pull the relay topic out of anything the phone might be handed: the QR payload
    /// (`stowly://pair?topic=…`), the ntfy address the Shortcut flow shows
    /// (`https://ntfy.sh/<topic>`), or a bare topic. Returns nil for anything else.
    static func topic(from raw: String) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("ntfy.sh/") { trimmed = "https://" + trimmed }

        let candidate: String?
        if let comps = URLComponents(string: trimmed), let scheme = comps.scheme?.lowercased() {
            switch scheme {
            case Pairing.scheme where comps.host?.lowercased() == host:
                candidate = comps.queryItems?.first { $0.name == "topic" }?.value
            case "https" where comps.host?.lowercased() == "ntfy.sh":
                // Only the first path component is the topic (`/json`, `/ws` etc. are endpoints).
                candidate = comps.path.split(separator: "/").first.map(String.init)
            default:
                candidate = nil
            }
        } else {
            candidate = trimmed
        }

        guard let topic = candidate, isValidTopic(topic) else { return nil }
        return topic
    }

    /// ntfy topic names: 1–64 of `A–Z a–z 0–9 _ -`.
    static func isValidTopic(_ topic: String) -> Bool {
        (1...64).contains(topic.count)
            && topic.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

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
