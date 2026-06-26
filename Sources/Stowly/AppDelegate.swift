import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var aiMenuItem: NSMenuItem?
    private var appearanceItems: [AppAppearance: NSMenuItem] = [:]
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

        // Bring up the notch pill. On notched Macs this shows a compact pill beside
        // the notch; hovering it expands the queue. On non-notch Macs the status-item
        // menu is the way in (compact isn't supported there).
        notchController = NotchController(store: store)
        Task { await notchController?.showPill() }

        // Clear any stale download fragments a previous run's failed extraction left behind.
        ReelExtractor.sweepCache()

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
        menu.addItem(
            withTitle: "Set Up iPhone Sync…",
            action: #selector(setUpiPhoneSync),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        let aiItem = menu.addItem(
            withTitle: AIConfig.usingGemini ? "AI: Gemini ✓ (change key…)" : "AI: Use Gemini (set API key…)",
            action: #selector(setGeminiKey),
            keyEquivalent: ""
        )
        aiItem.target = self
        aiMenuItem = aiItem

        // Panel Position: nudge the expanded panel up/down so its header clears the physical
        // notch (DynamicNotchKit's inset under-measures it on some Macs).
        let positionItem = menu.addItem(withTitle: "Panel Position", action: nil, keyEquivalent: "")
        let positionMenu = NSMenu()
        positionMenu.addItem(
            withTitle: "Move Down",
            action: #selector(movePanelDown),
            keyEquivalent: ""
        ).target = self
        positionMenu.addItem(
            withTitle: "Move Up",
            action: #selector(movePanelUp),
            keyEquivalent: ""
        ).target = self
        positionMenu.addItem(.separator())
        positionMenu.addItem(
            withTitle: "Reset to Default",
            action: #selector(resetPanelPosition),
            keyEquivalent: ""
        ).target = self
        positionItem.submenu = positionMenu

        // Appearance: Light / Dark / System (System follows the macOS setting).
        let appearanceItem = menu.addItem(withTitle: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        for mode in AppAppearance.allCases {
            let item = appearanceMenu.addItem(
                withTitle: mode.label,
                action: #selector(changeAppearance(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode
            item.state = store.appearance == mode ? .on : .off
            appearanceItems[mode] = item
        }
        appearanceMenu.delegate = self   // refresh checkmarks if changed via the header toggle
        appearanceItem.submenu = appearanceMenu

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Stowly",
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
            // Don't auto-expand — the white pill glow signals the reel arrived; hover to view.
        } else {
            notify("Couldn't add that", "Not a new supported link (Instagram, TikTok, YouTube, LinkedIn, X, Handshake) — or it's already in your queue.")
        }
    }

    @objc private func setUpiPhoneSync() {
        let address = inboxRelay.publishURL

        // Copy the address so the user can paste it straight into the Shortcut.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(address, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Send posts from your iPhone"
        alert.informativeText = """
        Your private inbox address (copied to clipboard — keep it secret):

            \(address)

        One-time iOS Shortcut setup:

        1. Shortcuts app → + → rename it "Stowly".
        2. Tap ⓘ → turn on "Show in Share Sheet"; tap "Receive Input"
           and set the types to URLs AND Text. Tap Done.
           (Text matters: LinkedIn / X share the post as text with a link,
            not a bare URL — without Text the action is hidden there.)
        3. Add Action → "Text". Tap the field → Insert Variable →
           Shortcut Input.
        4. Add "Get Contents of URL" → Show More:
             • URL: the address above
             • Method: POST
             • Request Body: File  →  pick the Text from step 3
           (File, not JSON/Form — ntfy reads the raw body as the message.)
        5. Done. From any post — Instagram, TikTok, YouTube, LinkedIn, X,
           Handshake — tap Share → More → Stowly.

        The Mac pulls the link out of whatever you share. Posts appear here
        automatically — even on cellular.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Copy Address Again")
        if runModalAboveNotch(alert) == .alertSecondButtonReturn {
            pasteboard.clearContents()
            pasteboard.setString(address, forType: .string)
        }
    }

    @objc private func setGeminiKey() {
        let existing = Keychain.get(KeychainAccount.geminiAPIKey)

        let alert = NSAlert()
        alert.messageText = "Gemini API key"
        alert.informativeText = """
        Paste a free Gemini API key to use Google's \(AIConfig.geminiModelName) — far better reel \
        summaries, and it reads the video itself (on-screen text + visuals). Leave empty to \
        clear it and go back to the local model.

        Get a free key at: aistudio.google.com/apikey

        Note: with Gemini on, the reel's video is sent to Google for processing.
        """
        alert.alertStyle = .informational

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = existing == nil ? "Paste API key…" : "•••• (set — paste to replace)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard runModalAboveNotch(alert) == .alertFirstButtonReturn else { return }

        let entered = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty input with an existing key = clear; empty with no key = no-op.
        if entered.isEmpty {
            if existing != nil {
                Keychain.delete(KeychainAccount.geminiAPIKey)
                notify("Switched to local model", "Gemini key cleared. Reels now use local Ollama.")
            }
        } else {
            Keychain.set(entered, account: KeychainAccount.geminiAPIKey)
            notify("Gemini enabled", "New reels will be understood by Gemini \(AIConfig.geminiModelName).")
        }
        aiMenuItem?.title = AIConfig.usingGemini ? "AI: Gemini ✓ (change key…)" : "AI: Use Gemini (set API key…)"
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

    // MARK: Panel position

    /// Nudge the expanded panel down 4px and re-show it so the change is visible immediately.
    @objc private func movePanelDown() {
        store.nudgeNotchOffset(by: 4)
        Task { await notchController?.expand() }
    }

    /// Nudge the expanded panel up 4px and re-show it.
    @objc private func movePanelUp() {
        store.nudgeNotchOffset(by: -4)
        Task { await notchController?.expand() }
    }

    /// Restore the built-in default clearance.
    @objc private func resetPanelPosition() {
        store.resetNotchTopOffset()
        Task { await notchController?.expand() }
    }

    /// Switch the app appearance from the menu and refresh the submenu checkmarks. Stays in
    /// sync with the in-panel header toggle since both read/write `store.appearance`.
    @objc private func changeAppearance(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? AppAppearance else { return }
        store.setAppearance(mode)
        for (m, item) in appearanceItems { item.state = m == mode ? .on : .off }
    }

    /// Keep the Appearance submenu's checkmarks in sync when it's opened (covers changes made
    /// from the in-panel header toggle).
    func menuNeedsUpdate(_ menu: NSMenu) {
        for (mode, item) in appearanceItems { item.state = store.appearance == mode ? .on : .off }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
