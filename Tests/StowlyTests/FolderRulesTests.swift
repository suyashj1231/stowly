import Testing
@testable import Stowly

/// Folder rules applied on top of the Apple on-device model's pick (pure, no model needed).
@Suite struct FolderRulesTests {
    let folders = ["Apply", "Certifications", "Misc"]

    @Test func sameNameIgnoresCaseAndPlurals() {
        #expect(FolderRules.sameName("Certification", "certifications"))
        #expect(FolderRules.sameName("Story", "Stories"))
        #expect(FolderRules.sameName("Hackathons ", "hackathon"))
        #expect(!FolderRules.sameName("Courses", "Certifications"))
        #expect(!FolderRules.sameName("", ""))
    }

    @Test func jobFolderOnlyTakesOpenings() {
        // Free cert voucher that says "apply now": model picks Apply, kind is learning.
        let (f, note) = FolderRules.route(folder: "Apply", kind: "learning", topic: "Certifications", folders: folders)
        #expect(f == "Certifications")
        #expect(note != nil)
        #expect(FolderRules.route(folder: "Apply", kind: "opening", topic: "Internships", folders: folders).0 == "Apply")
    }

    @Test func miscTopicMatchingExistingFolderIsFiledThere() {
        #expect(FolderRules.route(folder: "Misc", kind: "learning", topic: "Certification", folders: folders).0 == "Certifications")
        #expect(FolderRules.route(folder: "Misc", kind: "other", topic: "Recipes", folders: folders).0 == "Misc")
    }

    @Test func proposesOnlyGenuinelyNewNonJobFolders() {
        #expect(FolderRules.proposal(folder: "Misc", kind: "event", topic: "Hackathons", folders: folders) == "Hackathons")
        #expect(FolderRules.proposal(folder: "Misc", kind: "learning", topic: "certification", folders: folders) == nil)
        #expect(FolderRules.proposal(folder: "Misc", kind: "opening", topic: "Internships", folders: folders) == nil)
        #expect(FolderRules.proposal(folder: "Misc", kind: "other", topic: "Misc", folders: folders) == nil)
        // Bait hackathon post tagged #internships: kind event, topic "Internships" → no offer.
        #expect(FolderRules.proposal(folder: "Misc", kind: "event", topic: "Internships", folders: folders) == nil)
        #expect(FolderRules.proposal(folder: "Apply", kind: "opening", topic: "Jobs", folders: folders) == nil)
    }

    @Test func linksComeOnlyFromText() {
        let urls = FolderRules.links(in: "Apply: https://stripe.com/jobs/1 and again https://stripe.com/jobs/1, mail me@x.com")
        #expect(urls.map(\.absoluteString) == ["https://stripe.com/jobs/1"])
    }
}

/// Every icon the on-device model may pick must be a real SF Symbol on this Mac.
@Suite struct AppleIconOptionsTests {
    @Test func allIconOptionsExist() {
        for o in AppleProvider.iconOptions { #expect(FolderIcon.isValidSymbol(o.symbol), "\(o.symbol)") }
    }
}
