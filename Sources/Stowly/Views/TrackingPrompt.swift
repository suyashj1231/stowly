import AppKit

/// Modal prompt for adding a "what I'm working on" entry to the Tracking tab. Single text field;
/// the timer starts as soon as it's added. Uses NSAlert (the notch panel can't take keyboard focus).
enum TrackingPrompt {
    @MainActor
    static func run() -> String? {
        // Accessory (LSUIElement) app: promote to regular for the dialog so the alert becomes a
        // real key window and runModal() doesn't freeze behind an un-focused dialog. (Same pattern
        // as FolderNamePrompt / ManualEntryPrompt.)
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(previousPolicy) }

        let alert = NSAlert()
        alert.messageText = "What are you working on?"
        alert.informativeText = "It goes straight to the Tracking tab and a timer starts now."
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "e.g. Apply to Stripe new-grad role"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        // The notch panel sits at `.screenSaver` level, so lift the alert one step above it.
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        alert.window.makeKeyAndOrderFront(nil)

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let task = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return task.isEmpty ? nil : task
    }
}
