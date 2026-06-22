import SwiftUI

/// The always-visible compact indicator that sits beside the notch: a glassy capsule
/// with a tray glyph and the pending-count badge. Hovering it expands the full queue.
struct CompactPill: View {
    var count: Int
    var onHoverStart: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.s1 + 1) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.foreground)

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.accent))
            }
        }
        .padding(.horizontal, Theme.s2)
        .padding(.vertical, Theme.s1)
        .background(
            Capsule(style: .continuous)
                .fill(hovering ? Theme.surfaceHover : Theme.surface)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .contentShape(Capsule(style: .continuous))
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovering = h }
            if h { onHoverStart() }
        }
    }
}
