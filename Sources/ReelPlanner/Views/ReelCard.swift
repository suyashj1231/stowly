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
    var onOpenLink: (ReelLink) -> Void
    var onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Theme.s3) {
                Circle()
                    .fill(reel.status.dotColor)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: Theme.s1) {
                    Text(reel.task)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(reel.summary)
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
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.foregroundMuted.opacity(hovering ? 0.9 : 0.4))
                    .padding(.top, 3)
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
