import Foundation

/// Raw data pulled from a reel by the Python helper.
struct ReelRawData: Sendable {
    let originalURL: String
    let creator: String
    let caption: String
    let transcript: String
    /// Local mp4 path when extracted in `--video` mode (multimodal). Caller deletes it.
    let videoPath: String?
    /// Local image path for photo posts (no video). Caller deletes it.
    let imagePath: String?
}

enum ExtractError: LocalizedError {
    case scriptMissing
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .scriptMissing: "Bundled extract_reel.py not found."
        case .failed(let s): "Extraction failed: \(s)"
        }
    }
}

/// Shells out to the bundled `extract_reel.py` (yt-dlp + ffmpeg + whisper) and parses its
/// JSON result. Runs off the main thread.
enum ReelExtractor {
    /// Where the Python helper drops downloaded clips/images. Mirrors `CACHE_DIR` in
    /// extract_reel.py.
    private static var cacheDir: URL {
        URL.applicationSupportDirectory.appending(path: "ReelPlanner/cache", directoryHint: .isDirectory)
    }

    /// Best-effort cleanup of stale cache files. Successful runs delete their own download, but a
    /// yt-dlp that downloads then fails to merge (or grabs a non-mp4) can leave fragments behind.
    /// Only removes files older than an hour so an in-flight download is never touched.
    static func sweepCache() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-3600)
        guard let files = try? fm.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return }
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }

    /// Run the Python helper. `metaOnly` skips yt-dlp/whisper and does only an Open Graph scrape
    /// (for link-only platforms like Handshake). The detected platform is passed as a hint so the
    /// helper can parse creator/caption per platform.
    static func extract(urlString: String, needsVideo: Bool = false, metaOnly: Bool = false) async throws -> ReelRawData {
        guard let script = Bundle.module.url(forResource: "extract_reel", withExtension: "py") else {
            throw ExtractError.scriptMissing
        }
        let platform = Platform.detect(from: urlString).rawValue

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                var args = ["python3", script.path, urlString, "--platform", platform]
                if needsVideo { args.append("--video") }
                if metaOnly { args.append("--meta-only") }
                process.arguments = args

                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice  // helper already captures tool stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Watchdog: never let a stuck yt-dlp/whisper hang the queue forever.
                let watchdog = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 180, execute: watchdog)

                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()

                guard
                    let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    let raw = String(data: data, encoding: .utf8) ?? "<no output>"
                    continuation.resume(throwing: ExtractError.failed(raw))
                    return
                }

                if obj["ok"] as? Bool != true {
                    continuation.resume(throwing: ExtractError.failed(obj["error"] as? String ?? "unknown"))
                    return
                }

                continuation.resume(returning: ReelRawData(
                    originalURL: obj["originalURL"] as? String ?? urlString,
                    creator: obj["creator"] as? String ?? "",
                    caption: obj["caption"] as? String ?? "",
                    transcript: obj["transcript"] as? String ?? "",
                    videoPath: obj["videoPath"] as? String,
                    imagePath: obj["imagePath"] as? String
                ))
            }
        }
    }
}
