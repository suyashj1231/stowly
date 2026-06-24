import Testing
@testable import Stowly

/// The platform model: host detection, capability flags, and display/asset metadata. These pin the
/// multi-platform contract (which hosts are accepted, which extract fully vs link-only, which use
/// @handles) so v2 behaviour can't silently regress.
struct PlatformTests {

    // MARK: detection

    @Test func detectsEachPlatformFromHost() {
        #expect(Platform.detect(from: "https://www.instagram.com/reel/x") == .instagram)
        #expect(Platform.detect(from: "https://www.linkedin.com/posts/x") == .linkedin)
        #expect(Platform.detect(from: "https://lnkd.in/abc") == .linkedin)
        #expect(Platform.detect(from: "https://joinhandshake.com/jobs/1") == .handshake)
        #expect(Platform.detect(from: "https://www.tiktok.com/@x/video/1") == .tiktok)
        #expect(Platform.detect(from: "https://youtu.be/x") == .youtube)
        #expect(Platform.detect(from: "https://m.youtube.com/shorts/x") == .youtube)
        #expect(Platform.detect(from: "https://twitter.com/x/status/1") == .twitter)
        #expect(Platform.detect(from: "https://x.com/x/status/1") == .twitter)
    }

    @Test func unknownAndLookAlikeHostsAreWeb() {
        #expect(Platform.detect(from: "https://example.com") == .web)
        #expect(Platform.detect(from: "https://instagram.com.evil.com/x") == .web)
        #expect(Platform.detect(from: "https://notlinkedin.com/x") == .web)
        #expect(Platform.detect(from: "") == .web)
    }

    @Test func detectIsSchemeless() {
        #expect(Platform.detect(from: "tiktok.com/@a/video/1") == .tiktok)
    }

    // MARK: capability flags

    @Test func onlySupportedPlatformsAreSharable() {
        for p in Platform.allCases {
            #expect(p.isSupportedShare == (p != .web))
        }
    }

    @Test func extractCapability() {
        #expect(Platform.instagram.canExtract)
        #expect(Platform.tiktok.canExtract)
        #expect(Platform.youtube.canExtract)
        #expect(Platform.twitter.canExtract)
        #expect(Platform.linkedin.canExtract)
        #expect(!Platform.handshake.canExtract)   // login-gated → link-only
        #expect(!Platform.web.canExtract)
    }

    @Test func atHandlePlatforms() {
        #expect(Platform.instagram.usesAtHandle)
        #expect(Platform.tiktok.usesAtHandle)
        #expect(Platform.youtube.usesAtHandle)
        #expect(Platform.twitter.usesAtHandle)
        #expect(!Platform.linkedin.usesAtHandle)   // real names
        #expect(!Platform.handshake.usesAtHandle)
    }

    // MARK: metadata

    @Test func displayNamesAndAssetsArePresent() {
        for p in Platform.allCases {
            #expect(!p.displayName.isEmpty)
            #expect(p.logoAsset == "logo-\(p.rawValue)")
        }
    }
}
