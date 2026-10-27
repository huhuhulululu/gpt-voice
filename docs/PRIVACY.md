# Privacy

Goice has no developer-operated server, analytics, or account database.
The default Codex path requires an internet connection and sends recorded audio to ChatGPT.
An OpenAI-compatible server that you configure can stay on your machine. This app does not ship a local speech model.

| Data | Where it goes |
| --- | --- |
| Audio | A private temporary folder on your Mac, then ChatGPT or your configured transcription server |
| ChatGPT session | The existing Codex CLI configuration on your Mac, when using Codex |
| API key | macOS Keychain on this Mac, when using an OpenAI-compatible server |
| Chat cleanup | Each transcript and your word list's top terms and corrections go to the chat server you configure when chat cleanup is on and its URL, model and key are set. Its key is a separate Keychain item. |
| Transcript | The selected text field, or your clipboard for manual paste |
| Transcript history | `~/Library/Application Support/GPT Voice/history.json` on your Mac |
| Word list | `~/Library/Application Support/GPT Voice/lexicon.json` on your Mac |
| Preferences | macOS preferences on your Mac |

The app removes owned audio files after successful transcription, cancellation, and normal cleanup.
A failed request can keep its audio for Retry until another recording starts or the app quits.
A crash can leave temporary files until macOS removes them.
Successful transcriptions are saved on this Mac with their date, time, and delivery result.
When paste keystrokes are sent to a known app, history includes its name. Copied rows store a short reason enum, not the transcript twice and not tokens or other secrets. The app cannot confirm whether that app accepted the text.
Practice transcriptions, failed requests, and cancelled recordings are not saved.
Use **History** to copy a transcript, delete one entry, or clear all entries.
History is not uploaded by Goice. The file is readable only by your macOS user account.
Normal Mac backups can include this file. Audio is not kept in history.
The word list holds only the words and corrections you add, with hit counts and dates. It is not stored in the Keychain, not synced, and Goice never reads Contacts or other apps' text to fill it.
Recently heard words are sent as the transcription prompt to the service you chose. `--diagnose` prints counts only, never the words.
ChatGPT's handling of uploaded audio is subject to your account settings and OpenAI's policies.

Microphone access permits recording after you start dictation.
Accessibility access permits automatic paste. You can decline it and paste with Command–V instead.
The app rechecks permissions when you return from System Settings.

The website's interactive preview runs in your browser with fixed sample text.
It does not record or upload audio. Its video is a staged demonstration, not an accuracy benchmark.
