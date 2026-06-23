import Foundation

/// Serializes reel processing (one at a time, so the local model isn't thrashed) and keeps
/// the store's transient `processingIDs` / glow in sync to drive the notch UI.
@MainActor
final class ProcessingQueue {
    private let store: LibraryStore
    private var pending: [Reel] = []
    private var running = false
    /// Per-run bookkeeping for the end-of-queue glow.
    private var batchHadError = false
    private var batchProcessed = 0

    init(store: LibraryStore) {
        self.store = store
    }

    func enqueue(_ reel: Reel) {
        guard isLive(reel),
              !store.isProcessing(reel),
              !pending.contains(where: { $0.persistentModelID == reel.persistentModelID })
        else { return }
        pending.append(reel)
        pump()
    }

    /// Re-queue any reels that were added but never finished parsing (e.g. app quit mid-run).
    func enqueuePending() {
        store.pendingReels().forEach(enqueue)
    }

    /// Still present in the store? (Reels deleted while queued must be skipped.)
    private func isLive(_ reel: Reel) -> Bool {
        store.reels.contains { $0.persistentModelID == reel.persistentModelID }
    }

    private func pump() {
        guard !running else { return }
        // Drop any reels deleted while waiting in the queue.
        pending.removeAll { !isLive($0) }
        guard !pending.isEmpty else { finishBatch(); return }

        running = true
        let reel = pending.removeFirst()

        Task {
            store.processingIDs.insert(reel.persistentModelID)
            await ReelProcessor.process(reel, store: store)
            store.processingIDs.remove(reel.persistentModelID)
            // Ignore reels deleted mid-flight (no spurious red glow / batch count).
            if isLive(reel) {
                batchProcessed += 1
                if reel.status != .processed {
                    store.flashGlow(.red)   // this reel errored
                    batchHadError = true
                }
            }
            running = false
            pump()
        }
    }

    /// Called when the queue drains. Flash green only if something actually completed cleanly.
    private func finishBatch() {
        guard batchProcessed > 0 else { return }   // nothing ran (e.g. all were deleted)
        if !batchHadError { store.flashGlow(.green) }   // whole queue finished cleanly
        batchProcessed = 0
        batchHadError = false
        Task { await AIConfig.provider.idle() }         // free the local model from memory
    }
}
