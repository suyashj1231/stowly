import SwiftUI
import DynamicNotchKit

/// Owns the DynamicNotch and drives the collapse/expand interaction:
/// a compact pill sits by the notch; hovering it expands the queue; moving the
/// mouse off the expanded panel collapses back to the pill.
@MainActor
final class NotchController {
    private var notch: DynamicNotch<NotchPanelView, EmptyView, CompactPill>?

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    /// Builds (once) and shows the compact pill.
    func showPill() async {
        let notch = makeNotch()
        self.notch = notch
        await notch.compact(on: screen)
    }

    func expand() async {
        await notch?.expand(on: screen)
    }

    func collapse() async {
        await notch?.compact(on: screen)
    }

    private func makeNotch() -> DynamicNotch<NotchPanelView, EmptyView, CompactPill> {
        let folders = MockData.folders
        let reels = MockData.reels

        return DynamicNotch(hoverBehavior: .all, style: .auto) {
            NotchPanelView(
                folders: folders,
                reels: reels,
                onHoverEnd: { [weak self] in
                    Task { await self?.collapse() }
                },
                onOpenURL: { url in
                    NSWorkspace.shared.open(url)
                }
            )
        } compactLeading: {
            EmptyView()
        } compactTrailing: {
            CompactPill(
                count: reels.count,
                onHoverStart: { [weak self] in
                    Task { await self?.expand() }
                }
            )
        }
    }
}
