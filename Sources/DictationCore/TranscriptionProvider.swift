import Foundation

/// How audio is sent for speech-to-text. Codex (ChatGPT via Codex CLI) stays the default.
public enum TranscriptionProvider: String, CaseIterable, Identifiable, Sendable {
    case codex
    case openAICompatible

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .codex: return "Codex"
        case .openAICompatible: return "OpenAI-compatible"
        }
    }
}

public struct OpenAICompatibleEndpoint: Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var language: String

    public init(baseURL: String, model: String, language: String = "") {
        self.baseURL = baseURL
        self.model = model
        self.language = language
    }

    public var languageHint: String? {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum OpenAICompatibleURL {
    public static func transcriptions(from base: String) throws -> URL {
        try join(base, suffix: "v1/audio/transcriptions")
    }

    public static func chatCompletions(from base: String) throws -> URL {
        try join(base, suffix: "v1/chat/completions")
    }

    public static func models(from base: String) throws -> URL {
        try join(base, suffix: "v1/models")
    }

    public static func isLocalHost(_ base: String) -> Bool {
        guard let host = URL(string: trimmed(base))?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    private static func trimmed(_ base: String) -> String {
        var value = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private static func join(_ base: String, suffix: String) throws -> URL {
        let value = trimmed(base)
        guard !value.isEmpty, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw DictationError.invalidEndpoint
        }
        let lower = value.lowercased()
        if lower.hasSuffix("/" + suffix) || lower == suffix { return url }
        if lower.hasSuffix("/v1"), suffix.hasPrefix("v1/") {
            let rest = String(suffix.dropFirst(3))
            return url.appendingPathComponent(rest)
        }
        return suffix.split(separator: "/").reduce(url) { $0.appendingPathComponent(String($1)) }
    }
}
