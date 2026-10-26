# How GPT Voice works

GPT Voice is a native Swift app with AppKit windows and SwiftUI content.
It does not contain extracted ChatGPT application code or a local transcription model.
The implementation sends a request shaped like the transcription request observed in the ChatGPT desktop app.

1. A global shortcut starts AVFoundation audio capture.
2. Releasing a held shortcut, or a second press after a tap, stops capture.
3. `DictationCore` sends the audio to ChatGPT over HTTPS.
4. The response becomes a transcript.
5. Automatic paste inserts or pastes into the original app, then restores the clipboard. Manual paste leaves the transcript on the clipboard for Command–V.

`Sources/DictationCore` owns credentials, request construction, token renewal and transcript handling.
`Sources/GPTVoice` owns recording, shortcuts, paste delivery, settings and the recording pill.
`Tests` covers request behavior, empty speech, shortcut ownership, practice mode, overlay lifecycle, and clipboard restore after automatic paste.

Automatic paste first tries an Accessibility insert at the caret. If that is not available it writes the transcript, posts Command–V, then restores the previous clipboard when the app still owns that text. A clipboard helper that rewrites the same transcript does not leave it sticky. If GPT Voice itself is frontmost (overlay or activation), delivery re-activates the captured target and still inserts or pastes. Manual paste, missing Accessibility, a different third-party app in front, or a failed keystroke keep the transcript for Command–V and record that `ManualReason` in history. A clipboard that changed during recording is left alone.

Sign-in and token renewal use the installed Codex CLI app-server protocol.
GPT Voice reads the resulting file-backed ChatGPT session. API-key authentication is not supported.
The current implementation does not read Codex sessions stored only in the macOS Keychain.

The service route is `https://chatgpt.com/backend-api/transcribe`.
It is private, undocumented for this use, and can change.
The project does not guarantee access on every plan or for every account.

The recording pill appears as soon as a hold is accepted, then uses a short fade and a 0.96–1.0 scale on entrance. Width changes ease out. Dismiss uses a fade and a slight scale-down.
Reduce Motion keeps a short fade and snaps the size. Result notices disappear automatically. Recovery actions stay in the menu bar.

## Local history

`TranscriptionHistory` publishes saved transcripts to the History page. It serializes commands and delegates file access to `HistoryRepository`.
The repository writes a versioned JSON document through a private temporary file and an atomic replacement.
Entries contain the exact text, completion time, and delivery result. They do not contain audio, window titles, document paths, or account data.
Normal dictation saves once after delivery. Practice, errors, and cancellation before a result do not create entries. Copying an old result does not duplicate it.
The app waits for pending delivery and history writes before normal quit.
