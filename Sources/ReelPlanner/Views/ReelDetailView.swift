import SwiftUI

/// Full detail for a single reel: task, summary, extracted links (each opens in the
/// browser), and a prominent "Open original reel" action.
struct ReelDetailView: View {
    let reel: Reel
    let folder: Folder?
    var onBack: () -> Void
    var onOpenURL: (URL) -> Void
    var onApproveFolder: () -> Void = {}
    var onDismissProposal: () -> Void = {}
    var onRetry: () -> Void = {}

    private var accent: Color { folder?.accent ?? Theme.accent }
    private let errorRed = Color(red: 0.94, green: 0.42, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            backBar

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s4) {
                    header
                    if let err = reel.lastError, !err.isEmpty {
                        errorRetry(err)
                    } else if !reel.summary.isEmpty {
                        Text(reel.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.foreground.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let proposed = reel.proposedFolderName, !proposed.isEmpty {
                        folderSuggestion(proposed)
                    }
                }
                .padding(.horizontal, Theme.s4)
                .padding(.bottom, Theme.s4)
            }
            .frame(maxHeight: Theme.panelMaxHeight - 120)

            // Actions: extracted links first, then "Open original reel" (reels only).
            VStack(spacing: Theme.s2) {
                ForEach(reel.links) { link in
                    linkButton(link)
                }
                if !reel.isManual, !reel.originalURLString.isEmpty {
                    openOriginalButton
                }
            }
            .padding(.horizontal, Theme.s4)
        }
        .padding(.top, Theme.s3)
        .padding(.bottom, Theme.s4)
    }

    private var backBar: some View {
        Button(action: onBack) {
            HStack(spacing: Theme.s1) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Label(folder?.name ?? "Back", systemImage: folder?.symbol ?? "tray.full")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.foregroundMuted)
            .padding(.horizontal, Theme.s4)
            .padding(.bottom, Theme.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack(spacing: Theme.s2) {
                Circle().fill(reel.status.dotColor).frame(width: 7, height: 7)
                Text(reel.creator)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accent)
            }
            Text(reel.task)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.s1)
    }

    /// Processing failed — show why + a retry (e.g. after restarting Ollama or a rate-limit window).
    private func errorRetry(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Couldn't process this reel")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(errorRed)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.foreground.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRetry) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try again")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.s3)
                .padding(.vertical, 6)
                .background(Capsule().fill(errorRed))
            }
            .buttonStyle(PressableCardStyle())
        }
        .padding(Theme.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(errorRed.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(errorRed.opacity(0.3), lineWidth: 1)
        )
    }

    /// AI proposed a folder that doesn't exist yet — offer to create it or keep the reel in Misc.
    private func folderSuggestion(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("Suggested new folder")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)

            Text(name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.foreground)

            HStack(spacing: Theme.s2) {
                Button(action: onApproveFolder) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Create folder")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.s3)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(PressableCardStyle())

                Button(action: onDismissProposal) {
                    Text("Keep in Misc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.foregroundMuted)
                        .padding(.horizontal, Theme.s3)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.surface))
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(PressableCardStyle())
            }
        }
        .padding(Theme.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
        )
    }

    private func linkButton(_ link: ReelLink) -> some View {
        Button { onOpenURL(link.url) } label: {
            HStack(spacing: Theme.s2) {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .semibold))
                Text("Open \(link.label)")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, Theme.s3)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(accent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(accent.opacity(0.5), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
    }

    private var openOriginalButton: some View {
        Button { onOpenURL(reel.originalURL) } label: {
            HStack(spacing: Theme.s2) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Open original reel")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.s3)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.accent)
                    .shadow(color: Theme.accentGlow, radius: 8, y: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
    }
}
