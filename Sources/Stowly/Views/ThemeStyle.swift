import Foundation

/// The look the `Theme` tokens resolve to. `standard` is the regular light/dark design; the
/// others are dark-only, game-inspired skins chosen from the Appearance button.
enum ThemeStyle {
    case standard
    /// Near-black, neon yellow + cyan, cut corners, monospaced labels.
    case cyberpunk
    /// Black, white and bold red, heavy italic uppercase headings, slanted shapes.
    case persona
}
