#!/usr/bin/env python3
"""
Post extraction helper for Stowly.

Input:  argv[1] = post URL (Instagram, TikTok, YouTube, LinkedIn, X, Handshake, …)
Flags:  --video        download the clip/image for multimodal models (else transcribe audio)
        --platform <p>  source platform hint (instagram/linkedin/tiktok/youtube/twitter/handshake)
        --meta-only     skip yt-dlp/whisper; scrape Open Graph metadata only (link-only platforms)
Output: a single JSON object on stdout:
  {"ok": true, "originalURL", "creator", "caption", "durationSeconds", "transcript"}
  or {"ok": false, "error": "..."}

Pipeline: yt-dlp (metadata + audio, anonymous first then browser-cookie fallback)
-> ffmpeg (16kHz mono) -> whisper.cpp (transcript). yt-dlp natively handles Instagram/TikTok/
YouTube/X; LinkedIn/Handshake fall through to the Open Graph scrape. Self-contained; downloads
the whisper model on first use. Uses only the Python standard library.
"""
import sys, os, json, subprocess, tempfile, shutil, urllib.request, hashlib, re, html

BIN_DIRS = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

CACHE_DIR = os.path.expanduser("~/Library/Application Support/Stowly/cache")


def which(name):
    for d in BIN_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    return name  # fall back to PATH lookup


YTDLP = which("yt-dlp")
FFMPEG = which("ffmpeg")
WHISPER = which("whisper-cli")

MODEL_DIR = os.path.expanduser("~/Library/Application Support/Stowly/models")
MODEL_PATH = os.path.join(MODEL_DIR, "ggml-base.en.bin")
MODEL_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def ensure_model():
    if not os.path.exists(MODEL_PATH):
        os.makedirs(MODEL_DIR, exist_ok=True)
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)


def yt_metadata(url, cookies=None):
    cmd = [YTDLP, "-J", "--no-warnings"]
    if cookies:
        cmd += ["--cookies-from-browser", cookies]
    cmd += [url]
    r = run(cmd)
    if r.returncode != 0 or not r.stdout.strip():
        return None, r.stderr
    try:
        return json.loads(r.stdout), None
    except json.JSONDecodeError as e:
        return None, str(e)


def download_audio(url, work, cookies=None):
    out = os.path.join(work, "audio.%(ext)s")
    cmd = [YTDLP, "-f", "bestaudio/best", "-x", "--audio-format", "wav",
           "--no-warnings", "-o", out]
    if cookies:
        cmd += ["--cookies-from-browser", cookies]
    cmd += [url]
    run(cmd)
    wav = os.path.join(work, "audio.wav")
    return wav if os.path.exists(wav) else None


def transcribe(wav, work):
    audio16 = os.path.join(work, "audio16.wav")
    run([FFMPEG, "-y", "-i", wav, "-ar", "16000", "-ac", "1", audio16])
    if not os.path.exists(audio16):
        return ""
    ensure_model()
    r = run([WHISPER, "-m", MODEL_PATH, "-f", audio16, "-nt"])
    return " ".join(r.stdout.split()).strip()


def download_video(url, cookies=None):
    """Download a size-capped (<=480p) mp4 into the cache dir for multimodal providers.
    Returns the file path, or None on failure. Caller deletes it after use."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    stem = "reel_" + hashlib.sha1(url.encode()).hexdigest()[:16]
    out = os.path.join(CACHE_DIR, stem + ".%(ext)s")
    cmd = [YTDLP, "-S", "res:480,ext:mp4:m4a", "--merge-output-format", "mp4",
           "--no-warnings", "-o", out]
    if cookies:
        cmd += ["--cookies-from-browser", cookies]
    cmd += [url]
    run(cmd)
    mp4 = os.path.join(CACHE_DIR, stem + ".mp4")
    return mp4 if os.path.exists(mp4) else None


def best_image_url(meta):
    """Pick the highest-res still image from yt-dlp metadata (photo posts / carousels)."""
    # Carousel: metadata may nest entries; use the first entry's image.
    entries = meta.get("entries")
    if entries:
        for e in entries:
            u = best_image_url(e)
            if u:
                return u
    thumbs = meta.get("thumbnails") or []
    if thumbs:
        # thumbnails are usually ordered small→large; take the last with a URL.
        for t in reversed(thumbs):
            if t.get("url"):
                return t["url"]
    return meta.get("thumbnail")


def og_fallback(url, platform=""):
    """Scrape a page's Open Graph tags (image + caption + creator), which most platforms serve
    anonymously. Used for posts yt-dlp refuses (Instagram photos) and for link-only platforms
    (LinkedIn/Handshake). Returns a dict (possibly without an image) or None if the page is
    unreachable."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"})
        with urllib.request.urlopen(req, timeout=30) as r:
            page = r.read().decode("utf-8", "ignore")
    except Exception:
        return None

    def meta(prop):
        # property/name may appear before or after content, in single or double quotes.
        esc = re.escape(prop)
        for pat in (
            r'<meta[^>]+(?:property|name)=["\']' + esc + r'["\'][^>]*content=["\']([^"\']*)["\']',
            r'<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:property|name)=["\']' + esc + r'["\']',
        ):
            m = re.search(pat, page, re.IGNORECASE)
            if m:
                return html.unescape(m.group(1))
        return None

    title, desc, image = meta("og:title"), meta("og:description"), meta("og:image")
    site = meta("og:site_name")
    if not title and not desc and not image:
        return None

    # Creator: titles are often "<Name> on Instagram", "<Name> | LinkedIn", "<Name> (@h) on X".
    creator = ""
    if title:
        seps = [" on Instagram", " on TikTok", " on LinkedIn", " on Handshake",
                " on X", " on Twitter", " | LinkedIn", " | Handshake"]
        if platform:
            seps += [" on " + platform.capitalize(), " | " + platform.capitalize()]
        if site:
            seps += [" on " + site, " | " + site]
        for sep in seps:
            if sep in title:
                creator = title.split(sep)[0].strip()
                break

    # Caption: Instagram nests it as `description: "..."`; otherwise use description/title.
    caption = ""
    for s in (desc, title):
        if s and ': "' in s:
            caption = s.split(': "', 1)[1]
            if caption.endswith('"'):
                caption = caption[:-1]
            break
    if not caption:
        caption = desc or title or ""

    return {"creator": creator, "caption": caption, "image": image}


def download_image(image_url):
    """Download a still image (photo post) into the cache dir. Returns path or None."""
    if not image_url:
        return None
    os.makedirs(CACHE_DIR, exist_ok=True)
    stem = "reel_" + hashlib.sha1(image_url.encode()).hexdigest()[:16]
    path = os.path.join(CACHE_DIR, stem + ".jpg")
    try:
        req = urllib.request.Request(image_url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as r, open(path, "wb") as f:
            f.write(r.read())
        return path if os.path.exists(path) and os.path.getsize(path) > 0 else None
    except Exception:
        return None


def parse_args(argv):
    """Pull the URL plus flags out of argv. Skips the value after --platform."""
    want_video = "--video" in argv
    meta_only = "--meta-only" in argv
    platform = ""
    positional, i = [], 0
    while i < len(argv):
        a = argv[i]
        if a == "--platform":
            if i + 1 < len(argv):
                platform = argv[i + 1]
            i += 2
            continue
        if a.startswith("--"):
            i += 1
            continue
        positional.append(a)
        i += 1
    url = positional[0] if positional else ""
    return url, want_video, meta_only, platform


def og_result(url, platform, want_video):
    """Build a JSON result from Open Graph metadata alone (no yt-dlp/whisper)."""
    og = og_fallback(url, platform)
    if not og:
        return None
    return {
        "ok": True,
        "originalURL": url,
        "creator": og.get("creator", ""),
        "caption": og.get("caption", ""),
        "durationSeconds": None,
        "transcript": "",
        "videoPath": None,
        "imagePath": download_image(og["image"]) if (want_video and og.get("image")) else None,
    }


def main():
    url, want_video, meta_only, platform = parse_args(sys.argv[1:])
    if not url:
        print(json.dumps({"ok": False, "error": "no URL provided"}))
        return

    # Link-only platforms (Handshake) and the meta-only fallback: scrape Open Graph and stop.
    if meta_only:
        res = og_result(url, platform, want_video)
        print(json.dumps(res or {"ok": False, "error": "no metadata"}))
        return

    work = tempfile.mkdtemp(prefix="reel_")
    try:
        # Metadata: anonymous first, then browser-cookie fallbacks (rate-limit/login).
        meta, err = None, ""
        for cookies in (None, "safari", "chrome"):
            meta, err = yt_metadata(url, cookies)
            if meta:
                break
        if not meta:
            # yt-dlp refuses non-video posts ("no video in post") and doesn't support every
            # platform. Fall back to Open Graph tags (image + caption + creator).
            res = og_result(url, platform, want_video)
            if res and (res["caption"] or res["creator"] or res["imagePath"]):
                print(json.dumps(res))
                return
            print(json.dumps({"ok": False, "error": "metadata failed: " + (err or "")[:300]}))
            return

        caption = meta.get("description") or ""
        creator = meta.get("channel") or meta.get("uploader") or ""
        duration = meta.get("duration")

        out = {
            "ok": True,
            "originalURL": url,
            "creator": creator,
            "caption": caption,
            "durationSeconds": duration,
            "transcript": "",
            "videoPath": None,
            "imagePath": None,
        }

        if want_video:
            # Multimodal path: hand the video to the model (it transcribes + reads on-screen
            # text itself), so skip Whisper. Try anonymous then browser cookies.
            out["videoPath"] = (download_video(url) or download_video(url, "safari")
                                or download_video(url, "chrome"))
            # Photo post (no video)? Fall back to the post image so it's still processable.
            if not out["videoPath"]:
                out["imagePath"] = download_image(best_image_url(meta))
        else:
            # Text path: audio transcript (best-effort; caption alone still returns).
            wav = (download_audio(url, work) or download_audio(url, work, "safari")
                   or download_audio(url, work, "chrome"))
            if wav:
                out["transcript"] = transcribe(wav, work)

        print(json.dumps(out))
    except Exception as e:  # noqa: BLE001 — surface any failure as JSON
        print(json.dumps({"ok": False, "error": str(e)[:300]}))
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
