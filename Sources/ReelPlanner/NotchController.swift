import SwiftUI
import AppKit
import DynamicNotchKit

/// Owns the DynamicNotch and drives the collapse/expand interaction:
/// a compact pill sits by the notch; hovering it expands the queue; moving the
/// mouse off the expanded panel collapses back to the pill.
@MainActor
final class NotchController {
    private let store: LibraryStore
    private var notch: DynamicNotch<NotchPanelView, EmptyView, CompactPill>?

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    init(store: LibraryStore) {
        self.store = store
    }

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
        DynamicNotch(hoverBehavior: .all, style: .auto) { [store] in
            NotchPanelView(
                store: store,
                onHoverEnd: { [weak self] in
                    Task { await self?.collapse() }
                },
                onOpenURL: { url in
                    NSWorkspace.shared.open(url)
                }
            )
        } compactLeading: {
            EmptyView()
        } compactTrailing: { [store] in
            CompactPill(
                store: store,
                onHoverStart: { [weak self] in
                    Task { await self?.expand() }
                }
            )
        }
    }
}
