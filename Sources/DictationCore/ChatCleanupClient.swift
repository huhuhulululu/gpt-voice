import Foundation

/// Optional OpenAI-compatible `/v1/chat/completions` polish. Failures must fall back to deterministic text.
public enum ChatCleanupClient {
    public static func clean(_ text: String, model: String, baseURL: String, apiKey: String?,
                             session: URLSession) async throws -> String {
        let url = try OpenAICompatibleURL.chatCompletions(from: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [
                [
                    "role": "system",
                    "content": "Clean this voice transcript. Fix punctuation and sentence breaks. Remove filler words and trailing sign-offs. Keep the original language and script; never translate. Do not add, invent, or summarize content. Return only the cleaned transcript."
                ],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw DictationError.invalidResponse }
        if response.statusCode == 401 { throw DictationError.apiKeyRejected }
        guard response.statusCode == 200 else { throw DictationError.service(response.statusCode) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw DictationError.invalidResponse
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DictationError.emptyTranscript }
        return trimmed
    }
}

public enum TranscriptPostProcessor {
    public static func apply(
        _ text: String,
        deterministicCleanup: Bool,
        extraFilterWords: [String],
        replacements: [VocabularyReplacement],
        chineseScript: ChineseScript = .unchanged,
        prompt: String? = nil,
        chat: (model: String, baseURL: String, apiKey: String?)?,
        session: URLSession
    ) async -> String {
        var result = Vocabulary.stripPromptEcho(text, prompt: prompt)
        result = chineseScript.convert(result)
        if deterministicCleanup {
            var filters = TranscriptCleanup.defaultFilterWords
            filters.append(contentsOf: extraFilterWords)
            result = TranscriptCleanup.apply(result, filterWords: filters)
        }
        if !replacements.isEmpty {
            result = Vocabulary.applyReplacements(result, replacements)
        }
        if let chat, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let cleaned = try await ChatCleanupClient.clean(result, model: chat.model, baseURL: chat.baseURL,
                                                                apiKey: chat.apiKey, session: session)
                if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result = chineseScript.convert(cleaned)
                }
            } catch {
                // Keep the deterministic result.
            }
        }
        return result
    }
}
