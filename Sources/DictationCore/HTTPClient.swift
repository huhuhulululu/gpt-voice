import Foundation

/// Shared transport defaults for Codex, OpenAI-compatible STT, and optional chat cleanup.
public enum HTTPClient {
    /// Product token shipped since the OpenAI-compatible path. Groq GET /models and POST
    /// /audio/transcriptions returned the same 401/404 for `GPTVoice`, a CFNetwork-style
    /// token, and an empty UA, so the sparse token is kept.
    public static let userAgent = "GPTVoice"

    /// Ephemeral so audio and keys never hit the URL cache. System HTTP proxies (Clash) stay inherited.
    /// `waitsForConnectivity` stays off so a hold does not sit on “waiting for network.”
    public static func makeSession(timeout: TimeInterval = 90) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 20
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
}
