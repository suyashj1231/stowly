import AppKit

/// Confirm before deleting a folder that still holds posts. Deleting moves every post in it —
/// including archived and done ones you can't see on the current tab — to Misc, so say so.
enum FolderDeletePrompt {
    @MainActor
    static func confirm(folder name: String, posts: Int, hidden: Int) -> Bool {
        guard posts > 0 else { return true }   // empty folder: nothing to lose

        // Same activation dance as FolderNamePrompt: an accessory app can't make a modal key
        // on its own, and the alert must sit above the notch panel's `.screenSaver` level.
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(previousPolicy) }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(name)”?"
        var info = "\(posts) post\(posts == 1 ? "" : "s") will move to Misc."
        if hidden > 0 { info += " That includes \(hidden) archived or done." }
        alert.informativeText = info
        alert.addButton(withTitle: "Delete Folder")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        alert.window.makeKeyAndOrderFront(nil)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
