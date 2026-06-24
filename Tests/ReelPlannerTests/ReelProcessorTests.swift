import Testing
import Foundation
@testable import ReelPlanner

/// Pure helpers from the processing pipeline: creator-handle normalization and the
/// error→user-message mapping that drives the card's retry copy.
struct ReelProcessorTests {

    // MARK: normalizedHandle

    @Test func handleGetsAtPrefix() {
        #expect(ReelProcessor.normalizedHandle("amaansbuilds") == "@amaansbuilds")
    }

    @Test func handleKeepsExistingAt() {
        #expect(ReelProcessor.normalizedHandle("@designdaily") == "@designdaily")
    }

    @Test func handleTrimsWhitespace() {
        #expect(ReelProcessor.normalizedHandle("  jobsdrop  ") == "@jobsdrop")
        #expect(ReelProcessor.normalizedHandle("  @jobsdrop ") == "@jobsdrop")
    }

    @Test func emptyHandleStaysEmpty() {
        #expect(ReelProcessor.normalizedHandle("") == "")
        #expect(ReelProcessor.normalizedHandle("   ") == "")
    }

    // MARK: friendlyError

    @Test func ollamaConnectionErrorIsFriendly() {
        let err = NSError(domain: "t", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "could not connect to the server"])
        #expect(ReelProcessor.friendlyError(err).contains("Ollama"))
    }

    @Test func instagramBlockErrorIsFriendly() {
        let err = NSError(domain: "t", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "rate-limit reached"])
        #expect(ReelProcessor.friendlyError(err).contains("Instagram"))
    }

    @Test func loginErrorIsFriendly() {
        let err = NSError(domain: "t", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "login required"])
        #expect(ReelProcessor.friendlyError(err).contains("Instagram"))
    }

    @Test func unknownErrorFallsBackToGenericMessage() {
        let err = NSError(domain: "t", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "disk on fire"])
        let msg = ReelProcessor.friendlyError(err)
        #expect(msg.contains("Processing failed"))
        #expect(msg.contains("disk on fire"))
    }
}
