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
                    onDismissProposal: { store.dismissProposal(for: reel) },
                    onRetry: { store.retry(reel) }
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
        // No glow on the expanded panel — when open you see the card spinners directly; the
        // glow lives on the compact pill (white arrived / green done / red error).
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

    @State private var shelf: Shelf = .active

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            header
            tabBar

            if store.count(for: shelf) == 0 {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.s4) {
                        ForEach(store.folders) { folder in
                            let items = store.reels(in: folder, shelf: shelf)
                            if !items.isEmpty {
                                FolderSection(
                                    folder: folder,
                                    items: items,
                                    shelf: shelf,
                                    isCollapsed: store.isCollapsed(folder),
                                    isProcessing: { store.isProcessing($0) },
                                    onToggleCollapse: { withAnimation(.easeOut(duration: 0.16)) { store.toggleCollapsed(folder) } },
                                    onSelect: onSelect,
                                    onDelete: { store.deleteReel($0) },
                                    onOpenURL: onOpenURL,
                                    onApproveFolder: { store.approveProposedFolder(for: $0) },
                                    onDismissProposal: { store.dismissProposal(for: $0) },
                                    onRetry: { store.retry($0) },
                                    onComplete: { store.setCompleted($0, shelf != .completed) },
                                    onArchive: { store.setArchived($0, shelf != .archived) }
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

    private var tabBar: some View {
        HStack(spacing: Theme.s1) {
            ForEach(Shelf.allCases, id: \.self) { tab in
                let selected = tab == shelf
                Button { withAnimation(.easeOut(duration: 0.15)) { shelf = tab } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.symbol).font(.system(size: 9, weight: .semibold))
                        Text(tab.title).font(.system(size: 10, weight: .semibold))
                        let c = store.count(for: tab)
                        if c > 0 {
                            Text("\(c)").font(.system(size: 9, weight: .bold)).opacity(0.7)
                        }
                    }
                    .foregroundStyle(selected ? Theme.foreground : Theme.foregroundMuted)
                    .padding(.horizontal, Theme.s2)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(selected ? Theme.surfaceHover : .clear))
                    .overlay(Capsule().stroke(selected ? Theme.border : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.s4)
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
            Image(systemName: shelf.symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.foregroundMuted)
            Text(emptyTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.foreground)
            Text(emptySubtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.foregroundMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, Theme.s5)
    }

    private var emptyTitle: String {
        switch shelf {
        case .active: "No reels yet"
        case .archived: "Nothing archived"
        case .completed: "Nothing completed yet"
        }
    }

    private var emptySubtitle: String {
        switch shelf {
        case .active: "Share a reel from your phone, or add one from the menu-bar icon."
        case .archived: "Archive a reel (the box icon) to save it here for later."
        case .completed: "Tap the ✓ on a reel to mark it done — it lands here."
        }
    }
}

/// One folder's collapsible header (disclosure + symbol + name + count) and its reel cards.
private struct FolderSection: View {
    let folder: Folder
    let items: [Reel]
    var shelf: Shelf
    var isCollapsed: Bool
    var isProcessing: (Reel) -> Bool
    var onToggleCollapse: () -> Void
    var onSelect: (Reel) -> Void
    var onDelete: (Reel) -> Void
    var onOpenURL: (URL) -> Void
    var onApproveFolder: (Reel) -> Void
    var onDismissProposal: (Reel) -> Void
    var onRetry: (Reel) -> Void
    var onComplete: (Reel) -> Void
    var onArchive: (Reel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            Button(action: onToggleCollapse) {
                HStack(spacing: Theme.s2) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.foregroundMuted)
                        .frame(width: 10)
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
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                ForEach(items) { reel in
                    ReelCard(
                        reel: reel,
                        accent: folder.accent,
                        isProcessing: isProcessing(reel),
                        onOpenLink: { link in onOpenURL(link.url) },
                        onDelete: { onDelete(reel) },
                        onSelect: { onSelect(reel) },
                        onApproveFolder: { onApproveFolder(reel) },
                        onDismissProposal: { onDismissProposal(reel) },
                        onRetry: { onRetry(reel) },
                        shelf: shelf,
                        onComplete: { onComplete(reel) },
                        onArchive: { onArchive(reel) }
                    )
                }
            }
        }
    }
}
