import Foundation
import SwiftData

/// Processing state of a reel as it moves through the pipeline.
enum ReelStatus: String, Codable, CaseIterable {
    case new        // ingested, not yet parsed
    case processed  // AI has parsed it
    case done       // user acted on it (completed)
}

/// Which tab a reel lives in.
enum Shelf: CaseIterable {
    case active      // the working queue
    case archived    // saved for later
    case completed   // task finished

    var title: String {
        switch self {
        case .active: "Home"
        case .archived: "Archive"
        case .completed: "Done"
        }
    }
    var symbol: String {
        switch self {
        case .active: "house"
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
