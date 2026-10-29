import Foundation
import StowlyShared

/// One post shared from the phone, and whether the Mac has confirmed it.
struct SentPost: Codable, Identifiable, Sendable, Equatable {
    enum State: String, Codable, Sendable {
        case sending     // POST in flight
        case sent        // on the relay, no ack from the Mac yet
        case delivered   // the Mac acked one of `relayIds`
        case failed      // couldn't reach the relay
    }

    let id: UUID
    let url: String
    let firstSent: Date
    var lastAttempt: Date
    /// ntfy message ids, one per send. The Mac acks whichever one it ingests.
    var relayIds: [String]
    var state: State

    var platform: Platform { Platform.detect(from: url) }
}

/// The paired topic plus the list of sent posts, newest first, kept in `SharedStore` so the share
/// extension writes it and the app reads it.
enum SentLog {
    private static let postsKey = "sentPosts"
    private static let topicKey = "topic"
    private static let maxPosts = 100

    static var topic: String? {
        get { SharedStore.string(for: topicKey) }
        set { SharedStore.set(newValue, for: topicKey) }
    }

    static func load() -> [SentPost] {
        guard let data = SharedStore.data(for: postsKey) else { return [] }
        return (try? JSONDecoder().decode([SentPost].self, from: data)) ?? []
    }

    static func save(_ posts: [SentPost]) {
        SharedStore.set(try? JSONEncoder().encode(Array(posts.prefix(maxPosts))), for: postsKey)
    }

    /// Start a send of `url`: reuses the existing entry for the same link (moved to the top)
    /// so sharing a post twice doesn't list it twice.
    static func begin(_ url: String) -> SentPost {
        var posts = load()
        let now = Date()
        var post: SentPost
        if let index = posts.firstIndex(where: { $0.url == url }) {
            post = posts.remove(at: index)
            post.lastAttempt = now
            post.state = .sending
        } else {
            post = SentPost(id: UUID(), url: url, firstSent: now, lastAttempt: now, relayIds: [], state: .sending)
        }
        posts.insert(post, at: 0)
        save(posts)
        return post
    }

    /// Apply `change` to the post with `id` (re-read first, since the other process may have written).
    @discardableResult
    static func update(_ id: UUID, _ change: (inout SentPost) -> Void) -> SentPost? {
        var posts = load()
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return nil }
        change(&posts[index])
        save(posts)
        return posts[index]
    }

    static func remove(_ id: UUID) {
        save(load().filter { $0.id != id })
    }
}
