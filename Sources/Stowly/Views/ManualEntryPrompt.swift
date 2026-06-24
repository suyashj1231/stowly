import AppKit

/// A small modal prompt for creating a manual card. Uses NSAlert because the notch panel
/// is a non-activating panel and can't receive keyboard input for SwiftUI TextFields.
enum ManualEntryPrompt {
    @MainActor
    static func run() -> (task: String, link: String)? {
        // This is an accessory (LSUIElement) app, so `NSApp.activate` alone can't reliably make a
        // modal window key — the alert can come up un-focused while `runModal()` blocks the whole
        // app forever (you can't even Quit). Promote to a regular app for the duration of the
        // dialog so it activates and the alert becomes a real key window, then restore.
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(previousPolicy) }

        let alert = NSAlert()
        alert.messageText = "New card"
        alert.informativeText = "Add a task or note, and an optional link."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let width: CGFloat = 280
        let taskField = NSTextField(frame: NSRect(x: 0, y: 30, width: width, height: 24))
        taskField.placeholderString = "Task or note"
        let linkField = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        linkField.placeholderString = "Link (optional)"

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 58))
        container.addSubview(taskField)
        container.addSubview(linkField)
        alert.accessoryView = container
        alert.window.initialFirstResponder = taskField
        // The notch panel sits at `.screenSaver` level, so without this the alert renders behind
        // it and you can't see what you type. Put the alert one step above the notch.
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        alert.window.makeKeyAndOrderFront(nil)

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let task = taskField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return nil }
        return (task, linkField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
