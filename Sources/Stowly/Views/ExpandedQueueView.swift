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
        // Push the whole panel below the physical notch (the library inset can fall short).
        // User-tunable from the menu via "Panel Position".
        .padding(.top, store.notchTopOffset)
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
    // Live drag state for the insertion (snap) line: the cursor Y in "folderList" space and the
    // name of the folder being dragged. Both nil when no drag is in progress.
    @State private var dragLocationY: CGFloat?
    @State private var draggingFolder: String?

    /// Drop a dragged folder where it was released: count how many folders sit above the drop
    /// point and insert there. Uses measured header positions, so it's accurate regardless of
    /// folder heights.
    private func dropFolder(_ folder: Folder, at dropY: CGFloat) {
        let above = store.sortedFolders.filter {
            $0.name != folder.name && (headerMidYs[$0.name] ?? 0) < dropY
        }.count
        store.moveFolder(folder, toIndex: above)
    }

    /// True if the snap line should be drawn just above `folder` — i.e. it's the closest folder
    /// *below* the cursor (excluding the one being dragged).
    private func showLineBefore(_ folder: Folder) -> Bool {
        guard let y = dragLocationY, let dragging = draggingFolder, folder.name != dragging else { return false }
        let myMid = headerMidYs[folder.name] ?? 0
        guard myMid > y else { return false }
        let closerBelow = store.sortedFolders.contains {
            $0.name != dragging && $0.name != folder.name &&
            (headerMidYs[$0.name] ?? 0) > y && (headerMidYs[$0.name] ?? 0) < myMid
        }
        return !closerBelow
    }

    /// True when the cursor is below every folder, so the line goes at the very bottom.
    private func showLineAtEnd() -> Bool {
        guard let y = dragLocationY, let dragging = draggingFolder else { return false }
        return !store.sortedFolders.contains { $0.name != dragging && (headerMidYs[$0.name] ?? 0) > y }
    }

    private var dropLine: some View {
        Capsule()
            .fill(Theme.foreground.opacity(0.85))
            .frame(height: 2)
            .shadow(color: Theme.foreground.opacity(0.4), radius: 3)
            .transition(.opacity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            header
            tabBar
            if showSort && shelf != .tracking { sortRow }

            if shelf == .tracking {
                trackingTab
            } else {
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
                                if showLineBefore(folder) { dropLine }
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
                                    isTracking: { store.isTracking($0) },
                                    onToggleTracking: { store.toggleTracking($0) },
                                    onMove: { reel, folder in store.moveReel(reel, to: folder) },
                                    onDeleteFolder: { store.deleteFolder(folder) },
                                    canReorder: store.folderSort == .custom,
                                    onMoveUp: { store.moveFolder(folder, up: true) },
                                    onMoveDown: { store.moveFolder(folder, up: false) },
                                    headerMidYs: headerMidYs,
                                    onDrop: { dropY in dropFolder(folder, at: dropY) },
                                    onDragChange: { y in
                                        withAnimation(.easeOut(duration: 0.12)) {
                                            if let y {
                                                dragLocationY = y
                                                draggingFolder = folder.name
                                            } else {
                                                dragLocationY = nil
                                                draggingFolder = nil
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        if showLineAtEnd() { dropLine }
                    }
                    .padding(.horizontal, Theme.s4)
                    .padding(.bottom, Theme.s5)
                    .coordinateSpace(name: "folderList")
                    .onPreferenceChange(FolderMidYKey.self) { headerMidYs = $0 }
                }
                // Shrink the scroll area by the top offset so pushing the panel down doesn't grow
                // its total height and clip the last card at the bottom.
                .frame(maxHeight: Theme.panelMaxHeight - store.notchTopOffset)
            }
            }
        }
        .padding(.top, Theme.s4)
    }

    /// The Tracking tab: a flat, folder-agnostic list of items with a running work timer.
    private var trackingTab: some View {
        Group {
            if store.trackedReels.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.s2) {
                        ForEach(store.trackedReels) { reel in
                            TrackingRow(
                                reel: reel,
                                onSelect: { onSelect(reel) },
                                onPauseResume: { withAnimation(.easeOut(duration: 0.15)) { store.togglePause(reel) } },
                                onStop: { withAnimation(.easeOut(duration: 0.15)) { store.stopTracking(reel) } }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.s4)
                    .padding(.bottom, Theme.s5)
                }
                .frame(maxHeight: Theme.panelMaxHeight - store.notchTopOffset)
            }
        }
    }

    private func addTracking() {
        if let task = TrackingPrompt.run() {
            store.addTrackingItem(task: task)
        }
    }

    // Home (the working list) · Tracking · Archive · Done.
    private var tabBar: some View {
        HStack(spacing: Theme.s1) {
            tabChip(.active)
            tabChip(.tracking)
            tabChip(.archived)
            tabChip(.completed)
            Spacer()
        }
        .padding(.horizontal, Theme.s4)
    }

    // In-panel sort selector (avoids a system menu popup, which would make the notch collapse).
    private var sortRow: some View {
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
            Text("Stowly")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Spacer()

            // Folder-management controls only apply to the grouped tabs, not flat Tracking.
            if shelf != .tracking {
                circleButton(store.allCollapsed ? "chevron.down.2" : "chevron.up.2",
                             help: store.allCollapsed ? "Expand all folders" : "Collapse all folders") {
                    withAnimation(.easeOut(duration: 0.16)) { store.allCollapsed ? store.expandAll() : store.collapseAll() }
                }
                circleButton("arrow.up.arrow.down", help: "Sort folders", active: showSort) {
                    withAnimation(.easeOut(duration: 0.15)) { showSort.toggle() }
                }
                circleButton("folder.badge.plus", help: "New folder", action: addFolder)
            }

            circleButton("plus",
                         help: shelf == .tracking ? "Track something you're working on" : "Add a manual card") {
                if shelf == .tracking { addTracking() } else { addManual() }
            }

            countBadge
        }
        .padding(.horizontal, Theme.s4)
    }

    private var countBadge: some View {
        Text("\(store.reels.count)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.foregroundMuted)
            .padding(.horizontal, Theme.s2)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }

    /// A 22pt circular icon button used across the header toolbar.
    private func circleButton(_ symbol: String, help: String, active: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.foreground)
                .frame(width: 22, height: 22)
                .background(Circle().fill(active ? Theme.surfaceHover : Theme.surface))
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
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
        case .active: "No posts yet"
        case .tracking: "Nothing in progress"
        case .archived: "Nothing archived"
        case .completed: "Nothing completed yet"
        }
    }

    private var emptySubtitle: String {
        switch shelf {
        case .active: "Share a post from your phone, or add one from the menu-bar icon."
        case .tracking: "Tap + to start a timer on what you're working on, or right-click a card → Start tracking."
        case .archived: "Archive a post (the box icon) to save it here for later."
        case .completed: "Tap the ✓ on a post to mark it done — it lands here."
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
    var isTracking: (Reel) -> Bool
    var onToggleTracking: (Reel) -> Void
    var onMove: (Reel, Folder) -> Void
    var onDeleteFolder: () -> Void
    var canReorder: Bool
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var headerMidYs: [String: CGFloat]
    var onDrop: (CGFloat) -> Void
    var onDragChange: (CGFloat?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            FolderHeader(
                folder: folder,
                count: items.count,
                isCollapsed: isCollapsed,
                canReorder: canReorder,
                // Drag-reorder only on Home, where every folder is rendered. On Archive/Done the
                // empty folders are hidden, so their positions are unknown and a drop would land
                // at the wrong index.
                canDrag: shelf == .active,
                onToggleCollapse: onToggleCollapse,
                onDrop: onDrop,
                onDragChange: onDragChange,
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
                        isTracking: isTracking(reel),
                        onToggleTracking: { onToggleTracking(reel) },
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
    var canDrag: Bool
    var onToggleCollapse: () -> Void
    var onDrop: (CGFloat) -> Void
    var onDragChange: (CGFloat?) -> Void
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
            // feed back into the translation (which was the source of the lag). Only on Home —
            // see `canDrag`.
            if canDrag {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.foreground.opacity(isDragging ? 0.9 : 0.55))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 3, coordinateSpace: .named("folderList"))
                            .onChanged { value in
                                isDragging = true
                                dragY = value.translation.height
                                onDragChange(value.location.y)
                            }
                            .onEnded { value in
                                onDrop(value.location.y)
                                onDragChange(nil)
                                isDragging = false
                                dragY = 0
                            }
                    )
                    .help("Drag to reorder")
            }
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

/// A single row in the Tracking tab: platform/stopwatch mark, task, a live elapsed timer, and a
/// stop button. Tapping the row opens the detail; the timer ticks while the panel is open.
private struct TrackingRow: View {
    let reel: Reel
    var onSelect: () -> Void
    var onPauseResume: () -> Void
    var onStop: () -> Void

    private var accent: Color { reel.platform == .web ? Theme.accent : reel.platform.accent }
    private var running: Bool { reel.isTrackingRunning }

    var body: some View {
        HStack(spacing: Theme.s2) {
            Button(action: onSelect) {
                HStack(spacing: Theme.s3) {
                    Image(systemName: running ? "stopwatch.fill" : "pause.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(running ? accent : Theme.foregroundMuted)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(reel.task.isEmpty ? "Working…" : reel.task)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                        Text(running ? sinceText : "Paused")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.foregroundMuted)
                    }

                    Spacer(minLength: Theme.s2)

                    // Live stopwatch — ticks while running, holds steady while paused.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsedString(seconds: reel.trackingElapsed(asOf: context.date) ?? 0))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(running ? Theme.foreground : Theme.foregroundMuted)
                            .monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())

            Button(action: onPauseResume) {
                Image(systemName: running ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(running ? Theme.foreground : accent)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(running ? "Pause" : "Resume")

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.foregroundMuted)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Stop tracking")
        }
        .padding(Theme.s3)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var sinceText: String {
        guard let start = reel.trackingStartedAt else { return "" }
        return "since \(start.formatted(date: .omitted, time: .shortened))"
    }
}

/// Format a duration as a stopwatch string: `M:SS`, or `H:MM:SS` once it passes an hour.
func elapsedString(seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

/// Compact worked-time label for the logged-time badge: `1h 23m`, `23m`, or `<1m`.
func loggedDurationString(seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    let h = s / 3600, m = (s % 3600) / 60
    if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
    if m > 0 { return "\(m)m" }
    return "<1m"
}
