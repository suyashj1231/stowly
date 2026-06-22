import Foundation

/// A single extracted link found inside a reel (e.g. an application page, a resource).
struct ReelLink: Identifiable, Hashable {
    let id = UUID()
    var url: URL
    var label: String   // e.g. "application", "resource", "signup"
}

enum ReelStatus: String {
    case new        // ingested, not yet processed
    case processed  // AI has parsed it
    case done       // user acted on it
}

/// One saved reel turned into a task.
struct Reel: Identifiable, Hashable {
    let id = UUID()
    var originalURL: URL
    var addedAt: Date
    var status: ReelStatus

    var task: String          // the gist, e.g. "Apply to Google STEP internship"
    var summary: String       // short description of what the reel is about
    var creator: String       // @handle
    var links: [ReelLink]

    var folderID: UUID
}

/// A category bucket. User-defined starter folders + AI-proposed (approved) ones.
struct Folder: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var symbol: String        // SF Symbol name for the folder
    var isUserCreated: Bool
    var sortOrder: Int
}
