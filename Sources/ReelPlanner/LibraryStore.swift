import Foundation
import SwiftData
import Observation

/// Owns the SwiftData stack and exposes the observable lists the notch UI renders.
/// Seeds starter content on first run. Re-fetches after mutations so SwiftUI updates.
/// How folder sections are ordered in the panel.
enum FolderSort: String, CaseIterable {
    case custom, nameAsc, nameDesc, countDesc, countAsc

    var title: String {
        switch self {
        case .custom: "Custom"
        case .nameAsc: "Name A–Z"
        case .nameDesc: "Name Z–A"
        case .countDesc: "Most cards"
        case .countAsc: "Fewest cards"
        }
    }
}

@MainActor
@Observable
final class LibraryStore {
    let container: ModelContainer

    private(set) var folders: [Folder] = []
    private(set) var reels: [Reel] = []

    /// Chosen folder ordering (persisted).
    var folderSort: FolderSort = .custom

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
        if let raw = UserDefaults.standard.string(forKey: "folderSort"), let s = FolderSort(rawValue: raw) {
            folderSort = s
        }
        seedIfEmpty()
        reload()
    }

    /// Re-read folders (by manual sort order) and reels (newest first) from the store. The
    /// display order is then re-applied by `sortedFolders` per the chosen `folderSort`.
    func reload() {
        let folderOrder = [SortDescriptor(\Folder.sortOrder, order: .forward)]
        folders = (try? context.fetch(FetchDescriptor<Folder>(sortBy: folderOrder))) ?? []

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

    func collapseAll() { collapsedFolders = Set(folders.map(\.persistentModelID)) }
    func expandAll() { collapsedFolders = [] }
    var allCollapsed: Bool { !folders.isEmpty && folders.allSatisfy { collapsedFolders.contains($0.persistentModelID) } }

    /// Folders in display order per the chosen sort. Card count = total reels in the folder.
    var sortedFolders: [Folder] {
        switch folderSort {
        case .custom:
            return folders   // already fetched by sortOrder
        case .nameAsc:
            return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .countDesc:
            return folders.sorted { reels(in: $0).count > reels(in: $1).count }
        case .countAsc:
            return folders.sorted { reels(in: $0).count < reels(in: $1).count }
        }
    }

    func setFolderSort(_ sort: FolderSort) {
        folderSort = sort
        UserDefaults.standard.set(sort.rawValue, forKey: "folderSort")
    }

    /// Drag-to-reorder: move a folder `steps` positions (negative = up) in the shown order,
    /// renumber, and switch to Custom so the new order sticks.
    func moveFolder(_ folder: Folder, by steps: Int) {
        guard steps != 0 else { return }
        var ordered = sortedFolders
        guard let from = ordered.firstIndex(where: { $0.persistentModelID == folder.persistentModelID }) else { return }
        let to = max(0, min(ordered.count - 1, from + steps))
        guard to != from else { return }
        let dragged = ordered.remove(at: from)
        ordered.insert(dragged, at: to)
        for (i, f) in ordered.enumerated() { f.sortOrder = i }
        setFolderSort(.custom)
        try? context.save()
        reload()
    }

    /// Manual reorder (custom mode): swap a folder with its neighbour and renumber sortOrder.
    func moveFolder(_ folder: Folder, up: Bool) {
        var ordered = folders   // sortOrder order
        guard let idx = ordered.firstIndex(where: { $0.persistentModelID == folder.persistentModelID }) else { return }
        let target = up ? idx - 1 : idx + 1
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(idx, target)
        for (i, f) in ordered.enumerated() { f.sortOrder = i }
        setFolderSort(.custom)
        try? context.save()
        reload()
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
            folder = insertFolder(named: name)
        }
        reel.folder = folder
        reel.proposedFolderName = nil
        try? context.save()
        reload()
    }

    /// Create a folder by hand (from the "New Folder" button). Icon is filled in by AI if available.
    @discardableResult
    func createFolder(name: String) -> Folder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !folders.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return nil }
        let folder = insertFolder(named: trimmed)
        try? context.save()
        reload()
        return folder
    }

    /// Move a reel into a folder (right-click → Move to). Clears any pending proposal.
    func moveReel(_ reel: Reel, to folder: Folder) {
        reel.folder = folder
        reel.proposedFolderName = nil
        try? context.save()
        reload()
    }

    /// Delete a folder. Its reels aren't lost — they move to Misc. Misc itself can't be deleted
    /// (it's the fallback bucket).
    func deleteFolder(_ folder: Folder) {
        guard folder.name != "Misc" else { return }
        let fallback = folders.first { $0.name == "Misc" }
            ?? folders.first { $0.persistentModelID != folder.persistentModelID }
        for reel in reels(in: folder) { reel.folder = fallback }
        collapsedFolders.remove(folder.persistentModelID)
        context.delete(folder)
        try? context.save()
        reload()
    }

    /// Insert a new folder with an instant heuristic icon, then upgrade it to an AI-chosen
    /// symbol in the background. Caller saves/reloads.
    private func insertFolder(named name: String) -> Folder {
        let order = (folders.map(\.sortOrder).max() ?? 0) + 1
        let folder = Folder(name: name, symbol: FolderIcon.heuristic(for: name), isUserCreated: true, sortOrder: order)
        context.insert(folder)
        resolveAIIcon(for: folder)
        return folder
    }

    /// Ask the AI for a nicer icon and apply it when it comes back (no-op without a key/offline).
    private func resolveAIIcon(for folder: Folder) {
        let name = folder.name
        let id = folder.persistentModelID
        Task {
            guard let symbol = await FolderIcon.aiSuggestion(for: name),
                  let target = folders.first(where: { $0.persistentModelID == id }),
                  target.symbol != symbol
            else { return }
            target.symbol = symbol
            try? context.save()
            reload()
        }
    }

    /// Dismiss a proposal: the reel stays in Misc, no folder is created.
    func dismissProposal(for reel: Reel) {
        reel.proposedFolderName = nil
        try? context.save()
        reload()
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
