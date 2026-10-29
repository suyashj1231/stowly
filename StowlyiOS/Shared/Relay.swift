import Foundation

/// The ntfy.sh relay, from the phone's side. The Mac subscribes to `<topic>` and publishes the id
/// of every message it ingests to `<topic>-ack` (see `InboxRelay` in the Mac app).
enum Relay {
    /// Post a link. Returns the ntfy message id, which is what the Mac acks.
    static func publish(_ url: String, topic: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://ntfy.sh/\(topic)")!)
        request.httpMethod = "POST"
        request.httpBody = Data(url.utf8)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Event.self, from: data).id
    }

    /// Message ids the Mac has acked since `since`. ntfy keeps about 12h of messages.
    static func ackedIds(topic: String, since: Date) async throws -> Set<String> {
        var comps = URLComponents(string: "https://ntfy.sh/\(topic)-ack/json")!
        comps.queryItems = [
            URLQueryItem(name: "poll", value: "1"),
            URLQueryItem(name: "since", value: String(Int(since.timeIntervalSince1970) - 60)),
        ]
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        // Newline-delimited JSON, one event per line; the ack's message body is the acked id.
        var ids = Set<String>()
        for line in data.split(separator: UInt8(ascii: "\n")) {
            if let event = try? JSONDecoder().decode(Event.self, from: Data(line)),
               event.event == "message", let id = event.message {
                ids.insert(id.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return ids
    }

    private struct Event: Decodable {
        let id: String
        let event: String?
        let message: String?
    }
}

/// Sending and delivery tracking, used by both the share extension and the app.
enum Sender {
    /// Unacked posts older than this are resent, so they're back on the relay before ntfy's
    /// ~12h cache drops them (e.g. the Mac was off overnight).
    static let resendAfter: TimeInterval = 10 * 3600

    /// Send `url` (new or a resend) and record the outcome.
    static func send(_ url: String, topic: String) async -> SentPost {
        let post = SentLog.begin(url)
        do {
            let relayId = try await Relay.publish(url, topic: topic)
            return SentLog.update(post.id) {
                $0.relayIds.append(relayId)
                $0.state = .sent
            } ?? post
        } catch {
            return SentLog.update(post.id) { $0.state = .failed } ?? post
        }
    }

    /// Mark posts the Mac has acked as delivered. Returns the updated log.
    @discardableResult
    static func refreshDelivery(topic: String) async -> [SentPost] {
        let pending = SentLog.load().filter { $0.state == .sent }
        guard let oldest = pending.map(\.lastAttempt).min(),
              let acked = try? await Relay.ackedIds(topic: topic, since: oldest)
        else { return SentLog.load() }

        for post in pending where post.relayIds.contains(where: acked.contains) {
            SentLog.update(post.id) { $0.state = .delivered }
        }
        return SentLog.load()
    }

    /// Wait briefly for the Mac to ack `post`, for the share sheet's "Delivered" confirmation.
    static func waitForDelivery(of post: SentPost, topic: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(800))
            if let acked = try? await Relay.ackedIds(topic: topic, since: post.lastAttempt),
               post.relayIds.contains(where: acked.contains) {
                SentLog.update(post.id) { $0.state = .delivered }
                return true
            }
        }
        return false
    }

    /// Resend failed posts and ones still unacked after `resendAfter`.
    static func resendStale(topic: String) async {
        let now = Date()
        let stale = SentLog.load().filter {
            $0.state == .failed || ($0.state == .sent && now.timeIntervalSince($0.lastAttempt) > resendAfter)
        }
        for post in stale {
            _ = await send(post.url, topic: topic)
        }
    }
}
