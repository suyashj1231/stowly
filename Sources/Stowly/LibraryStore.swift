import Foundation
import SwiftData
import Observation
import AppKit
import StowlyShared

/// Owns the SwiftData stack and exposes the observable lists the notch UI renders.
/// Seeds starter content on first run. Re-fetches after mutations so SwiftUI updates.
/// How folder sections are ordered in the panel.
enum FolderSort: String, CaseIterable {
    case custom, nameAsc, nameDesc, countDesc, countAsc

    var title: String {
        switch self {
        case .custom: "Custom"
        case .nameAsc: "A–Z"
        case .nameDesc: "Z–A"
        case .countDesc: "Most cards"
        case .countAsc: "Fewest cards"
        }
    }
}

/// User-chosen app appearance. `.system` follows the macOS setting; the others force it.
/// Cyberpunk and Persona are dark game-inspired themes (see `ThemeStyle`).
enum AppAppearance: String, CaseIterable {
    case system, light, dark, cyberpunk, persona

    /// The `NSAppearance` to apply globally (`nil` = follow the system setting).
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light:  NSAppearance(named: .aqua)
        case .dark, .cyberpunk, .persona: NSAppearance(named: .darkAqua)
        }
    }

    /// Which set of `Theme` tokens this appearance uses.
    var style: ThemeStyle {
        switch self {
        case .system, .light, .dark: .standard
        case .cyberpunk: .cyberpunk
        case .persona: .persona
        }
    }

    /// SF Symbol shown on the header toggle button for this mode.
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light:  "sun.max.fill"
        case .dark:   "moon.fill"
        case .cyberpunk: "bolt.fill"
        case .persona: "theatermasks.fill"
        }
    }

    var label: String { rawValue.capitalized }
}

@MainActor
@Observable
final class LibraryStore {
    let container: ModelContainer

    private(set) var folders: [Folder] = []
    private(set) var reels: [Reel] = []

    /// Derived once per `reload()` so the views don't rescan all reels on every access:
    /// reels grouped by folder (newest first, matching `reels`) and per-tab totals.
    private(set) var reelsByFolder: [PersistentIdentifier: [Reel]] = [:]
    private(set) var shelfCounts: [Shelf: Int] = [:]

    /// Items with a running timer, most-recently-started first — the flat Tracking tab list.
    private(set) var trackedReels: [Reel] = []

    /// Active search query (empty = not searching). When set, the panel shows a flat results list.
    var searchQuery: String = ""

    /// Multi-select mode: tapping a card toggles its selection instead of opening it.
    var selectionMode = false
    var selection: Set<PersistentIdentifier> = []

    /// Chosen folder ordering (persisted).
    var folderSort: FolderSort = .custom

    /// Chosen app appearance (persisted). Defaults to `.dark` to preserve the app's original
    /// dark-only look for existing users; light/system are opt-in.
    var appearance: AppAppearance = .dark

    /// Whether newly-created folders kick off a background AI-icon lookup. Off in tests so the
    /// suite never calls the on-device model.
    var resolvesAIIcons = true

    /// Reels currently being processed (transient, in-memory) — drives the card spinner.
    var processingIDs: Set<PersistentIdentifier> = []
    /// Bumped to flash the notch glow; `glowColor` says which color. White = reel arrived,
    /// green = queue finished cleanly, red = a reel errored.
    var glowToken: Int = 0
    var glowColor: GlowColor = .white

    /// Set by AppDelegate so the store can (re)submit a reel to the processing queue (retry).
    var requestProcessing: ((Reel) -> Void)?

    /// Set by AppDelegate so the store can ask the model to re-sort a reel into a folder from its
    /// saved text (no re-download). Nil in tests, so they stay offline.
    var requestReclassify: ((Reel) -> Void)?

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
            let support = URL.applicationSupportDirectory
            let dir = support.appending(path: "Stowly", directoryHint: .isDirectory)
            // One-time migration from the pre-rename folder ("ReelPlanner") so existing data,
            // and cache carry over to Stowly.
            let legacy = support.appending(path: "ReelPlanner", directoryHint: .isDirectory)
            let fm = FileManager.default
            if !fm.fileExists(atPath: dir.path), fm.fileExists(atPath: legacy.path) {
                try? fm.moveItem(at: legacy, to: dir)
            }
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let config = ModelConfiguration(url: dir.appending(path: "Library.store"))
            container = try ModelContainer(for: Reel.self, Folder.self, ReelLink.self, configurations: config)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
        loadPreferences()
        seedIfEmpty()
        reload()
    }

    #if DEBUG
    /// Test/preview hook: build the store on a caller-provided container (e.g. an in-memory one)
    /// so store logic can be exercised hermetically without touching the on-disk app store.
    /// Does not seed — tests insert exactly the fixtures they need.
    init(container: ModelContainer, loadPreferences: Bool = false) {
        self.container = container
        self.resolvesAIIcons = false   // keep tests offline/hermetic
        if loadPreferences { self.loadPreferences() }
        reload()
    }

    /// In-memory store for tests/previews. Empty unless `seed` is set.
    static func inMemory(seed: Bool = false) -> LibraryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Reel.self, Folder.self, ReelLink.self, configurations: config)
        let store = LibraryStore(container: container)
        if seed {
            SeedData.seed(into: store.context)
            store.reload()
        }
        return store
    }
    #endif

    /// Restore persisted UI preferences (folder sort, appearance) from UserDefaults.
    private func loadPreferences() {
        if let raw = UserDefaults.standard.string(forKey: "folderSort"), let s = FolderSort(rawValue: raw) {
            folderSort = s
        }
        UserDefaults.standard.removeObject(forKey: "notchTopOffset")   // retired: panel position is fixed
        if let raw = UserDefaults.standard.string(forKey: "appearance"), let a = AppAppearance(rawValue: raw) {
            appearance = a
            Theme.style = a.style
        }
    }

    /// Re-read folders (by manual sort order) and reels (newest first) from the store. The
    /// display order is then re-applied by `sortedFolders` per the chosen `folderSort`.
    func reload() {
        let folderOrder = [SortDescriptor(\Folder.sortOrder, order: .forward)]
        folders = (try? context.fetch(FetchDescriptor<Folder>(sortBy: folderOrder))) ?? []

        let reelSort = [SortDescriptor(\Reel.addedAt, order: .reverse)]
        reels = (try? context.fetch(FetchDescriptor<Reel>(sortBy: reelSort))) ?? []

        // Build the derived lookups in a single pass over the freshly-fetched reels.
        var grouped: [PersistentIdentifier: [Reel]] = [:]
        var counts: [Shelf: Int] = [.active: 0, .archived: 0, .completed: 0]
        for reel in reels {
            if let fid = reel.folder?.persistentModelID {
                grouped[fid, default: []].append(reel)
            }
            counts[shelf(of: reel), default: 0] += 1
        }
        reelsByFolder = grouped
        shelfCounts = counts

        // Tracking is a cross-cutting filter (not a shelf bucket): most-recently-started first.
        trackedReels = reels
            .filter { $0.trackingStartedAt != nil }
            .sorted { ($0.trackingStartedAt ?? .distantPast) > ($1.trackingStartedAt ?? .distantPast) }
    }

    /// Folder sections the user has collapsed in the panel (in-memory, per session).
    var collapsedFolders: Set<PersistentIdentifier> = []

    /// Reels belonging to a folder, newest first.
    func reels(in folder: Folder) -> [Reel] {
        reelsByFolder[folder.persistentModelID] ?? []
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

    /// Total reels in a tab (drives the tab badges). Tracking is a cross-cutting filter.
    func count(for shelf: Shelf) -> Int {
        shelf == .tracking ? trackedReels.count : (shelfCounts[shelf] ?? 0)
    }

    func setSearchQuery(_ query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cards whose task, summary, or creator contains the current query (case-insensitive),
    /// newest first. Empty when not searching.
    func searchResults() -> [Reel] {
        let q = searchQuery.lowercased()
        guard !q.isEmpty else { return [] }
        return reels.filter {
            $0.task.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
                || $0.creator.lowercased().contains(q)
        }
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

    /// Set the app appearance, persist it, and apply it live across every window
    /// (panel, pill, vibrancy, NSAlerts) via the global `NSApp.appearance`.
    func setAppearance(_ a: AppAppearance) {
        appearance = a
        Theme.style = a.style
        UserDefaults.standard.set(a.rawValue, forKey: "appearance")
        NSApp?.appearance = a.nsAppearance
    }

    /// Cycle System → Light → Dark → Cyberpunk → Persona → System, for the Appearance button.
    func cycleAppearance() {
        let order = AppAppearance.allCases
        let next = order[(order.firstIndex(of: appearance).map { $0 + 1 } ?? 0) % order.count]
        setAppearance(next)
    }

    /// Drag-to-reorder: drop a folder at `index` in the shown order (clamped), renumber, and
    /// switch to Custom so the new order sticks.
    func moveFolder(_ folder: Folder, toIndex index: Int) {
        var ordered = sortedFolders
        guard let from = ordered.firstIndex(where: { $0.persistentModelID == folder.persistentModelID }) else { return }
        let dragged = ordered.remove(at: from)
        let clamped = max(0, min(index, ordered.count))
        ordered.insert(dragged, at: clamped)
        guard ordered.map(\.persistentModelID) != folders.map(\.persistentModelID) || folderSort != .custom else { return }
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
        // Back in the Inbox but stranded in Misc (e.g. its folder was deleted while it sat in the
        // archive)? Give the model another look so it can land in a folder or propose one.
        if !archived, needsResort(reel) { requestReclassify?(reel) }
    }

    /// A finished, non-manual post parked in Misc with no folder suggestion pending.
    func needsResort(_ reel: Reel) -> Bool {
        !reel.isManual && reel.status == .processed && reel.lastError == nil
            && reel.proposedFolderName == nil && (reel.folder == nil || reel.folder?.name == "Misc")
    }

    // MARK: Tracking (work timers)

    func isTracking(_ reel: Reel) -> Bool { reel.trackingStartedAt != nil }

    /// Start tracking with a running timer (no-op if already tracked, so it isn't reset).
    func startTracking(_ reel: Reel) {
        guard reel.trackingStartedAt == nil else { return }
        let now = Date()
        reel.trackingStartedAt = now
        reel.trackingRunningSince = now
        reel.trackingAccumulated = 0
        try? context.save()
        reload()
    }

    /// Stop tracking entirely — the item leaves the Tracking tab (the card itself is untouched).
    /// The session's elapsed time is banked into `trackingLoggedSeconds` so it isn't lost.
    func stopTracking(_ reel: Reel) {
        guard reel.trackingStartedAt != nil else { return }
        reel.trackingLoggedSeconds += reel.trackingElapsed() ?? 0
        reel.trackingStartedAt = nil
        reel.trackingRunningSince = nil
        reel.trackingAccumulated = 0
        try? context.save()
        reload()
    }

    /// Bank every running timer's current segment and pause it. Called on quit so time spent with
    /// the app closed isn't counted as worked time (a running timer would otherwise keep climbing).
    func pauseAllRunning() {
        let now = Date()
        var changed = false
        for reel in reels where reel.trackingRunningSince != nil {
            reel.trackingAccumulated += max(0, now.timeIntervalSince(reel.trackingRunningSince!))
            reel.trackingRunningSince = nil
            changed = true
        }
        if changed { try? context.save(); reload() }
    }

    func toggleTracking(_ reel: Reel) {
        reel.trackingStartedAt == nil ? startTracking(reel) : stopTracking(reel)
    }

    /// Pause the timer: bank the current running segment, keep the item on the tab.
    func pauseTracking(_ reel: Reel) {
        guard let since = reel.trackingRunningSince else { return }   // only when running
        reel.trackingAccumulated += max(0, Date().timeIntervalSince(since))
        reel.trackingRunningSince = nil
        try? context.save()
        reload()
    }

    /// Resume a paused timer (only if it's tracked and currently paused).
    func resumeTracking(_ reel: Reel) {
        guard reel.trackingStartedAt != nil, reel.trackingRunningSince == nil else { return }
        reel.trackingRunningSince = Date()
        try? context.save()
        reload()
    }

    /// Pause if running, resume if paused (no-op when not tracked).
    func togglePause(_ reel: Reel) {
        reel.trackingRunningSince == nil ? resumeTracking(reel) : pauseTracking(reel)
    }

    // MARK: Multi-select / bulk actions

    func enterSelection() { selectionMode = true; selection = [] }
    func exitSelection() { selectionMode = false; selection = [] }

    func isSelected(_ reel: Reel) -> Bool { selection.contains(reel.persistentModelID) }

    func toggleSelected(_ reel: Reel) {
        let id = reel.persistentModelID
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private var selectedReels: [Reel] { reels.filter { selection.contains($0.persistentModelID) } }

    /// Mark every selected card done (and clear its archive flag), then leave selection mode.
    func bulkComplete() {
        for r in selectedReels { r.status = .done; r.isArchived = false }
        finishBulk()
    }

    /// Archive every selected card (un-completing any that were done), then leave selection mode.
    func bulkArchive() {
        for r in selectedReels {
            r.isArchived = true
            if r.status == .done { r.status = .processed }
        }
        finishBulk()
    }

    /// Delete every selected card, then leave selection mode.
    func bulkDelete() {
        for r in selectedReels {
            processingIDs.remove(r.persistentModelID)
            context.delete(r)
        }
        finishBulk()
    }

    private func finishBulk() {
        try? context.save()
        exitSelection()
        reload()
    }

    /// Add a fresh "what I'm working on" entry straight to the Tracking tab — a manual card with
    /// its timer already running. Lands in Misc so it's also reachable from Home.
    @discardableResult
    func addTrackingItem(task: String) -> Reel {
        let reel = Reel(
            originalURLString: "",
            status: .processed,
            task: task.isEmpty ? "Working…" : task,
            summary: "",
            creator: "",
            folder: miscFolder
        )
        reel.isManual = true
        let now = Date()
        reel.trackingStartedAt = now
        reel.trackingRunningSince = now
        context.insert(reel)
        try? context.save()
        reload()
        flashGlow(.white)
        return reel
    }

    private var miscFolder: Folder? {
        folders.first { $0.name == "Misc" } ?? folders.last
    }

    /// See `ShareLink.normalizedURLString` (kept here so existing call sites read naturally).
    nonisolated static func normalizedURLString(_ raw: String) -> String {
        ShareLink.normalizedURLString(raw)
    }

    /// See `ShareLink.extractShareableURL`.
    nonisolated static func extractShareableURL(from raw: String) -> String? {
        ShareLink.extractShareableURL(from: raw)
    }

    /// Add a saved item from pasted/ingested text or URL. Accepts any supported platform
    /// (Instagram, LinkedIn, Handshake, TikTok, YouTube, X) and rejects unknown hosts. It lands in
    /// Misc as a `.new` placeholder; the extraction + LLM pipeline fills task/summary/folder.
    @discardableResult
    func addReel(urlString raw: String) -> Reel? {
        guard let trimmed = Self.extractShareableURL(from: raw) else {
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

    /// Re-run processing for a reel that errored (e.g. after turning on Apple Intelligence, or
    /// once a platform rate-limit passes). Resets it to a fresh `.new` state and re-enqueues.
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
    /// Look the folder back up by name (not persistentModelID): the id captured here is the
    /// pre-save *temporary* one, which SwiftData swaps for a permanent id on `save()` — so an
    /// id match would fail and the icon would never upgrade. Names are unique, so they're safe.
    private func resolveAIIcon(for folder: Folder) {
        guard resolvesAIIcons else { return }
        let name = folder.name
        Task {
            guard let symbol = await FolderIcon.aiSuggestion(for: name),
                  let target = folders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
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
        // Accept scheme-less links (e.g. "google.com") by normalizing to https first, so a typed
        // link isn't silently dropped.
        if let link, !link.isEmpty {
            let normalized = Self.normalizedURLString(link)
            if let url = URL(string: normalized), url.scheme != nil, url.host() != nil {
                let model = ReelLink(urlString: normalized, label: "link")
                context.insert(model)
                model.reel = reel
            }
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
