import SwiftUI

/// Root of the expanded notch panel. Switches between the grouped queue and a
/// single-reel detail view, and collapses back to the pill when the mouse leaves.
struct NotchPanelView: View {
    let folders: [Folder]
    let reels: [Reel]
    var onHoverEnd: () -> Void
    var onOpenURL: (URL) -> Void

    @State private var selected: Reel?

    var body: some View {
        ZStack {
            if let reel = selected {
                ReelDetailView(
                    reel: reel,
                    folder: folder(for: reel),
                    onBack: { withAnimation(Theme.easeExpo) { selected = nil } },
                    onOpenURL: onOpenURL
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                QueueListView(
                    folders: folders,
                    reels: reels,
                    onSelect: { reel in withAnimation(Theme.easeExpo) { selected = reel } },
                    onOpenURL: onOpenURL
                )
                .transition(.opacity)
            }
        }
        .frame(width: Theme.panelWidth)
        .onHover { hovering in
            if !hovering { onHoverEnd() }
        }
    }

    private func folder(for reel: Reel) -> Folder? {
        folders.first { $0.id == reel.folderID }
    }
}

/// The grouped queue: a header with a count, then one section per non-empty folder.
struct QueueListView: View {
    let folders: [Folder]
    let reels: [Reel]
    var onSelect: (Reel) -> Void
    var onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s4) {
                    ForEach(folders.sorted { $0.sortOrder < $1.sortOrder }) { folder in
                        let items = reels.filter { $0.folderID == folder.id }
                        if !items.isEmpty {
                            FolderSection(
                                folder: folder,
                                items: items,
                                onSelect: onSelect,
                                onOpenURL: onOpenURL
                            )
                        }
                    }
                }
                .padding(.horizontal, Theme.s4)
                .padding(.bottom, Theme.s4)
            }
            .frame(maxHeight: Theme.panelMaxHeight)
        }
        .padding(.top, Theme.s4)
    }

    private var header: some View {
        HStack {
            Text("Reel Planner")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Spacer()
            Text("\(reels.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.foregroundMuted)
                .padding(.horizontal, Theme.s2)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .padding(.horizontal, Theme.s4)
    }
}

/// One folder's header (symbol + name + count) followed by its reel cards.
private struct FolderSection: View {
    let folder: Folder
    let items: [Reel]
    var onSelect: (Reel) -> Void
    var onOpenURL: (URL) -> Void

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
                    onOpenLink: { link in onOpenURL(link.url) },
                    onSelect: { onSelect(reel) }
                )
            }
        }
    }
}
