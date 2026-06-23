import AppKit

/// A small modal prompt for creating a manual card. Uses NSAlert because the notch panel
/// is a non-activating panel and can't receive keyboard input for SwiftUI TextFields.
enum ManualEntryPrompt {
    @MainActor
    static func run() -> (task: String, link: String)? {
        NSApp.activate(ignoringOtherApps: true)

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

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let task = taskField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return nil }
        return (task, linkField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
