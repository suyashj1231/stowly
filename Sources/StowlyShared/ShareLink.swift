import Foundation

/// Turning whatever the share sheet / clipboard hands us into a clean, supported post URL.
/// Shared by the Mac app (ingest) and the iPhone share extension (before it posts to the relay).
public enum ShareLink {
    /// Trim a URL string and prepend `https://` when the user omitted a scheme (e.g. pasted
    /// "instagram.com/reel/…" or typed "google.com"), so URL parsing finds a host.
    public static func normalizedURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.contains("://") { return trimmed }
        return "https://" + trimmed
    }

    /// Extract a shareable, supported-platform URL from arbitrary shared input. Many apps
    /// (LinkedIn, X) share the post as *text containing a link* rather than a bare URL, so pull the
    /// first http(s) URL out of the text. Falls back to treating the whole (scheme-less) string as
    /// a URL. Returns the cleaned URL string only if it's a supported platform, else nil.
    public static func extractShareableURL(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidate = trimmed
        if let range = trimmed.range(of: #"https?://[^\s]+"#, options: .regularExpression) {
            candidate = String(trimmed[range])
        }
        // Strip punctuation that often clings to a URL embedded in prose ("…/post). "
        let cleaned = normalizedURLString(candidate)
            .trimmingCharacters(in: CharacterSet(charactersIn: ").,]}\"'»"))
        guard Platform.detect(from: cleaned).isSupportedShare else { return nil }
        return cleaned
    }
}
