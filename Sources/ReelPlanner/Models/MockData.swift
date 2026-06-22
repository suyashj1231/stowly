import Foundation

/// Hard-coded sample content so the notch UI has realistic data to render before
/// SwiftData + the ingestion/parsing pipeline exist. Replaced in later phases.
enum MockData {
    static let folders: [Folder] = [
        Folder(name: "Learn / Certs", symbol: "graduationcap.fill", isUserCreated: true, sortOrder: 0),
        Folder(name: "Apply Jobs", symbol: "briefcase.fill", isUserCreated: true, sortOrder: 1),
        Folder(name: "Apply Internships", symbol: "building.2.fill", isUserCreated: true, sortOrder: 2),
        Folder(name: "Misc", symbol: "tray.full.fill", isUserCreated: true, sortOrder: 3)
    ]

    static func folder(_ name: String) -> UUID {
        folders.first { $0.name == name }!.id
    }

    static let reels: [Reel] = [
        Reel(
            originalURL: URL(string: "https://www.instagram.com/reel/ABC123/")!,
            addedAt: Date().addingTimeInterval(-3600),
            status: .processed,
            task: "Apply to Google STEP Internship",
            summary: "Reel walks through the STEP internship for 1st/2nd-year students and the application timeline.",
            creator: "@techcareers",
            links: [
                ReelLink(url: URL(string: "https://buildyourfuture.withgoogle.com/programs/step")!, label: "application")
            ],
            folderID: folder("Apply Internships")
        ),
        Reel(
            originalURL: URL(string: "https://www.instagram.com/reel/DEF456/")!,
            addedAt: Date().addingTimeInterval(-7200),
            status: .processed,
            task: "Learn system design fundamentals",
            summary: "Creator recommends a free roadmap covering load balancing, caching, and DB sharding for interviews.",
            creator: "@designdaily",
            links: [
                ReelLink(url: URL(string: "https://roadmap.sh/system-design")!, label: "resource")
            ],
            folderID: folder("Learn / Certs")
        ),
        Reel(
            originalURL: URL(string: "https://www.instagram.com/reel/GHI789/")!,
            addedAt: Date().addingTimeInterval(-10800),
            status: .new,
            task: "AWS Cloud Practitioner cert",
            summary: "Says the CLF-C02 is the easiest entry cert; mentions a 10-hour free course to pass it.",
            creator: "@cloudwithme",
            links: [],
            folderID: folder("Learn / Certs")
        ),
        Reel(
            originalURL: URL(string: "https://www.instagram.com/reel/JKL012/")!,
            addedAt: Date().addingTimeInterval(-14400),
            status: .new,
            task: "New-grad SWE role at Stripe",
            summary: "Lists open 2026 new-grad backend roles and says referrals double your odds.",
            creator: "@jobsdrop",
            links: [
                ReelLink(url: URL(string: "https://stripe.com/jobs")!, label: "careers")
            ],
            folderID: folder("Apply Jobs")
        )
    ]

    static func reels(in folder: Folder) -> [Reel] {
        reels.filter { $0.folderID == folder.id }
    }
}
