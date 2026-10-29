import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os
import StowlyShared

/// Share → Stowly. Pulls the post link out of what the host app shared, posts it to the Mac's
/// relay topic, shows a quick confirmation and closes itself. No processing happens on the phone.
final class ShareViewController: UIViewController {
    private let model = ShareModel()
    nonisolated static let log = Logger(subsystem: "com.suyash.stowly.ios.share", category: "share")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        model.close = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }

        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { await model.run(sharedText: await Self.sharedStrings(in: items)) }
    }

    /// Every URL and piece of text the host app attached. Instagram and YouTube share a URL;
    /// TikTok, LinkedIn and X often share text with the link inside it.
    private static func sharedStrings(in items: [NSExtensionItem]) async -> [String] {
        var strings: [String] = []
        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty { strings.append(text) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await load(URL.self, from: provider) {
                    strings.append(url.absoluteString)
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = await load(String.self, from: provider) {
                    strings.append(text)
                }
            }
        }
        log.debug("shared: \(strings, privacy: .private) types: \(items.flatMap { $0.attachments ?? [] }.flatMap(\.registeredTypeIdentifiers), privacy: .public)")
        return strings
    }

    private static func load<T: _ObjectiveCBridgeable & Sendable>(_ type: T.Type, from provider: NSItemProvider) async -> T?
    where T._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { value, _ in continuation.resume(returning: value) }
        }
    }
}

@MainActor @Observable
final class ShareModel {
    enum Phase: Equatable {
        case sending
        case delivered        // the Mac acked it
        case queued           // on the relay; the Mac will pick it up when it's online
        case failed
        case notPaired
        case unsupported
    }

    var phase: Phase = .sending
    var platform: Platform = .web
    var close: () -> Void = {}

    func run(sharedText: [String]) async {
        guard let topic = SentLog.topic else { phase = .notPaired; return }
        guard let url = sharedText.lazy.compactMap(ShareLink.extractShareableURL(from:)).first else {
            phase = .unsupported
            return
        }
        platform = Platform.detect(from: url)

        let post = await Sender.send(url, topic: topic)
        guard post.state == .sent else { phase = .failed; return }

        // A running Mac acks within a second or two; don't hold the share sheet longer than that.
        phase = await Sender.waitForDelivery(of: post, topic: topic, timeout: 3.5) ? .delivered : .queued
        try? await Task.sleep(for: .seconds(phase == .delivered ? 0.9 : 1.6))
        close()
    }
}

struct ShareView: View {
    let model: ShareModel

    var body: some View {
        // iOS presents share extensions in its own full-height sheet; center the status in it.
        VStack(spacing: 14) {
            icon
                .font(.system(size: 52, weight: .semibold))
                .frame(height: 60)
                .contentTransition(.symbolEffect(.replace))

            VStack(spacing: 4) {
                Text(title).font(.title3.bold())
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if showsDone {
                Button("Done", action: model.close)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy, value: model.phase)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        switch model.phase {
        case .sending: ProgressView().controlSize(.large)
        case .delivered: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .queued: Image(systemName: "paperplane.circle.fill").foregroundStyle(.tint)
        case .failed: Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
        case .notPaired: Image(systemName: "laptopcomputer.and.iphone").foregroundStyle(.tint)
        case .unsupported: Image(systemName: "link.badge.plus").foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch model.phase {
        case .sending: "Sending to your Mac…"
        case .delivered: "On your Mac"
        case .queued: "Sent"
        case .failed: "Couldn't send"
        case .notPaired: "Connect your Mac first"
        case .unsupported: "Not a supported post"
        }
    }

    private var detail: String {
        switch model.phase {
        case .sending, .delivered: model.platform == .web ? "" : "\(model.platform.displayName) post"
        case .queued: "It'll show up in Stowly when your Mac is online."
        case .failed: "Check your connection. Open Stowly to try again."
        case .notPaired: "Open the Stowly app on this iPhone and scan the code from your Mac."
        case .unsupported: "Stowly saves posts from Instagram, TikTok, YouTube, LinkedIn, X and Handshake."
        }
    }

    private var showsDone: Bool {
        switch model.phase {
        case .failed, .notPaired, .unsupported: true
        case .sending, .delivered, .queued: false
        }
    }
}
