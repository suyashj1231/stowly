import Testing
import Foundation
@testable import Stowly

/// Pure helpers from the processing pipeline: creator-handle normalization (platform-aware) and
/// the error→user-message mapping that drives the card's retry copy.
struct ReelProcessorTests {

    // MARK: normalizedHandle — handle platforms get "@", name platforms don't

    @Test func handleGetsAtPrefixOnHandlePlatforms() {
        #expect(ReelProcessor.normalizedHandle("amaansbuilds", platform: .instagram) == "@amaansbuilds")
        #expect(ReelProcessor.normalizedHandle("cscrashcourse", platform: .youtube) == "@cscrashcourse")
    }

    @Test func handleKeepsExistingAt() {
        #expect(ReelProcessor.normalizedHandle("@designdaily", platform: .tiktok) == "@designdaily")
    }

    @Test func nameKeptAsIsOnNamePlatforms() {
        // LinkedIn / Handshake show real names, not @handles.
        #expect(ReelProcessor.normalizedHandle("Priya Sharma", platform: .linkedin) == "Priya Sharma")
        #expect(ReelProcessor.normalizedHandle("Career Center", platform: .handshake) == "Career Center")
    }

    @Test func handleTrimsWhitespace() {
        #expect(ReelProcessor.normalizedHandle("  jobsdrop  ", platform: .instagram) == "@jobsdrop")
        #expect(ReelProcessor.normalizedHandle("  @jobsdrop ", platform: .instagram) == "@jobsdrop")
    }

    @Test func emptyHandleStaysEmpty() {
        #expect(ReelProcessor.normalizedHandle("", platform: .instagram) == "")
        #expect(ReelProcessor.normalizedHandle("   ", platform: .linkedin) == "")
    }

    // MARK: friendlyError — names the right platform

    @Test func ollamaConnectionErrorIsFriendly() {
        let err = NSError(domain: "t", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "could not connect to the server"])
        #expect(ReelProcessor.friendlyError(err, platform: .instagram).contains("Ollama"))
    }

    @Test func blockErrorNamesThePlatform() {
        let err = NSError(domain: "t", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "rate-limit reached"])
        #expect(ReelProcessor.friendlyError(err, platform: .instagram).contains("Instagram"))
        #expect(ReelProcessor.friendlyError(err, platform: .linkedin).contains("LinkedIn"))
    }

    @Test func loginErrorIsFriendly() {
        let err = NSError(domain: "t", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "login required"])
        #expect(ReelProcessor.friendlyError(err, platform: .tiktok).contains("TikTok"))
    }

    @Test func unknownErrorFallsBackToGenericMessage() {
        let err = NSError(domain: "t", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "disk on fire"])
        let msg = ReelProcessor.friendlyError(err, platform: .youtube)
        #expect(msg.contains("Processing failed"))
        #expect(msg.contains("disk on fire"))
    }
}
