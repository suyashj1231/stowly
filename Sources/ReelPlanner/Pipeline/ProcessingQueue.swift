import Foundation

/// Serializes reel processing (one at a time, so the local model isn't thrashed) and keeps
/// the store's transient `processingIDs` / `glowToken` in sync to drive the notch UI.
@MainActor
final class ProcessingQueue {
    private let store: LibraryStore
    private var pending: [Reel] = []
    private var running = false
    /// Whether the current run of the queue saw any failure (drives green-vs-red at the end).
    private var batchHadError = false

    init(store: LibraryStore) {
        self.store = store
    }

    func enqueue(_ reel: Reel) {
        guard !store.isProcessing(reel),
              !pending.contains(where: { $0.persistentModelID == reel.persistentModelID })
        else { return }
        pending.append(reel)
        pump()
    }

    /// Re-queue any reels that were added but never finished parsing (e.g. app quit mid-run).
    func enqueuePending() {
        store.pendingReels().forEach(enqueue)
    }

    private func pump() {
        guard !running, !pending.isEmpty else { return }
        running = true
        let reel = pending.removeFirst()

        Task {
            store.processingIDs.insert(reel.persistentModelID)
            await ReelProcessor.process(reel, store: store)
            store.processingIDs.remove(reel.persistentModelID)

            if reel.status == .processed {
                // Success — no per-reel glow; the green flashes when the whole queue drains.
            } else {
                store.flashGlow(.red)     // this reel errored
                batchHadError = true
            }

            running = false
            if pending.isEmpty {
                if !batchHadError { store.flashGlow(.green) }   // whole queue finished cleanly
                batchHadError = false
                await AIConfig.provider.idle()   // batch done → free the model from memory
            } else {
                pump()
            }
        }
    }
}
