# Stowly

A macOS notch app that turns posts you save — from **Instagram, TikTok, YouTube, LinkedIn,
X, and Handshake** — into an actionable, auto-categorized task queue. Share a post from your
phone (or paste a link), and it shows up in a glassy panel that drops down from the MacBook
notch — grouped into folders, each card carrying the parsed task, a summary, extracted links,
the source-platform badge, and a one-tap "Open on …" button.

## How it works

1. **Ingestion** — an iOS Shortcut in the Share Sheet POSTs the shared post to a free public
   relay ([ntfy.sh](https://ntfy.sh)) on a secret per-user topic; the Mac app holds a streaming
   subscription and turns each link into a card. Works anywhere (incl. cellular), no account, no
   cloud storage. The Mac pulls the link out of whatever you share — a bare URL *or* text with a
   link in it (LinkedIn/X share text). See [Send posts from your iPhone](#send-posts-from-your-iphone).
2. **Parsing** — a helper (yt-dlp + ffmpeg + Whisper) pulls the caption + video and transcribes
   the audio; for link-only sources (Handshake) or posts that can't be fetched, it falls back to
   an Open Graph scrape so a best-effort link card is always saved.
3. **Understanding** — a model turns the raw text/video into `{task, summary, links, folder}`.
4. **Storage** — local SwiftData DB of posts + folders.
5. **UI** — `DynamicNotchKit` notch panel: hover the pill → expanded queue → tap a card →
   detail with links + a platform-branded "Open on …" button.

## Platforms

| Platform | Extraction | Badge |
|---|---|---|
| Instagram | full (video/transcript) | camera, gradient |
| TikTok · YouTube · X | full (yt-dlp) | per-platform color |
| LinkedIn | full when public, else link card | blue `in` |
| Handshake | link card (login-gated) | green `h` |

## Build & run

This is a Swift Package (no `.xcodeproj` required).

**As a standalone app (recommended — no terminal):**
```bash
./build_app.sh        # produces Stowly.app
open Stowly.app
```
Move `Stowly.app` to `/Applications` and add it to **System Settings → General → Login Items**
to have it always running. It lives in the menu bar (no Dock icon); quit via the tray icon → **Quit**.

**For development:**
```bash
swift build
swift test            # 97 tests across 9 suites
swift run             # ties the app's life to the terminal — keep it open while posts process
```

Requires a local **Ollama** (`ollama serve`) with `llama3.2` pulled (`ollama pull llama3.2`),
plus `yt-dlp`, `ffmpeg`, `whisper-cpp` (`brew install yt-dlp ffmpeg whisper-cpp`). Gemini (below)
is recommended for much better results.

### ⚠️ Requires full Xcode (not just Command Line Tools)

SwiftData (`@Model`) and SwiftUI macros need compiler plugins that ship only with **full Xcode**:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

### Send posts from your iPhone

Posts can flow in from your phone over a free relay ([ntfy.sh](https://ntfy.sh)) — no iCloud,
no account, no cloud storage. Set it up once:

On the Mac: menu-bar icon → **Set Up iPhone Sync…** — it copies your private inbox address
(`https://ntfy.sh/stowly-…`) to the clipboard. **Keep it secret** — anyone with it could read
your saved links or push junk into your queue.

Then build the Shortcut on the iPhone:

1. **Shortcuts** app → **+** → rename it **Stowly**.
2. Tap **ⓘ** → **Show in Share Sheet** ON → **Receive Input** → set the types to **URLs *and*
   Text** → **Done**. (Text matters: LinkedIn/X share the post as text with a link, not a bare
   URL — without Text the action is hidden there.)
3. **Add Action** → **Text** → tap the field → **Insert Variable** → **Shortcut Input**.
4. **+** → **Get Contents of URL** → **Show More**: **URL** = your address, **Method** = **POST**,
   **Request Body → File** (not JSON/Form) = the **Text** from step 3.
5. **Done**. From any post — Instagram, TikTok, YouTube, LinkedIn, X, Handshake — tap **Share** →
   **More** → **Stowly**.

Posts appear on the Mac within a second or two — even on cellular. Anything shared while the Mac
is asleep is caught up on next launch (ntfy caches ~12h).

> The relay only carries links; the address is the only secret, stored locally in `UserDefaults`
> (never committed). The Mac drops anything that isn't a new supported-platform link.

### AI model — local Ollama (default) or free Gemini

By default posts are understood by a **local** model via Ollama (`llama3.2`) — private, free,
offline, but small (weaker summaries, can't see the video).

For much better results, plug in a free **Gemini** key: menu-bar icon → **AI: Use Gemini (set
API key…)** → paste a key from [aistudio.google.com/apikey](https://aistudio.google.com/apikey).
With Gemini on, the app sends the post's **video** to Gemini, so it reads the spoken audio, the
**on-screen text**, and the visuals. Clear the key anytime to switch back to local.

- The key is stored in the macOS **Keychain** (never in files or git).
- Privacy: with Gemini active, a size-capped (≤480p) copy of the video is uploaded to Google for
  processing, then deleted from the local cache after the call.
- Override the model with the `geminiModel` UserDefaults key (default `gemini-3.1-flash-lite`).

### Storage

Local SwiftData store at `~/Library/Application Support/Stowly/Library.store` (auto-migrated from
the previous location on first launch). Starter folders + sample posts are seeded on first run.
Add a post manually via the menu-bar icon → **Add Reel from Clipboard** (copy a supported link first).

## Tech

Swift + SwiftUI · [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) · SwiftData ·
yt-dlp/Whisper helper · Gemini (multimodal) / Ollama.

## Project layout

```
Package.swift
Sources/Stowly/
  main.swift              # AppKit bootstrap (.accessory agent)
  AppDelegate.swift       # status-item menu + launches the notch
  NotchController.swift   # owns DynamicNotch; pill ⇄ expand interaction
  Models/                 # Reel, ReelLink, Folder, Platform, SeedData
  Pipeline/               # InboxRelay, ProcessingQueue, ReelExtractor, ReelProcessor
  AI/                     # LLMProvider (Ollama), GeminiProvider
  Views/                  # Theme, CompactPill, NotchPanelView, ReelCard, ReelDetailView, PlatformBadge
Tests/StowlyTests/        # 97 tests
```
