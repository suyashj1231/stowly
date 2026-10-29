import Testing
@testable import Stowly
import StowlyShared

/// Guards URL handling: scheme-less links must be salvaged (a past bug silently dropped them)
/// and platform detection must match the *host*, not merely contain the word (a past bug let
/// look-alike hosts through).
struct URLNormalizationTests {

    // MARK: normalizedURLString

    @Test func prependsHTTPSWhenSchemeMissing() {
        #expect(LibraryStore.normalizedURLString("instagram.com/reel/abc") == "https://instagram.com/reel/abc")
        #expect(LibraryStore.normalizedURLString("google.com") == "https://google.com")
    }

    @Test func keepsExistingScheme() {
        #expect(LibraryStore.normalizedURLString("https://instagram.com/reel/abc") == "https://instagram.com/reel/abc")
        #expect(LibraryStore.normalizedURLString("http://example.com") == "http://example.com")
    }

    @Test func trimsWhitespace() {
        #expect(LibraryStore.normalizedURLString("  https://instagram.com/reel/abc \n") == "https://instagram.com/reel/abc")
    }

    @Test func emptyStaysEmpty() {
        #expect(LibraryStore.normalizedURLString("") == "")
        #expect(LibraryStore.normalizedURLString("   ") == "")
    }

    // MARK: platform detection (host-strict)

    @Test func detectsInstagramHosts() {
        #expect(Platform.detect(from: "https://www.instagram.com/reel/abc") == .instagram)
        #expect(Platform.detect(from: "https://instagram.com/reel/abc") == .instagram)
        // Scheme-less still detected (normalized first).
        #expect(Platform.detect(from: "instagram.com/reel/abc") == .instagram)
    }

    @Test func rejectsLookAlikeHosts() {
        #expect(Platform.detect(from: "https://notinstagram.com/reel/abc") == .web)
        #expect(Platform.detect(from: "https://instagram.com.evil.com/reel/abc") == .web)
        #expect(Platform.detect(from: "https://evil.com/?u=instagram.com") == .web)
    }

    @Test func detectsOtherSupportedPlatforms() {
        #expect(Platform.detect(from: "https://youtube.com/watch?v=abc") == .youtube)
        #expect(Platform.detect(from: "https://youtu.be/abc") == .youtube)
        #expect(Platform.detect(from: "https://www.tiktok.com/@x/video/1") == .tiktok)
        #expect(Platform.detect(from: "https://x.com/x/status/1") == .twitter)
        #expect(Platform.detect(from: "https://www.linkedin.com/posts/x") == .linkedin)
        #expect(Platform.detect(from: "https://joinhandshake.com/jobs/1") == .handshake)
    }

    @Test func unknownHostsAreWeb() {
        #expect(Platform.detect(from: "https://example.com/x") == .web)
        #expect(Platform.detect(from: "") == .web)
    }

    // MARK: extractShareableURL — pull a link out of shared text

    @Test func extractsURLFromSharedText() {
        // LinkedIn / X share the post as text containing a link, not a bare URL.
        let shared = "Check out this role:\nhttps://www.linkedin.com/posts/abc-123 #hiring"
        #expect(LibraryStore.extractShareableURL(from: shared) == "https://www.linkedin.com/posts/abc-123")
    }

    @Test func extractsBareSchemelessURL() {
        #expect(LibraryStore.extractShareableURL(from: "instagram.com/reel/x") == "https://instagram.com/reel/x")
    }

    @Test func stripsTrailingPunctuation() {
        #expect(LibraryStore.extractShareableURL(from: "see (https://x.com/a/status/1).") == "https://x.com/a/status/1")
    }

    @Test func rejectsTextWithNoSupportedURL() {
        #expect(LibraryStore.extractShareableURL(from: "just some text") == nil)
        #expect(LibraryStore.extractShareableURL(from: "read https://example.com/x now") == nil)
        #expect(LibraryStore.extractShareableURL(from: "") == nil)
    }

    @Test func extractsFirstOfMultipleURLs() {
        let s = "https://x.com/a/status/1 and https://youtube.com/watch?v=2"
        #expect(LibraryStore.extractShareableURL(from: s) == "https://x.com/a/status/1")
    }

    @Test func preservesQueryAndFragment() {
        let s = "https://www.youtube.com/watch?v=abc&t=10s"
        #expect(LibraryStore.extractShareableURL(from: s) == s)
    }

    @Test func extractsLnkdInShortLink() {
        #expect(LibraryStore.extractShareableURL(from: "FYI https://lnkd.in/abc123") == "https://lnkd.in/abc123")
    }
}
