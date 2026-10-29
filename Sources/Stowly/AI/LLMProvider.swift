import Foundation

/// The raw material handed to the model.
struct ReelInput {
    let caption: String
    let transcript: String
    let creator: String
    /// Source platform display name (e.g. "Instagram", "LinkedIn") so the model has context.
    var platform: String = ""
    /// Local video file (transcribed + read on-device). Nil for photo / link-only posts.
    var videoURL: URL? = nil
    /// Local stills for photo posts, one per carousel slide (no video).
    var imageURLs: [URL] = []
}

/// Strict structured result the provider returns.
struct ReelUnderstanding: Codable {
    struct Link: Codable { let label: String; let url: String }
    let task: String
    let summary: String
    let links: [Link]
    let suggested_folder: String
    let is_new_folder: Bool
    let new_folder_name: String?
}

/// Turns a post into a `ReelUnderstanding`. One real implementation (`AppleProvider`); the
/// protocol stays so the pipeline can be tested with a stub.
protocol LLMProvider: Sendable {
    func understand(_ input: ReelInput, folders: [String]) async throws -> ReelUnderstanding
    /// Suggest an SF Symbol identifier for a folder name (used for folder icons). Returns nil
    /// if the provider can't/won't. Default: nil.
    func suggestSymbol(for name: String) async -> String?
}

extension LLMProvider {
    func suggestSymbol(for name: String) async -> String? { nil }
}

enum LLMError: LocalizedError {
    case badResponse(String)
    case appleIntelligenceOff
    var errorDescription: String? {
        switch self {
        case .badResponse(let s): "AI returned an unexpected response: \(s)"
        case .appleIntelligenceOff: "Turn on Apple Intelligence in System Settings, then retry."
        }
    }
}

/// Stand-in when Apple Intelligence is off / still downloading: every post gets a retryable
/// error card telling the user what to do, instead of silently failing.
struct UnavailableProvider: LLMProvider {
    func understand(_ input: ReelInput, folders: [String]) async throws -> ReelUnderstanding {
        throw LLMError.appleIntelligenceOff
    }
}

/// Where the app reads its provider from. Apple's on-device model only — nothing leaves the Mac.
@MainActor
enum AIConfig {
    static var provider: LLMProvider {
        AppleProvider.isAvailable ? AppleProvider() : UnavailableProvider()
    }
}
