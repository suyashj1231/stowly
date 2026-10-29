#!/usr/bin/env python3
"""
Post extraction helper for Stowly.

Input:  argv[1] = post URL (Instagram, TikTok, YouTube, LinkedIn, X, Handshake, …)
Flags:  --platform <p>  source platform hint (instagram/linkedin/tiktok/youtube/twitter/handshake)
        --meta-only     skip yt-dlp; scrape Open Graph metadata only (link-only platforms)
Output: a single JSON object on stdout:
  {"ok": true, "originalURL", "creator", "caption", "durationSeconds", "transcript",
   "videoPath", "imagePaths"}
  or {"ok": false, "error": "..."}

Pipeline: yt-dlp (metadata + a size-capped mp4, anonymous first then browser-cookie fallback);
photo posts and carousels download every slide's image. The app transcribes and reads the clip on-device.
yt-dlp natively handles Instagram/TikTok/YouTube/X; LinkedIn/Handshake fall through to the
Open Graph scrape. Uses only the Python standard library.
"""
import sys, os, json, subprocess, urllib.request, urllib.parse, hashlib, re, html

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


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def yt_metadata(url, cookies=None):
    # Photo posts have no formats; without this flag yt-dlp refuses them ("no video in post")
    # and we'd lose every carousel slide but the Open Graph thumbnail.
    cmd = [YTDLP, "-J", "--no-warnings", "--ignore-no-formats-error"]
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


def download_video(url, cookies=None):
    """Download a size-capped (<=480p) mp4 into the cache dir for on-device processing.
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


MAX_SLIDES = 10  # Instagram's carousel cap


def best_image_url(meta):
    """Pick the highest-res still image from one post / slide's yt-dlp metadata."""
    thumbs = [t["url"] for t in meta.get("thumbnails") or [] if t.get("url")]
    # Instagram lists resized variants with an `stp=` size param; the one without is the
    # original, uncropped upload.
    for u in thumbs:
        if "stp=" not in u:
            return u
    # Otherwise thumbnails are usually ordered small→large; take the last.
    return thumbs[-1] if thumbs else meta.get("thumbnail")


def slide_image_urls(meta):
    """One image per carousel slide (a video slide contributes its cover), or the post's own."""
    entries = meta.get("entries") or [meta]
    urls = [best_image_url(e) for e in entries[:MAX_SLIDES]]
    return [u for u in urls if u]


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
    ext = os.path.splitext(urllib.parse.urlparse(image_url).path)[1].lower()
    path = os.path.join(CACHE_DIR, stem + (ext if ext in (".jpg", ".jpeg", ".png", ".webp", ".heic") else ".jpg"))
    try:
        req = urllib.request.Request(image_url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as r, open(path, "wb") as f:
            f.write(r.read())
        return path if os.path.exists(path) and os.path.getsize(path) > 0 else None
    except Exception:
        return None


def parse_args(argv):
    """Pull the URL plus flags out of argv. Skips the value after --platform."""
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
    return url, meta_only, platform


def og_result(url, platform):
    """Build a JSON result from Open Graph metadata alone (no yt-dlp)."""
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
        "imagePaths": [p for p in [download_image(og.get("image"))] if p],
    }


def main():
    url, meta_only, platform = parse_args(sys.argv[1:])
    if not url:
        print(json.dumps({"ok": False, "error": "no URL provided"}))
        return

    # Link-only platforms (Handshake) and the meta-only fallback: scrape Open Graph and stop.
    if meta_only:
        res = og_result(url, platform)
        print(json.dumps(res or {"ok": False, "error": "no metadata"}))
        return

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
            res = og_result(url, platform)
            if res and (res["caption"] or res["creator"] or res["imagePaths"]):
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
            "imagePaths": [],
        }

        # Carousel or photo post: read every slide's image. Otherwise download the clip so the
        # app can transcribe + read it on-device (anonymous, then browser cookies), falling
        # back to its cover image.
        is_photo = not meta.get("entries") and not meta.get("formats")
        if not meta.get("entries") and not is_photo:
            out["videoPath"] = (download_video(url) or download_video(url, "safari")
                                or download_video(url, "chrome"))
        if not out["videoPath"]:
            paths = [download_image(u) for u in slide_image_urls(meta)]
            out["imagePaths"] = [p for p in paths if p]

        print(json.dumps(out))
    except Exception as e:  # noqa: BLE001 — surface any failure as JSON
        print(json.dumps({"ok": False, "error": str(e)[:300]}))


if __name__ == "__main__":
    main()
