import DictationCore
import Foundation

/// A user-facing failure with one recovery path.
struct DictationFailure: Equatable {
    enum Kind: Equatable {
        case noSpeech
        case other
    }

    enum Recovery: Equatable {
        /// The audio is kept. Retry sends it again.
        case retry
        /// The audio is kept. Sign in, then Retry.
        case signInThenRetry
        /// Turn on the microphone in System Settings.
        case microphoneSettings
        /// Nothing to retry.
        case none
    }

    let message: String
    let recovery: Recovery
    let overlayMessage: String
    let kind: Kind

    var keepsAudio: Bool { recovery == .retry || recovery == .signInThenRetry }

    /// Compact overlay button that runs `AppModel.recoverFromOverlay`.
    var overlayActionTitle: String? {
        switch recovery {
        case .microphoneSettings: return "Open Settings"
        case .signInThenRetry: return "Sign in"
        case .retry: return "Retry"
        case .none: return nil
        }
    }

    init(message: String, recovery: Recovery, overlayMessage: String = "Dictation stopped", kind: Kind = .other) {
        self.message = message
        self.recovery = recovery
        self.overlayMessage = overlayMessage
        self.kind = kind
    }

    /// Maps a transcription error to plain recovery text.
    init(transcriptionError error: Error) {
        switch error {
        case DictationError.signInRequired, DictationError.invalidCredentials,
             DictationError.refreshFailed, DictationError.service(401):
            self.init(message: "Your ChatGPT sign-in is missing or expired. Sign in, then select Retry.",
                      recovery: .signInThenRetry, overlayMessage: "Sign in to ChatGPT")
        case DictationError.apiKeyRejected:
            self.init(message: "The transcription server rejected the API key. Check Settings → Transcription, then select Retry.",
                      recovery: .retry, overlayMessage: "Check the API key")
        case DictationError.invalidEndpoint:
            self.init(message: "The transcription server URL is not valid. Check Settings → Transcription.",
                      recovery: .retry, overlayMessage: "Check the server URL")
        case DictationError.refreshUnavailable:
            self.init(message: "Install Codex CLI and sign in with ChatGPT, then select Retry.",
                      recovery: .signInThenRetry, overlayMessage: "Sign in to ChatGPT")
        case DictationError.audioTooLarge:
            self.init(message: "This recording is too large to send. Record a shorter one.", recovery: .none,
                      overlayMessage: "Recording too long")
        case DictationError.invalidAudio:
            self.init(message: "The recording could not be read. Record again.", recovery: .none,
                      overlayMessage: "Recording unreadable")
        case DictationError.emptyTranscript:
            self.init(message: "No speech found. Try another recording.", recovery: .none,
                      overlayMessage: "No speech found", kind: .noSpeech)
        case DictationError.service(429):
            self.init(message: "ChatGPT reached a request limit. Wait a moment, then select Retry.", recovery: .retry,
                      overlayMessage: "Try again in a moment")
        case let error as DictationError:
            self.init(message: "\(error.localizedDescription) Select Retry to send the audio again.", recovery: .retry,
                      overlayMessage: "Transcription failed")
        case is URLError:
            self.init(message: "The transcription server could not be reached. Check your network, then select Retry.", recovery: .retry,
                      overlayMessage: "Couldn’t reach the server")
        default:
            self.init(message: "Transcription failed. Select Retry to send the audio again.", recovery: .retry,
                      overlayMessage: "Transcription failed")
        }
    }

    init(captureError error: AudioCaptureError, audioKept: Bool) {
        switch error {
        case .microphoneDenied:
            self.init(message: "Microphone access is off. Turn on \(AppBrand.displayName) in System Settings → Privacy & Security → Microphone, then start again.",
                      recovery: .microphoneSettings, overlayMessage: "Microphone access is off")
        case .deviceFailed where audioKept:
            self.init(message: "The microphone stopped. Select Retry to transcribe the audio recorded so far.",
                      recovery: .retry, overlayMessage: "Microphone stopped")
        default:
            self.init(message: error.localizedDescription + " Start dictation again.", recovery: .none,
                      overlayMessage: "Microphone unavailable")
        }
    }
}
