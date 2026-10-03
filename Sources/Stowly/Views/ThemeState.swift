import Observation

/// Holds the active `ThemeStyle` as observable state. `Theme`'s tokens read it, so SwiftUI
/// tracks every view that uses a theme color, font or shape and redraws just those when the
/// theme changes — no view-tree rebuild (which made the notch panel collapse mid-click).
@Observable
final class ThemeState {
    nonisolated(unsafe) static let shared = ThemeState()
    var style: ThemeStyle = .standard
}
