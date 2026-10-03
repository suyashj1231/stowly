import SwiftUI

/// A small chip representing an extracted link (label + arrow). Tappable.
struct LinkChip: View {
    var link: ReelLink
    var action: () -> Void

    @State private var hovering = false

    /// Keep the chip to one short line. Trim to a few words; if it's one giant word
    /// (or empty), just say "Link".
    private var displayLabel: String {
        let l = link.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if l.isEmpty { return "Link" }
        if !l.contains(" "), l.count > 16 { return "Link" }        // single huge token
        if l.count > 22 {
            return String(l.prefix(22)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return l
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(displayLabel)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .font(.system(size: 10, weight: .medium))
            // No horizontal `fixedSize`: in the card's tight metadata row the chip must be allowed
            // to compress (the label truncates via its own `lineLimit(1)`) instead of forcing the
            // whole card wider than the panel column — which, inside DynamicNotchKit's `.fixedSize()`
            // host, punches through the scroll view's pinned width and bleeds the cards.
            .foregroundStyle(hovering ? Theme.foreground : Theme.foregroundMuted)
            .padding(.horizontal, Theme.s2)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                    .fill(hovering ? Theme.surfaceHover : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// One reel rendered as a card: status dot, task title, summary, @creator, link chips.
struct ReelCard: View {
    var reel: Reel
    var accent: Color
    var isProcessing: Bool
    var onOpenLink: (ReelLink) -> Void
    var onDelete: () -> Void
    var onSelect: () -> Void
    var onApproveFolder: () -> Void = {}
    var onDismissProposal: () -> Void = {}
    var onRetry: () -> Void = {}
    var shelf: Shelf = .active
    var onComplete: () -> Void = {}
    var onArchive: () -> Void = {}
    var isTracking: Bool = false
    var onToggleTracking: () -> Void = {}
    var selecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: () -> Void = {}
    var moveTargets: [Folder] = []
    var onMove: (Folder) -> Void = { _ in }

    @State private var hovering = false

    private var isErrored: Bool { reel.lastError != nil && !isProcessing }
    private let errorRed = Theme.danger
    private let doneGreen = Theme.success
    private let archiveAmber = Theme.warning
    private let trackBlue = Theme.track

    /// A leading marker only when there's something to notice: selecting, processing, an error,
    /// or a post that hasn't been read yet. Finished cards stay clean.
    private var showsMarker: Bool {
        selecting || isProcessing || isErrored || reel.status == .new
    }

    private var titleText: String {
        if !reel.task.isEmpty { return reel.task }
        return isProcessing ? "Reading reel…" : "New reel"
    }

    /// Keep the creator handle on one line — handles are a single token, so just clip with an
    /// ellipsis rather than falling back to a generic word.
    private var displayCreator: String {
        let c = reel.creator.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.count > 16 ? String(c.prefix(15)) + "…" : c
    }

    private var summaryText: String {
        if !reel.summary.isEmpty { return reel.summary }
        if reel.isManual { return "" }   // hand-made note: no pipeline status to report
        return isProcessing ? "Fetching caption, transcript & tags…" : "Queued"
    }

    var body: some View {
        Button(action: selecting ? onToggleSelect : onSelect) {
            HStack(alignment: .top, spacing: Theme.s3) {
                if showsMarker {
                Group {
                    if selecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? accent : Theme.foregroundMuted)
                    } else if isProcessing {
                        SyncSpinner(tint: accent)
                    } else {
                        Circle()
                            .fill(isErrored ? errorRed : reel.status.dotColor)
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(width: 12, height: 12)
                .padding(.top, 3)
                }

                VStack(alignment: .leading, spacing: Theme.s1) {
                    Text(titleText)
                        .font(Theme.display(13))
                        .foregroundStyle(reel.task.isEmpty ? Theme.foregroundMuted : Theme.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !summaryText.isEmpty {
                        Text(summaryText)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.foregroundMuted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: Theme.s2) {
                        PlatformBadge(platform: reel.platform, size: 13)

                        Text(displayCreator)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.foregroundMuted)
                            .lineLimit(1)
                            // Prefer keeping the handle over the link chip when the row is tight,
                            // but stay compressible (no `fixedSize`) so it can never push the card
                            // past the column width.
                            .layoutPriority(1)

                        if !reel.links.isEmpty {
                            ForEach(reel.links) { link in
                                LinkChip(link: link) { onOpenLink(link) }
                            }
                        }

                        if reel.trackingLoggedSeconds > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "stopwatch")
                                Text(loggedDurationString(seconds: reel.trackingLoggedSeconds))
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(trackBlue)
                            .help("Time worked")
                            .accessibilityLabel("Time worked: \(loggedDurationString(seconds: reel.trackingLoggedSeconds))")
                        }
                    }
                    .padding(.top, 2)

                    if let proposed = reel.proposedFolderName, !proposed.isEmpty {
                        FolderSuggestionPill(name: proposed, onApprove: onApproveFolder, onDismiss: onDismissProposal)
                            .padding(.top, 4)
                    }
                }

                Spacer(minLength: Theme.s2)

                if !selecting, isErrored {
                    CardActionButton(system: "arrow.clockwise", label: "Retry", tint: errorRed, action: onRetry)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .padding(Theme.s3)
            .padding(.horizontal, Theme.style == .persona ? 4 : 0)   // room for the slanted edges
            .background(
                Theme.cardShape
                    .fill(isSelected ? accent.opacity(0.10) : (hovering ? Theme.surfaceHover : Theme.surface))
                    .stroke(isSelected ? accent.opacity(0.8) : (hovering ? Theme.borderStrong : Theme.border),
                            lineWidth: isSelected ? 1.5 : Theme.cardBorderWidth)
            )
            .contentShape(Theme.cardShape)
            // Actions float in over the top-right on hover (frosted chip) instead of living in a
            // permanently reserved column — so the title & summary get the card's full width.
            .overlay(alignment: .topTrailing) {
                if hovering && !selecting {
                    hoverActions
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                        .padding(6)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)))
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovering = h }
        }
        .contextMenu {
            if !moveTargets.isEmpty {
                Menu("Move to") {
                    ForEach(moveTargets) { folder in
                        Button { onMove(folder) } label: { Label(folder.name, systemImage: folder.symbol) }
                    }
                }
            }
            Button { onToggleTracking() } label: {
                Label(isTracking ? "Stop tracking" : "Start tracking",
                      systemImage: isTracking ? "stop.circle" : "stopwatch")
            }
            Button { onComplete() } label: {
                Label(shelf == .completed ? "Mark not done" : "Mark done", systemImage: "checkmark.circle")
            }
            Button { onArchive() } label: {
                Label(shelf == .archived ? "Move Back to Inbox" : "Archive", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }

    /// Top-right actions on hover: done, archive, delete. Tracking lives in the context menu.
    /// The done/archive icons stay highlighted while the reel is in that tab, signalling a click
    /// sends it back.
    private var hoverActions: some View {
        HStack(spacing: 2) {
            CardActionButton(
                system: shelf == .completed ? "checkmark.circle.fill" : "checkmark.circle",
                label: shelf == .completed ? "Mark Not Done" : "Mark Done",
                tint: doneGreen, active: shelf == .completed, action: onComplete
            )

            if shelf != .completed {
                CardActionButton(
                    system: shelf == .archived ? "archivebox.fill" : "archivebox",
                    label: shelf == .archived ? "Move Back to Inbox" : "Archive",
                    tint: archiveAmber, active: shelf == .archived, action: onArchive
                )
            }

            CardActionButton(system: "trash", label: "Delete", tint: errorRed, action: onDelete)
        }
    }
}

/// Inline affordance shown when the AI proposed a new folder for this reel: name + create /
/// dismiss. Tapping "create" makes the folder and moves the reel; "dismiss" leaves it in Misc.
private struct FolderSuggestionPill: View {
    let name: String
    let onApprove: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.s2) {
            Text("Create “\(name)” folder?")
                .font(.system(size: 11))
                .foregroundStyle(Theme.foregroundMuted)
                .lineLimit(1)
            Button("Create", action: onApprove)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
                .help("Create “\(name)” and move this post into it")
            Button(action: onDismiss) {
                Label("Not Now", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.foregroundMuted)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())   // inside the label so the whole square is clickable
            }
            .buttonStyle(.plain)
            .help("Keep this post in Misc")
        }
    }
}

/// Small icon button revealed on card hover. `active` highlights it (filled tint) to show a
/// persistent state — e.g. amber when a reel is archived, green when it's completed.
private struct CardActionButton: View {
    let system: String
    let label: String
    let tint: Color
    var active: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .accessibilityLabel(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active || hover ? tint : Theme.foregroundMuted)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? tint.opacity(0.18) : (hover ? Theme.surfaceHover : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(active ? tint.opacity(0.55) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { hover = $0 }
    }
}
