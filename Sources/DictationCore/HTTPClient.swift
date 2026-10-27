import Foundation

/// Shared transport defaults for Codex, OpenAI-compatible STT, and optional chat cleanup.
public enum HTTPClient {
    /// Product token shipped since the OpenAI-compatible path. Groq GET /models and POST
    /// /audio/transcriptions returned the same 401/404 for `GPTVoice`, a CFNetwork-style
    /// token, and an empty UA, so the sparse token is kept.
    public static let userAgent = "GPTVoice"
    /// Chat routers behind Cloudflare reject bare or bot-like agents (error 1010 / 403), so chat
    /// cleanup presents as desktop Safari.
    public static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// One session for the app lifetime. A session per request was never invalidated, so each dictation
    /// leaked one and paid a fresh TLS handshake; this one keeps the connection warm between takes.
    public static let shared: URLSession = makeSession()

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
