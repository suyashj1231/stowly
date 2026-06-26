import SwiftUI
import AppKit

/// Builds a `Color` that resolves to `light` or `dark` depending on the appearance of the
/// view rendering it. The whole appearance toggle hangs off this: we drive the effective
/// appearance globally via `NSApp.appearance` (see `LibraryStore.setAppearance`), and every
/// `Theme.*` token below re-resolves automatically — so call sites never change.
private func dynamicColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    })
}

/// "Native glass" design tokens.
///
/// Derived from the ui-ux-pro-max "Modern Dark (Cinema Mobile)" style + glassmorphism
/// guidance, adapted for a macOS notch panel (DynamicNotchKit already supplies the
/// translucent vibrancy background, so surfaces here are subtle opacity layers with
/// hairline borders rather than their own heavy blur). Colors that must read on both a
/// dark and a light backdrop are defined via `dynamicColor(light:dark:)`; the dark values
/// match the app's original dark-only look.
enum Theme {
    // MARK: Surfaces & borders (layered over the panel's glass)
    // Dark: subtle white-on-dark. Light: subtle black-on-light (inverted so they still read).
    static let surface = dynamicColor(light: NSColor(white: 0, alpha: 0.04),
                                      dark: NSColor(white: 1, alpha: 0.05))
    static let surfaceHover = dynamicColor(light: NSColor(white: 0, alpha: 0.07),
                                           dark: NSColor(white: 1, alpha: 0.10))
    static let border = dynamicColor(light: NSColor(white: 0, alpha: 0.12),
                                     dark: NSColor(white: 1, alpha: 0.08))
    static let borderStrong = dynamicColor(light: NSColor(white: 0, alpha: 0.20),
                                           dark: NSColor(white: 1, alpha: 0.14))

    // MARK: Text
    static let foreground = dynamicColor(
        light: NSColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1),  // #1C1C1E
        dark:  NSColor(srgbRed: 0.929, green: 0.929, blue: 0.937, alpha: 1))  // #EDEDEF
    static let foregroundMuted = dynamicColor(
        light: NSColor(srgbRed: 0.420, green: 0.440, blue: 0.470, alpha: 1),  // #6B7078
        dark:  NSColor(srgbRed: 0.541, green: 0.561, blue: 0.592, alpha: 1))  // #8A8F98

    // MARK: Panel backdrop
    // DynamicNotchKit hardcodes a black notch backdrop, so light mode needs to paint its own.
    // Dark = clear (let the library's black show through, preserving the original look);
    // light = a near-white surface that we bleed out to cover the black notch shape.
    static let panelBackground = dynamicColor(
        light: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1),
        dark:  NSColor(white: 0, alpha: 0))

    // MARK: Accent
    static let accent = Color(red: 0.369, green: 0.416, blue: 0.823)       // #5E6AD2
    static let accentGlow = Color(red: 0.369, green: 0.416, blue: 0.823).opacity(0.20)

    // MARK: Semantic action colors (saturated enough to read in both light & dark)
    static let success = Color(red: 0.30, green: 0.85, blue: 0.50) // green — complete / done
    static let danger  = Color(red: 0.94, green: 0.42, blue: 0.42) // red — delete / error
    static let warning = Color(red: 0.96, green: 0.78, blue: 0.30) // amber — archive
    static let track   = Color(red: 0.36, green: 0.66, blue: 0.95) // blue — tracking

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
    /// Horizontal inset from the panel's edges to its content (header, tabs, cards). Tighter than the
    /// 4/8 rhythm's 16pt so the cards stretch closer to the rounded sides — the side borders read as
    /// thinner without the cards hugging the edge. Everything in the column shares it, so the header,
    /// folder labels, and cards stay aligned.
    static let contentInset: CGFloat = 6
    /// Breathing room kept below the last row so it clears the panel's rounded bottom border.
    /// Kept small: DynamicNotchKit already adds a 15pt bottom safe-area inset of its own, so this
    /// only needs to top that up enough to clear the corner curve — more just reads as dead space.
    static let bottomInset: CGFloat = 6
    /// Default top offset for the expanded panel. Slightly negative pulls it up to sit snug under
    /// the notch (the header is beside the notch, so it stays visible); DynamicNotchKit's own notch
    /// inset already provides the baseline clearance. The live value is `LibraryStore.notchTopOffset`,
    /// tunable from the menu (Panel Position → Move Up/Down).
    static let notchTopClearance: CGFloat = -4

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
