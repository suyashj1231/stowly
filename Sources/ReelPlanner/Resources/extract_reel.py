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
import sys, os, json, subprocess, tempfile, shutil, urllib.request

BIN_DIRS = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]


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


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "no URL provided"}))
        return
    url = sys.argv[1]
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

        # Audio + transcript (best-effort; a reel without usable audio still returns caption).
        transcript = ""
        wav = download_audio(url, work) or download_audio(url, work, "safari")
        if wav:
            transcript = transcribe(wav, work)

        print(json.dumps({
            "ok": True,
            "originalURL": url,
            "creator": creator,
            "caption": caption,
            "durationSeconds": duration,
            "transcript": transcript,
        }))
    except Exception as e:  # noqa: BLE001 — surface any failure as JSON
        print(json.dumps({"ok": False, "error": str(e)[:300]}))
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
