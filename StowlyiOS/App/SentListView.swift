import SwiftUI
import StowlyShared

/// Posts sent from the share sheet and whether each has reached the Mac.
struct SentListView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingUnpair = false

    var body: some View {
        NavigationStack {
            Group {
                if model.posts.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(model.posts) { post in
                                PostRow(post: post) { Task { await model.resend(post) } }
                                    .swipeActions {
                                        Button("Delete", role: .destructive) { model.delete(post) }
                                        Button("Resend") { Task { await model.resend(post) } }
                                            .tint(.indigo)
                                    }
                            }
                        } footer: {
                            Text("Swipe a post to resend it. Posts your Mac hasn't confirmed are resent automatically.")
                        }
                    }
                    .refreshable { await model.refresh() }
                }
            }
            .navigationTitle("Stowly")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Label("Connected to your Mac", systemImage: "checkmark.circle")
                        Button("Disconnect…", systemImage: "xmark.circle", role: .destructive) {
                            confirmingUnpair = true
                        }
                    } label: {
                        Image(systemName: "laptopcomputer")
                            .accessibilityLabel("Mac connection")
                    }
                }
            }
            .confirmationDialog("Disconnect from your Mac?", isPresented: $confirmingUnpair, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { model.unpair() }
            } message: {
                Text("Share → Stowly will stop working until you scan the code again.")
            }
            // While something is still on its way, check for the Mac's confirmation every few seconds.
            .task(id: model.hasPending) {
                while model.hasPending, !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    await model.refresh()
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Ready to save posts", systemImage: "square.and.arrow.up")
        } description: {
            Text("In Instagram, TikTok, YouTube, LinkedIn or X, tap **Share**, then **Stowly**. The post appears in Stowly on your Mac.\n\nDon't see Stowly? Scroll the app row to the end, tap **More**, and add it to your favorites.")
        }
    }
}

private struct PostRow: View {
    let post: SentPost
    let resend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(post.platform == .web ? "Link" : post.platform.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(displayURL)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(post.lastAttempt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            status
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        switch post.state {
        case .delivered:
            Label("On Mac", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.green)
                .font(.title3)
        case .sent:
            Label("Waiting for Mac", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .sending:
            ProgressView()
        case .failed:
            Button("Retry", systemImage: "arrow.clockwise", action: resend)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.orange)
        }
    }

    private var displayURL: String {
        post.url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "www.", with: "")
    }
}
