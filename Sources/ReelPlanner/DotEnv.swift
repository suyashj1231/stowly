import Foundation

/// Tiny `.env` loader for local secrets (e.g. GEMINI_API_KEY) during development.
/// Looked up once from, in order:
///   1. the process environment,
///   2. `<cwd>/.env`               (works for `swift run` from the project root),
///   3. `~/Library/Application Support/ReelPlanner/.env`  (works for the packaged .app).
/// `.env` files are gitignored — keys never get committed.
enum DotEnv {
    static func value(_ key: String) -> String? {
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
        if let v = values[key], !v.isEmpty { return v }
        return nil
    }

    private static let values: [String: String] = load()

    private static func load() -> [String: String] {
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: ".env"),
            URL.applicationSupportDirectory.appending(path: "ReelPlanner/.env"),
        ]
        var out: [String: String] = [:]
        for url in candidates {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for raw in text.split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#"),
                      let eq = line.firstIndex(of: "=") else { continue }
                let k = line[..<eq].trimmingCharacters(in: .whitespaces)
                var v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                // Strip surrounding quotes if present.
                if v.count >= 2, (v.first == "\"" && v.last == "\"") || (v.first == "'" && v.last == "'") {
                    v = String(v.dropFirst().dropLast())
                }
                if out[k] == nil { out[k] = v }   // earlier files win
            }
        }
        return out
    }
}
