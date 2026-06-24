import Testing
@testable import ReelPlanner

/// Guards URL handling: scheme-less links must be salvaged (a past bug silently dropped them)
/// and Instagram detection must match the *host*, not merely contain the word (a past bug let
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

    // MARK: isInstagramURLString

    @Test func acceptsInstagramHosts() {
        #expect(LibraryStore.isInstagramURLString("https://www.instagram.com/reel/abc"))
        #expect(LibraryStore.isInstagramURLString("https://instagram.com/reel/abc"))
        // Scheme-less still accepted (normalized first).
        #expect(LibraryStore.isInstagramURLString("instagram.com/reel/abc"))
    }

    @Test func rejectsLookAlikeHosts() {
        #expect(!LibraryStore.isInstagramURLString("https://notinstagram.com/reel/abc"))
        #expect(!LibraryStore.isInstagramURLString("https://instagram.com.evil.com/reel/abc"))
        #expect(!LibraryStore.isInstagramURLString("https://evil.com/?u=instagram.com"))
    }

    @Test func rejectsNonInstagram() {
        #expect(!LibraryStore.isInstagramURLString("https://youtube.com/watch?v=abc"))
        #expect(!LibraryStore.isInstagramURLString(""))
    }
}
