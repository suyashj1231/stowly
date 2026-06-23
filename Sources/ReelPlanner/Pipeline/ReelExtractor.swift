import Foundation

/// Raw data pulled from a reel by the Python helper.
struct ReelRawData: Sendable {
    let originalURL: String
    let creator: String
    let caption: String
    let transcript: String
    /// Local mp4 path when extracted in `--video` mode (multimodal). Caller deletes it.
    let videoPath: String?
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
    static func extract(urlString: String, needsVideo: Bool = false) async throws -> ReelRawData {
        guard let script = Bundle.module.url(forResource: "extract_reel", withExtension: "py") else {
            throw ExtractError.scriptMissing
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                var args = ["python3", script.path, urlString]
                if needsVideo { args.append("--video") }
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
                    videoPath: obj["videoPath"] as? String
                ))
            }
        }
    }
}
