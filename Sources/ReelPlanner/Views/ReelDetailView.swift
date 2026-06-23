import SwiftUI

/// Full detail for a single reel: task, summary, extracted links (each opens in the
/// browser), and a prominent "Open original reel" action.
struct ReelDetailView: View {
    let reel: Reel
    let folder: Folder?
    var onBack: () -> Void
    var onOpenURL: (URL) -> Void

    private var accent: Color { folder?.accent ?? Theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            backBar

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s4) {
                    header
                    if !reel.summary.isEmpty {
                        Text(reel.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.foreground.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
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
        .padding(.horizontal, Theme.s4)
    }
}
