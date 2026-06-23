import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notchController: NotchController?
    private let store = LibraryStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        // Bring up the notch pill. On notched Macs this shows a compact pill beside
        // the notch; hovering it expands the queue. On non-notch Macs the status-item
        // menu is the way in (compact isn't supported there).
        notchController = NotchController(store: store)
        Task { await notchController?.showPill() }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "tray.full",
            accessibilityDescription: "Reel Planner"
        )

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open Queue",
            action: #selector(openQueue),
            keyEquivalent: "o"
        ).target = self
        menu.addItem(
            withTitle: "Add Reel from Clipboard",
            action: #selector(addFromClipboard),
            keyEquivalent: "v"
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Reel Planner",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        item.menu = menu
        statusItem = item
    }

    @objc private func openQueue() {
        Task { await notchController?.expand() }
    }

    @objc private func addFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let raw = pasteboard.string(forType: .string) else {
            notify("Clipboard is empty", "Copy an Instagram reel link first.")
            return
        }
        if store.addReel(urlString: raw) != nil {
            Task { await notchController?.expand() }
        } else {
            notify("Couldn't add that", "Not a new Instagram link (or already in your queue).")
        }
    }

    private func notify(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
