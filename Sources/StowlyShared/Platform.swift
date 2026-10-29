import Foundation

/// The source a saved item came from. Derived from the URL host (not stored), so existing reels
/// resolve their platform retroactively and no SwiftData migration is needed.
///
/// `.web` is the catch-all for manual cards / unrecognized hosts — it's the one value that is *not*
/// a supported share target, so it doubles as "reject this ingest".
public enum Platform: String, CaseIterable, Sendable {
    case instagram, linkedin, handshake, tiktok, youtube, twitter, web

    /// Hosts that map to this platform (matched exactly or as a subdomain). `.web` matches nothing.
    public var hosts: [String] {
        switch self {
        case .instagram: ["instagram.com"]
        case .linkedin:  ["linkedin.com", "lnkd.in"]
        case .handshake: ["joinhandshake.com"]
        case .tiktok:    ["tiktok.com"]
        case .youtube:   ["youtube.com", "youtu.be"]
        case .twitter:   ["twitter.com", "x.com"]
        case .web:       []
        }
    }

    /// User-facing name (used in buttons, prompts, error messages).
    public var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .linkedin:  "LinkedIn"
        case .handshake: "Handshake"
        case .tiktok:    "TikTok"
        case .youtube:   "YouTube"
        case .twitter:   "X"
        case .web:       "Link"
        }
    }

    /// Whether we attempt full extraction (yt-dlp video/audio → transcript). Login-gated or
    /// unknown sources are link-only: we scrape what metadata we can and skip the heavy pipeline.
    public var canExtract: Bool {
        switch self {
        case .instagram, .tiktok, .youtube, .twitter, .linkedin: true
        case .handshake, .web: false
        }
    }

    /// Whether the creator is an `@handle` (prepend `@`) vs a real name (LinkedIn, Handshake).
    public var usesAtHandle: Bool {
        switch self {
        case .instagram, .tiktok, .youtube, .twitter: true
        case .linkedin, .handshake, .web: false
        }
    }

    /// True for anything we accept from the share sheet / clipboard. `.web` (unknown host) is the
    /// single rejection case for ingestion.
    public var isSupportedShare: Bool { self != .web }

    /// Bundled image name for the platform logo (see Resources/Media.xcassets). `.web` has none.
    public var logoAsset: String { "logo-\(rawValue)" }

    /// Resolve a platform from a (possibly scheme-less) URL string. Unknown/empty → `.web`.
    /// Host must equal a platform host or be a true subdomain of it, so look-alikes like
    /// `instagram.com.evil.com` or `notinstagram.com` resolve to `.web`.
    public static func detect(from urlString: String) -> Platform {
        let normalized = ShareLink.normalizedURLString(urlString)
        guard let host = URL(string: normalized)?.host()?.lowercased() else { return .web }
        for platform in allCases where platform != .web {
            for h in platform.hosts where host == h || host.hasSuffix("." + h) {
                return platform
            }
        }
        return .web
    }
}
