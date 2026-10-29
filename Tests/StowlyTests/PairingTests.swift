import AppKit
import CoreImage
import Testing
@testable import Stowly
import StowlyShared

/// iPhone pairing: the QR payload must round-trip to the same topic, and the parser must accept
/// every form the phone might be handed (QR, pasted ntfy address, bare topic) while rejecting
/// anything that isn't a usable ntfy topic.
struct PairingTests {

    private let topic = "stowly-abc123def456ghi7"

    @Test func qrPayloadRoundTrips() {
        let url = Pairing.url(topic: topic)
        #expect(url.absoluteString == "stowly://pair?topic=\(topic)")
        #expect(Pairing.topic(from: url.absoluteString) == topic)
    }

    @Test func acceptsNtfyAddressForms() {
        #expect(Pairing.topic(from: "https://ntfy.sh/\(topic)") == topic)
        #expect(Pairing.topic(from: "  https://ntfy.sh/\(topic)\n") == topic)
        #expect(Pairing.topic(from: "ntfy.sh/\(topic)") == topic)
        #expect(Pairing.topic(from: "https://ntfy.sh/\(topic)/json") == topic)
        #expect(Pairing.topic(from: topic) == topic)
    }

    @Test func rejectsJunk() {
        #expect(Pairing.topic(from: "") == nil)
        #expect(Pairing.topic(from: "https://example.com/\(topic)") == nil)
        #expect(Pairing.topic(from: "http://ntfy.sh/\(topic)") == nil)       // https only
        #expect(Pairing.topic(from: "https://ntfy.sh/") == nil)
        #expect(Pairing.topic(from: "stowly://other?topic=\(topic)") == nil)
        #expect(Pairing.topic(from: "stowly://pair") == nil)
        #expect(Pairing.topic(from: "has spaces") == nil)
        #expect(Pairing.topic(from: "stowly://pair?topic=bad/slash") == nil)
        #expect(Pairing.topic(from: String(repeating: "a", count: 65)) == nil)
    }

    @Test func rendersQRCode() {
        let image = Pairing.qrImage(for: Pairing.url(topic: topic).absoluteString, size: 220)
        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 100)
        #expect(image?.size.width == image?.size.height)
    }

    @Test func qrCodeDecodesBackToPayload() throws {
        let payload = Pairing.url(topic: topic).absoluteString
        let image = try #require(Pairing.qrImage(for: payload, size: 220))
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil))
        let decoded = detector.features(in: CIImage(cgImage: cg)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(decoded == [payload])
    }
}
