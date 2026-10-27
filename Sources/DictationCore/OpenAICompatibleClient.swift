import Foundation

public struct ConnectionTestResult: Equatable, Sendable {
    public var ok: Bool
    public var message: String

    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }
}

public final class OpenAICompatibleClient {
    private let session: URLSession

    public init() {
        self.session = HTTPClient.shared
    }

    init(session: URLSession) { self.session = session }

    public func transcribe(file: URL, endpoint: OpenAICompatibleEndpoint, apiKey: String?,
                           prompt: String? = nil) async throws -> String {
        let types = ["wav": "audio/wav", "m4a": "audio/mp4", "mp4": "audio/mp4", "mp3": "audio/mpeg",
                     "webm": "audio/webm", "ogg": "audio/ogg", "flac": "audio/flac"]
        guard let contentType = types[file.pathExtension.lowercased()] else { throw DictationError.invalidAudio }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue > 0 else { throw DictationError.invalidAudio }
        guard size.intValue < 20_000_000 else { throw DictationError.audioTooLarge }
        let audio = try AudioPreparation.prepareForUpload(Data(contentsOf: file), fileExtension: file.pathExtension)
        return try await send(audio: audio, filename: "dictation.\(file.pathExtension.lowercased())",
                              contentType: contentType, endpoint: endpoint, prompt: prompt,
                              url: try OpenAICompatibleURL.transcriptions(from: endpoint.baseURL), apiKey: apiKey)
    }

    /// gpt-4o transcription models accept only `json` and `text`.
    static func supportsVerboseJSON(model: String) -> Bool {
        !model.lowercased().hasPrefix("gpt-4o")
    }

    static func transcriptionFields(endpoint: OpenAICompatibleEndpoint, prompt: String?,
                                    verbose: Bool) -> [String: String] {
        var fields: [String: String] = ["model": endpoint.model]
        if let prompt, !prompt.isEmpty { fields["prompt"] = prompt }
        if verbose { fields["response_format"] = "verbose_json" }
        return fields
    }

    /// Asks for `verbose_json` so the hallucination gate can read segment scores. A server that
    /// rejects the format gets one plain retry.
    func send(audio: Data, filename: String, contentType: String, endpoint: OpenAICompatibleEndpoint,
              prompt: String?, url: URL, apiKey: String?) async throws -> String {
        func multipart(verbose: Bool) -> MultipartAudio {
            MultipartAudio(audio: audio, filename: filename, contentType: contentType,
                           language: endpoint.languageHint,
                           extraFields: Self.transcriptionFields(endpoint: endpoint, prompt: prompt, verbose: verbose))
        }
        let verbose = Self.supportsVerboseJSON(model: endpoint.model)
        do {
            return try await request(multipart(verbose: verbose), url: url, apiKey: apiKey)
        } catch DictationError.service(let code) where verbose && (code == 400 || code == 422) {
            return try await request(multipart(verbose: false), url: url, apiKey: apiKey)
        }
    }

    func request(_ multipart: MultipartAudio, url: URL, apiKey: String?) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(multipart.boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = multipart.body
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw DictationError.invalidResponse }
        if response.statusCode == 401 { throw DictationError.apiKeyRejected }
        guard response.statusCode == 200 else { throw DictationError.service(response.statusCode) }
        return try parseTranscript(data)
    }

    public func testConnection(endpoint: OpenAICompatibleEndpoint, apiKey: String?) async -> ConnectionTestResult {
        let url: URL
        do {
            url = try OpenAICompatibleURL.models(from: endpoint.baseURL)
        } catch {
            return ConnectionTestResult(ok: false, message: "The server URL is not valid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                return ConnectionTestResult(ok: false, message: "The server returned an unreadable response.")
            }
            switch response.statusCode {
            case 200..<300:
                return ConnectionTestResult(ok: true, message: "Connected. You can dictate now.")
            case 401:
                return ConnectionTestResult(ok: false, message: "The server rejected the API key.")
            case 403:
                return ConnectionTestResult(ok: false,
                                           message: "The server refused the request (HTTP 403). Check the URL, then try again.")
            case 404:
                return ConnectionTestResult(ok: true,
                                            message: "Reached the server. It does not list models; try a short dictation.")
            default:
                return ConnectionTestResult(ok: false, message: "The server responded with HTTP \(response.statusCode).")
            }
        } catch {
            return ConnectionTestResult(ok: false, message: "Could not reach the server.")
        }
    }

    private func parseTranscript(_ data: Data) throws -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let raw = object["text"] as? String {
            let segments = (object["segments"] as? [[String: Any]] ?? []).compactMap(TranscriptSegment.init(json:))
            let text = HallucinationGate.filter(text: raw, segments: segments)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw DictationError.emptyTranscript }
            return text
        }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
           !text.hasPrefix("{") {
            return text
        }
        throw DictationError.invalidResponse
    }
}
