# Reel Planner

A macOS notch app that turns Instagram Reels you save into an actionable, categorized
task queue. Forward a reel from your phone, and it shows up in a glassy panel that drops
down from the MacBook notch — grouped into folders (Learn/Certs, Apply Jobs, Apply
Internships, …), each item carrying the parsed task, a summary, extracted links, and the
original reel link.

> Status: **Phase 1 complete** — the notch UI runs on mock data. Ingestion, parsing, and
> AI categorization are next. See the roadmap below.

## How it works (target architecture)

1. **Ingestion** — an iOS Shortcut in the Share Sheet POSTs the reel URL to a free public
   relay ([ntfy.sh](https://ntfy.sh)) on a secret per-user topic; the Mac app holds a
   streaming subscription and turns each URL into a card. Works anywhere (incl. cellular),
   no account, no cloud storage. (No Instagram API — personal accounts have none.) See
   [Send reels from your iPhone](#send-reels-from-your-iphone) below.
2. **Parsing** — a helper pulls caption + video, transcribes the audio (Whisper), and OCRs
   on-screen text. The video is the reliable signal; captions are often reach-bait.
3. **Understanding** — Claude turns the raw text into `{task, summary, links, folder}`.
4. **Storage** — local SwiftData DB of reels + folders.
5. **UI** — `DynamicNotchKit` notch panel: hover the pill → expanded queue → tap a card →
   detail with links + "Open original reel".

## Build & run

This is a Swift Package (no `.xcodeproj` required).

**As a standalone app (recommended — no terminal):**
```bash
./build_app.sh        # produces ReelPlanner.app
open ReelPlanner.app
```
Move `ReelPlanner.app` to `/Applications` and add it to **System Settings → General → Login Items** to have it always running. It lives in the menu bar (no Dock icon); quit via the tray icon → **Quit**.

**For development:**
```bash
swift build
swift run             # ties the app's life to the terminal — keep it open while reels process
```

Requires a local **Ollama** running (`ollama serve` or the Ollama app) with the default model
`llama3.2:3b` pulled (`ollama pull llama3.2`), plus `yt-dlp`, `ffmpeg`, `whisper-cpp`
(`brew install yt-dlp ffmpeg whisper-cpp`).

### ⚠️ Requires full Xcode (not just Command Line Tools)

SwiftData (`@Model`) and SwiftUI (`@Entry`, `#Preview`) use Swift **macros**, whose compiler
plugins ship only with **full Xcode**. With Command Line Tools alone the build fails on those
macros. Install Xcode, then point the toolchain at it:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

### Send reels from your iPhone

Reels can flow in from your phone over a free relay ([ntfy.sh](https://ntfy.sh)) — no iCloud,
no account, no cloud storage. Set it up once:

First, on the Mac: click the menu-bar icon → **Set Up iPhone Sync…** — it copies your private
reel address (`https://ntfy.sh/reelplanner-…`) to the clipboard. **Keep it secret** — anyone
with it could read your saved reel links or push junk into your queue.

Then build the Shortcut on the iPhone:

**1. Create the Shortcut**
- Open the **Shortcuts** app → tap **+** (top right).
- Tap the shortcut name at the top → **Rename** → type **Reel Planner** → **Done**.

**2. Enable the Share Sheet**
- Tap the **ⓘ** (info) button at the bottom of the editor.
- Toggle **Show in Share Sheet** ON.
- Tap **Receive Input** and set the accepted type to **URLs only** — so Instagram passes the
  reel URL cleanly. Tap **Done**.

**3. Add the actions**
- *Action 1 — capture the URL:* tap **Add Action** → search **Text** → add it. Tap inside the
  Text field → **Insert Variable** → select **Shortcut Input** (the reel URL from the share sheet).
- *Action 2 — POST to ntfy:* tap **+** below → search **Get Contents of URL** → add it. Tap
  **Show More** to expand. Set **URL** to your ntfy address, **Method** to **POST**, and
  **Request Body → File** (not JSON, not Form). Set the file value to the **Text** variable
  from Action 1 — this sends the raw URL as the body, which ntfy reads as the message.

**4. Save & test**
- Tap **Done**. In **Instagram**, open a Reel → tap the **paper airplane (Share)** → **More**
  → scroll to **Reel Planner** → tap it.

The reel appears on the Mac within a second or two — even on cellular. Reels shared while the
Mac is asleep are caught up on next launch (ntfy caches ~12h).

> The relay only carries reel links; the address is the only secret and is stored locally in
> `UserDefaults` (never committed). The Mac drops anything that isn't a new `instagram.com` link.

### AI model — local Ollama (default) or free Gemini

By default reels are understood by a **local** model via Ollama (`llama3.2:3b`) — private,
free, offline, but small (weaker summaries, and it can't see the video).

For much better results, plug in a free **Gemini 2.5 Flash** key: menu-bar icon →
**AI: Use Gemini (set API key…)** → paste a key from
[aistudio.google.com/apikey](https://aistudio.google.com/apikey). With Gemini on, the app
sends the reel's **video** to Gemini, so it reads the spoken audio, the **on-screen text**,
and the visuals — fixing the common text-on-screen / music reels the audio-only local path
can't. Clear the key anytime to switch back to local.

- The key is stored in the macOS **Keychain** (never in files or git).
- Privacy: with Gemini active, a size-capped (≤480p) copy of the reel video is uploaded to
  Google for processing, then deleted from the local cache after the call.
- Switch models with the `GEMINI_MODEL` env var (default `gemini-2.5-flash`).

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
