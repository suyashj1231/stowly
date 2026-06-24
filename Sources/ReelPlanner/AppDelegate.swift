import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var aiMenuItem: NSMenuItem?
    private var notchController: NotchController?
    private let store = LibraryStore()
    private lazy var processingQueue = ProcessingQueue(store: store)
    private lazy var inboxRelay = InboxRelay(store: store, queue: processingQueue)

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            // Don't auto-expand — the white pill glow signals the reel arrived; hover to view.
        } else {
            notify("Couldn't add that", "Not a new Instagram link (or already in your queue).")
        }
    }

    @objc private func setUpiPhoneSync() {
        let address = inboxRelay.publishURL

        // Copy the address so the user can paste it straight into the Shortcut.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(address, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Send reels from your iPhone"
        alert.informativeText = """
        Your private reel address (copied to clipboard — keep it secret):

            \(address)

        One-time iOS Shortcut setup:

        1. Shortcuts app → + → rename it "Reel Planner".
        2. Tap ⓘ → turn on "Show in Share Sheet"; tap "Receive Input"
           and set the type to URLs only. Tap Done.
        3. Add Action → "Text". Tap the field → Insert Variable →
           Shortcut Input (the reel URL).
        4. Add "Get Contents of URL" → Show More:
             • URL: the address above
             • Method: POST
             • Request Body: File  →  pick the Text from step 3
           (File, not JSON/Form — ntfy reads the raw body as the message.)
        5. Done. In Instagram: open a Reel → Share (paper airplane) →
           More → Reel Planner.

        Reels you share will appear here automatically — even on cellular.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Copy Address Again")
        raiseAboveNotch(alert)
        if alert.runModal() == .alertSecondButtonReturn {
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
        raiseAboveNotch(alert)

        guard alert.runModal() == .alertFirstButtonReturn else { return }

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
        raiseAboveNotch(alert)
        alert.runModal()
    }

    /// The notch panel sits at `.screenSaver` level; lift an alert one step above it so it isn't
    /// drawn behind the panel.
    private func raiseAboveNotch(_ alert: NSAlert) {
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
