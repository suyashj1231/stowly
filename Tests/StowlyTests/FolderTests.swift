import Testing
@testable import Stowly

/// Guards the folder sort labels and the offline icon heuristic. These are pure and have
/// regressed before (the sort chips were shortened to "A–Z"/"Z–A"; an icon regression once
/// showed plain folders), so they're cheap, high-value regression anchors.
struct FolderTests {

    // MARK: FolderSort labels

    @Test func sortTitlesAreStable() {
        #expect(FolderSort.custom.title == "Custom")
        #expect(FolderSort.nameAsc.title == "A–Z")
        #expect(FolderSort.nameDesc.title == "Z–A")
        #expect(FolderSort.countDesc.title == "Most cards")
        #expect(FolderSort.countAsc.title == "Fewest cards")
    }

    @Test func everySortCaseHasNonEmptyTitle() {
        for sort in FolderSort.allCases {
            #expect(!sort.title.isEmpty)
        }
    }

    @Test func sortRawValuesRoundTrip() {
        // Persistence relies on rawValue <-> case; breaking it would silently reset users' choice.
        for sort in FolderSort.allCases {
            #expect(FolderSort(rawValue: sort.rawValue) == sort)
        }
    }

    // MARK: FolderIcon heuristic

    @Test func heuristicMapsKnownKeywords() {
        #expect(FolderIcon.heuristic(for: "Apply Jobs") == "paperplane.fill")
        #expect(FolderIcon.heuristic(for: "Learn / Certs") == "graduationcap.fill")
        #expect(FolderIcon.heuristic(for: "Gym") == "dumbbell.fill")
        #expect(FolderIcon.heuristic(for: "Recipes") == "fork.knife")
        #expect(FolderIcon.heuristic(for: "Music") == "music.note")
        #expect(FolderIcon.heuristic(for: "Hackathons") == "trophy.fill")
        #expect(FolderIcon.heuristic(for: "Events") == "calendar")
    }

    @Test func heuristicIsCaseInsensitive() {
        #expect(FolderIcon.heuristic(for: "GYM") == "dumbbell.fill")
        #expect(FolderIcon.heuristic(for: "gym workout") == "dumbbell.fill")
    }

    @Test func heuristicFallsBackToGenericFolder() {
        #expect(FolderIcon.heuristic(for: "Zzzqx") == "folder.fill")
    }

    @Test func heuristicNeverReturnsEmpty() {
        for name in ["", "Apply Jobs", "random words here", "Misc"] {
            #expect(!FolderIcon.heuristic(for: name).isEmpty)
        }
    }
}
