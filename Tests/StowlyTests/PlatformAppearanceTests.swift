import Testing
import SwiftUI
@testable import Stowly
import StowlyShared

/// Guards the platform branding contract used by the badge + open button: Instagram is the only
/// gradient brand, every supported platform has a distinct non-muted accent, and `.web` stays
/// neutral (no branding on manual cards).
struct PlatformAppearanceTests {

    @Test func onlyInstagramHasAGradient() {
        #expect(Platform.instagram.gradient != nil)
        for p in Platform.allCases where p != .instagram {
            #expect(p.gradient == nil)
        }
    }

    @Test func webUsesNeutralAccent() {
        #expect(Platform.web.accent == Theme.foregroundMuted)
    }

    @Test func brandedPlatformsHaveNonMutedAccents() {
        let branded: [Platform] = [.instagram, .linkedin, .handshake, .tiktok, .youtube, .twitter]
        for p in branded {
            #expect(p.accent != Theme.foregroundMuted)
        }
    }

    @Test func accentsAreDistinctAcrossPlatforms() {
        // A couple of representative pairs should not collide.
        #expect(Platform.linkedin.accent != Platform.youtube.accent)
        #expect(Platform.handshake.accent != Platform.instagram.accent)
    }
}
