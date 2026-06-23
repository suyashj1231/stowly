import SwiftUI

/// Root of the expanded notch panel. Switches between the grouped queue and a
/// single-reel detail view, and collapses back to the pill when the mouse leaves.
struct NotchPanelView: View {
    var store: LibraryStore
    var onHoverEnd: () -> Void
    var onOpenURL: (URL) -> Void

    @State private var selected: Reel?

    var body: some View {
        ZStack {
            if let reel = selected {
                ReelDetailView(
                    reel: reel,
                    folder: reel.folder,
                    onBack: { withAnimation(Theme.easeExpo) { selected = nil } },
                    onOpenURL: onOpenURL,
                    onApproveFolder: { store.approveProposedFolder(for: reel) },
                    onDismissProposal: { store.dismissProposal(for: reel) }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                QueueListView(
                    store: store,
                    onSelect: { reel in withAnimation(Theme.easeExpo) { selected = reel } },
                    onOpenURL: onOpenURL
                )
                .transition(.opacity)
            }
        }
        .frame(width: Theme.panelWidth)
        .greenGlow(token: store.glowToken, cornerRadius: Theme.panelRadius)
        .onHover { hovering in
            if !hovering { onHoverEnd() }
        }
    }
}

/// The grouped queue: a header with a count, then one section per non-empty folder.
struct QueueListView: View {
    var store: LibraryStore
    var onSelect: (Reel) -> Void
    var onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            header

            if store.reels.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.s4) {
                        ForEach(store.folders) { folder in
                            let items = store.reels(in: folder)
                            if !items.isEmpty {
                                FolderSection(
                                    folder: folder,
                                    items: items,
                                    isProcessing: { store.isProcessing($0) },
                                    onSelect: onSelect,
                                    onDelete: { store.deleteReel($0) },
                                    onOpenURL: onOpenURL,
                                    onApproveFolder: { store.approveProposedFolder(for: $0) },
                                    onDismissProposal: { store.dismissProposal(for: $0) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, Theme.s4)
                    .padding(.bottom, Theme.s4)
                }
                .frame(maxHeight: Theme.panelMaxHeight)
            }
        }
        .padding(.top, Theme.s4)
    }

    private var header: some View {
        HStack(spacing: Theme.s2) {
            Text("Reel Planner")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Spacer()
            Button(action: addManual) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Add a manual card")

            Text("\(store.reels.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.foregroundMuted)
                .padding(.horizontal, Theme.s2)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .padding(.horizontal, Theme.s4)
    }

    private func addManual() {
        if let entry = ManualEntryPrompt.run() {
            store.addManualReel(task: entry.task, link: entry.link.isEmpty ? nil : entry.link)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.s2) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.foregroundMuted)
            Text("No reels yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.foreground)
            Text("Share a reel from your phone, or add one from the menu-bar icon.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.foregroundMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, Theme.s5)
    }
}

/// One folder's header (symbol + name + count) followed by its reel cards.
private struct FolderSection: View {
    let folder: Folder
    let items: [Reel]
    var isProcessing: (Reel) -> Bool
    var onSelect: (Reel) -> Void
    var onDelete: (Reel) -> Void
    var onOpenURL: (URL) -> Void
    var onApproveFolder: (Reel) -> Void
    var onDismissProposal: (Reel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack(spacing: Theme.s2) {
                Image(systemName: folder.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(folder.accent)
                Text(folder.name.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.foregroundMuted)
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.foregroundMuted.opacity(0.7))
            }

            ForEach(items) { reel in
                ReelCard(
                    reel: reel,
                    accent: folder.accent,
                    isProcessing: isProcessing(reel),
                    onOpenLink: { link in onOpenURL(link.url) },
                    onDelete: { onDelete(reel) },
                    onSelect: { onSelect(reel) },
                    onApproveFolder: { onApproveFolder(reel) },
                    onDismissProposal: { onDismissProposal(reel) }
                )
            }
        }
    }
}
