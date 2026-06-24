import Testing
import Foundation
@testable import Stowly

/// Library search: matches task / summary / creator, case-insensitively, across all folders.
@MainActor
struct SearchTests {

    private func store(with reels: [(task: String, summary: String, creator: String)]) -> LibraryStore {
        let s = LibraryStore.inMemory()
        let misc = Folder(name: "Misc", symbol: "tray.full.fill", isUserCreated: true, sortOrder: 0)
        s.context.insert(misc)
        for r in reels {
            let reel = Reel(originalURLString: "https://instagram.com/reel/\(UUID().uuidString)",
                            status: .processed, task: r.task, summary: r.summary, creator: r.creator, folder: misc)
            s.context.insert(reel)
        }
        try? s.context.save(); s.reload()
        return s
    }

    @Test func emptyQueryReturnsNothing() {
        let s = store(with: [("Apply to Stripe", "", "@jobs")])
        #expect(s.searchResults().isEmpty)
    }

    @Test func matchesTaskCaseInsensitively() {
        let s = store(with: [("Apply to Stripe", "", "@jobs"), ("Cook pasta", "", "@chef")])
        s.setSearchQuery("STRIPE")
        let results = s.searchResults()
        #expect(results.count == 1)
        #expect(results.first?.task == "Apply to Stripe")
    }

    @Test func matchesSummaryAndCreator() {
        let s = store(with: [
            ("Task A", "a funded fellowship in AI", "@amaan"),
            ("Task B", "unrelated", "@other"),
        ])
        s.setSearchQuery("fellowship")
        #expect(s.searchResults().count == 1)
        s.setSearchQuery("amaan")
        #expect(s.searchResults().count == 1)
    }

    @Test func nonMatchingQueryReturnsEmpty() {
        let s = store(with: [("Apply to Stripe", "", "@jobs")])
        s.setSearchQuery("nonexistent")
        #expect(s.searchResults().isEmpty)
    }

    @Test func setSearchQueryTrims() {
        let s = store(with: [("Apply to Stripe", "", "@jobs")])
        s.setSearchQuery("  stripe  ")
        #expect(s.searchQuery == "stripe")
        #expect(s.searchResults().count == 1)
    }
}
