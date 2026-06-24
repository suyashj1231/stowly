import Foundation
import SwiftData

/// Processing state of a reel as it moves through the pipeline.
enum ReelStatus: String, Codable, CaseIterable {
    case new        // ingested, not yet parsed
    case processed  // AI has parsed it
    case done       // user acted on it (completed)
}

/// Which tab the panel is showing. `active`/`archived`/`completed` are mutually-exclusive
/// buckets (see `LibraryStore.shelf(of:)`); `tracking` is a cross-cutting filter — any item with
/// a running timer, shown flat (not grouped by folder).
enum Shelf: CaseIterable {
    case active      // the working queue
    case tracking    // items you're actively working on (flat, timed)
    case archived    // saved for later
    case completed   // task finished

    var title: String {
        switch self {
        case .active: "Home"
        case .tracking: "Tracking"
        case .archived: "Archive"
        case .completed: "Done"
        }
    }
    var symbol: String {
        switch self {
        case .active: "house"
        case .tracking: "stopwatch"
        case .archived: "archivebox"
        case .completed: "checkmark.circle"
        }
    }
}

/// A category bucket. User-defined starter folders + AI-proposed (approved) ones.
@Model
final class Folder {
    var name: String = ""
    var symbol: String = ""           // SF Symbol name
    var isUserCreated: Bool = true
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Reel.folder)
    var reels: [Reel] = []

    init(name: String, symbol: String, isUserCreated: Bool, sortOrder: Int) {
        self.name = name
        self.symbol = symbol
        self.isUserCreated = isUserCreated
        self.sortOrder = sortOrder
    }
}

/// One saved reel turned into a task card.
@Model
final class Reel {
    var originalURLString: String = ""
    var addedAt: Date = Date()
    var statusRaw: String = ReelStatus.new.rawValue

    // Raw extracted material (filled by the parsing pipeline, Phase 4)
    var caption: String?
    var transcript: String?
    var ocrText: String?

    // Understood fields (filled by the LLM, Phase 5)
    var task: String = ""
    var summary: String = ""
    var creator: String = ""

    /// True for cards the user created by hand (no reel to fetch/process).
    var isManual: Bool = false

    /// Saved for later — shows in the Archive tab instead of the working queue.
    var isArchived: Bool = false

    /// When this item was added to the Tracking tab — a stable "since" time. Nil = not tracked.
    /// Additive optional → SwiftData handles the lightweight migration (nil for existing rows).
    var trackingStartedAt: Date?

    /// Start of the current *running* segment; nil while paused. (Pause support.)
    var trackingRunningSince: Date?

    /// Seconds banked from earlier running segments (before pauses).
    var trackingAccumulated: Double = 0

    /// Set when processing failed (e.g. Ollama down, Gemini rate-limited). Drives the card's
    /// retry button; cleared on a successful run. Nil means no error.
    var lastError: String?

    /// A folder the AI proposed but that doesn't exist yet. The reel parks in Misc until the
    /// user approves creating it (or dismisses). Nil when there's no pending proposal.
    var proposedFolderName: String?

    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \ReelLink.reel)
    var links: [ReelLink] = []

    init(
        originalURLString: String,
        addedAt: Date = Date(),
        status: ReelStatus = .new,
        task: String = "",
        summary: String = "",
        creator: String = "",
        folder: Folder? = nil
    ) {
        self.originalURLString = originalURLString
        self.addedAt = addedAt
        self.statusRaw = status.rawValue
        self.task = task
        self.summary = summary
        self.creator = creator
        self.folder = folder
    }

    // MARK: Conveniences (keep views readable)
    var originalURL: URL {
        URL(string: originalURLString) ?? URL(string: "https://instagram.com")!
    }

    /// Source platform, derived from the URL host (not stored). Manual/empty-URL cards → `.web`.
    var platform: Platform { Platform.detect(from: originalURLString) }

    /// On the Tracking tab (whether the timer is running or paused).
    var isTracking: Bool { trackingStartedAt != nil }
    /// Timer actively counting.
    var isTrackingRunning: Bool { trackingRunningSince != nil }
    /// Tracked, but the timer is paused.
    var isTrackingPaused: Bool { isTracking && trackingRunningSince == nil }

    /// Total seconds worked: banked time + the current running segment (nil when not tracked).
    func trackingElapsed(asOf now: Date = .now) -> TimeInterval? {
        guard isTracking else { return nil }
        let live = trackingRunningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return trackingAccumulated + live
    }

    var status: ReelStatus {
        get { ReelStatus(rawValue: statusRaw) ?? .new }
        set { statusRaw = newValue.rawValue }
    }
}

/// An extracted link found inside a reel (e.g. an application page, a resource).
@Model
final class ReelLink {
    var urlString: String = ""
    var label: String = ""       // e.g. "application", "resource"
    var reel: Reel?

    init(urlString: String, label: String) {
        self.urlString = urlString
        self.label = label
    }

    var url: URL {
        URL(string: urlString) ?? URL(string: "https://instagram.com")!
    }
}
