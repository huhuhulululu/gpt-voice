import Foundation

/// Words the speaker uses, given to the chat corrector so it can repair mishears toward them.
public struct ChatCleanupContext: Equatable, Sendable {
    public var terms: [String]
    public var corrections: [VocabularyReplacement]

    public static let empty = ChatCleanupContext()
    public static let maxTerms = 40
    public static let maxCorrections = 20

    public init(terms: [String] = [], corrections: [VocabularyReplacement] = []) {
        self.terms = terms
        self.corrections = corrections
    }
}

/// OpenAI-compatible `/v1/chat/completions` correction after STT. Failures must fall back to deterministic text.
public enum ChatCleanupClient {
    public static let timeout: TimeInterval = 12

    /// Chinese-capable ASR corrector. Fixes recognition errors only, and treats the word list as the
    /// strongest evidence for what was said.
    public static func systemPrompt(context: ChatCleanupContext = .empty) -> String {
        var lines = [
            "You correct speech-recognition (ASR) output from voice dictation. The user spoke this text; the recognizer may have written wrong characters or words that sound like the intended ones.",
            "Fix only clear recognition errors: homophones or near-sounding words that make no sense in context, and broken punctuation. Keep the language, script (简体/繁體), wording, word order, tone, and meaning.",
            "Never translate, summarize, expand, explain, answer, or add content. Do not replace an ordinary word that makes sense with another word. If you are not sure, leave the text exactly as it is.",
            "Return only the corrected text, with no quotes, notes, or explanations.",
            "这是语音听写的识别结果，可能有同音或近音错字。只改明显的识别错误，不要改写、润色、扩写、翻译或回答；不确定时原样返回。只输出修正后的文本。",
        ]
        let terms = unique(context.terms + context.corrections.map(\.correct)).prefix(ChatCleanupContext.maxTerms)
        if !terms.isEmpty {
            lines.append("The speaker often says these exact words and phrases; when the text has a near-sounding mistake of one, use it (常用词): " + terms.joined(separator: "、"))
        }
        let corrections = context.corrections.prefix(ChatCleanupContext.maxCorrections)
        if !corrections.isEmpty {
            lines.append("Known recognition errors (heard → meant): "
                         + corrections.map { "\($0.mishear) → \($0.correct)" }.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    /// The transcription key may only go to the same host it was issued for.
    public static func canShareTranscriptionKey(chatBaseURL: String, transcriptionBaseURL: String) -> Bool {
        guard let chat = host(chatBaseURL), let transcription = host(transcriptionBaseURL) else { return false }
        return chat == transcription
    }

    /// Rejects replies that are clearly not a corrected copy: empty, far longer, or far shorter.
    public static func isPlausibleCorrection(original: String, cleaned: String) -> Bool {
        let before = original.trimmingCharacters(in: .whitespacesAndNewlines).count
        let after = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard after > 0 else { return false }
        guard before > 0 else { return false }
        return after <= before * 3 / 2 + 8 && after * 2 >= before - 4
    }

    public static func clean(_ text: String, model: String, baseURL: String, apiKey: String?,
                             context: ChatCleanupContext = .empty, session: URLSession) async throws -> String {
        let url = try OpenAICompatibleURL.chatCompletions(from: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(HTTPClient.browserUserAgent, forHTTPHeaderField: "User-Agent")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": systemPrompt(context: context)],
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
        let trimmed = unwrap(content, original: text)
        guard !trimmed.isEmpty else { throw DictationError.emptyTranscript }
        guard isPlausibleCorrection(original: text, cleaned: trimmed) else { throw DictationError.invalidResponse }
        return trimmed
    }

    /// Drops a code fence or one pair of wrapping quotes that some models add, unless the
    /// transcript itself was quoted.
    static func unwrap(_ content: String, original: String) -> String {
        let source = original.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), text.hasSuffix("```"), text.count >= 6 {
            text = String(text.dropFirst(3).dropLast(3))
            if let newline = text.firstIndex(of: "\n"), !text[..<newline].contains(" ") {
                text = String(text[text.index(after: newline)...])
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("\"", "\""), ("“", "”"), ("「", "」")] where text.count >= 2 {
            if text.hasPrefix(open), text.hasSuffix(close), !source.hasPrefix(open),
               !text.dropFirst().dropLast().contains(where: { String($0) == open || String($0) == close }) {
                text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    private static func host(_ baseURL: String) -> String? {
        URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased()
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
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
        chatContext: ChatCleanupContext = .empty,
        session: URLSession
    ) async -> String {
        await applyReporting(text, deterministicCleanup: deterministicCleanup, extraFilterWords: extraFilterWords,
                             replacements: replacements, chineseScript: chineseScript, prompt: prompt,
                             chat: chat, chatContext: chatContext, session: session).text
    }

    /// Also returns the text that replacements saw, so a correction copied from History
    /// (already cleaned and script-converted) counts its hit.
    public static func applyReporting(
        _ text: String,
        deterministicCleanup: Bool,
        extraFilterWords: [String],
        replacements: [VocabularyReplacement],
        chineseScript: ChineseScript = .unchanged,
        prompt: String? = nil,
        chat: (model: String, baseURL: String, apiKey: String?)?,
        chatContext: ChatCleanupContext = .empty,
        session: URLSession
    ) async -> (text: String, beforeReplacements: String) {
        var result = Vocabulary.stripPromptEcho(text, prompt: prompt)
        result = chineseScript.convert(result)
        if deterministicCleanup {
            var filters = TranscriptCleanup.defaultFilterWords
            filters.append(contentsOf: extraFilterWords)
            result = TranscriptCleanup.apply(result, filterWords: filters)
        }
        let beforeReplacements = result
        if !replacements.isEmpty {
            result = Vocabulary.applyReplacements(result, replacements)
        }
        if let chat, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let cleaned = try await ChatCleanupClient.clean(result, model: chat.model, baseURL: chat.baseURL,
                                                                apiKey: chat.apiKey, context: chatContext,
                                                                session: session)
                if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let converted = chineseScript.convert(cleaned)
                    result = deterministicCleanup ? TranscriptCleanup.normalizeChinesePunctuation(converted) : converted
                }
            } catch {
                // Keep the deterministic result.
            }
        }
        return (result, beforeReplacements)
    }
}
