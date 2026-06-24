import Testing
import Foundation
@testable import ReelPlanner

/// `ReelUnderstanding` is the strict shape every LLM provider (Ollama, Gemini) must return and
/// that the pipeline decodes. These tests pin the JSON contract so a field rename can't silently
/// break every reel's processing.
struct UnderstandingDecodingTests {

    private func decode(_ json: String) throws -> ReelUnderstanding {
        try JSONDecoder().decode(ReelUnderstanding.self, from: Data(json.utf8))
    }

    @Test func decodesFullPayload() throws {
        let u = try decode("""
        {
          "task": "Apply to fellowship",
          "summary": "A funded AI fellowship.",
          "links": [{"label": "application", "url": "https://example.com/apply"}],
          "suggested_folder": "Apply Internships",
          "is_new_folder": false,
          "new_folder_name": null
        }
        """)
        #expect(u.task == "Apply to fellowship")
        #expect(u.summary == "A funded AI fellowship.")
        #expect(u.links.count == 1)
        #expect(u.links.first?.label == "application")
        #expect(u.links.first?.url == "https://example.com/apply")
        #expect(u.suggested_folder == "Apply Internships")
        #expect(u.is_new_folder == false)
        #expect(u.new_folder_name == nil)
    }

    @Test func decodesWithoutOptionalNewFolderName() throws {
        // new_folder_name is optional (only present when is_new_folder is true).
        let u = try decode("""
        {"task":"T","summary":"S","links":[],"suggested_folder":"Misc","is_new_folder":false}
        """)
        #expect(u.new_folder_name == nil)
        #expect(u.links.isEmpty)
    }

    @Test func decodesNewFolderProposal() throws {
        let u = try decode("""
        {"task":"Cook this","summary":"Recipe.","links":[],
         "suggested_folder":"Recipes","is_new_folder":true,"new_folder_name":"Recipes"}
        """)
        #expect(u.is_new_folder)
        #expect(u.new_folder_name == "Recipes")
    }

    @Test func decodesMultipleLinks() throws {
        let u = try decode("""
        {"task":"T","summary":"S",
         "links":[{"label":"a","url":"https://a.com"},{"label":"b","url":"https://b.com"}],
         "suggested_folder":"Misc","is_new_folder":false}
        """)
        #expect(u.links.map(\.url) == ["https://a.com", "https://b.com"])
    }

    @Test func missingRequiredFieldThrows() {
        // No "task" → decoding must fail rather than silently produce garbage.
        #expect(throws: (any Error).self) {
            try decode("""
            {"summary":"S","links":[],"suggested_folder":"Misc","is_new_folder":false}
            """)
        }
    }
}
