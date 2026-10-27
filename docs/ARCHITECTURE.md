# How Goice works

Goice is a native Swift app with AppKit windows and SwiftUI content. The display name is Goice; the Swift package, executable, and bundle identifier stay GPTVoice.
It does not contain extracted ChatGPT application code or a local transcription model.
The implementation sends a request shaped like the transcription request observed in the ChatGPT desktop app.

1. A global shortcut starts AVFoundation audio capture.
2. Releasing a held shortcut, or a second press after a tap, stops capture.
3. `DictationCore` sends the audio to the selected provider over HTTPS. Codex (ChatGPT via Codex CLI) is the default. An OpenAI-compatible `/v1/audio/transcriptions` server is optional.
4. Optional local cleanup and vocabulary replacements run on the transcript. Optional chat cleanup is off by default and falls back to the local result.
5. Automatic paste inserts or pastes into the original app, then restores the clipboard. Manual paste leaves the transcript on the clipboard for Command–V.

`Sources/DictationCore` owns credentials, request construction, token renewal and transcript handling.
`Sources/GPTVoice` owns recording, shortcuts, paste delivery, settings and the recording pill.
`Tests` covers request behavior, empty speech, shortcut ownership, practice mode, overlay lifecycle, and clipboard restore after automatic paste.

Automatic paste first tries an Accessibility insert at the caret. If that is not available it writes the transcript, posts Command–V, then restores the previous clipboard when the app still owns that text. A clipboard helper that rewrites the same transcript does not leave it sticky. If Goice itself is frontmost (overlay or activation), delivery re-activates the captured target and still inserts or pastes. Manual paste, missing Accessibility, a different third-party app in front, or a failed keystroke keep the transcript for Command–V and record that `ManualReason` in history. A clipboard that changed during recording is left alone.

Sign-in and token renewal for the Codex path use the installed Codex CLI app-server protocol.
Goice reads the resulting file-backed ChatGPT session. Codex API-key auth files are still rejected.
OpenAI-compatible API keys are stored in the login keychain, never in the repository or UserDefaults. The Data Protection keychain is not used: it needs a keychain-access-groups entitlement and provisioning profile this Developer ID app does not have.
Menu and `--diagnose` only check that an item exists; they never decrypt it, so they cannot raise SecurityAgent or hang a headless packaging check. Codex dictation never reads the key.
Each item records the signature that wrote it (team ID for Developer ID, CDHash for ad-hoc). After a re-sign, the first OpenAI-compatible dictation reads the old item once — the only moment SecurityAgent can appear — then re-adds it under the new signature, writing a staging copy first so a failed replace never loses the key. The value is cached for the process, so later recordings are silent, and relaunches of the same signature read silently. Reads run off the main thread, one at a time, with the hold listener paused; Deny becomes a Retry failure instead of a keyless request.

Before upload, a WAV under 0.3 s is rejected as too short (accidental holds otherwise come back as Whisper hallucinations), and quiet 16-bit speech is lifted toward −20 dBFS, capped at +20 dB, without clipping; near-silence is left alone. For Chinese (`zh`), the Whisper prompt is a Mandarin lead sentence (plus custom words in Chinese style), echoes of that prompt are dropped, and output can be converted to Simplified or Traditional. Cleanup removes fillers such as 嗯 only when they stand alone, so 金额 and 额外 are untouched.
The current implementation does not read Codex sessions stored only in the macOS Keychain.

The service route is `https://chatgpt.com/backend-api/transcribe`.
It is private, undocumented for this use, and can change.
The project does not guarantee access on every plan or for every account.

The recording pill appears as soon as a hold is accepted, then uses a short fade and a 0.96–1.0 scale on entrance (0.16s; exit 0.11s). Width changes ease out. Transcribing and Pasting share one working surface so the flowing dots do not remount. Success holds for 1.15s; a Command–V hint holds for 1.8s. Dismiss uses a fade and a slight scale-down.
The pill is frosted glass: the system popover material behind the window (`NSVisualEffectView`, forced active because Goice never becomes the active app) under a soft white or charcoal tint, a 0.5 pt hairline and a lighter inner rim. Listening shows a breathing accent dot (1.6s loop), a 13-bar scrolling waveform driven only by the real input level, the timer, cancel, and an accent stop button. Working shows five dots with a wave running through them; Pasted shows an accent check that blooms once. Only the accent changes between the five colorways (waveform, live dot, stop, check, Retry); glass, text, quiet controls and the coral warning mark stay the same.
Reduce Motion keeps a short fade, snaps the size, stops the scroll and holds the dot and dots still. Reduce Transparency and Increase Contrast replace the glass with a solid surface, and Increase Contrast also uses solid accent fills behind white labels. Result notices disappear automatically. Accessibility paste failures can show a recovery card that opens System Settings. A missing Groq or OpenAI-compatible key opens Settings → Transcription. The menu bar also offers Microphone, Accessibility, Input Monitoring, Sign In, or Transcription Settings when that is the current failure.

## Local history

`TranscriptionHistory` publishes saved transcripts to the History page. It serializes commands and delegates file access to `HistoryRepository`.
The repository writes a versioned JSON document through a private temporary file and an atomic replacement.
Entries contain the exact text, completion time, and delivery result. Copied rows include a `ManualReason`. They do not contain audio, window titles, document paths, tokens, or account data. The History page shows a short caption (`Pasted into Notes` or `Copied · Accessibility off`) and, for copied rows, a tooltip that points to the fix.
Normal dictation saves once after delivery. Practice, errors, and cancellation before a result do not create entries. Copying an old result does not duplicate it.
The app waits for pending delivery and history writes before normal quit.
