import Foundation

/// Google Gemini provider — multimodal. Sends the reel's video inline so the model reads the
/// speech, the on-screen text, AND the visuals in a single call (fixing the text-on-screen /
/// music reels the audio-only pipeline couldn't). Free tier (AI Studio key) covers personal
/// volume. Falls back to a text-only request if no/oversized video.
struct GeminiProvider: LLMProvider {
    let apiKey: String
    var model = "gemini-2.5-flash"

    /// Inline request payload cap is ~20 MB; keep a margin for the base64 + JSON overhead.
    private let maxInlineBytes = 18 * 1024 * 1024

    var needsVideo: Bool { true }

    func understand(_ input: ReelInput, folders: [String]) async throws -> ReelUnderstanding {
        var parts: [[String: Any]] = [["text": userPrompt(input, folders: folders)]]

        // Attach the video when present and small enough for an inline request.
        if let url = input.videoURL,
           let data = try? Data(contentsOf: url),
           data.count <= maxInlineBytes {
            parts.append([
                "inline_data": [
                    "mime_type": "video/mp4",
                    "data": data.base64EncodedString(),
                ]
            ])
        }

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": LLMPrompt.system]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": [
                "temperature": 0,
                "response_mime_type": "application/json",
                "response_schema": Self.responseSchema,
            ],
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw mapError(status: http.statusCode, body: data)
        }

        // candidates[0].content.parts[0].text holds the JSON string.
        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = obj["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let outParts = content["parts"] as? [[String: Any]],
            let text = outParts.first?["text"] as? String
        else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "<binary>")
        }
        return try JSONDecoder().decode(ReelUnderstanding.self, from: Data(text.utf8))
    }

    // MARK: - Helpers

    private var endpoint: URL {
        var c = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        c.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        return c.url!
    }

    private func userPrompt(_ input: ReelInput, folders: [String]) -> String {
        var s = """
        EXISTING FOLDERS: \(folders)

        Watch the attached reel video — the on-screen text, visuals, and spoken audio are the \
        primary signal. The caption is often reach-bait; use it only as a hint.

        --- CAPTION ---
        \(input.caption)
        """
        if !input.transcript.isEmpty {
            s += "\n\n--- TRANSCRIPT (auto, may have typos) ---\n\(input.transcript)"
        }
        return s
    }

    private func mapError(status: Int, body: Data) -> Error {
        switch status {
        case 429: return LLMError.badResponse("Gemini rate limit reached — try again shortly.")
        case 400, 403: return LLMError.badResponse("Gemini rejected the request (API key invalid or quota). Check your key.")
        default:
            let snippet = String(data: body, encoding: .utf8)?.prefix(200) ?? ""
            return LLMError.badResponse("Gemini error \(status): \(snippet)")
        }
    }

    /// Gemini structured-output schema (OpenAPI subset; types are uppercase Type enums).
    private static var responseSchema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "task": ["type": "STRING"],
                "summary": ["type": "STRING"],
                "links": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "label": ["type": "STRING"],
                            "url": ["type": "STRING"],
                        ],
                        "required": ["label", "url"],
                    ],
                ],
                "suggested_folder": ["type": "STRING"],
                "is_new_folder": ["type": "BOOLEAN"],
                "new_folder_name": ["type": "STRING"],
            ],
            "required": ["task", "summary", "links", "suggested_folder", "is_new_folder"],
        ]
    }
}
