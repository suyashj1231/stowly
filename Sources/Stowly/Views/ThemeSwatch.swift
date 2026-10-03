import SwiftUI

/// One theme choice in the picker: a small circle previewing the theme's colors, ringed when
/// it's the current one.
struct ThemeSwatch: View {
    let appearance: AppAppearance
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            fill
                .frame(width: 18, height: 18)
                .clipShape(Circle())
                .overlay { Circle().stroke(.white.opacity(0.25), lineWidth: 1) }
                .padding(3)
                .overlay { Circle().stroke(isSelected ? Theme.accent : .clear, lineWidth: 2) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(appearance.label)
        .accessibilityLabel("\(appearance.label) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var fill: some View {
        switch appearance {
        case .system:
            HStack(spacing: 0) {
                Color(white: 0.95)
                Color(white: 0.12)
            }
        case .light: Color(white: 0.95)
        case .dark: Color(white: 0.12)
        case .cyberpunk:
            ZStack(alignment: .bottomTrailing) {
                Theme.neonYellow
                Theme.neonCyan.frame(width: 8, height: 8)
            }
        case .persona:
            ZStack {
                Theme.personaRed
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
            }
        }
    }
}
