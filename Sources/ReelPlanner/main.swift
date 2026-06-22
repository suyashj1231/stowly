import AppKit

// Classic AppKit bootstrap (top-level code lives in main.swift so we avoid the
// @main / -parse-as-library dance). Runs as a background "accessory" agent: no
// Dock icon, no main window — the UI lives entirely in the notch + a status item.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
