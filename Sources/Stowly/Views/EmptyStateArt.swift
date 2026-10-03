import SwiftUI

/// Small looping animation shown on empty tabs, drawn per theme: a calm pulse (standard), a
/// glitching symbol over moving scanlines (Cyberpunk), or a spinning red star (Persona).
/// Holds still when Reduce Motion is on.
struct EmptyStateArt: View {
    let symbol: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            switch Theme.style {
            case .standard: pulse(t)
            case .cyberpunk: glitch(t)
            case .persona: star(t)
            }
        }
        .frame(width: 64, height: 48)
        .accessibilityHidden(true)
    }

    private func pulse(_ t: Double) -> some View {
        let phase = (sin(t * 1.6) + 1) / 2   // 0…1, ~4s breath
        return Image(systemName: symbol)
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(Theme.foregroundMuted)
            .scaleEffect(1 + 0.06 * phase)
            .opacity(0.6 + 0.4 * phase)
    }

    private func glitch(_ t: Double) -> some View {
        // Mostly steady, with a short burst of RGB-split jitter every ~2.5s.
        let cycle = t.truncatingRemainder(dividingBy: 2.5)
        let bursting = cycle < 0.22
        let jitter = bursting ? CGFloat(sin(t * 90) * 3) : 0
        let icon = Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
        return ZStack {
            // Scanlines drifting down.
            VStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { _ in
                    Rectangle().fill(Theme.neonYellow.opacity(0.08)).frame(height: 1)
                }
            }
            .offset(y: CGFloat(t.truncatingRemainder(dividingBy: 1)) * 4)
            .clipped()
            icon.foregroundStyle(Theme.neonCyan.opacity(bursting ? 0.8 : 0)).offset(x: -jitter - 1.5)
            icon.foregroundStyle(Color(red: 1, green: 0.16, blue: 0.43).opacity(bursting ? 0.8 : 0)).offset(x: jitter + 1.5)
            icon.foregroundStyle(Theme.neonYellow).offset(x: jitter / 2)
        }
    }

    private func star(_ t: Double) -> some View {
        ZStack {
            Image(systemName: "star.fill")
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(Theme.personaRed)
                .rotationEffect(.degrees(t * 40))
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-8))
        }
    }
}
