import SwiftUI
import StowlyShared

@main
struct StowlyApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // Scanning the Mac's QR with the Camera app opens stowly://pair?topic=…
                .onOpenURL { model.pair(with: $0.absoluteString) }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { Task { await model.refresh() } }
                }
        }
    }
}

/// The app's state: which Mac topic we're paired with and the posts sent from the share sheet.
@MainActor @Observable
final class AppModel {
    private(set) var topic: String? = SentLog.topic
    private(set) var posts: [SentPost] = SentLog.load()
    var pairingError: String?

    var isPaired: Bool { topic != nil }

    /// Pair from a scanned QR payload, a pasted ntfy address or a bare topic.
    @discardableResult
    func pair(with raw: String) -> Bool {
        guard let topic = Pairing.topic(from: raw) else {
            pairingError = "That isn't a Stowly pairing code. On your Mac, choose Connect iPhone… in the Stowly menu."
            return false
        }
        SentLog.topic = topic
        self.topic = topic
        pairingError = nil
        return true
    }

    func unpair() {
        SentLog.topic = nil
        topic = nil
    }

    /// Re-read the log (the share extension writes to it), resend anything stale, then pick up
    /// the Mac's delivery acks.
    func refresh() async {
        posts = SentLog.load()
        guard let topic else { return }
        await Sender.resendStale(topic: topic)
        posts = await Sender.refreshDelivery(topic: topic)
    }

    func resend(_ post: SentPost) async {
        guard let topic else { return }
        _ = await Sender.send(post.url, topic: topic)
        posts = SentLog.load()
        _ = await Sender.waitForDelivery(of: SentLog.load().first { $0.id == post.id } ?? post, topic: topic, timeout: 4)
        posts = SentLog.load()
    }

    func delete(_ post: SentPost) {
        SentLog.remove(post.id)
        posts = SentLog.load()
    }

    /// Whether any post is still waiting on the Mac (drives the foreground polling).
    var hasPending: Bool { posts.contains { $0.state == .sent || $0.state == .sending } }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isPaired {
            SentListView()
        } else {
            PairView()
        }
    }
}
