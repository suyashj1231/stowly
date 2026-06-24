import AppKit

/// Modal prompt for searching the library. Uses NSAlert because the notch panel is non-activating
/// (can't take keyboard focus) and auto-collapses on mouse-leave — so live inline typing isn't
/// viable. Returns the entered query (empty string clears the search), or nil if cancelled.
enum SearchPrompt {
    @MainActor
    static func run(current: String) -> String? {
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(previousPolicy) }

        let alert = NSAlert()
        alert.messageText = "Search"
        alert.informativeText = "Find cards by task, summary, or creator."
        alert.addButton(withTitle: "Search")
        alert.addButton(withTitle: "Cancel")
        if !current.isEmpty { alert.addButton(withTitle: "Clear") }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "e.g. internship, recipe, @creator"
        field.stringValue = current
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        alert.window.makeKeyAndOrderFront(nil)

        switch alert.runModal() {
        case .alertFirstButtonReturn:  return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        case .alertThirdButtonReturn:  return ""   // Clear
        default:                       return nil   // Cancel
        }
    }
}
