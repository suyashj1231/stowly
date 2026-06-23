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
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 10, weight: .medium))
            .fixedSize(horizontal: true, vertical: false)
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
    var moveTargets: [Folder] = []
    var onMove: (Folder) -> Void = { _ in }

    @State private var hovering = false

    private var isErrored: Bool { reel.lastError != nil && !isProcessing }
    private let errorRed = Color(red: 0.94, green: 0.42, blue: 0.42)
    private let doneGreen = Color(red: 0.30, green: 0.85, blue: 0.50)
    private let archiveAmber = Color(red: 0.96, green: 0.78, blue: 0.30)

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
        return isProcessing ? "Fetching caption, transcript & tags…" : "Queued"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Theme.s3) {
                Group {
                    if isProcessing {
                        SyncSpinner(tint: accent)
                    } else {
                        Circle()
                            .fill(isErrored ? errorRed : reel.status.dotColor)
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(width: 12, height: 12)
                .padding(.top, 3)

                VStack(alignment: .leading, spacing: Theme.s1) {
                    Text(titleText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(reel.task.isEmpty ? Theme.foregroundMuted : Theme.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(summaryText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.foregroundMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: Theme.s2) {
                        Text(displayCreator)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        if !reel.links.isEmpty {
                            ForEach(reel.links) { link in
                                LinkChip(link: link) { onOpenLink(link) }
                            }
                        }
                    }
                    .padding(.top, 2)

                    if let proposed = reel.proposedFolderName, !proposed.isEmpty {
                        FolderSuggestionPill(name: proposed, onApprove: onApproveFolder, onDismiss: onDismissProposal)
                            .padding(.top, 4)
                    }
                }

                Spacer(minLength: 4)

                trailingColumn
            }
            .padding(Theme.s3)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(hovering ? Theme.surfaceHover : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(hovering ? Theme.borderStrong : Theme.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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
            Button { onComplete() } label: {
                Label(shelf == .completed ? "Mark not done" : "Mark done", systemImage: "checkmark.circle")
            }
            Button { onArchive() } label: {
                Label(shelf == .archived ? "Move to list" : "Archive", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }

    /// Right edge of the card: a persistent indicator at the vertical middle (chevron, or a
    /// retry when errored), with the hover action icons pinned to the top — so hovering no
    /// longer "replaces" the arrow.
    private var trailingColumn: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if isErrored {
                    CardActionButton(system: "arrow.clockwise", tint: errorRed, action: onRetry)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.foregroundMuted.opacity(0.4))
                        .frame(width: 20, height: 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            if hovering {
                hoverActions
            }
        }
        .frame(width: 58)
        .frame(maxHeight: .infinity)
    }

    /// Top-right actions on hover: complete, archive, delete. (No link button here — the link
    /// already shows as a chip at the bottom of the card.) The complete/archive icons stay
    /// highlighted (green / amber) while the reel is in that tab, signalling a click sends it back.
    private var hoverActions: some View {
        HStack(spacing: 2) {
            CardActionButton(
                system: shelf == .completed ? "checkmark.circle.fill" : "checkmark.circle",
                tint: doneGreen, active: shelf == .completed, action: onComplete
            )
            .help(shelf == .completed ? "Mark as not done (back to list)" : "Mark done")

            if shelf != .completed {
                CardActionButton(
                    system: shelf == .archived ? "archivebox.fill" : "archivebox",
                    tint: archiveAmber, active: shelf == .archived, action: onArchive
                )
                .help(shelf == .archived ? "Move back to list" : "Archive for later")
            }

            CardActionButton(system: "trash", tint: errorRed, action: onDelete)
                .help("Delete")
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
        HStack(spacing: Theme.s1) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
            Text("New folder: \(name)")
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)

            Button(action: onApprove) {
                HStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                    Text("Create")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.accent))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Create “\(name)” and move this reel into it")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.foregroundMuted)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Keep this reel in Misc")
        }
        .padding(.horizontal, Theme.s2)
        .padding(.vertical, 3)
        .foregroundStyle(Theme.accent)
        .background(
            RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                .fill(Theme.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
        )
    }
}

/// Small icon button revealed on card hover. `active` highlights it (filled tint) to show a
/// persistent state — e.g. amber when a reel is archived, green when it's completed.
private struct CardActionButton: View {
    let system: String
    let tint: Color
    var active: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 10, weight: .semibold))
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
        .onHover { hover = $0 }
    }
}
