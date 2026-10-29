import Testing
import Foundation
@testable import Stowly

/// A canned provider for pipeline tests: returns a fixed understanding (or throws), no model.
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
                    caption: "cap", transcript: "trans", videoPath: nil, imagePaths: [])
    }

    private func understanding(
        folder: String, isNew: Bool = false, newName: String? = nil,
        links: [ReelUnderstanding.Link] = []
    ) -> ReelUnderstanding {
        ReelUnderstanding(task: "Do thing", summary: "Summary.", links: links,
                          suggested_folder: folder, is_new_folder: isNew, new_folder_name: newName)
    }

    // MARK: reclassify — re-sort a restored post from saved text

    /// A processed post stranded in Misc, with real task/summary text to keep.
    private func strandedReel(in store: LibraryStore) -> Reel {
        let reel = newReel(in: store)
        reel.status = .processed
        reel.task = "Apply for Google internship"
        reel.summary = "Applications close Friday."
        reel.caption = "We're hiring interns"
        try? store.context.save()
        store.reload()
        return reel
    }

    @Test func reclassifyMovesStrandedReelIntoMatchingFolder() async {
        let store = makeStore()
        let reel = strandedReel(in: store)
        let other = understanding(folder: "Apply Jobs")
        await ReelProcessor.reclassify(reel, store: store, provider: StubProvider(result: .success(other)))
        #expect(reel.folder?.name == "Apply Jobs")
        #expect(reel.task == "Apply for Google internship")   // only the folder changes
        #expect(reel.summary == "Applications close Friday.")
    }

    @Test func reclassifyCanProposeANewFolder() async {
        let store = makeStore()
        let reel = strandedReel(in: store)
        let u = understanding(folder: "Misc", isNew: true, newName: "Hackathons")
        await ReelProcessor.reclassify(reel, store: store, provider: StubProvider(result: .success(u)))
        #expect(reel.folder?.name == "Misc")
        #expect(reel.proposedFolderName == "Hackathons")
    }

    @Test func reclassifyFailureLeavesCardUntouched() async {
        let store = makeStore()
        let reel = strandedReel(in: store)
        await ReelProcessor.reclassify(reel, store: store, provider: StubProvider(result: .failure(StubError())))
        #expect(reel.folder?.name == "Misc")
        #expect(reel.task == "Apply for Google internship")
        #expect(reel.lastError == nil)
        #expect(reel.status == .processed)
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

    @Test func proposesNewFolderEvenWhenSuggestedIsExistingMisc() {
        let store = makeStore()
        let reel = newReel(in: store)
        // Real-world model output: it parks suggested_folder on the closest existing folder
        // ("Misc") but flags a brand-new folder. The new-folder proposal must win, not be
        // discarded by the "Misc" match — otherwise everything lands in Misc with no suggestion.
        ReelProcessor.apply(raw: raw(), understanding: understanding(folder: "Misc", isNew: true, newName: "Hackathons"),
                            to: reel, store: store)
        #expect(reel.folder?.name == "Misc")
        #expect(reel.proposedFolderName == "Hackathons")
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
        // Extractor throws on every call (incl. the meta-only fallback) → error state with a
        // non-empty platform-named task and a retry-able lastError.
        await ReelProcessor.process(reel, store: store, provider: provider) { _, _ in throw StubError() }

        #expect(reel.task == "Couldn't read Instagram")
        #expect(reel.lastError != nil)
        #expect(reel.status != .processed)
    }

    @Test func processUnderstandFailureRecordsError() async {
        let store = makeStore()
        let reel = newReel(in: store)
        // Extraction succeeds but the LLM fails → transient, so leave a retryable error card
        // (do NOT silently degrade to a bare title for an extractable platform).
        let provider = StubProvider(result: .failure(StubError()))
        await ReelProcessor.process(reel, store: store, provider: provider) { _, _ in self.raw() }

        #expect(reel.lastError != nil)
        #expect(reel.status != .processed)
    }

    @Test func linkOnlyPlatformProducesCardFromMetadata() async {
        let store = makeStore()
        // Handshake is link-only (canExtract == false): metadata-only path, no error even though
        // the LLM is unavailable — it degrades to a basic title card.
        let misc = store.folders.first { $0.name == "Misc" }
        let reel = Reel(originalURLString: "https://joinhandshake.com/jobs/42", status: .new, folder: misc)
        store.context.insert(reel); try? store.context.save(); store.reload()

        let provider = StubProvider(result: .failure(StubError()))
        await ReelProcessor.process(reel, store: store, provider: provider) { _, metaOnly in
            #expect(metaOnly)   // link-only platforms always use the meta-only path
            return self.raw(creator: "Career Center")
        }

        #expect(reel.status == .processed)
        #expect(reel.lastError == nil)
        #expect(!reel.task.isEmpty)
        #expect(reel.creator == "Career Center")   // name kept as-is (no @) for Handshake
    }

    @Test func linkOnlyEmptyScrapeStillSavesLinkCard() async {
        let store = makeStore()
        let misc = store.folders.first { $0.name == "Misc" }
        let reel = Reel(originalURLString: "https://joinhandshake.com/jobs/7", status: .new, folder: misc)
        store.context.insert(reel); try? store.context.save(); store.reload()

        // Scrape returns nothing usable (login-gated) AND the LLM is down — the link must still
        // be saved as a basic card so nothing is lost.
        let provider = StubProvider(result: .failure(StubError()))
        await ReelProcessor.process(reel, store: store, provider: provider) { _, _ in
            ReelRawData(originalURL: "https://joinhandshake.com/jobs/7", creator: "", caption: "",
                        transcript: "", videoPath: nil, imagePaths: [])
        }
        #expect(reel.status == .processed)
        #expect(reel.lastError == nil)
        #expect(reel.task == "Handshake post")
    }

    @Test func linkOnlyExtractFailureStillSavesLinkCard() async {
        let store = makeStore()
        let misc = store.folders.first { $0.name == "Misc" }
        let reel = Reel(originalURLString: "https://joinhandshake.com/jobs/8", status: .new, folder: misc)
        store.context.insert(reel); try? store.context.save(); store.reload()

        // Even when the scrape itself throws, a link-only platform never errors — the URL is kept.
        let provider = StubProvider(result: .success(understanding(folder: "Misc")))
        await ReelProcessor.process(reel, store: store, provider: provider) { _, _ in throw StubError() }
        #expect(reel.status == .processed)
        #expect(reel.lastError == nil)
        #expect(reel.task == "Handshake post")
    }
}
