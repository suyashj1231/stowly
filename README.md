# Reel Planner

A macOS notch app that turns Instagram Reels you save into an actionable, categorized
task queue. Forward a reel from your phone, and it shows up in a glassy panel that drops
down from the MacBook notch — grouped into folders (Learn/Certs, Apply Jobs, Apply
Internships, …), each item carrying the parsed task, a summary, extracted links, and the
original reel link.

> Status: **Phase 1 complete** — the notch UI runs on mock data. Ingestion, parsing, and
> AI categorization are next. See the roadmap below.

## How it works (target architecture)

1. **Ingestion** — an iOS Shortcut in the Share Sheet appends a reel URL to an iCloud Drive
   file; the Mac app watches that file. (No Instagram API — personal accounts have none.)
2. **Parsing** — a helper pulls caption + video, transcribes the audio (Whisper), and OCRs
   on-screen text. The video is the reliable signal; captions are often reach-bait.
3. **Understanding** — Claude turns the raw text into `{task, summary, links, folder}`.
4. **Storage** — local SwiftData DB of reels + folders.
5. **UI** — `DynamicNotchKit` notch panel: hover the pill → expanded queue → tap a card →
   detail with links + "Open original reel".

## Build & run

This is a Swift Package (no `.xcodeproj` required):

```bash
swift build
swift run            # runs as a background agent: menu-bar tray icon + notch pill
```

Quit via the menu-bar tray icon → **Quit**.

### ⚠️ Requires full Xcode (not just Command Line Tools)

SwiftData (`@Model`) and SwiftUI (`@Entry`, `#Preview`) use Swift **macros**, whose compiler
plugins ship only with **full Xcode**. With Command Line Tools alone the build fails on those
macros. Install Xcode, then point the toolchain at it:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

### Storage

Local SwiftData store at `~/Library/Application Support/ReelPlanner/Library.store`.
Starter folders + sample reels are seeded on first launch. Add a reel manually via the
menu-bar icon → **Add Reel from Clipboard** (copy an Instagram link first).

## Tech

Swift + SwiftUI · [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) · SwiftData ·
yt-dlp/Whisper helper · Apple Vision (OCR) · Claude API.

## Project layout

```
Package.swift
Sources/ReelPlanner/
  main.swift              # AppKit bootstrap (.accessory agent)
  AppDelegate.swift       # status-item menu + launches the notch
  NotchController.swift    # owns DynamicNotch; pill ⇄ expand interaction
  Models/                 # Reel, ReelLink, Folder, MockData
  Views/                  # Theme, CompactPill, NotchPanelView, ReelCard, ReelDetailView
```
