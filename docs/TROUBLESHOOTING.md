# Troubleshooting

## Sign-in

Install [Codex CLI](https://developers.openai.com/codex/cli/) before starting browser sign-in.
Goice checks `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin` and the app's PATH for `codex`.
If a custom installation is not found, place the executable in one of those locations, then reopen the app.

Select **Sign in with ChatGPT** in the app. The flow uses Codex CLI's browser login.
The current build reads file-backed sessions in `~/.codex/auth.json`, or the directory set by `CODEX_HOME`.
It does not read keychain-only sessions. Do not paste access tokens into issues or send them to the maintainer.

If an account request fails after sign-in, try signing in again.
The private transcription endpoint can reject accounts or change. A subscription does not guarantee access to this third-party client.

For an OpenAI-compatible server, open **Settings → Transcription**, set the base URL and model, then use **Save & Test**. API keys stay in the Keychain. Localhost servers can omit a key.

## Microphone

Open **System Settings → Privacy & Security → Microphone** and enable Goice.
Return to the app to refresh its status.
If macOS did not yet list the app, select **Allow** inside Goice to request access.

## Accessibility and paste

Accessibility is optional. Choose manual paste to copy text and paste it with Command–V.
For automatic paste, enable Goice in **System Settings → Privacy & Security → Accessibility**.
Return to the app, or select its refresh button.
The status check also tries a read-only Accessibility request if macOS has not refreshed its trust flag.

A local rebuild can change an ad hoc signature. macOS can keep an old switch on while rejecting the new build.
In that case, remove the old Goice entry from Accessibility and add the current app again.
Quit and reopen the app after macOS applies the change.
For repeated local builds, use the same valid signing certificate. An ad hoc signature changes with the executable.
Do not reset all privacy permissions or disable macOS protections.

After you reinstall a Developer ID build, or replace Goice with a newly signed copy, macOS often keeps the old Accessibility grant against the previous signature. The switch can stay on while automatic paste silently fails.
In **System Settings → Privacy & Security → Accessibility**, turn Goice off and on again, or select the old entry, remove it with −, then add `/Applications/Goice.app` with +.
Quit and reopen Goice after macOS applies the change.
The same steps are in **Settings → Home** and **Privacy** under **Paste not working after an update?** (or **Already turned on?** when Accessibility still looks missing). History marks those results **Copied · paste failed**.

After a successful automatic paste, Goice restores the previous clipboard. The transcript is not left sitting there for the next Command–V.
Turn **Paste automatically** off if you want the text to stay on the clipboard.
Paste can fall back to copy if the destination app, Accessibility, or clipboard changes during a recording.
This protects newer clipboard content and avoids sending text to the wrong app.
History records `pasted` on success, or `copied` with a `reason` (`automaticPasteOff`, `accessibilityMissing`, `targetChanged`, `noTarget`, `injectionFailed`) when automatic paste is skipped.
Use **Copy Last Transcript** from the menu bar to recover the last result.

## Shortcut

Use **Settings → Shortcut → Test** to check receipt without recording.
Command–Space often belongs to Spotlight or another app.
Change that competing shortcut, or select a different shortcut in Goice.
The default is Control–Option–Space.

Hold one modifier key, such as Left Option, to record. Let go and the transcript is pasted.
A quick tap does nothing. The microphone opens after a brief hold, so Option can still be used with other keys.
That shortcut needs Input Monitoring. Enable Goice in System Settings → Privacy & Security → Input Monitoring, then quit and reopen the app if the hold does not respond.

## Download and installation

Download the official GitHub release. Open the DMG and drag Goice to Applications.
Eject the image, then open the installed copy.

If macOS shows a verification warning, ignore it and open **System Settings → Privacy & Security → Open Anyway**.
You can also [build from source](../README.md#build-from-source).

## Diagnostics

```sh
"/Applications/Goice.app/Contents/MacOS/Goice" --diagnose
```

Review the output before sharing it. It does not print account credentials or word-list entries.
If Goice is running, `runningApp` shows its phase, whether the level meter, menu bar animation or overlay is live, and a two-second sample of `residentMB`, `cpuPercent` and `wakeupsPerSecond`. At rest, `idleQuiet` should be `true` and CPU near 0%.
A command launched from a terminal can have a different macOS privacy context from a Finder-launched app.
Check permission behavior in the actual installed app as well.

## History

Successful transcriptions appear in **Settings → History**, newest first.
Copy an entry, delete one entry, or use **Clear all**. Deletion requires confirmation.
The app saves local dates and times. Pasted rows show **Pasted into** the destination app when it is known.
Copied rows show why automatic paste was skipped (`paste off`, `Accessibility off`, `app changed`, `no target`, or `paste failed`) without storing tokens or other secrets.
A manual Command–V cannot be tracked after the fact.

If History reports a save error, keep Goice open and select **Try again**.
An unreadable history file is kept intact. Goice does not replace it with an empty history.
