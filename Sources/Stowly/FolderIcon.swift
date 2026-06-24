import AppKit

/// Picks an SF Symbol for a folder. A fast keyword heuristic gives an instant icon; if an AI
/// provider is configured it proposes a better one, validated to actually exist before use.
enum FolderIcon {
    /// Instant, offline guess from the folder name.
    static func heuristic(for name: String) -> String {
        let n = name.lowercased()
        if n.matches("apply", "job", "intern", "fellow", "career", "resume") { return "paperplane.fill" }
        if n.matches("learn", "cert", "course", "study", "edu", "skill", "tutorial") { return "graduationcap.fill" }
        if n.matches("gym", "fit", "workout", "exercise", "training", "muscle") { return "dumbbell.fill" }
        if n.matches("health", "wellness", "medical") { return "heart.fill" }
        if n.matches("recipe", "food", "cook", "meal", "eat", "kitchen") { return "fork.knife" }
        if n.matches("watch", "video", "film", "movie", "show", "series") { return "play.rectangle.fill" }
        if n.matches("buy", "shop", "gear", "product", "deal") { return "cart.fill" }
        if n.matches("shoe", "fashion", "outfit", "wear", "cloth") { return "tshirt.fill" }
        if n.matches("travel", "trip", "place", "visit", "vacation") { return "airplane" }
        if n.matches("money", "financ", "invest", "budget", "saving", "stock") { return "dollarsign.circle.fill" }
        if n.matches("code", "dev", "program", "tech", "software") { return "chevron.left.forwardslash.chevron.right" }
        if n.matches("read", "book", "article") { return "book.fill" }
        if n.matches("music", "song", "playlist") { return "music.note" }
        if n.matches("art", "design", "creat", "draw") { return "paintbrush.fill" }
        if n.matches("game", "gaming") { return "gamecontroller.fill" }
        if n.matches("home", "house", "decor", "interior") { return "house.fill" }
        if n.matches("idea", "inspir", "tip") { return "lightbulb.fill" }
        if n.matches("photo", "camera", "edit") { return "camera.fill" }
        if n.matches("misc", "other", "random") { return "tray.full.fill" }
        return "folder.fill"
    }

    /// True if `name` is a real SF Symbol on this system (guards against AI hallucinations).
    static func isValidSymbol(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// AI-suggested symbol, validated. Nil when no AI provider / offline / invalid suggestion.
    @MainActor
    static func aiSuggestion(for name: String) async -> String? {
        guard let raw = await AIConfig.provider.suggestSymbol(for: name) else { return nil }
        // Take the first token only, strip code fences / quotes the model might add.
        let cleaned = raw
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t`'\"."))
            .split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init) ?? ""
        return isValidSymbol(cleaned) ? cleaned : nil
    }
}

private extension String {
    func matches(_ needles: String...) -> Bool { needles.contains(where: contains) }
}
