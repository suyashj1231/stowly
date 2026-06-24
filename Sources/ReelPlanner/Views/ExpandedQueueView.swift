import SwiftUI

/// Root of the expanded notch panel. Switches between the grouped queue and a
/// single-reel detail view, and collapses back to the pill when the mouse leaves.
struct NotchPanelView: View {
    var store: LibraryStore
    var onHoverStart: () -> Void = {}
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
            if hovering { onHoverStart() } else { onHoverEnd() }
        }
    }
}

/// The grouped queue: a header with a count, then one section per non-empty folder.
struct QueueListView: View {
    var store: LibraryStore
    var onSelect: (Reel) -> Void
    var onOpenURL: (URL) -> Void

    @State private var shelf: Shelf = .active
    @State private var showSort = false
    @State private var headerMidYs: [String: CGFloat] = [:]

    /// Drop a dragged folder where it was released: count how many folders sit above the drop
    /// point and insert there. Uses measured header positions, so it's accurate regardless of
    /// folder heights.
    private func dropFolder(_ folder: Folder, at dropY: CGFloat) {
        let above = store.sortedFolders.filter {
            $0.name != folder.name && (headerMidYs[$0.name] ?? 0) < dropY
        }.count
        store.moveFolder(folder, toIndex: above)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            header
            tabBar
            if showSort { sortRow }

            // Home shows every folder (so folders you create are visible and droppable, even
            // empty). Archive / Done only show folders that actually have reels there.
            let showList = shelf == .active ? !store.folders.isEmpty : store.count(for: shelf) > 0
            if !showList {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.s4) {
                        ForEach(store.sortedFolders) { folder in
                            let items = store.reels(in: folder, shelf: shelf)
                            if !items.isEmpty || shelf == .active {
                                FolderSection(
                                    folder: folder,
                                    items: items,
                                    shelf: shelf,
                                    isCollapsed: store.isCollapsed(folder),
                                    allFolders: store.folders,
                                    isProcessing: { store.isProcessing($0) },
                                    onToggleCollapse: { withAnimation(.easeOut(duration: 0.16)) { store.toggleCollapsed(folder) } },
                                    onSelect: onSelect,
                                    onDelete: { store.deleteReel($0) },
                                    onOpenURL: onOpenURL,
                                    onApproveFolder: { store.approveProposedFolder(for: $0) },
                                    onDismissProposal: { store.dismissProposal(for: $0) },
                                    onRetry: { store.retry($0) },
                                    onComplete: { store.setCompleted($0, shelf != .completed) },
                                    onArchive: { store.setArchived($0, shelf != .archived) },
                                    onMove: { reel, folder in store.moveReel(reel, to: folder) },
                                    onDeleteFolder: { store.deleteFolder(folder) },
                                    canReorder: store.folderSort == .custom,
                                    onMoveUp: { store.moveFolder(folder, up: true) },
                                    onMoveDown: { store.moveFolder(folder, up: false) },
                                    headerMidYs: headerMidYs,
                                    onDrop: { dropY in dropFolder(folder, at: dropY) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, Theme.s4)
                    .padding(.bottom, Theme.s4)
                    .coordinateSpace(name: "folderList")
                    .onPreferenceChange(FolderMidYKey.self) { headerMidYs = $0 }
                }
                .frame(maxHeight: Theme.panelMaxHeight)
            }
        }
        .padding(.top, Theme.s4)
    }

    // Home (the working list) · Archive · Done.
    private var tabBar: some View {
        HStack(spacing: Theme.s1) {
            tabChip(.active)
            tabChip(.archived)
            tabChip(.completed)
            Spacer()
        }
        .padding(.horizontal, Theme.s4)
    }

    // In-panel sort selector (avoids a system menu popup, which would make the notch collapse).
    private var sortRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.s1) {
                ForEach(FolderSort.allCases, id: \.self) { mode in
                    let selected = store.folderSort == mode
                    Button {
                        store.setFolderSort(mode)
                        withAnimation(.easeOut(duration: 0.15)) { showSort = false }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(selected ? Theme.foreground : Theme.foregroundMuted)
                            .padding(.horizontal, Theme.s2 + 2)
                            .frame(height: 24)
                            .background(Capsule().fill(selected ? Theme.surfaceHover : Theme.surface))
                            .overlay(Capsule().stroke(selected ? Theme.borderStrong : Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.s4)
        }
    }

    private func tabChip(_ tab: Shelf) -> some View {
        let selected = shelf == tab
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { shelf = tab }
        } label: {
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

    private var header: some View {
        HStack(spacing: Theme.s2) {
            Text("Reel Planner")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Spacer()

            Button(action: { withAnimation(.easeOut(duration: 0.16)) { store.allCollapsed ? store.expandAll() : store.collapseAll() } }) {
                Image(systemName: store.allCollapsed ? "chevron.down.2" : "chevron.up.2")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(store.allCollapsed ? "Expand all folders" : "Collapse all folders")

            Button { withAnimation(.easeOut(duration: 0.15)) { showSort.toggle() } } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(showSort ? Theme.surfaceHover : Theme.surface))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Sort folders")

            Button(action: addFolder) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("New folder")

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

    private func addFolder() {
        if let name = FolderNamePrompt.run() {
            store.createFolder(name: name)
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
    var allFolders: [Folder]
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
    var onMove: (Reel, Folder) -> Void
    var onDeleteFolder: () -> Void
    var canReorder: Bool
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var headerMidYs: [String: CGFloat]
    var onDrop: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            FolderHeader(
                folder: folder,
                count: items.count,
                isCollapsed: isCollapsed,
                canReorder: canReorder,
                onToggleCollapse: onToggleCollapse,
                onDrop: onDrop,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                onDeleteFolder: onDeleteFolder
            )

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
                        onArchive: { onArchive(reel) },
                        moveTargets: allFolders.filter { $0.persistentModelID != folder.persistentModelID },
                        onMove: { onMove(reel, $0) }
                    )
                }
            }
        }
    }
}

/// Each folder header reports its vertical midpoint (in the "folderList" space) so a drop can
/// land at the right index regardless of folder heights.
private struct FolderMidYKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Folder header in its own view so the drag gesture only re-renders the header (not the
/// folder's cards) — keeping the drag smooth. Tap collapses; drag the right-edge grip to reorder.
private struct FolderHeader: View {
    let folder: Folder
    let count: Int
    let isCollapsed: Bool
    var canReorder: Bool
    var onToggleCollapse: () -> Void
    var onDrop: (CGFloat) -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onDeleteFolder: () -> Void

    @State private var dragY: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
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
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.foregroundMuted.opacity(0.7))
            Spacer()

            // Drag handle, right margin. Drag it up/down to reorder; the rest taps to collapse.
            // Gesture runs in the fixed "folderList" space so offsetting the header doesn't
            // feed back into the translation (which was the source of the lag).
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.foreground.opacity(0.55))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named("folderList"))
                        .onChanged { value in
                            isDragging = true
                            dragY = value.translation.height
                        }
                        .onEnded { value in
                            onDrop(value.location.y)
                            isDragging = false
                            dragY = 0
                        }
                )
                .help("Drag to reorder")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, Theme.s1)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDragging ? folder.accent.opacity(0.16) : .clear)
        )
        .background(
            GeometryReader { geo in
                // Skip reporting while this header is being dragged (its offset would otherwise
                // spam preference changes and re-render the whole list each frame → lag).
                Color.clear.preference(
                    key: FolderMidYKey.self,
                    value: isDragging ? [:] : [folder.name: geo.frame(in: .named("folderList")).midY]
                )
            }
        )
        .offset(y: isDragging ? dragY : 0)
        .opacity(isDragging ? 0.92 : 1)
        .zIndex(isDragging ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { onToggleCollapse() }
        .contextMenu {
            if canReorder {
                Button(action: onMoveUp) { Label("Move up", systemImage: "arrow.up") }
                Button(action: onMoveDown) { Label("Move down", systemImage: "arrow.down") }
                Divider()
            }
            if folder.name != "Misc" {
                Button(role: .destructive, action: onDeleteFolder) {
                    Label("Delete folder", systemImage: "trash")
                }
            }
        }
    }
}
