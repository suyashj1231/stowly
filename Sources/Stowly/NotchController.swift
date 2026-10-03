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
    private var collapseTask: Task<Void, Never>?
    /// True while another app is full screen on the notch's display; the pill stays hidden.
    private var hiddenForFullScreen = false
    private var fullScreenObservers: [NSObjectProtocol] = []

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    init(store: LibraryStore) {
        self.store = store
    }

    /// Builds (once) and shows the compact pill.
    func showPill() async {
        let notch = makeNotch()
        self.notch = notch
        await notch.compact(on: screen)
        watchFullScreen()
    }

    func expand() async {
        guard !hiddenForFullScreen else { return }
        cancelCollapse()
        await notch?.expand(on: screen)
    }

    func collapse() async {
        guard !hiddenForFullScreen else { return }
        await notch?.compact(on: screen)
    }

    // MARK: Full-screen apps

    /// Hide the pill while another app is full screen (games, video, presentations) and bring it
    /// back when you leave. Re-checked on every Space / app switch; the second check catches
    /// the end of the ~0.7s full-screen animation, when the window list has settled.
    private func watchFullScreen() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        fullScreenObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.updateFullScreen()
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    await self?.updateFullScreen()
                }
            }
        }
        Task { await updateFullScreen() }
    }

    /// User setting (status menu): hide the pill while an app is full screen. On by default.
    static var hidesInFullScreen: Bool {
        get { UserDefaults.standard.object(forKey: "hideInFullScreen") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hideInFullScreen") }
    }

    /// Re-apply after the setting changes (shows the pill again if it was hidden).
    func refreshFullScreen() {
        Task { await updateFullScreen() }
    }

    private func updateFullScreen() async {
        let fullScreen = Self.hidesInFullScreen && Self.otherAppIsFullScreen(on: screen)
        guard fullScreen != hiddenForFullScreen else { return }
        if fullScreen {
            cancelCollapse()
            hiddenForFullScreen = true
            await notch?.hide()
        } else {
            hiddenForFullScreen = false
            await notch?.compact(on: screen)
        }
    }

    /// Is the display's current Space a full-screen app Space? Asked of the window server
    /// directly: on a notched Mac a full-screen window stops under the notch, and with an
    /// auto-hiding Dock it's the same size as a zoomed window, so geometry alone can't tell.
    static func otherAppIsFullScreen(on screen: NSScreen) -> Bool {
        if let fullScreen = currentSpaceIsFullScreen(on: screen) { return fullScreen }
        return fullScreenWindowGeometry(on: screen)
    }

    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias DisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    /// `CGSCopyManagedDisplaySpaces` (private, looked up at runtime so a missing symbol just
    /// falls back): each display's "Current Space" has `type` 4 when it's a full-screen Space.
    /// Nil when unavailable.
    private static func currentSpaceIsFullScreen(on screen: NSScreen) -> Bool? {
        guard let handle = dlopen(nil, RTLD_NOW),
              let connSym = dlsym(handle, "CGSMainConnectionID"),
              let spacesSym = dlsym(handle, "CGSCopyManagedDisplaySpaces")
        else { return nil }
        let conn = unsafeBitCast(connSym, to: ConnectionFn.self)()
        guard let displays = unsafeBitCast(spacesSym, to: DisplaySpacesFn.self)(conn)?
            .takeRetainedValue() as? [[String: Any]]
        else { return nil }

        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let uuid = number.flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }
            .map { CFUUIDCreateString(nil, $0) as String }
        // "Main" when "Displays have separate Spaces" is off (one Space set spans all screens).
        let display = displays.first { ($0["Display Identifier"] as? String) == uuid }
            ?? displays.first { ($0["Display Identifier"] as? String) == "Main" }
        guard let space = display?["Current Space"] as? [String: Any],
              let type = space["type"] as? Int
        else { return nil }
        return type == 4
    }

    /// Fallback: another app's normal-level window spans the full width from the top of the
    /// usable area (under the menu bar / notch) to the bottom edge. Can false-positive on a
    /// zoomed window with an auto-hiding Dock, hence only used when the Space check fails.
    private static func fullScreenWindowGeometry(on screen: NSScreen) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        // CG window bounds are top-left-origin global coordinates; convert the screen frame.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = screen.frame
        let top = primaryHeight - f.maxY
        let topInset = max(screen.safeAreaInsets.top, f.maxY - screen.visibleFrame.maxY) + 1
        let me = ProcessInfo.processInfo.processIdentifier
        return info.contains { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? pid_t) != me,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict)
            else { return false }
            return abs(b.minX - f.minX) < 1 && abs(b.width - f.width) < 1
                && b.minY <= top + topInset && abs(b.maxY - (top + f.height)) < 1
        }
    }

    /// Collapse after a short grace period (cancelled if the pointer returns). This keeps the
    /// panel open while you interact with menus, prompts, or briefly drift off the edge.
    func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)   // 0.9s grace
            guard !Task.isCancelled else { return }
            await self?.collapse()
        }
    }

    func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func makeNotch() -> DynamicNotch<NotchPanelView, EmptyView, CompactPill> {
        DynamicNotch(hoverBehavior: .all, style: .auto) { [store] in
            NotchPanelView(
                store: store,
                onHoverStart: { [weak self] in
                    self?.cancelCollapse()
                },
                onHoverEnd: { [weak self] in
                    self?.scheduleCollapse()
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
