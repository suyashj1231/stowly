import SwiftUI

/// A small continuously-rotating sync glyph shown on cards while a reel is being parsed.
struct SyncSpinner: View {
    var tint: Color = Theme.accent
    @State private var spinning = false

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(tint)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

/// Semantic glow colors: white = a reel arrived, green = the whole queue finished cleanly,
/// red = a reel errored.
enum GlowColor {
    case white, green, red

    var color: Color {
        switch self {
        case .white: Theme.foreground   // adapts: bright on dark, dark on light, so it always reads
        case .green: Theme.success
        case .red:   Theme.danger
        }
    }
}

/// One-shot border glow that flashes (in `color`) whenever `token` changes.
private struct Glow: ViewModifier {
    let token: Int
    let color: Color
    let cornerRadius: CGFloat
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color, lineWidth: 2)
                    .shadow(color: color.opacity(0.7), radius: 7)
                    .opacity(opacity)
                    .allowsHitTesting(false)
            )
            .onChange(of: token) { _, _ in
                opacity = 0.95
                withAnimation(.easeOut(duration: 1.1)) { opacity = 0 }
            }
    }
}

extension View {
    func glow(token: Int, color: Color, cornerRadius: CGFloat) -> some View {
        modifier(Glow(token: token, color: color, cornerRadius: cornerRadius))
    }
}
