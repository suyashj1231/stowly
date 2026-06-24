import SwiftUI

/// "Native dark glass" design tokens.
///
/// Derived from the ui-ux-pro-max "Modern Dark (Cinema Mobile)" style + glassmorphism
/// guidance, adapted for a macOS notch panel (DynamicNotchKit already supplies the
/// translucent vibrancy background, so surfaces here are subtle white-opacity layers
/// with hairline borders rather than their own heavy blur).
enum Theme {
    // MARK: Surfaces & borders (layered over the panel's glass)
    static let surface = Color.white.opacity(0.05)
    static let surfaceHover = Color.white.opacity(0.10)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.14)

    // MARK: Text
    static let foreground = Color(red: 0.929, green: 0.929, blue: 0.937)   // #EDEDEF
    static let foregroundMuted = Color(red: 0.541, green: 0.561, blue: 0.592) // #8A8F98

    // MARK: Accent
    static let accent = Color(red: 0.369, green: 0.416, blue: 0.823)       // #5E6AD2
    static let accentGlow = Color(red: 0.369, green: 0.416, blue: 0.823).opacity(0.20)

    // MARK: Status
    static let statusNew = accent
    static let statusProcessed = Color(red: 0.30, green: 0.78, blue: 0.50) // green
    static let statusDone = foregroundMuted

    // MARK: Radii
    static let panelRadius: CGFloat = 18
    static let cardRadius: CGFloat = 12
    static let chipRadius: CGFloat = 6

    // MARK: Spacing (4 / 8 rhythm)
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20

    // MARK: Layout
    static let panelWidth: CGFloat = 372
    static let panelMaxHeight: CGFloat = 440
    /// Default extra top clearance for the expanded panel so the header clears the physical
    /// notch. DynamicNotchKit's own inset under-measures the notch on some MacBooks. This is just
    /// the default — the live value is `LibraryStore.notchTopOffset`, tunable from the menu.
    static let notchTopClearance: CGFloat = 34

    // MARK: Motion — Expo.out, the signature easing of the chosen style
    static let easeExpo = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.4)
    static let pressSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)
}

extension ReelStatus {
    var dotColor: Color {
        switch self {
        case .new: Theme.statusNew
        case .processed: Theme.statusProcessed
        case .done: Theme.statusDone
        }
    }
}

extension Folder {
    /// Subtle, desaturated per-folder accent that reads on dark glass.
    var accent: Color {
        switch name {
        case "Learn / Certs":       Color(red: 0.18, green: 0.83, blue: 0.75) // teal
        case "Apply Jobs":          Color(red: 0.29, green: 0.56, blue: 0.95) // blue
        case "Apply Internships":   Color(red: 0.58, green: 0.47, blue: 0.96) // violet
        default:                    Theme.foregroundMuted                     // misc
        }
    }
}

extension Platform {
    /// Brand-ish accent that reads on dark glass (slightly desaturated from the official hue).
    var accent: Color {
        switch self {
        case .instagram: Color(red: 0.88, green: 0.19, blue: 0.42)  // magenta-pink
        case .linkedin:  Color(red: 0.16, green: 0.47, blue: 0.78)  // LinkedIn blue
        case .handshake: Color(red: 0.16, green: 0.64, blue: 0.42)  // Handshake green
        case .tiktok:    Color(red: 0.99, green: 0.17, blue: 0.33)  // TikTok red/pink
        case .youtube:   Color(red: 0.90, green: 0.22, blue: 0.21)  // YouTube red
        case .twitter:   Color(red: 0.55, green: 0.62, blue: 0.70)  // X — light slate
        case .web:       Theme.foregroundMuted
        }
    }

    /// Instagram is the one brand defined by a gradient; everyone else is a flat accent.
    var gradient: LinearGradient? {
        guard self == .instagram else { return nil }
        return LinearGradient(
            colors: [
                Color(red: 0.51, green: 0.23, blue: 0.71),  // purple #833AB4
                Color(red: 0.91, green: 0.21, blue: 0.32),  // red    #E8364F
                Color(red: 0.99, green: 0.62, blue: 0.20),  // orange #FCAF45
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// Soft glow color for the open button shadow.
    var glow: Color { accent.opacity(0.28) }
}

/// Press feedback: subtle scale, no layout shift (per style: scale 0.97–1.0).
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
