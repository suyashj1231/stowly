import Foundation

/// Phone ↔ Mac pairing. The Mac shows a QR of `stowly://pair?topic=<topic>`; the Stowly iPhone
/// app scans it (or the user pastes the ntfy address) to learn which relay topic to POST to.
/// The topic is the only thing exchanged — no accounts, no server.
public enum Pairing {
    public static let scheme = "stowly"
    public static let host = "pair"

    /// The payload encoded in the pairing QR.
    public static func url(topic: String) -> URL {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host
        comps.queryItems = [URLQueryItem(name: "topic", value: topic)]
        return comps.url!
    }

    /// Pull the relay topic out of anything the phone might be handed: the QR payload
    /// (`stowly://pair?topic=…`), the ntfy address the Shortcut flow shows
    /// (`https://ntfy.sh/<topic>`), or a bare topic. Returns nil for anything else.
    public static func topic(from raw: String) -> String? {
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
    public static func isValidTopic(_ topic: String) -> Bool {
        (1...64).contains(topic.count)
            && topic.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}
