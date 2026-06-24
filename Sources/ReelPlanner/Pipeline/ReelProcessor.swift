import Foundation

/// Orchestrates a single reel through the full pipeline:
/// extract (yt-dlp + Whisper) -> understand (LLM) -> persist, flipping status .new -> .processed.
/// SwiftData mutations happen on the main actor; the heavy I/O is awaited off-main.
@MainActor
enum ReelProcessor {
    /// `extract` is injectable so the pipeline can be tested with a stub (the default shells out
    /// to the bundled Python helper). Signature matches `ReelExtractor.extract`.
    static func process(
        _ reel: Reel,
        store: LibraryStore,
        provider: LLMProvider = AIConfig.provider,
        extract: (_ urlString: String, _ needsVideo: Bool) async throws -> ReelRawData = ReelExtractor.extract
    ) async {
        let urlString = reel.originalURLString
        let folderNames = store.folders.map(\.name)

        do {
            let raw = try await extract(urlString, provider.needsVideo)
            // Multimodal providers download the clip/image; delete it once we're done with it.
            defer {
                if let path = raw.videoPath { try? FileManager.default.removeItem(atPath: path) }
                if let path = raw.imagePath { try? FileManager.default.removeItem(atPath: path) }
            }
            let understanding = try await provider.understand(
                ReelInput(
                    caption: raw.caption,
                    transcript: raw.transcript,
                    creator: raw.creator,
                    videoURL: raw.videoPath.map { URL(fileURLWithPath: $0) },
                    imageURL: raw.imagePath.map { URL(fileURLWithPath: $0) }
                ),
                folders: folderNames
            )
            apply(raw: raw, understanding: understanding, to: reel, store: store)
        } catch {
            // Mark with a non-empty task + lastError so it isn't auto-retried every launch; the
            // user can re-run it with the card's retry button (e.g. after restarting Ollama).
            let message = friendlyError(error)
            reel.task = "Couldn't read reel"
            reel.summary = message
            reel.lastError = message
            try? store.context.save()
            store.reload()
        }
    }

    nonisolated static func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.contains("could not connect") || msg.contains("Connection refused") {
            return "AI model isn't reachable. Is Ollama running? (ollama serve)"
        }
        if msg.lowercased().contains("login") || msg.contains("rate-limit") {
            return "Instagram blocked the fetch (rate-limit/login). Try again shortly."
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
        reel.creator = normalizedHandle(raw.creator)
        reel.task = u.task
        reel.summary = u.summary
        reel.lastError = nil          // success clears any prior error

        // Folder: prefer an existing match. If the AI proposed a genuinely new folder, park the
        // reel in Misc but remember the proposal so the card can offer to create it (approval).
        if let match = store.folders.first(where: { $0.name.caseInsensitiveCompare(u.suggested_folder) == .orderedSame }) {
            reel.folder = match
            reel.proposedFolderName = nil
        } else {
            reel.folder = store.folders.first { $0.name == "Misc" } ?? store.folders.last
            let proposed = (u.is_new_folder ? u.new_folder_name : nil) ?? u.suggested_folder
            let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
            // Don't propose "Misc" or an empty/already-existing name.
            let exists = store.folders.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
            reel.proposedFolderName = (trimmed.isEmpty || exists || trimmed.caseInsensitiveCompare("Misc") == .orderedSame) ? nil : trimmed
        }

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

    nonisolated static func normalizedHandle(_ creator: String) -> String {
        let trimmed = creator.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("@") ? trimmed : "@" + trimmed
    }
}
