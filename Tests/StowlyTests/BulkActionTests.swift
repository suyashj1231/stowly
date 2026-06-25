import Testing
import Foundation
@testable import Stowly

/// Multi-select + bulk actions: complete / archive / delete on a selected set, then auto-exit.
@MainActor
struct BulkActionTests {

    private func storeWith3() -> (LibraryStore, Folder, [Reel]) {
        let store = LibraryStore.inMemory()
        let misc = Folder(name: "Misc", symbol: "tray.full.fill", isUserCreated: true, sortOrder: 0)
        store.context.insert(misc)
        let reels = (0..<3).map { i -> Reel in
            let r = Reel(originalURLString: "https://instagram.com/reel/\(i)", status: .processed, folder: misc)
            store.context.insert(r); return r
        }
        try? store.context.save(); store.reload()
        return (store, misc, reels)
    }

    @Test func selectionToggles() {
        let (store, _, reels) = storeWith3()
        store.enterSelection()
        #expect(store.selectionMode)
        store.toggleSelected(reels[0])
        store.toggleSelected(reels[1])
        #expect(store.isSelected(reels[0]))
        #expect(store.selection.count == 2)
        store.toggleSelected(reels[0])           // deselect
        #expect(!store.isSelected(reels[0]))
        #expect(store.selection.count == 1)
    }

    @Test func bulkCompleteMarksSelectedDoneAndExits() {
        let (store, _, reels) = storeWith3()
        store.enterSelection()
        store.toggleSelected(reels[0])
        store.toggleSelected(reels[1])
        store.bulkComplete()

        #expect(reels[0].status == .done)
        #expect(reels[1].status == .done)
        #expect(reels[2].status == .processed)   // untouched
        #expect(!store.selectionMode)            // auto-exits
        #expect(store.selection.isEmpty)
    }

    @Test func bulkArchiveArchivesSelected() {
        let (store, _, reels) = storeWith3()
        store.enterSelection()
        store.toggleSelected(reels[2])
        store.bulkArchive()

        #expect(reels[2].isArchived)
        #expect(store.count(for: .archived) == 1)
        #expect(!store.selectionMode)
    }

    @Test func bulkDeleteRemovesSelected() {
        let (store, _, reels) = storeWith3()
        store.enterSelection()
        store.toggleSelected(reels[0])
        store.toggleSelected(reels[1])
        store.bulkDelete()

        #expect(store.reels.count == 1)
        #expect(store.reels.first?.persistentModelID == reels[2].persistentModelID)
        #expect(!store.selectionMode)
    }

    @Test func exitSelectionClearsState() {
        let (store, _, reels) = storeWith3()
        store.enterSelection()
        store.toggleSelected(reels[0])
        store.exitSelection()
        #expect(!store.selectionMode)
        #expect(store.selection.isEmpty)
    }
}
