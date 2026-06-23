import Foundation
import SwiftData
import Observation

/// Owns the SwiftData stack and exposes the observable lists the notch UI renders.
/// Seeds starter content on first run. Re-fetches after mutations so SwiftUI updates.
@MainActor
@Observable
final class LibraryStore {
    let container: ModelContainer

    private(set) var folders: [Folder] = []
    private(set) var reels: [Reel] = []

    /// Reels currently being processed (transient, in-memory) — drives the card spinner.
    var processingIDs: Set<PersistentIdentifier> = []
    /// Bumped to flash the notch glow; `glowColor` says which color. White = reel arrived,
    /// green = queue finished cleanly, red = a reel errored.
    var glowToken: Int = 0
    var glowColor: GlowColor = .white

    /// Set by AppDelegate so the store can (re)submit a reel to the processing queue (retry).
    var requestProcessing: ((Reel) -> Void)?

    /// Flash the notch glow in a semantic color.
    func flashGlow(_ color: GlowColor) {
        glowColor = color
        glowToken += 1
    }

    var context: ModelContext { container.mainContext }

    func isProcessing(_ reel: Reel) -> Bool {
        processingIDs.contains(reel.persistentModelID)
    }

    /// Reels that still need parsing (placeholders added but not yet understood).
    /// Includes the legacy "Untitled reel" placeholder from earlier builds.
    func pendingReels() -> [Reel] {
        reels.filter { $0.status == .new && ($0.task.isEmpty || $0.task == "Untitled reel") }
    }

    init() {
        do {
            // Dedicated, app-specific store (avoid the shared default.store location).
            let dir = URL.applicationSupportDirectory.appending(path: "ReelPlanner", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let config = ModelConfiguration(url: dir.appending(path: "Library.store"))
            container = try ModelContainer(for: Reel.self, Folder.self, ReelLink.self, configurations: config)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
        seedIfEmpty()
        reload()
    }

    /// Re-read folders (by sort order) and reels (newest first) from the store.
    func reload() {
        let folderSort = [SortDescriptor(\Folder.sortOrder, order: .forward)]
        folders = (try? context.fetch(FetchDescriptor<Folder>(sortBy: folderSort))) ?? []

        let reelSort = [SortDescriptor(\Reel.addedAt, order: .reverse)]
        reels = (try? context.fetch(FetchDescriptor<Reel>(sortBy: reelSort))) ?? []
    }

    /// Folder sections the user has collapsed in the panel (in-memory, per session).
    var collapsedFolders: Set<PersistentIdentifier> = []

    /// Reels belonging to a folder, newest first.
    func reels(in folder: Folder) -> [Reel] {
        reels.filter { $0.folder?.persistentModelID == folder.persistentModelID }
    }

    /// Which tab a reel belongs to (completed wins over archived over active).
    func shelf(of reel: Reel) -> Shelf {
        if reel.status == .done { return .completed }
        if reel.isArchived { return .archived }
        return .active
    }

    /// Reels in a folder filtered to one tab, newest first.
    func reels(in folder: Folder, shelf: Shelf) -> [Reel] {
        reels(in: folder).filter { self.shelf(of: $0) == shelf }
    }

    /// Total reels in a tab (drives the tab badges).
    func count(for shelf: Shelf) -> Int {
        reels.filter { self.shelf(of: $0) == shelf }.count
    }

    func isCollapsed(_ folder: Folder) -> Bool {
        collapsedFolders.contains(folder.persistentModelID)
    }

    func toggleCollapsed(_ folder: Folder) {
        let id = folder.persistentModelID
        if collapsedFolders.contains(id) { collapsedFolders.remove(id) } else { collapsedFolders.insert(id) }
    }

    /// Mark a reel completed (Done tab) or send it back to the active queue.
    func setCompleted(_ reel: Reel, _ completed: Bool) {
        reel.status = completed ? .done : .processed
        if completed { reel.isArchived = false }   // completing supersedes archive
        try? context.save()
        reload()
    }

    /// Move a reel to the Archive tab (or back to the active queue).
    func setArchived(_ reel: Reel, _ archived: Bool) {
        reel.isArchived = archived
        if archived, reel.status == .done { reel.status = .processed }   // un-complete when archiving
        try? context.save()
        reload()
    }

    private var miscFolder: Folder? {
        folders.first { $0.name == "Misc" } ?? folders.last
    }

    /// Add a reel from a pasted/ingested URL. For now it lands in Misc as a `.new`
    /// placeholder; the parsing + LLM pipeline (Phases 4–5) will fill task/summary/folder.
    @discardableResult
    func addReel(urlString raw: String) -> Reel? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host(), host.contains("instagram.com") else {
            return nil
        }
        // Skip duplicates of the same URL.
        if reels.contains(where: { $0.originalURLString == trimmed }) { return nil }

        let reel = Reel(
            originalURLString: trimmed,
            status: .new,
            task: "",                 // empty => UI shows a "new reel" placeholder
            summary: "",
            creator: "",
            folder: miscFolder
        )
        context.insert(reel)
        try? context.save()
        reload()
        flashGlow(.white)            // white glow: a reel just arrived
        return reel
    }

    /// Re-run processing for a reel that errored (e.g. after restarting Ollama, or once a
    /// Gemini rate-limit window passes). Resets it to a fresh `.new` state and re-enqueues.
    func retry(_ reel: Reel) {
        reel.task = ""
        reel.summary = ""
        reel.lastError = nil
        reel.status = .new
        try? context.save()
        reload()
        requestProcessing?(reel)
    }

    func deleteReel(_ reel: Reel) {
        // Clear any in-flight spinner state for this reel so deleting the one being processed
        // (or a batch) doesn't leave the pill spinner stuck rotating.
        processingIDs.remove(reel.persistentModelID)
        context.delete(reel)
        try? context.save()
        reload()
    }

    /// Approve an AI-proposed folder: create it (or reuse if it now exists), move the reel into
    /// it, and clear the proposal. Driven by the "Create folder?" card affordance.
    func approveProposedFolder(for reel: Reel) {
        guard let name = reel.proposedFolderName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return }

        let folder: Folder
        if let existing = folders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            folder = existing
        } else {
            let nextOrder = (folders.map(\.sortOrder).max() ?? 0) + 1
            folder = Folder(name: name, symbol: Self.symbol(for: name), isUserCreated: true, sortOrder: nextOrder)
            context.insert(folder)
        }
        reel.folder = folder
        reel.proposedFolderName = nil
        try? context.save()
        reload()
    }

    /// Dismiss a proposal: the reel stays in Misc, no folder is created.
    func dismissProposal(for reel: Reel) {
        reel.proposedFolderName = nil
        try? context.save()
        reload()
    }

    /// Pick a reasonable SF Symbol for a newly-approved folder from its name.
    private static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("apply") || n.contains("job") || n.contains("intern") || n.contains("fellow") { return "paperplane.fill" }
        if n.contains("learn") || n.contains("cert") || n.contains("course") || n.contains("study") { return "graduationcap.fill" }
        if n.contains("watch") || n.contains("video") || n.contains("film") { return "play.rectangle.fill" }
        if n.contains("buy") || n.contains("shop") || n.contains("gear") { return "bag.fill" }
        if n.contains("recipe") || n.contains("food") || n.contains("cook") { return "fork.knife" }
        if n.contains("travel") || n.contains("trip") || n.contains("place") { return "airplane" }
        return "folder.fill"
    }

    /// Create a hand-made card (no reel to fetch). Lands in Misc, already "processed".
    @discardableResult
    func addManualReel(task: String, link: String?) -> Reel {
        let reel = Reel(
            originalURLString: "",
            status: .processed,
            task: task.isEmpty ? "New note" : task,
            summary: "",
            creator: "",
            folder: miscFolder
        )
        reel.isManual = true
        context.insert(reel)
        if let link, !link.isEmpty, let url = URL(string: link), url.scheme != nil {
            let model = ReelLink(urlString: link, label: "link")
            context.insert(model)
            model.reel = reel
        }
        try? context.save()
        reload()
        flashGlow(.white)
        return reel
    }

    private func seedIfEmpty() {
        let count = (try? context.fetchCount(FetchDescriptor<Folder>())) ?? 0
        if count == 0 {
            SeedData.seed(into: context)
        }
    }
}
