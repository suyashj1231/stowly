import Testing
import Foundation
@testable import Stowly

/// The Tracking tab: work timers on items. Covers the model helpers, the store's start/stop/toggle
/// + add-to-tracking logic (a cross-cutting filter, not a shelf bucket), and the elapsed formatter.
@MainActor
struct TrackingTests {

    private func storeWithMisc() -> (LibraryStore, Folder) {
        let store = LibraryStore.inMemory()
        let misc = Folder(name: "Misc", symbol: "tray.full.fill", isUserCreated: true, sortOrder: 99)
        store.context.insert(misc)
        try? store.context.save()
        store.reload()
        return (store, misc)
    }

    private func reel(in store: LibraryStore, _ misc: Folder, status: ReelStatus = .processed) -> Reel {
        let r = Reel(originalURLString: "https://instagram.com/reel/x", status: status, folder: misc)
        store.context.insert(r); try? store.context.save(); store.reload()
        return r
    }

    // MARK: model helpers

    @Test func isTrackingAndElapsed() {
        let r = Reel(originalURLString: "")
        #expect(!r.isTracking)
        #expect(r.trackingElapsed() == nil)

        r.trackingStartedAt = Date()
        r.trackingRunningSince = Date().addingTimeInterval(-90)
        #expect(r.isTracking)
        #expect(r.isTrackingRunning)
        let elapsed = r.trackingElapsed() ?? 0
        #expect(elapsed >= 89 && elapsed <= 92)
    }

    // MARK: store start / stop / toggle

    @Test func startTrackingAddsToTrackedList() {
        let (store, misc) = storeWithMisc()
        let r = reel(in: store, misc)
        #expect(store.trackedReels.isEmpty)

        store.startTracking(r)
        #expect(store.isTracking(r))
        #expect(r.isTrackingRunning)
        #expect(store.trackedReels.count == 1)
        #expect(store.count(for: .tracking) == 1)
        #expect(r.trackingStartedAt != nil)
    }

    // MARK: pause / resume

    @Test func pauseAndResumeKeepItemTracked() {
        let (store, misc) = storeWithMisc()
        let r = reel(in: store, misc)
        store.startTracking(r)
        #expect(r.isTrackingRunning)

        store.pauseTracking(r)
        #expect(!r.isTrackingRunning)
        #expect(r.isTrackingPaused)
        #expect(store.isTracking(r))            // still on the Tracking tab while paused
        #expect(store.trackedReels.count == 1)

        store.resumeTracking(r)
        #expect(r.isTrackingRunning)

        store.stopTracking(r)
        #expect(!store.isTracking(r))
        #expect(store.trackedReels.isEmpty)
    }

    @Test func pauseBanksElapsedAndFreezesIt() {
        let (store, misc) = storeWithMisc()
        let r = reel(in: store, misc)
        store.startTracking(r)
        r.trackingRunningSince = Date().addingTimeInterval(-30)   // pretend 30s have run
        store.pauseTracking(r)

        #expect(r.trackingAccumulated >= 29 && r.trackingAccumulated <= 32)
        #expect(r.trackingRunningSince == nil)
        let frozen = r.trackingElapsed() ?? 0
        #expect(frozen >= 29 && frozen <= 32)   // doesn't keep climbing while paused
    }

    @Test func togglePauseFlipsRunningState() {
        let (store, misc) = storeWithMisc()
        let r = reel(in: store, misc)
        store.startTracking(r)
        store.togglePause(r)
        #expect(r.isTrackingPaused)
        store.togglePause(r)
        #expect(r.isTrackingRunning)
    }

    // MARK: logged time (survives stop) + pause-on-quit

    @Test func stopLogsWorkedTime() {
        let (store, misc) = storeWithMisc()
        let r = reel(in: store, misc)
        store.startTracking(r)
        r.trackingRunningSince = Date().addingTimeInterval(-45)   // ~45s worked
        store.stopTracking(r)

        #expect(!store.isTracking(r))                 // left the tab
        #expect(r.trackingLoggedSeconds >= 44 && r.trackingLoggedSeconds <= 47)
    }

    @Test func loggedTimeAccumulatesAcrossSessions() {
        let (store, misc) = storeWithMisc()
        let r = reel(in: store, misc)
        store.startTracking(r)
        r.trackingRunningSince = Date().addingTimeInterval(-20)
        store.stopTracking(r)
        store.startTracking(r)
        r.trackingRunningSince = Date().addingTimeInterval(-10)
        store.stopTracking(r)
        #expect(r.trackingLoggedSeconds >= 29 && r.trackingLoggedSeconds <= 33)
    }

    @Test func pauseAllRunningFreezesTimersOnQuit() {
        let (store, misc) = storeWithMisc()
        let a = reel(in: store, misc)
        let b = reel(in: store, misc)
        store.startTracking(a)
        store.startTracking(b)
        store.pauseTracking(b)                        // b already paused
        a.trackingRunningSince = Date().addingTimeInterval(-60)

        store.pauseAllRunning()
        #expect(!a.isTrackingRunning)                 // running timer frozen
        #expect(a.isTracking)                         // still tracked (paused), not stopped
        #expect(a.trackingAccumulated >= 59 && a.trackingAccumulated <= 62)
        #expect(!b.isTrackingRunning)                 // already-paused stays paused
    }

    @Test func startTrackingIsIdempotent() {
        let (store, misc) = storeWithMisc()
        let r = reel(in: store, misc)
        store.startTracking(r)
        let firstStart = r.trackingStartedAt
        store.startTracking(r)   // must NOT reset the timer
        #expect(r.trackingStartedAt == firstStart)
    }

    @Test func stopTrackingRemovesFromList() {
        let (store, misc) = storeWithMisc()
        let r = reel(in: store, misc)
        store.startTracking(r)
        store.stopTracking(r)
        #expect(!store.isTracking(r))
        #expect(store.trackedReels.isEmpty)
        #expect(store.count(for: .tracking) == 0)
    }

    @Test func toggleTracking() {
        let (store, misc) = storeWithMisc()
        let r = reel(in: store, misc)
        store.toggleTracking(r)
        #expect(store.isTracking(r))
        store.toggleTracking(r)
        #expect(!store.isTracking(r))
    }

    @Test func trackingIsCrossCutting() {
        // A tracked item still lives in its normal shelf/folder — tracking doesn't move it.
        let (store, misc) = storeWithMisc()
        let r = reel(in: store, misc, status: .processed)
        store.startTracking(r)
        #expect(store.shelf(of: r) == .active)
        #expect(store.reels(in: misc).contains { $0.persistentModelID == r.persistentModelID })
    }

    @Test func trackedReelsSortedMostRecentFirst() {
        let (store, misc) = storeWithMisc()
        let a = reel(in: store, misc)
        let b = reel(in: store, misc)
        a.trackingStartedAt = Date().addingTimeInterval(-600)  // older
        b.trackingStartedAt = Date()                            // newer
        try? store.context.save(); store.reload()
        #expect(store.trackedReels.first?.persistentModelID == b.persistentModelID)
    }

    // MARK: add-to-tracking entry

    @Test func addTrackingItemCreatesRunningManualCard() {
        let (store, _) = storeWithMisc()
        let r = store.addTrackingItem(task: "Apply to Stripe")
        #expect(r.task == "Apply to Stripe")
        #expect(r.isManual)
        #expect(r.isTracking)
        #expect(r.isTrackingRunning)   // starts running
        #expect(r.status == .processed)
        #expect(store.trackedReels.count == 1)
        #expect(r.folder?.name == "Misc")
    }

    @Test func addTrackingItemEmptyGetsPlaceholder() {
        let (store, _) = storeWithMisc()
        #expect(store.addTrackingItem(task: "").task == "Working…")
    }

    // MARK: elapsed formatting

    @Test func elapsedFormatting() {
        #expect(elapsedString(seconds: 0) == "0:00")
        #expect(elapsedString(seconds: 65) == "1:05")
        #expect(elapsedString(seconds: 3599) == "59:59")
        #expect(elapsedString(seconds: 3661) == "1:01:01")
        #expect(elapsedString(seconds: -5) == "0:00")   // clamps negatives
    }
}
