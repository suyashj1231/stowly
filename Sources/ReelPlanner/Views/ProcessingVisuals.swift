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

/// One-shot green border glow that flashes whenever `token` changes (reel added / processed).
private struct GreenGlow: ViewModifier {
    let token: Int
    let cornerRadius: CGFloat
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(red: 0.30, green: 0.85, blue: 0.50), lineWidth: 2)
                    .shadow(color: Color(red: 0.30, green: 0.85, blue: 0.50).opacity(0.7), radius: 7)
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
    func greenGlow(token: Int, cornerRadius: CGFloat) -> some View {
        modifier(GreenGlow(token: token, cornerRadius: cornerRadius))
    }
}
