import Testing
import SwiftUI
@testable import Stowly

/// Guards the data-model contracts the UI and persistence depend on: status round-trips,
/// tab labels (the Queue→Home rename lives here), URL fallbacks, and per-folder accents.
struct ModelTests {

    // MARK: ReelStatus (persisted as rawValue)

    @Test func reelStatusRawValuesAreStable() {
        // These strings are written to the store; changing them would orphan existing data.
        #expect(ReelStatus.new.rawValue == "new")
        #expect(ReelStatus.processed.rawValue == "processed")
        #expect(ReelStatus.done.rawValue == "done")
    }

    @Test func reelStatusRoundTrips() {
        for status in ReelStatus.allCases {
            #expect(ReelStatus(rawValue: status.rawValue) == status)
        }
    }

    @Test func unknownStatusRawDefaultsToNew() {
        // Reel.status getter falls back to .new for an unrecognized stored value.
        let reel = Reel(originalURLString: "https://instagram.com/reel/x")
        reel.statusRaw = "garbage"
        #expect(reel.status == .new)
    }

    @Test func reelStatusSetterWritesRaw() {
        let reel = Reel(originalURLString: "https://instagram.com/reel/x")
        reel.status = .done
        #expect(reel.statusRaw == "done")
        reel.status = .processed
        #expect(reel.statusRaw == "processed")
    }

    // MARK: Shelf (tab) labels & symbols

    @Test func shelfTitlesAreStable() {
        #expect(Shelf.active.title == "Home")        // renamed from "Queue" — keep it Home
        #expect(Shelf.archived.title == "Archive")
        #expect(Shelf.completed.title == "Done")
    }

    @Test func shelfSymbolsAreStable() {
        #expect(Shelf.active.symbol == "house")
        #expect(Shelf.archived.symbol == "archivebox")
        #expect(Shelf.completed.symbol == "checkmark.circle")
    }

    @Test func shelfHasThreeTabs() {
        #expect(Shelf.allCases.count == 3)
    }

    // MARK: URL conveniences (never crash on bad input)

    @Test func reelOriginalURLFallsBackWhenEmpty() {
        #expect(Reel(originalURLString: "").originalURL == URL(string: "https://instagram.com")!)
    }

    @Test func reelOriginalURLPreservesValidString() {
        let reel = Reel(originalURLString: "https://www.instagram.com/reel/abc")
        #expect(reel.originalURL == URL(string: "https://www.instagram.com/reel/abc")!)
    }

    @Test func reelLinkURLFallsBackWhenInvalid() {
        #expect(ReelLink(urlString: "", label: "x").url == URL(string: "https://instagram.com")!)
    }

    // MARK: Reel.platform (derived from URL)

    @Test func reelPlatformDerivedFromURL() {
        #expect(Reel(originalURLString: "https://www.instagram.com/reel/x").platform == .instagram)
        #expect(Reel(originalURLString: "https://www.linkedin.com/posts/x").platform == .linkedin)
        #expect(Reel(originalURLString: "https://youtu.be/x").platform == .youtube)
    }

    @Test func manualCardPlatformIsWeb() {
        // Empty URL (manual card) → no platform branding.
        #expect(Reel(originalURLString: "").platform == .web)
    }

    // MARK: Folder accent

    @Test func knownFoldersGetDistinctAccents() {
        let learn = Folder(name: "Learn / Certs", symbol: "", isUserCreated: true, sortOrder: 0)
        let jobs = Folder(name: "Apply Jobs", symbol: "", isUserCreated: true, sortOrder: 1)
        #expect(learn.accent != jobs.accent)
        #expect(jobs.accent != Theme.foregroundMuted)
    }

    @Test func unknownFolderUsesMutedAccent() {
        let misc = Folder(name: "Whatever", symbol: "", isUserCreated: true, sortOrder: 0)
        #expect(misc.accent == Theme.foregroundMuted)
    }
}
