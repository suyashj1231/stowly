import AppKit

/// Modal prompt for creating a new folder. Uses NSAlert (the notch panel can't take keyboard
/// focus). The icon is chosen automatically afterward (AI / heuristic).
enum FolderNamePrompt {
    @MainActor
    static func run() -> String? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "New folder"
        alert.informativeText = "Name a category (e.g. Food, Gym, Travel). An icon is picked for you."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Folder name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        // The notch panel sits at `.screenSaver` level, so without this the alert renders behind
        // it and you can't see what you type. Put the alert one step above the notch.
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
