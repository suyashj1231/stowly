import Foundation

/// Phone → Mac ingestion bridge over a free public pub/sub relay (ntfy.sh).
///
/// An iOS Shortcut in the reel's Share Sheet POSTs the reel URL to a secret, per-user topic
/// (`https://ntfy.sh/<topic>`). This class holds a streaming subscription to that topic and
/// turns each new URL into a Reel via the same path as the menu-bar clipboard import.
///
/// No account, no cloud storage. ntfy.sh caches messages server-side (~12h), so reels saved
/// while the Mac was asleep are caught up on reconnect via `?since=<last-id>`. The topic is
/// the only secret: it's generated at runtime, stored in UserDefaults, and never committed.
@MainActor
final class InboxRelay {
    private let store: LibraryStore
    private let queue: ProcessingQueue

    private static let topicKey = "ntfyTopic"
    private static let lastIdKey = "ntfyLastId"
    private static let ingestedKey = "ntfyIngestedIds"
    private static let maxIngested = 500

    /// Per-user secret topic, e.g. `stowly-8f3kd91 za…`. Created once, then reused (existing
    /// users keep their previously-generated topic — it's persisted in UserDefaults).
    let topic: String

    /// The address the iOS Shortcut POSTs reel URLs to.
    var publishURL: String { "https://ntfy.sh/\(topic)" }

    /// Message ids we've already ingested — persisted so a reel you delete never comes back
    /// when ntfy replays its cache on reconnect. Capped; ordered oldest→newest.
    private var ingestedIds: [String]
    private var ingestedSet: Set<String>

    private var task: Task<Void, Never>?

    init(store: LibraryStore, queue: ProcessingQueue) {
        self.store = store
        self.queue = queue

        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.topicKey), !existing.isEmpty {
            topic = existing
        } else {
            let generated = Self.makeTopic()
            defaults.set(generated, forKey: Self.topicKey)
            topic = generated
        }

        ingestedIds = defaults.stringArray(forKey: Self.ingestedKey) ?? []
        ingestedSet = Set(ingestedIds)

        // One-time upgrade: older builds advanced `lastId` on keepalive events, whose ids
        // ntfy can't resolve — so reconnecting replayed the whole cache and re-added reels you
        // had deleted. If we've never recorded ingested ids, reset the high-water mark to now
        // so already-handled reels aren't re-imported.
        if defaults.object(forKey: Self.ingestedKey) == nil, defaults.string(forKey: Self.lastIdKey) != nil {
            defaults.set(String(Int(Date().timeIntervalSince1970)), forKey: Self.lastIdKey)
        }
    }

    /// Start the long-lived subscription. Safe to call once on launch.
    func start() {
        guard task == nil else { return }
        task = Task { await self.runLoop() }
    }

    // MARK: - Subscription loop

    private func runLoop() async {
        var backoff: UInt64 = 2_000_000_000   // 2s, capped at 30s
        while !Task.isCancelled {
            do {
                try await connectAndStream()
                backoff = 2_000_000_000        // clean end → reset backoff
            } catch is CancellationError {
                return
            } catch {
                // Network hiccup / server dropped the stream → wait and reconnect. Because we
                // reconnect with `?since=<lastId>`, nothing published in the gap is lost.
                try? await Task.sleep(nanoseconds: backoff)
                backoff = min(backoff * 2, 30_000_000_000)
            }
        }
    }

    /// Opens one streaming connection and processes lines until it ends or errors.
    private func connectAndStream() async throws {
        let since = UserDefaults.standard.string(forKey: Self.lastIdKey)
            ?? String(Int(Date().timeIntervalSince1970))   // first run: only future messages

        var comps = URLComponents(string: "https://ntfy.sh/\(topic)/json")!
        comps.queryItems = [URLQueryItem(name: "since", value: since)]

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 360   // ntfy keepalives (~45s) reset this
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)

        let (bytes, response) = try await session.bytes(from: comps.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // ntfy `/json` is newline-delimited JSON: one event object per line.
        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(NtfyEvent.self, from: data)
            else { continue }

            // Only real messages advance the high-water mark — keepalive/open events carry
            // synthetic ids that ntfy can't resolve as `since`, which would replay the cache.
            guard event.event == "message", let message = event.message else { continue }
            UserDefaults.standard.set(event.id, forKey: Self.lastIdKey)

            // Skip anything we've already taken in once (so deletes stay deleted on replay).
            guard !ingestedSet.contains(event.id) else { continue }
            markIngested(event.id)
            ingest(message)
        }
    }

    // MARK: - Ingestion

    /// Turn a received message into a Reel. Reuses the clipboard-import path: `addReel`
    /// validates the `instagram.com` host and dedupes against the DB, returning nil for
    /// junk/duplicates — so garbage or injected messages on the public topic are dropped.
    private func ingest(_ message: String) {
        guard let reel = store.addReel(urlString: message) else { return }
        queue.enqueue(reel)
        // Passive arrival: no notch auto-expand. The green glow + card spinner are the cue.
    }

    /// Record a message id as ingested (persisted, capped to the most recent `maxIngested`).
    private func markIngested(_ id: String) {
        ingestedSet.insert(id)
        ingestedIds.append(id)
        if ingestedIds.count > Self.maxIngested {
            let drop = ingestedIds.count - Self.maxIngested
            ingestedIds.prefix(drop).forEach { ingestedSet.remove($0) }
            ingestedIds.removeFirst(drop)
        }
        UserDefaults.standard.set(ingestedIds, forKey: Self.ingestedKey)
    }

    // MARK: - Topic

    private static func makeTopic() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let suffix = (0..<16).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] }
        return "stowly-" + String(suffix)
    }
}

/// A single line from ntfy's `/json` stream. We only care about `message` events;
/// `open` and `keepalive` events are ignored (but still advance the high-water mark).
private struct NtfyEvent: Decodable {
    let id: String
    let event: String
    let message: String?
}
