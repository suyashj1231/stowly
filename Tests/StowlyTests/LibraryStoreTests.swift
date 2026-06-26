import Testing
import Foundation
import SwiftData
@testable import Stowly

/// Exercises LibraryStore's mutation + query logic against an in-memory store, covering the
/// behaviours shipped across the project: folder CRUD, Instagram-only ingestion, manual cards,
/// shelf bucketing, drag-reorder, archive/complete transitions, and the notch-offset setting.
@MainActor
struct LibraryStoreTests {

    /// Empty in-memory store with a single "Misc" fallback folder (the bucket addReel/addManual
    /// drop into and that deleteFolder migrates orphans to).
    private func storeWithMisc() -> (LibraryStore, Folder) {
        let store = LibraryStore.inMemory()
        let misc = Folder(name: "Misc", symbol: "tray.full.fill", isUserCreated: true, sortOrder: 99)
        store.context.insert(misc)
        try? store.context.save()
        store.reload()
        return (store, misc)
    }

    // MARK: addReel (ingestion)

    @Test func addReelAcceptsInstagramAndLandsInMisc() {
        let (store, _) = storeWithMisc()
        let reel = store.addReel(urlString: "https://www.instagram.com/reel/abc")
        #expect(reel != nil)
        #expect(reel?.status == .new)
        #expect(reel?.folder?.name == "Misc")
        #expect(store.reels.count == 1)
    }

    @Test func addReelAcceptsOtherSupportedPlatforms() {
        let (store, _) = storeWithMisc()
        #expect(store.addReel(urlString: "https://www.tiktok.com/@x/video/1") != nil)
        #expect(store.addReel(urlString: "https://www.linkedin.com/posts/x") != nil)
        #expect(store.reels.count == 2)
    }

    @Test func addReelRejectsUnsupportedHost() {
        let (store, _) = storeWithMisc()
        #expect(store.addReel(urlString: "https://example.com/x") == nil)
        #expect(store.reels.isEmpty)
    }

    @Test func addReelExtractsLinkFromSharedText() {
        // LinkedIn/X share the post as text containing a link — the store should still ingest it,
        // storing the clean URL and resolving the platform.
        let (store, _) = storeWithMisc()
        let shared = "Great opportunity!\nhttps://www.linkedin.com/posts/xyz-123 #hiring"
        let reel = store.addReel(urlString: shared)
        #expect(reel?.originalURLString == "https://www.linkedin.com/posts/xyz-123")
        #expect(reel?.platform == .linkedin)
    }

    @Test func addReelDedupesSameURL() {
        let (store, _) = storeWithMisc()
        _ = store.addReel(urlString: "https://www.instagram.com/reel/abc")
        #expect(store.addReel(urlString: "https://www.instagram.com/reel/abc") == nil)
        #expect(store.reels.count == 1)
    }

    // MARK: addManualReel

    @Test func manualReelIsProcessedAndManual() {
        let (store, _) = storeWithMisc()
        let reel = store.addManualReel(task: "Buy milk", link: nil)
        #expect(reel.isManual)
        #expect(reel.status == .processed)
        #expect(reel.folder?.name == "Misc")
        #expect(reel.links.isEmpty)
    }

    @Test func manualReelNormalizesSchemelessLink() {
        let (store, _) = storeWithMisc()
        let reel = store.addManualReel(task: "Shop", link: "google.com")
        #expect(reel.links.count == 1)
        #expect(reel.links.first?.urlString == "https://google.com")
    }

    @Test func manualReelDropsUnparseableLink() {
        let (store, _) = storeWithMisc()
        let reel = store.addManualReel(task: "x", link: "not a url")
        #expect(reel.links.isEmpty)
    }

    @Test func manualReelEmptyTaskGetsPlaceholder() {
        let (store, _) = storeWithMisc()
        #expect(store.addManualReel(task: "", link: nil).task == "New note")
    }

    // MARK: createFolder

    @Test func createFolderTrimsAndPicksHeuristicIcon() {
        let (store, _) = storeWithMisc()
        let folder = store.createFolder(name: "  Gym  ")
        #expect(folder?.name == "Gym")
        #expect(folder?.symbol == "dumbbell.fill")   // heuristic mapping
    }

    @Test func createFolderRejectsDuplicatesCaseInsensitively() {
        let (store, _) = storeWithMisc()
        _ = store.createFolder(name: "Gym")
        #expect(store.createFolder(name: "gym") == nil)
        #expect(store.createFolder(name: "  GYM ") == nil)
    }

    @Test func createFolderRejectsEmpty() {
        let (store, _) = storeWithMisc()
        #expect(store.createFolder(name: "   ") == nil)
    }

    // MARK: deleteFolder

    @Test func deleteFolderMigratesReelsToMisc() {
        let (store, misc) = storeWithMisc()
        let gym = store.createFolder(name: "Gym")!
        let reel = Reel(originalURLString: "https://instagram.com/reel/1", status: .new, folder: gym)
        store.context.insert(reel)
        try? store.context.save()
        store.reload()

        store.deleteFolder(gym)
        #expect(!store.folders.contains { $0.name == "Gym" })
        #expect(reel.folder?.persistentModelID == misc.persistentModelID)
    }

    @Test func miscFolderCannotBeDeleted() {
        let (store, misc) = storeWithMisc()
        store.deleteFolder(misc)
        #expect(store.folders.contains { $0.name == "Misc" })
    }

    // MARK: shelf bucketing

    @Test func shelfClassificationAndCounts() {
        let (store, misc) = storeWithMisc()
        let active = Reel(originalURLString: "https://instagram.com/reel/a", status: .processed, folder: misc)
        let done = Reel(originalURLString: "https://instagram.com/reel/d", status: .done, folder: misc)
        let archived = Reel(originalURLString: "https://instagram.com/reel/r", status: .new, folder: misc)
        archived.isArchived = true
        [active, done, archived].forEach(store.context.insert)
        try? store.context.save()
        store.reload()

        #expect(store.shelf(of: active) == .active)
        #expect(store.shelf(of: done) == .completed)     // done wins over folder
        #expect(store.shelf(of: archived) == .archived)
        #expect(store.count(for: .active) == 1)
        #expect(store.count(for: .completed) == 1)
        #expect(store.count(for: .archived) == 1)
        #expect(store.reels(in: misc).count == 3)
        #expect(store.reels(in: misc, shelf: .active).count == 1)
    }

    // MARK: complete / archive transitions

    @Test func completingSetsDoneAndClearsArchive() {
        let (store, misc) = storeWithMisc()
        let reel = Reel(originalURLString: "https://instagram.com/reel/x", status: .processed, folder: misc)
        reel.isArchived = true
        store.context.insert(reel); try? store.context.save(); store.reload()

        store.setCompleted(reel, true)
        #expect(reel.status == .done)
        #expect(reel.isArchived == false)   // completing supersedes archive
    }

    @Test func archivingADoneReelUncompletesIt() {
        let (store, misc) = storeWithMisc()
        let reel = Reel(originalURLString: "https://instagram.com/reel/x", status: .done, folder: misc)
        store.context.insert(reel); try? store.context.save(); store.reload()

        store.setArchived(reel, true)
        #expect(reel.isArchived)
        #expect(reel.status == .processed)  // archiving un-completes
    }

    // MARK: ordering

    @Test func moveFolderUpReordersAndSwitchesToCustom() {
        let store = LibraryStore.inMemory()
        let a = Folder(name: "Alpha", symbol: "", isUserCreated: true, sortOrder: 0)
        let b = Folder(name: "Beta", symbol: "", isUserCreated: true, sortOrder: 1)
        [a, b].forEach(store.context.insert)
        try? store.context.save()
        store.setFolderSort(.nameAsc)
        store.reload()

        store.moveFolder(b, up: true)
        #expect(store.folders.map(\.name) == ["Beta", "Alpha"])
        #expect(store.folderSort == .custom)
    }

    @Test func sortedFoldersHonorsNameAscending() {
        let store = LibraryStore.inMemory()
        let z = Folder(name: "Zeta", symbol: "", isUserCreated: true, sortOrder: 0)
        let a = Folder(name: "Alpha", symbol: "", isUserCreated: true, sortOrder: 1)
        [z, a].forEach(store.context.insert)
        try? store.context.save()
        store.reload()

        store.setFolderSort(.nameAsc)
        #expect(store.sortedFolders.map(\.name) == ["Alpha", "Zeta"])
        store.setFolderSort(.nameDesc)
        #expect(store.sortedFolders.map(\.name) == ["Zeta", "Alpha"])
    }

    // MARK: notch offset setting

    @Test func notchOffsetClampsToRange() {
        let store = LibraryStore.inMemory()
        store.setNotchTopOffset(50)
        #expect(store.notchTopOffset == 50)
        store.setNotchTopOffset(999)
        #expect(store.notchTopOffset == 120)   // clamped high
        store.setNotchTopOffset(-30)
        #expect(store.notchTopOffset == 0)     // clamped low
    }

    @Test func notchOffsetNudgeAndReset() {
        let store = LibraryStore.inMemory()
        store.setNotchTopOffset(40)
        store.nudgeNotchOffset(by: 4)
        #expect(store.notchTopOffset == 44)
        store.nudgeNotchOffset(by: -8)
        #expect(store.notchTopOffset == 36)
        store.resetNotchTopOffset()
        #expect(store.notchTopOffset == Theme.notchTopClearance)
    }

    // MARK: appearance setting

    @Test func appearanceDefaultsToDark() {
        let store = LibraryStore.inMemory()
        #expect(store.appearance == .dark)
    }

    @Test func appearancePersistsAndReloads() {
        UserDefaults.standard.removeObject(forKey: "appearance")
        defer { UserDefaults.standard.removeObject(forKey: "appearance") }

        // Write-through setter records the choice in UserDefaults…
        let store = LibraryStore.inMemory()
        store.setAppearance(.light)
        #expect(store.appearance == .light)
        #expect(UserDefaults.standard.string(forKey: "appearance") == "light")

        // …and a fresh store that loads preferences reads it back.
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Reel.self, Folder.self, ReelLink.self, configurations: config)
        let reloaded = LibraryStore(container: container, loadPreferences: true)
        #expect(reloaded.appearance == .light)
    }

    @Test func appearanceCyclesSystemLightDark() {
        let store = LibraryStore.inMemory()
        store.setAppearance(.system)
        store.cycleAppearance()
        #expect(store.appearance == .light)
        store.cycleAppearance()
        #expect(store.appearance == .dark)
        store.cycleAppearance()
        #expect(store.appearance == .system)
    }
}
