import SwiftUI

/// A small chip representing an extracted link (label + arrow). Tappable.
struct LinkChip: View {
    var link: ReelLink
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(link.label)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 10, weight: .medium))
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

    @State private var hovering = false

    private var isErrored: Bool { reel.lastError != nil && !isProcessing }
    private let errorRed = Color(red: 0.94, green: 0.42, blue: 0.42)

    private var titleText: String {
        if !reel.task.isEmpty { return reel.task }
        return isProcessing ? "Reading reel…" : "New reel"
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
                        Text(reel.creator)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(accent)

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

                Spacer(minLength: 0)

                Group {
                    if hovering {
                        HStack(spacing: Theme.s1) {
                            if isErrored {
                                CardActionButton(system: "arrow.clockwise", tint: errorRed, action: onRetry)
                            } else if let link = reel.links.first {
                                CardActionButton(system: "link", tint: accent) { onOpenLink(link) }
                            }
                            CardActionButton(system: "trash", tint: errorRed, action: onDelete)
                        }
                    } else if isErrored {
                        // Always-visible retry when a reel failed (Ollama off, Gemini limit, …).
                        CardActionButton(system: "arrow.clockwise", tint: errorRed, action: onRetry)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.foregroundMuted.opacity(0.4))
                            .frame(width: 20, height: 20)
                    }
                }
                .padding(.top, 1)
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

/// Small icon button revealed on card hover (open-link / delete).
private struct CardActionButton: View {
    let system: String
    let tint: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hover ? tint : Theme.foregroundMuted)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hover ? Theme.surfaceHover : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
