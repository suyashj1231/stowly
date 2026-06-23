import Foundation

/// The raw material handed to the model.
struct ReelInput {
    let caption: String
    let transcript: String
    let creator: String
}

/// Strict structured result every provider must return (same shape regardless of service).
struct ReelUnderstanding: Codable {
    struct Link: Codable { let label: String; let url: String }
    let task: String
    let summary: String
    let links: [Link]
    let suggested_folder: String
    let is_new_folder: Bool
    let new_folder_name: String?
}

/// "Bring your own model": one protocol, swappable implementations (local Ollama, or any
/// OpenAI-compatible service). Each turns a reel's text into a `ReelUnderstanding`.
protocol LLMProvider: Sendable {
    func understand(_ input: ReelInput, folders: [String]) async throws -> ReelUnderstanding
}

enum LLMError: LocalizedError {
    case badResponse(String)
    var errorDescription: String? {
        switch self {
        case .badResponse(let s): "AI provider returned an unexpected response: \(s)"
        }
    }
}

// MARK: - Shared prompt

enum LLMPrompt {
    static let system = """
    You convert a saved Instagram reel into a single actionable task card.
    You receive the caption (often reach-bait / hashtag spam) and the voiceover transcript \
    (the reliable signal, may contain speech-to-text typos — normalize names). Extract what \
    the reel is actually about.
    Rules:
    - "task": a short imperative title, max 8 words.
    - "summary": 1-2 plain sentences of the real substance.
    - "links": ONLY real URLs that explicitly appear in the text. If none, return []. \
    Never invent links. Ignore "comment X to get the link" calls-to-action.
    - Classify into the single best EXISTING folder by the user's intent (weight the action: \
    "apply ..." => an Apply folder; "learn/cert ..." => Learn). Only set is_new_folder=true \
    and provide new_folder_name if no existing folder reasonably fits.
    """

    static func user(_ input: ReelInput, folders: [String]) -> String {
        """
        EXISTING FOLDERS: \(folders)

        --- CAPTION ---
        \(input.caption)

        --- TRANSCRIPT ---
        \(input.transcript)
        """
    }

    /// JSON schema for structured output (used by providers that support it).
    static var jsonSchema: [String: Any] {
        [
        "type": "object",
        "properties": [
            "task": ["type": "string"],
            "summary": ["type": "string"],
            "links": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "label": ["type": "string"],
                        "url": ["type": "string"],
                    ],
                    "required": ["label", "url"],
                ],
            ],
            "suggested_folder": ["type": "string"],
            "is_new_folder": ["type": "boolean"],
            "new_folder_name": ["type": "string"],
        ],
        "required": ["task", "summary", "links", "suggested_folder", "is_new_folder"],
        ]
    }
}

// MARK: - Ollama (local, default)

struct OllamaProvider: LLMProvider {
    var baseURL = URL(string: "http://localhost:11434")!
    var model = "gemma4:12b"

    func understand(_ input: ReelInput, folders: [String]) async throws -> ReelUnderstanding {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": LLMPrompt.system],
                ["role": "user", "content": LLMPrompt.user(input, folders: folders)],
            ],
            "format": LLMPrompt.jsonSchema,
            "stream": false,
            "keep_alive": "30m",
            "options": ["temperature": 0],
        ]

        var req = URLRequest(url: baseURL.appending(path: "api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 240

        let (data, _) = try await URLSession.shared.data(for: req)
        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = obj["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "<binary>")
        }
        return try JSONDecoder().decode(ReelUnderstanding.self, from: Data(content.utf8))
    }
}

// MARK: - Config (Settings UI will drive this later)

/// Central place the app reads the active provider from. Defaults to local Ollama/gemma4.
@MainActor
enum AIConfig {
    static var provider: LLMProvider = OllamaProvider()
}
