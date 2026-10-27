import Foundation

public enum TranscriptionService {
    public static func transcribe(
        file: URL,
        provider: TranscriptionProvider,
        language: String?,
        prompt: String?,
        openAI: OpenAICompatibleEndpoint,
        apiKey: String?,
        session: URLSession? = nil
    ) async throws -> String {
        switch provider {
        case .codex:
            if let session {
                return try await TranscriptionClient(session: session).transcribe(file: file, language: language)
            }
            return try await TranscriptionClient().transcribe(file: file, language: language)
        case .openAICompatible:
            let client: OpenAICompatibleClient
            if let session {
                client = OpenAICompatibleClient(session: session)
            } else {
                client = OpenAICompatibleClient()
            }
            var endpoint = openAI
            if let language { endpoint.language = language }
            return try await client.transcribe(file: file, endpoint: endpoint, apiKey: apiKey, prompt: prompt)
        }
    }
}
