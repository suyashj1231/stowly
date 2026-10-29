import Foundation
import StowlyShared

/// Orchestrates a single reel through the full pipeline:
/// extract (yt-dlp) -> understand (on-device model) -> persist, flipping status .new -> .processed.
/// SwiftData mutations happen on the main actor; the heavy I/O is awaited off-main.
@MainActor
enum ReelProcessor {
    /// `extract` is injectable so the pipeline can be tested with a stub (the default shells out
    /// to the bundled Python helper). Signature matches `ReelExtractor.extract`.
    static func process(
        _ reel: Reel,
        store: LibraryStore,
        provider: LLMProvider = AIConfig.provider,
        extract: (_ urlString: String, _ metaOnly: Bool) async throws -> ReelRawData = ReelExtractor.extract
    ) async {
        let platform = reel.platform

        // Link-only platforms (Handshake, unknown) skip yt-dlp: scrape metadata and
        // categorize from the title/caption. Nothing to retry, so no error card — and if even the
        // scrape comes back empty (login-gated), still save the shared link as a basic card.
        guard platform.canExtract else {
            if await processLinkOnly(reel, store: store, provider: provider, extract: extract) == false {
                saveLinkCard(reel, platform: platform, store: store)
            }
            return
        }

        // 1) Extract. A *fetch* failure (yt-dlp can't reach/parse the post) degrades to a
        //    metadata-only link card so nothing is lost; only a truly empty scrape errors out.
        let raw: ReelRawData
        do {
            raw = try await extract(reel.originalURLString, false)
        } catch {
            if await processLinkOnly(reel, store: store, provider: provider, extract: extract) { return }
            recordError(error, on: reel, platform: platform, store: store)
            return
        }
        // The clip/image was downloaded for on-device processing; delete it once we're done.
        defer {
            if let path = raw.videoPath { try? FileManager.default.removeItem(atPath: path) }
            for path in raw.imagePaths { try? FileManager.default.removeItem(atPath: path) }
        }

        // 2) Understand. A model failure here is usually transient (Apple Intelligence off/busy), so
        //    leave a retryable error card rather than silently degrading to a bare title.
        do {
            let understanding = try await provider.understand(
                ReelInput(
                    caption: raw.caption,
                    transcript: raw.transcript,
                    creator: raw.creator,
                    platform: platform.displayName,
                    videoURL: raw.videoPath.map { URL(fileURLWithPath: $0) },
                    imageURLs: raw.imagePaths.map { URL(fileURLWithPath: $0) }
                ),
                folders: store.folders.map(\.name)
            )
            apply(raw: raw, understanding: understanding, to: reel, store: store)
        } catch {
            recordError(error, on: reel, platform: platform, store: store)
        }
    }

    /// Save a bare link card when there's no metadata at all (login-gated link-only platforms).
    /// The post URL is preserved (it's `reel.originalURLString`), so "Open on …" still works.
    private static func saveLinkCard(_ reel: Reel, platform: Platform, store: LibraryStore) {
        let empty = ReelRawData(originalURL: reel.originalURLString, creator: "", caption: "",
                                transcript: "", videoPath: nil, imagePaths: [])
        apply(raw: empty, understanding: basicUnderstanding(from: empty, platform: platform),
              to: reel, store: store)
    }

    /// Leave a non-empty task + `lastError` so the reel isn't auto-retried every launch; the user
    /// re-runs it with the card's retry button (e.g. after turning on Apple Intelligence).
    private static func recordError(_ error: Error, on reel: Reel, platform: Platform, store: LibraryStore) {
        let message = friendlyError(error, platform: platform)
        reel.task = "Couldn't read \(platform.displayName)"
        reel.summary = message
        reel.lastError = message
        try? store.context.save()
        store.reload()
    }

    /// Metadata-only path: scrape the page's title/caption (no video/transcript) and categorize.
    /// Used for link-only platforms and as the graceful fallback when full extraction fails.
    /// Returns true when it produced a card, false when there was nothing usable to save.
    @discardableResult
    private static func processLinkOnly(
        _ reel: Reel,
        store: LibraryStore,
        provider: LLMProvider,
        extract: (_ urlString: String, _ metaOnly: Bool) async throws -> ReelRawData
    ) async -> Bool {
        let platform = reel.platform
        guard let raw = try? await extract(reel.originalURLString, true) else { return false }
        // Nothing scraped at all (e.g. login-gated with no public OG) → can't build a useful card.
        if raw.caption.isEmpty, raw.creator.isEmpty { return false }
        defer {
            for path in raw.imagePaths { try? FileManager.default.removeItem(atPath: path) }
        }

        // Try the LLM on the scraped text; fall back to a plain title card if it's unavailable.
        let understanding: ReelUnderstanding
        if let llm = try? await provider.understand(
            ReelInput(caption: raw.caption, transcript: raw.transcript, creator: raw.creator,
                      platform: platform.displayName),
            folders: store.folders.map(\.name)
        ) {
            understanding = llm
        } else {
            understanding = basicUnderstanding(from: raw, platform: platform)
        }
        apply(raw: raw, understanding: understanding, to: reel, store: store)
        return true
    }

    /// A no-LLM understanding built straight from scraped metadata (offline / LLM-down fallback).
    private static func basicUnderstanding(from raw: ReelRawData, platform: Platform) -> ReelUnderstanding {
        let firstLine = raw.caption.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let task = firstLine.isEmpty ? "\(platform.displayName) post" : String(firstLine.prefix(80))
        return ReelUnderstanding(task: task, summary: raw.caption, links: [],
                                 suggested_folder: "Misc", is_new_folder: false, new_folder_name: nil)
    }

    nonisolated static func friendlyError(_ error: Error, platform: Platform) -> String {
        let msg = error.localizedDescription
        if case LLMError.appleIntelligenceOff = error { return msg }
        if msg.lowercased().contains("login") || msg.contains("rate-limit") {
            return "\(platform.displayName) blocked the fetch (rate-limit/login). Try again shortly."
        }
        return "Processing failed — \(msg)"
    }

    static func apply(
        raw: ReelRawData,
        understanding u: ReelUnderstanding,
        to reel: Reel,
        store: LibraryStore
    ) {
        reel.caption = raw.caption
        reel.transcript = raw.transcript
        reel.creator = normalizedHandle(raw.creator, platform: reel.platform)
        reel.task = u.task
        reel.summary = u.summary
        reel.lastError = nil          // success clears any prior error

        assignFolder(u, to: reel, store: store)

        // Replace any prior links with the freshly extracted ones.
        for old in reel.links { store.context.delete(old) }
        for link in u.links where !link.url.isEmpty {
            let model = ReelLink(urlString: link.url, label: link.label)
            store.context.insert(model)
            model.reel = reel
        }

        reel.status = .processed
        try? store.context.save()
        store.reload()
    }

    /// Re-sort a reel that's stuck in Misc (e.g. its folder was deleted) from what we already
    /// saved — caption, transcript, task — without re-downloading. Only the folder/proposal is
    /// touched; a model failure leaves the card exactly as it was.
    static func reclassify(_ reel: Reel, store: LibraryStore, provider: LLMProvider = AIConfig.provider) async {
        let caption = [reel.caption ?? "", reel.task, reel.summary]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !caption.isEmpty,
              let u = try? await provider.understand(
                  ReelInput(caption: caption, transcript: reel.transcript ?? "", creator: reel.creator,
                            platform: reel.platform.displayName, videoURL: nil),
                  folders: store.folders.map(\.name)
              ),
              store.reels.contains(where: { $0.persistentModelID == reel.persistentModelID })
        else { return }
        assignFolder(u, to: reel, store: store)
        try? store.context.save()
        store.reload()
    }

    /// Folder classification. The model fills `suggested_folder` with the closest EXISTING
    /// folder (often "Misc") even while flagging a brand-new folder via is_new_folder +
    /// new_folder_name — so an explicit new-folder proposal must win over a suggested_folder
    /// that merely happens to match an existing folder. Otherwise a reel the model wanted in a
    /// new "Hackathons" folder silently lands in Misc with the proposal discarded.
    private static func assignFolder(_ u: ReelUnderstanding, to reel: Reel, store: LibraryStore) {
        let existingMatch = store.folders.first { $0.name.caseInsensitiveCompare(u.suggested_folder) == .orderedSame }

        // The name we'd offer to create: the explicit new-folder name when flagged, else the
        // suggested folder (covers a model that names an unknown folder without setting the flag).
        // Suppress empty, "Misc", and already-existing names.
        let proposed = (u.is_new_folder ? u.new_folder_name : nil) ?? u.suggested_folder
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let proposalExists = store.folders.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        let validProposal = !(trimmed.isEmpty || proposalExists || trimmed.caseInsensitiveCompare("Misc") == .orderedSame)

        if u.is_new_folder, validProposal {
            // Model explicitly wants a new folder → park in Misc and offer to create it, ignoring
            // suggested_folder (it's just the closest existing fallback).
            reel.folder = store.folders.first { $0.name == "Misc" } ?? store.folders.last
            reel.proposedFolderName = trimmed
        } else if let match = existingMatch {
            reel.folder = match
            reel.proposedFolderName = nil
        } else {
            // suggested_folder names a folder we don't have and it wasn't flagged new → park in
            // Misc, still offering to create the name when it's a valid one.
            reel.folder = store.folders.first { $0.name == "Misc" } ?? store.folders.last
            reel.proposedFolderName = validProposal ? trimmed : nil
        }
    }

    /// Normalize a creator string. Handle-style platforms (Instagram/TikTok/YouTube/X) get an `@`
    /// prefix; LinkedIn/Handshake use real names, so they're left as-is.
    nonisolated static func normalizedHandle(_ creator: String, platform: Platform) -> String {
        let trimmed = creator.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        guard platform.usesAtHandle else { return trimmed }
        return trimmed.hasPrefix("@") ? trimmed : "@" + trimmed
    }
}
