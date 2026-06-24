import Foundation
import SwiftData

/// First-run seed: the four starter folders plus a couple of sample reels so the notch
/// panel isn't empty before real ingestion exists. Inserted once into an empty store.
enum SeedData {
    @MainActor
    static func seed(into context: ModelContext) {
        let learn = Folder(name: "Learn / Certs", symbol: "graduationcap.fill", isUserCreated: true, sortOrder: 0)
        let jobs = Folder(name: "Apply Jobs", symbol: "briefcase.fill", isUserCreated: true, sortOrder: 1)
        let interns = Folder(name: "Apply Internships", symbol: "building.2.fill", isUserCreated: true, sortOrder: 2)
        let misc = Folder(name: "Misc", symbol: "tray.full.fill", isUserCreated: true, sortOrder: 3)
        [learn, jobs, interns, misc].forEach(context.insert)

        let r1 = Reel(
            originalURLString: "https://www.instagram.com/p/DZ3s8-spDxk/",
            addedAt: Date().addingTimeInterval(-3600),
            status: .processed,
            task: "Apply to Anthropic Claude Corps Fellowship",
            summary: "Fully funded 12-month AI fellowship paying $85k, no degree required; work at a nonprofit with mentorship from Anthropic.",
            creator: "@amaansbuilds",
            folder: interns
        )

        let r2 = Reel(
            originalURLString: "https://www.instagram.com/reel/DEF456/",
            addedAt: Date().addingTimeInterval(-7200),
            status: .processed,
            task: "Learn system design fundamentals",
            summary: "Free roadmap covering load balancing, caching, and DB sharding for interviews.",
            creator: "@designdaily",
            folder: learn
        )
        let r2link = ReelLink(urlString: "https://roadmap.sh/system-design", label: "resource")

        let r3 = Reel(
            originalURLString: "https://www.instagram.com/reel/JKL012/",
            addedAt: Date().addingTimeInterval(-14400),
            status: .new,
            task: "New-grad SWE role at Stripe",
            summary: "Open 2026 new-grad backend roles; referrals roughly double your odds.",
            creator: "@jobsdrop",
            folder: jobs
        )
        let r3link = ReelLink(urlString: "https://stripe.com/jobs", label: "careers")

        // Non-Instagram samples so the platform badges/colors are visible out of the box.
        let r4 = Reel(
            originalURLString: "https://www.linkedin.com/posts/example_hiring-activity-123/",
            addedAt: Date().addingTimeInterval(-18000),
            status: .processed,
            task: "Referral: backend role at a fintech",
            summary: "A connection is hiring backend engineers; comment to get the referral link.",
            creator: "Priya Sharma",
            folder: jobs
        )
        let r5 = Reel(
            originalURLString: "https://www.youtube.com/shorts/dQw4w9WgXcQ",
            addedAt: Date().addingTimeInterval(-21600),
            status: .processed,
            task: "Watch: 5-minute Big-O crash course",
            summary: "Quick visual primer on time complexity for coding interviews.",
            creator: "@cscrashcourse",
            folder: learn
        )

        [r1, r2, r3, r4, r5].forEach(context.insert)
        context.insert(r2link); r2link.reel = r2
        context.insert(r3link); r3link.reel = r3

        try? context.save()
    }
}
