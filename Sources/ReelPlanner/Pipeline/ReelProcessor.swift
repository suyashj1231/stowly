import Foundation

/// Orchestrates a single reel through the full pipeline:
/// extract (yt-dlp + Whisper) -> understand (LLM) -> persist, flipping status .new -> .processed.
/// SwiftData mutations happen on the main actor; the heavy I/O is awaited off-main.
@MainActor
enum ReelProcessor {
    static func process(_ reel: Reel, store: LibraryStore, provider: LLMProvider = AIConfig.provider) async {
        let urlString = reel.originalURLString
        let folderNames = store.folders.map(\.name)

        do {
            let raw = try await ReelExtractor.extract(urlString: urlString, needsVideo: provider.needsVideo)
            // Multimodal providers download the clip; delete it once we're done with it.
            defer {
                if let path = raw.videoPath { try? FileManager.default.removeItem(atPath: path) }
            }
            let understanding = try await provider.understand(
                ReelInput(
                    caption: raw.caption,
                    transcript: raw.transcript,
                    creator: raw.creator,
                    videoURL: raw.videoPath.map { URL(fileURLWithPath: $0) }
                ),
                folders: folderNames
            )
            apply(raw: raw, understanding: understanding, to: reel, store: store)
        } catch {
            // Mark with a non-empty task so it isn't auto-retried every launch; the user
            // can still re-run it manually from the detail view.
            reel.task = "Couldn't read reel"
            reel.summary = friendlyError(error)
            try? store.context.save()
            store.reload()
        }
    }

    private static func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.contains("could not connect") || msg.contains("Connection refused") {
            return "AI model isn't reachable. Is Ollama running? (ollama serve)"
        }
        if msg.lowercased().contains("login") || msg.contains("rate-limit") {
            return "Instagram blocked the fetch (rate-limit/login). Try again shortly."
        }
        return "Processing failed — \(msg)"
    }

    private static func apply(
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

        // Folder: match an existing one; otherwise (AI proposed new) park in Misc for now —
        // the new-folder *approval* UI lands in a later step.
        if let match = store.folders.first(where: { $0.name.caseInsensitiveCompare(u.suggested_folder) == .orderedSame }) {
            reel.folder = match
        } else {
            reel.folder = store.folders.first { $0.name == "Misc" } ?? store.folders.last
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

    private static func normalizedHandle(_ creator: String) -> String {
        let trimmed = creator.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("@") ? trimmed : "@" + trimmed
    }
}
