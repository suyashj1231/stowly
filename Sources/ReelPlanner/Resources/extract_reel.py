#!/usr/bin/env python3
"""
Reel extraction helper for Reel Planner.

Input:  argv[1] = Instagram reel URL
Output: a single JSON object on stdout:
  {"ok": true, "originalURL", "creator", "caption", "durationSeconds", "transcript"}
  or {"ok": false, "error": "..."}

Pipeline: yt-dlp (metadata + audio, anonymous first then browser-cookie fallback)
-> ffmpeg (16kHz mono) -> whisper.cpp (transcript). Self-contained; downloads the
whisper model on first use. Uses only the Python standard library.
"""
import sys, os, json, subprocess, tempfile, shutil, urllib.request, hashlib

BIN_DIRS = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

CACHE_DIR = os.path.expanduser("~/Library/Application Support/ReelPlanner/cache")


def which(name):
    for d in BIN_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    return name  # fall back to PATH lookup


YTDLP = which("yt-dlp")
FFMPEG = which("ffmpeg")
WHISPER = which("whisper-cli")

MODEL_DIR = os.path.expanduser("~/Library/Application Support/ReelPlanner/models")
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


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    want_video = "--video" in sys.argv[1:]
    if not args:
        print(json.dumps({"ok": False, "error": "no URL provided"}))
        return
    url = args[0]
    work = tempfile.mkdtemp(prefix="reel_")
    try:
        # Metadata: anonymous first, then browser-cookie fallbacks (rate-limit/login).
        meta, err = None, ""
        for cookies in (None, "safari", "chrome"):
            meta, err = yt_metadata(url, cookies)
            if meta:
                break
        if not meta:
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
            # text itself), so skip Whisper.
            out["videoPath"] = download_video(url) or download_video(url, "safari")
            # Photo post (no video)? Fall back to the post image so it's still processable.
            if not out["videoPath"]:
                out["imagePath"] = download_image(best_image_url(meta))
        else:
            # Text path: audio transcript (best-effort; caption alone still returns).
            wav = download_audio(url, work) or download_audio(url, work, "safari")
            if wav:
                out["transcript"] = transcribe(wav, work)

        print(json.dumps(out))
    except Exception as e:  # noqa: BLE001 — surface any failure as JSON
        print(json.dumps({"ok": False, "error": str(e)[:300]}))
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
