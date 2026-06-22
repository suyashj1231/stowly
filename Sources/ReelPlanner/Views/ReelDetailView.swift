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
                    Text(reel.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.foreground.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)

                    if !reel.links.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.s2) {
                            Text("LINKS")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(Theme.foregroundMuted)
                            ForEach(reel.links) { link in
                                linkRow(link)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.s4)
                .padding(.bottom, Theme.s4)
            }
            .frame(maxHeight: Theme.panelMaxHeight - 80)

            openOriginalButton
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

    private func linkRow(_ link: ReelLink) -> some View {
        Button { onOpenURL(link.url) } label: {
            HStack(spacing: Theme.s2) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text(link.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.foregroundMuted)
            }
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, Theme.s2 + 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
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
