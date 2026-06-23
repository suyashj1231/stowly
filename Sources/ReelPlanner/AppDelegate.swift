import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notchController: NotchController?
    private let store = LibraryStore()
    private lazy var processingQueue = ProcessingQueue(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        // Bring up the notch pill. On notched Macs this shows a compact pill beside
        // the notch; hovering it expands the queue. On non-notch Macs the status-item
        // menu is the way in (compact isn't supported there).
        notchController = NotchController(store: store)
        Task { await notchController?.showPill() }

        // Re-process any reels that were added but never finished parsing (e.g. prior crash/quit).
        processingQueue.enqueuePending()

        // Headless pipeline self-test: REEL_TEST_URL=<reel> ./ReelPlanner
        if let testURL = ProcessInfo.processInfo.environment["REEL_TEST_URL"] {
            Task {
                let reel = store.reels.first { $0.originalURLString == testURL } ?? store.addReel(urlString: testURL)
                guard let reel else { log("self-test: could not create reel"); return }
                log("self-test: processing \(testURL) …")
                await ReelProcessor.process(reel, store: store)
                log("""
                self-test result:
                  task:   \(reel.task)
                  folder: \(reel.folder?.name ?? "-")
                  creator:\(reel.creator)
                  links:  \(reel.links.map { "\($0.label)=\($0.urlString)" })
                  status: \(reel.status.rawValue)
                  summary:\(reel.summary)
                """)
            }
        }
    }

    private func log(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
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
        if let reel = store.addReel(urlString: raw) {
            processingQueue.enqueue(reel)
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
