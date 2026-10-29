import AppKit
import StowlyShared

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notchController: NotchController?
    private let store = LibraryStore()
    private lazy var processingQueue = ProcessingQueue(store: store)
    private lazy var inboxRelay = InboxRelay(store: store, queue: processingQueue)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply the saved appearance before any window appears (nil = follow the system).
        NSApp.appearance = store.appearance.nsAppearance

        setUpStatusItem()

        // Let the store re-submit reels to the processing queue (card retry button).
        store.requestProcessing = { [weak self] reel in self?.processingQueue.enqueue(reel) }
        store.requestReclassify = { [store] reel in
            let id = reel.persistentModelID
            Task {
                store.processingIDs.insert(id)
                await ReelProcessor.reclassify(reel, store: store)
                store.processingIDs.remove(id)
            }
        }

        // Bring up the notch pill. On notched Macs this shows a compact pill beside
        // the notch; hovering it expands the queue. On non-notch Macs the status-item
        // menu is the way in (compact isn't supported there).
        notchController = NotchController(store: store)
        Task { await notchController?.showPill() }

        // Clear any stale download fragments a previous run's failed extraction left behind.
        ReelExtractor.sweepCache()
        if AppleProvider.isAvailable { AppleProvider.warmUp() }

        // Re-process any reels that were added but never finished parsing (e.g. prior crash/quit).
        processingQueue.enqueuePending()

        // Listen for reels shared from the phone (iOS Shortcut → ntfy relay).
        inboxRelay.start()

        // Headless pipeline self-test: REEL_TEST_URL=<reel> ./Stowly
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

    func applicationWillTerminate(_ notification: Notification) {
        // Don't count time spent with the app closed as worked time — freeze any running timers.
        store.pauseAllRunning()
    }

    private func log(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "tray.full",
            accessibilityDescription: "Stowly"
        )

        // Kept to what a normal user needs. The panel sits at a fixed position, appearance lives
        // on the panel header, and the AI is always Apple's on-device model — no settings here.
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Stowly", action: #selector(openQueue), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Add Link from Clipboard", action: #selector(addFromClipboard), keyEquivalent: "v").target = self
        menu.addItem(withTitle: "Connect iPhone…", action: #selector(setUpiPhoneSync), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let fullScreenItem = menu.addItem(withTitle: "Hide in Full Screen", action: #selector(toggleHideInFullScreen(_:)), keyEquivalent: "")
        fullScreenItem.target = self
        fullScreenItem.state = NotchController.hidesInFullScreen ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Stowly", action: #selector(quit), keyEquivalent: "q").target = self

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleHideInFullScreen(_ sender: NSMenuItem) {
        NotchController.hidesInFullScreen.toggle()
        sender.state = NotchController.hidesInFullScreen ? .on : .off
        notchController?.refreshFullScreen()
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
            // Don't auto-expand — the white pill glow signals the reel arrived; hover to view.
        } else {
            notify("Couldn't add that", "Not a new supported link (Instagram, TikTok, YouTube, LinkedIn, X, Handshake) — or it's already in your queue.")
        }
    }

    @objc private func setUpiPhoneSync() {
        let address = inboxRelay.publishURL
        let pairingURL = Pairing.url(topic: inboxRelay.topic).absoluteString

        let alert = NSAlert()
        alert.messageText = "Pair your iPhone"
        alert.informativeText = """
        Open Stowly on your iPhone and scan this code. After that, Share → Stowly \
        from any app sends the post straight here (works on cellular too).

        The code holds your private inbox address, unique to this Mac — keep it to yourself.
        """
        alert.alertStyle = .informational
        alert.accessoryView = pairingView(qrPayload: pairingURL, address: address)
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Copy Address")
        alert.addButton(withTitle: "Use a Shortcut Instead…")

        switch runModalAboveNotch(alert) {
        case .alertSecondButtonReturn:
            copyToClipboard(address)
        case .alertThirdButtonReturn:
            showShortcutSetup(address: address)
        default:
            break
        }
    }

    /// QR code + the plain address beneath it (selectable, for pasting on the phone).
    private func pairingView(qrPayload: String, address: String) -> NSView {
        let qr = NSImageView()
        qr.image = Pairing.qrImage(for: qrPayload, size: 220)
        qr.imageScaling = .scaleNone
        qr.setAccessibilityLabel("Pairing QR code")

        let label = NSTextField(labelWithString: address)
        label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.isSelectable = true

        let stack = NSStackView(views: [qr, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: 260)
        return stack
    }

    private func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Fallback for people without the iPhone app: the hand-built iOS Shortcut.
    private func showShortcutSetup(address: String) {
        // Copy the address so the user can paste it straight into the Shortcut.
        copyToClipboard(address)

        let alert = NSAlert()
        alert.messageText = "Send posts from your iPhone"
        alert.informativeText = """
        Your private inbox address — copied to clipboard. Keep it secret, and
        note it's unique to this Mac (every install gets its own):

            \(address)

        One-time iOS Shortcut setup:

        1. Shortcuts app → + → rename it "Stowly".
        2. Tap ⓘ → turn on "Show in Share Sheet". Under "Receive", set the
           accepted types to URLs AND Text, then tap Done.
           (Text matters: LinkedIn / X share a post as text with a link,
            not a bare URL — without Text, Stowly won't appear there.)
        3. Add Action → "Text". Tap the field → Insert Variable →
           Shortcut Input.
        4. Add "Get Contents of URL" → Show More:
             • URL: paste the address above, exactly
             • Method: POST
             • Request Body: File  →  pick the Text from step 3
           (File, not JSON/Form — ntfy reads the raw body as the message.)
        5. Tap Done.

        Test it: open Safari → Share → Stowly. The page should land on your
        Mac within a few seconds (works on cellular too).

        Not arriving? Re-open this dialog and check the Shortcut's URL matches
        the address above character-for-character. The address is regenerated
        if you reinstall or reset Stowly, so an old Shortcut can be POSTing to
        a dead address — just paste the current one in.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Copy Address Again")
        if runModalAboveNotch(alert) == .alertSecondButtonReturn {
            copyToClipboard(address)
        }
    }

    private func notify(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        runModalAboveNotch(alert)
    }

    /// Run an alert reliably from this accessory (LSUIElement) app. Two things are needed:
    /// (1) the notch panel sits at `.screenSaver` level, so the alert is lifted one step above it
    /// or it draws behind the panel; (2) an accessory app can't reliably make a modal window key,
    /// so `runModal()` could block the whole app (Quit included) behind an un-focused dialog —
    /// promoting to `.regular` for the duration fixes that. Restores the policy afterward.
    @discardableResult
    private func runModalAboveNotch(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(previousPolicy) }

        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        alert.window.makeKeyAndOrderFront(nil)
        return alert.runModal()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
