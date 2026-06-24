import Testing
import Foundation
@testable import ReelPlanner

/// A canned LLM provider for pipeline tests: returns a fixed understanding (or throws), no
/// network. `needsVideo` defaults false so the stub extractor's text path is exercised.
private struct StubProvider: LLMProvider {
    var result: Result<ReelUnderstanding, Error>
    func understand(_ input: ReelInput, folders: [String]) async throws -> ReelUnderstanding {
        try result.get()
    }
}

private struct StubError: Error {}

/// Integration coverage for ReelProcessor: the folder-proposal/link logic in `apply`, and the
/// full `process` path driven by a stub extractor + stub provider (so no Python/network runs).
@MainActor
struct ReelProcessorApplyTests {

    /// In-memory store seeded with Misc + a couple of real folders to classify into.
    private func makeStore() -> LibraryStore {
        let store = LibraryStore.inMemory()
        [
            Folder(name: "Apply Jobs", symbol: "briefcase.fill", isUserCreated: true, sortOrder: 0),
            Folder(name: "Learn / Certs", symbol: "graduationcap.fill", isUserCreated: true, sortOrder: 1),
            Folder(name: "Misc", symbol: "tray.full.fill", isUserCreated: true, sortOrder: 2),
        ].forEach(store.context.insert)
        try? store.context.save()
        store.reload()
        return store
    }

    private func newReel(in store: LibraryStore) -> Reel {
        let misc = store.folders.first { $0.name == "Misc" }
        let reel = Reel(originalURLString: "https://instagram.com/reel/x", status: .new, folder: misc)
        store.context.insert(reel)
        try? store.context.save()
        store.reload()
        return reel
    }

    private func raw(creator: String = "creator") -> ReelRawData {
        ReelRawData(originalURL: "https://instagram.com/reel/x", creator: creator,
                    caption: "cap", transcript: "trans", videoPath: nil, imagePath: nil)
    }

    private func understanding(
        folder: String, isNew: Bool = false, newName: String? = nil,
        links: [ReelUnderstanding.Link] = []
    ) -> ReelUnderstanding {
        ReelUnderstanding(task: "Do thing", summary: "Summary.", links: links,
                          suggested_folder: folder, is_new_folder: isNew, new_folder_name: newName)
    }

    // MARK: apply — folder classification

    @Test func matchesExistingFolderCaseInsensitively() {
        let store = makeStore()
        let reel = newReel(in: store)
        ReelProcessor.apply(raw: raw(), understanding: understanding(folder: "apply jobs"), to: reel, store: store)
        #expect(reel.folder?.name == "Apply Jobs")
        #expect(reel.proposedFolderName == nil)
        #expect(reel.status == .processed)
    }

    @Test func unknownFolderParksInMiscWithProposal() {
        let store = makeStore()
        let reel = newReel(in: store)
        ReelProcessor.apply(raw: raw(), understanding: understanding(folder: "Recipes", isNew: true, newName: "Recipes"),
                            to: reel, store: store)
        #expect(reel.folder?.name == "Misc")
        #expect(reel.proposedFolderName == "Recipes")
    }

    @Test func proposalFallsBackToSuggestedWhenNotFlaggedNew() {
        let store = makeStore()
        let reel = newReel(in: store)
        // is_new_folder false, but the suggested folder doesn't exist → still offer to create it.
        ReelProcessor.apply(raw: raw(), understanding: understanding(folder: "Travel", isNew: false), to: reel, store: store)
        #expect(reel.folder?.name == "Misc")
        #expect(reel.proposedFolderName == "Travel")
    }

    @Test func neverProposesMisc() {
        let store = makeStore()
        let reel = newReel(in: store)
        ReelProcessor.apply(raw: raw(), understanding: understanding(folder: "Unmatched", isNew: true, newName: "Misc"),
                            to: reel, store: store)
        #expect(reel.proposedFolderName == nil)
    }

    @Test func neverProposesEmptyName() {
        let store = makeStore()
        let reel = newReel(in: store)
        ReelProcessor.apply(raw: raw(), understanding: understanding(folder: "Unmatched", isNew: true, newName: "   "),
                            to: reel, store: store)
        #expect(reel.proposedFolderName == nil)
    }

    @Test func neverProposesAnExistingFolder() {
        let store = makeStore()
        let reel = newReel(in: store)
        // Proposed new name collides with an existing folder → no proposal (it already exists).
        ReelProcessor.apply(raw: raw(), understanding: understanding(folder: "Unmatched", isNew: true, newName: "Apply Jobs"),
                            to: reel, store: store)
        #expect(reel.proposedFolderName == nil)
        #expect(reel.folder?.name == "Misc")
    }

    // MARK: apply — links, creator, fields

    @Test func replacesLinksAndSkipsEmptyURLs() {
        let store = makeStore()
        let reel = newReel(in: store)
        // Pre-existing link that should be cleared.
        let old = ReelLink(urlString: "https://old.com", label: "old")
        store.context.insert(old); old.reel = reel
        try? store.context.save(); store.reload()

        ReelProcessor.apply(
            raw: raw(),
            understanding: understanding(folder: "Misc", links: [
                .init(label: "apply", url: "https://new.com/apply"),
                .init(label: "empty", url: ""),                 // dropped
            ]),
            to: reel, store: store
        )
        #expect(reel.links.count == 1)
        #expect(reel.links.first?.urlString == "https://new.com/apply")
    }

    @Test func normalizesCreatorAndPopulatesRawFields() {
        let store = makeStore()
        let reel = newReel(in: store)
        ReelProcessor.apply(raw: raw(creator: "amaansbuilds"), understanding: understanding(folder: "Misc"),
                            to: reel, store: store)
        #expect(reel.creator == "@amaansbuilds")
        #expect(reel.caption == "cap")
        #expect(reel.transcript == "trans")
        #expect(reel.lastError == nil)
    }

    @Test func successClearsPriorError() {
        let store = makeStore()
        let reel = newReel(in: store)
        reel.lastError = "previous failure"
        ReelProcessor.apply(raw: raw(), understanding: understanding(folder: "Misc"), to: reel, store: store)
        #expect(reel.lastError == nil)
    }

    // MARK: process — full pipeline with stubs

    @Test func processSuccessClassifiesAndProcesses() async {
        let store = makeStore()
        let reel = newReel(in: store)
        let provider = StubProvider(result: .success(understanding(folder: "Learn / Certs",
                                                                   links: [.init(label: "x", url: "https://x.com")])))
        await ReelProcessor.process(reel, store: store, provider: provider) { _, _ in self.raw() }

        #expect(reel.status == .processed)
        #expect(reel.folder?.name == "Learn / Certs")
        #expect(reel.links.count == 1)
        #expect(reel.lastError == nil)
    }

    @Test func processExtractFailureRecordsError() async {
        let store = makeStore()
        let reel = newReel(in: store)
        let provider = StubProvider(result: .success(understanding(folder: "Misc")))
        // Extractor throws → reel should land in an error state with a non-empty task (so it isn't
        // auto-retried every launch) and a retry-able lastError.
        await ReelProcessor.process(reel, store: store, provider: provider) { _, _ in throw StubError() }

        #expect(reel.task == "Couldn't read reel")
        #expect(reel.lastError != nil)
        #expect(reel.status != .processed)
    }

    @Test func processUnderstandFailureRecordsError() async {
        let store = makeStore()
        let reel = newReel(in: store)
        let provider = StubProvider(result: .failure(StubError()))
        await ReelProcessor.process(reel, store: store, provider: provider) { _, _ in self.raw() }

        #expect(reel.lastError != nil)
        #expect(reel.status != .processed)
    }
}
