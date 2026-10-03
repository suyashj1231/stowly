import SwiftUI
import AppKit

/// Root of the expanded notch panel. Switches between the grouped queue and a
/// single-reel detail view, and collapses back to the pill when the mouse leaves.
struct NotchPanelView: View {
    var store: LibraryStore
    var onHoverStart: () -> Void = {}
    var onHoverEnd: () -> Void
    var onOpenURL: (URL) -> Void

    @State private var selected: Reel?
    // Tab and options-row state, owned by the panel root.
    @State private var shelf: Shelf = .active
    @State private var showOptions = false
    @State private var showThemes = false
    private let band = Theme.notchBand

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
                .padding(.top, Theme.notchTopClearance)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                QueueListView(
                    store: store,
                    band: band,
                    shelf: $shelf,
                    showOptions: $showOptions,
                    showThemes: $showThemes,
                    onSelect: { reel in withAnimation(Theme.easeExpo) { selected = reel } },
                    onOpenURL: onOpenURL
                )
                // With a notch band, pull the list up so its header sits beside the notch.
                .padding(.top, band.map { -$0.height } ?? Theme.notchTopClearance)
                .transition(.opacity)
            }
        }
        .frame(width: Theme.panelWidth)
        // Light mode needs its own backdrop: DynamicNotchKit always paints the notch shape
        // black. Bleed a near-white fill outward (masked back to the notch shape by the
        // library) so the panel reads light; in dark mode this token is clear (a no-op).
        .background { Theme.panelBackground.padding(-120) }
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
    /// Notch strip the header sits in (nil = header gets its own row). See `Theme.notchBand`.
    var band: CGSize?
    @Binding var shelf: Shelf
    @Binding var showOptions: Bool
    @Binding var showThemes: Bool
    var onSelect: (Reel) -> Void
    var onOpenURL: (URL) -> Void

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
            if !store.searchQuery.isEmpty {
                searchResultsView
            } else {
            tabBar
            if showOptions { optionsRow }

            if shelf == .tracking {
                trackingTab
            } else {
            // Home shows every folder (so folders you create are visible and droppable, even
            // empty). Archive / Done only show folders that actually have reels there.
            let showList = shelf == .active ? !store.folders.isEmpty : store.count(for: shelf) > 0
            if !showList {
                emptyState
            } else {
                SelfSizingScrollView(maxHeight: listMaxHeight) {
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
                                    selecting: store.selectionMode,
                                    isSelected: { store.isSelected($0) },
                                    onToggleSelect: { store.toggleSelected($0) },
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
                    .padding(.horizontal, Theme.contentInset)
                    .padding(.bottom, Theme.s2)
                    .coordinateSpace(name: "folderList")
                    .onPreferenceChange(FolderMidYKey.self) { headerMidYs = $0 }
                }
            }
            }
            }

            if store.selectionMode {
                selectionBar
            }
        }
        .padding(.top, band == nil ? Theme.s4 : 0)
        // Consistent breathing room at the panel's bottom edge — applied outside the scroll views
        // (where an internal padding would get clipped) so the last row never hugs the border.
        .padding(.bottom, Theme.bottomInset)
    }

    /// Max height for the scrollable lists. Crucial: this must subtract **everything else** that
    /// shares the panel's VStack with the list (top padding, header, tab/search row, and any
    /// sort/selection rows) — not just the top offset and bottom inset. Otherwise a long folder
    /// caps the list at a height that, once the header + tabs are stacked on top, pushes the whole
    /// panel past DynamicNotchKit's fixed half-screen window and the bottom gets clipped at the
    /// screen's middle (the "zoomed" bug). GeometryReader can't measure these rows inside the
    /// fixedSize host, so their heights are constants tuned to the rendered layout.
    private var listMaxHeight: CGFloat {
        let searching = !store.searchQuery.isEmpty
        let headerRow: CGFloat = band?.height ?? 22   // title + toolbar (the notch strip when banded)
        let tabOrSearchRow: CGFloat = 22  // the tab bar, or (when searching) the results-count row
        let optionsRow: CGFloat = 24
        let selectionBar: CGFloat = 28
        let topOffset = band.map { -$0.height } ?? Theme.notchTopClearance

        // Each sibling row above/below the list also costs one VStack gap (Theme.s3).
        var chrome = (band == nil ? Theme.s4 : 0) + Theme.bottomInset  // top padding + bottom room
        chrome += headerRow + Theme.s3
        chrome += tabOrSearchRow + Theme.s3
        if !searching, showOptions { chrome += optionsRow + Theme.s3 }
        if store.selectionMode { chrome += selectionBar + Theme.s3 }

        return panelHeightBudget - topOffset - chrome
    }

    /// The most height the whole expanded panel may take. DynamicNotchKit pins our content inside a
    /// window exactly half the screen tall, then insets the top by the notch height and the bottom
    /// by 15pt — so anything beyond that is clipped. We cap to the design max (`panelMaxHeight`) but
    /// shrink to the real budget on shorter displays, so the panel never renders past the middle of
    /// the screen regardless of how many cards a folder holds. Falls back to the design max if the
    /// screen can't be read.
    private var panelHeightBudget: CGFloat {
        guard let screen = NSScreen.main else { return Theme.panelMaxHeight }
        let topInset = screen.safeAreaInsets.top > 0
            ? screen.safeAreaInsets.top                          // notch height
            : screen.frame.maxY - screen.visibleFrame.maxY       // menubar height (non-notch)
        let usable = screen.frame.height / 2 - topInset - 15     // 15 = DNK's bottom safe-area inset
        return min(Theme.panelMaxHeight, usable)
    }

    /// Bottom action bar shown in multi-select mode: bulk complete / archive / delete.
    private var selectionBar: some View {
        let none = store.selection.isEmpty
        return HStack(spacing: Theme.s2) {
            Text("\(store.selection.count) selected")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Spacer(minLength: Theme.s2)
            bulkButton("checkmark.circle", "Done", Theme.success, disabled: none) { store.bulkComplete() }
            bulkButton("archivebox", "Archive", Theme.warning, disabled: none) { store.bulkArchive() }
            bulkButton("trash", "Delete", Theme.danger, disabled: none) { store.bulkDelete() }
        }
        .padding(.horizontal, Theme.contentInset)
        .padding(.top, Theme.s1)
    }

    private func bulkButton(_ symbol: String, _ label: String, _ tint: Color,
                            disabled: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15), action) } label: {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(label).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(disabled ? Theme.foregroundMuted.opacity(0.5) : tint)
            .padding(.horizontal, Theme.s2)
            .frame(height: 24)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().stroke(disabled ? Theme.border : tint.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// Cross-tab search results: a flat list of matching cards (each opens/acts in its own context).
    private var searchResultsView: some View {
        let results = store.searchResults()
        return VStack(alignment: .leading, spacing: Theme.s2) {
            HStack(spacing: Theme.s2) {
                Text("\(results.count) result\(results.count == 1 ? "" : "s") for “\(store.searchQuery)”")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.foregroundMuted)
                    .lineLimit(1)
                Spacer(minLength: Theme.s2)
                Button { withAnimation(.easeOut(duration: 0.15)) { store.setSearchQuery("") } } label: {
                    Text("Clear")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, Theme.s2)
                        .frame(height: 22)
                        .background(Capsule().fill(Theme.surface))
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.contentInset)

            if results.isEmpty {
                emptyState
            } else {
                SelfSizingScrollView(maxHeight: listMaxHeight) {
                    VStack(spacing: Theme.s2) {
                        ForEach(results) { reel in searchCard(reel) }
                    }
                    .padding(.horizontal, Theme.contentInset)
                    .padding(.bottom, Theme.s2)
                }
            }
        }
    }

    /// A ReelCard wired to the store, used in the flat search-results list (its shelf/accent come
    /// from the reel's own folder + state, so the action icons match where it lives).
    private func searchCard(_ reel: Reel) -> some View {
        ReelCard(
            reel: reel,
            accent: reel.folder?.accent ?? Theme.accent,
            isProcessing: store.isProcessing(reel),
            onOpenLink: { onOpenURL($0.url) },
            onDelete: { store.deleteReel(reel) },
            onSelect: { onSelect(reel) },
            onApproveFolder: { store.approveProposedFolder(for: reel) },
            onDismissProposal: { store.dismissProposal(for: reel) },
            onRetry: { store.retry(reel) },
            shelf: store.shelf(of: reel),
            onComplete: { store.setCompleted(reel, store.shelf(of: reel) != .completed) },
            onArchive: { store.setArchived(reel, store.shelf(of: reel) != .archived) },
            isTracking: store.isTracking(reel),
            onToggleTracking: { store.toggleTracking(reel) },
            selecting: store.selectionMode,
            isSelected: store.isSelected(reel),
            onToggleSelect: { store.toggleSelected(reel) },
            moveTargets: store.folders.filter { $0.persistentModelID != reel.folder?.persistentModelID },
            onMove: { store.moveReel(reel, to: $0) }
        )
    }

    private func openSearch() {
        if let q = SearchPrompt.run(current: store.searchQuery) {
            withAnimation(.easeOut(duration: 0.15)) { store.setSearchQuery(q) }
        }
    }

    /// The Tracking tab: a flat, folder-agnostic list of items with a running work timer.
    private var trackingTab: some View {
        Group {
            if store.trackedReels.isEmpty {
                emptyState
            } else {
                SelfSizingScrollView(maxHeight: listMaxHeight) {
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
                    .padding(.horizontal, Theme.contentInset)
                    .padding(.bottom, Theme.s2)
                }
            }
        }
    }

    private func addTracking() {
        if let task = TrackingPrompt.run() {
            store.addTrackingItem(task: task)
        }
    }

    // Inbox (the working list) · Tracking · Archive · Done.
    private var tabBar: some View {
        HStack(spacing: Theme.s4) {
            ForEach(Shelf.allCases, id: \.self) { tab in
                Button { select(tab) } label: {
                    HStack(spacing: Theme.s1) {
                        Text(Theme.displayText(tab.title))
                            .font(Theme.display(12, selected: shelf == tab))
                            .foregroundStyle(tabColor(selected: shelf == tab))
                        let count = store.count(for: tab)
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 11))
                                .foregroundStyle(shelf == tab && Theme.style == .persona ? .white : Theme.foregroundMuted)
                        }
                    }
                    .background { tabHighlight(selected: shelf == tab) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(shelf == tab ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, Theme.contentInset + Theme.s1)
    }

    private func tabColor(selected: Bool) -> Color {
        guard selected else { return Theme.foregroundMuted }
        return Theme.style == .cyberpunk ? Theme.neonYellow : Theme.foreground
    }

    /// Selected-tab marker: a red slanted block (Persona) or a neon underline (Cyberpunk).
    @ViewBuilder private func tabHighlight(selected: Bool) -> some View {
        if selected {
            switch Theme.style {
            case .standard: EmptyView()
            case .persona: SlantedRectangle(slant: 5).fill(Theme.personaRed).padding(.horizontal, -7).padding(.vertical, -3)
            case .cyberpunk: Rectangle().fill(Theme.neonYellow).frame(height: 2).offset(y: 10)
            }
        }
    }

    private func select(_ tab: Shelf) {
        withAnimation(.easeOut(duration: 0.15)) { store.exitSelection(); shelf = tab }
    }

    /// Everything that isn't needed every day, behind ⋯ as one inline row (a system menu would
    /// make the notch collapse). Sort and appearance cycle through their options on each tap.
    private var optionsRow: some View {
        Group {
            if showThemes { themeRow } else { optionChips }
        }
        .padding(.horizontal, Theme.contentInset)
        .transition(.opacity)
    }

    /// Theme picker: one swatch per appearance, popping in one after another.
    private var themeRow: some View {
        HStack(spacing: Theme.s1) {
            Button("Back", systemImage: "chevron.left") {
                withAnimation(.easeOut(duration: 0.15)) { showThemes = false }
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.foregroundMuted)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            Text(Theme.displayText("Theme"))
                .font(Theme.display(12))
                .foregroundStyle(Theme.foreground)
            Text(store.appearance.label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.foregroundMuted)
            Spacer(minLength: 0)
            ForEach(Array(AppAppearance.allCases.enumerated()), id: \.element) { index, mode in
                ThemeSwatch(appearance: mode, isSelected: store.appearance == mode) {
                    store.setAppearance(mode)
                }
                .transition(.scale(scale: 0.3).combined(with: .opacity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7).delay(Double(index) * 0.04)))
            }
        }
        .frame(height: 24)
    }

    private var optionChips: some View {
        HStack(spacing: Theme.s1) {
            if shelf != .tracking {
                optionChip(store.selectionMode ? "Done Selecting" : "Select") {
                    store.selectionMode ? store.exitSelection() : store.enterSelection()
                }
                optionChip(store.allCollapsed ? "Expand All" : "Collapse All") {
                    store.allCollapsed ? store.expandAll() : store.collapseAll()
                }
                optionChip("Sort: \(store.folderSort.title)", action: cycleSort)
                optionChip("New Folder", action: addFolder)
            }
            Spacer(minLength: 0)
            Button("Theme: \(store.appearance.label)", systemImage: store.appearance.symbol) {
                withAnimation(.easeOut(duration: 0.15)) { showThemes = true }
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.foregroundMuted)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Theme.surface).stroke(Theme.border, lineWidth: 1))
            .buttonStyle(.plain)
            .help("Theme: \(store.appearance.label)")
        }
    }

    private func optionChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15), action) } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, Theme.s2)
                .frame(height: 24)
                .background(Capsule().fill(Theme.surface).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func cycleSort() {
        let all = FolderSort.allCases
        let next = all[((all.firstIndex(of: store.folderSort) ?? 0) + 1) % all.count]
        store.setFolderSort(next)
    }

    /// Title on the left, three tools on the right. With a notch band the two halves sit either
    /// side of the physical notch (equal flexible halves around a notch-wide gap keep it centred).
    private var header: some View {
        HStack(spacing: 0) {
            wordmark
                .frame(maxWidth: .infinity, alignment: .leading)
            if let band { Color.clear.frame(width: band.width) }
            HStack(spacing: Theme.s1 + 2) {
                toolbarButton("Search", systemImage: "magnifyingglass",
                              active: !store.searchQuery.isEmpty, action: openSearch)
                toolbarButton(shelf == .tracking ? "Track Something" : "Add Card",
                              systemImage: "plus", action: addPrimary)
                toolbarButton("More Options", systemImage: "ellipsis", active: showOptions) {
                    withAnimation(.easeOut(duration: 0.15)) { showOptions.toggle(); showThemes = false }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: band?.height)
        .padding(.horizontal, Theme.contentInset + Theme.s1)
    }

    /// "Stowly", styled per theme: a blinking-cursor underscore for Cyberpunk, a red slash
    /// behind it for Persona.
    private var wordmark: some View {
        Text(Theme.displayText("Stowly"))
            .font(Theme.display(13))
            .foregroundStyle(Theme.titleColor)
            .overlay(alignment: .trailing) {
                if Theme.style == .cyberpunk {
                    Text("_").font(Theme.display(13)).foregroundStyle(Theme.neonCyan).offset(x: 9)
                }
            }
            .padding(.horizontal, Theme.style == .persona ? 6 : 0)
            .background {
                if Theme.style == .persona {
                    SlantedRectangle(slant: 5).fill(Theme.personaRed)
                }
            }
            .accessibilityLabel("Stowly")
    }

    /// A 22pt circular icon button for the header. Text label is kept for VoiceOver.
    private func toolbarButton(_ title: String, systemImage: String, active: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.foreground)
            .frame(width: 22, height: 22)
            .background(Circle().fill(active ? Theme.surfaceHover : Theme.surface).stroke(Theme.border, lineWidth: 1))
            .contentShape(Circle())
            .buttonStyle(.plain)
            .help(title)
    }

    private func addPrimary() {
        if shelf == .tracking { addTracking() } else { addManual() }
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
            EmptyStateArt(symbol: shelf.symbol)
            Text(Theme.displayText(emptyTitle))
                .font(Theme.display(12))
                .foregroundStyle(Theme.foreground)
            Text(emptySubtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.foregroundMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.contentInset)
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
        case .tracking: "Tap + to time what you're working on, or right-click a card and choose Start Tracking."
        case .archived: "Archive a post to keep it here for later."
        case .completed: "Mark a post done and it lands here."
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
    var selecting: Bool
    var isSelected: (Reel) -> Bool
    var onToggleSelect: (Reel) -> Void
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
                        selecting: selecting,
                        isSelected: isSelected(reel),
                        onToggleSelect: { onToggleSelect(reel) },
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

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A list area that hugs its content height but never exceeds `maxHeight` — past that it scrolls.
/// Keeps the panel compact & top-anchored when there are few cards.
///
/// Always a `ScrollView` whose height is the *measured* content height capped at `maxHeight`. When
/// the content fits, the frame equals its height (compact, top-anchored, nothing to scroll); when it
/// overflows, the frame caps and it scrolls. We deliberately do NOT swap between a bare view (fits)
/// and a ScrollView (overflows): that view-tree swap made SwiftUI replace the whole panel with a
/// transition every time expanding a folder crossed the height threshold (the "UI refreshes" bug).
/// A *fixed* `.frame(height:)` — unlike `.frame(maxHeight:)` — reports its real height as ideal in
/// DynamicNotchKit's `.fixedSize()` host, so it neither reserves the full height ("floats") nor
/// needs the swap. Height is measured with a background `GeometryReader` reading a marker's Y.
private struct SelfSizingScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0
    private let space = "ssvContent"

    // Content plus a zero-height trailing marker. The marker's Y *position* in the content's own
    // coordinate space equals the content height — we read a position (`.minY`), not a size, since
    // `geo.size`/`.height` collapse to 0 inside DynamicNotchKit's `.fixedSize()` host, while
    // committed-layout positions stay reliable (it's how the folder drag measures). The space sits
    // on this VStack so the value is scroll-offset independent.
    private var measuredContent: some View {
        VStack(spacing: 0) {
            content
            Color.clear
                .frame(height: 0)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self,
                                           value: geo.frame(in: .named(space)).minY)
                })
        }
        .coordinateSpace(name: space)
    }

    var body: some View {
        // Width is pinned three ways, all to the same `Theme.panelWidth` the panel itself uses, so a
        // wide (`fixedSize`) card can't make the ScrollView grow and bleed the cards past the
        // borders (inside DNK's `.fixedSize()` host a bare `.frame(width:)` isn't honored on the
        // first layout pass):
        //   1. hard-pin the *content* width so no `fixedSize` child can grow it,
        //   2. frame the ScrollView, and
        //   3. re-assert it as a fixed ideal width with `.fixedSize(horizontal:)`, which ignores
        //      whatever the host proposes — this is what survives the first pass.
        // Height = measured content height capped at `maxHeight` (compact when it fits, scrolls when
        // it overflows). `0` = not measured yet → fall back to `maxHeight` until the first value lands.
        ScrollView {
            measuredContent.frame(width: Theme.panelWidth)
        }
        .frame(width: Theme.panelWidth,
               height: contentHeight > 0 ? min(contentHeight, maxHeight) : maxHeight)
        .fixedSize(horizontal: true, vertical: false)
        .clipped()
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .animation(Theme.easeExpo, value: contentHeight)   // smooth grow/shrink as cards change
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
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.s2) {
            Button(action: onToggleCollapse) {
                HStack(spacing: Theme.s2) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.foregroundMuted)
                        .frame(width: 10)
                    Image(systemName: folder.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.foregroundMuted)
                    Text(Theme.displayText(folder.name))
                        .font(Theme.display(12))
                        .foregroundStyle(Theme.foreground)
                    Text("\(count)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.foregroundMuted)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(folder.name), \(count) cards")
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")

            // Drag handle, right margin, shown on hover. Drag it up/down to reorder. The gesture
            // runs in the fixed "folderList" space so offsetting the header doesn't feed back into
            // the translation (which was the source of the lag). Only on Inbox — see `canDrag`.
            if canDrag {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.foregroundMuted)
                    .opacity(hovering || isDragging ? 1 : 0)
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
                    .accessibilityHidden(true)   // reorder is also in the context menu
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
        .onHover { hovering = $0 }
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
                            .font(.system(size: 11))
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
                    .accessibilityLabel(running ? "Pause" : "Resume")
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
                    .accessibilityLabel("Stop Tracking")
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
        .background(Theme.cardShape.fill(Theme.surface).stroke(Theme.border, lineWidth: Theme.cardBorderWidth))
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
