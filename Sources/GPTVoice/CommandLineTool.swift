import AppKit
import ApplicationServices
import AVFoundation
import DictationCore
import Foundation

/// Command-line modes. Never prompts for permissions and never prints credential values.
enum CommandLineTool {
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
    }

    /// Prints status JSON. Reads status only.
    static func diagnose() -> Int32 {
        FontRegistration.registerBundledFonts()
        let keyConfigured = KeychainSecretStore().containsSecret(for: KeychainSecretStore.apiKeyAccount)
        var result: [String: Any] = [
            "appVersion": appVersion,
            "displayName": AppBrand.displayName,
            "microphone": microphoneName(AVCaptureDevice.authorizationStatus(for: .audio)),
            "accessibility": AccessibilityPermission.check(),
            "inputMonitoring": InputMonitoringPermission.isGranted,
            "codexCLIAvailable": CodexAuthentication.cliAvailable,
            "transcriptionProvider": UserDefaults.standard.string(forKey: "transcriptionProvider") ?? "codex",
            "openAIKeyConfigured": keyConfigured,
            "bundledFonts": FontRegistration.fontAvailability,
            "process": [
                "name": ProcessInfo.processInfo.processName,
                "executable": Bundle.main.executableURL?.lastPathComponent ?? "",
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            ],
            "lexicon": lexiconSummary(defaults: .standard),
            "chatCleanup": chatCleanupSummary(),
        ]
        if let running = runningAppSummary() {
            result["runningApp"] = running
        } else {
            result["runningApp"] = NSNull()
        }
        do {
            let credentials = try CodexCredentials.load()
            result["authAvailable"] = true
            result["needsRefresh"] = credentials.needsRefresh
        } catch {
            result["authAvailable"] = false
            result["needsRefresh"] = NSNull()
            result["authError"] = error.localizedDescription
        }
        return printJSON(result, to: .standardOutput) ? 0 : 1
    }

    /// Settings and key presence only; the key is never read and nothing is migrated.
    private static func chatCleanupSummary() -> [String: Any] {
        let defaults = UserDefaults.standard
        let migrated = defaults.integer(forKey: "chatCleanupDefaultsVersion") >= 1
        let stored = defaults.string(forKey: "chatCleanupBaseURL")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = migrated
            ? (stored?.isEmpty == false ? stored! : defaults.string(forKey: "openAIBaseURL") ?? "")
            : AppPreferences.defaultChatCleanupBaseURL
        return [
            "enabled": migrated ? (defaults.object(forKey: "chatCleanup") as? Bool ?? true) : true,
            "host": URL(string: base)?.host ?? "",
            "model": migrated
                ? (defaults.string(forKey: "chatCleanupModel") ?? AppPreferences.defaultChatCleanupModel)
                : AppPreferences.defaultChatCleanupModel,
            "chatKeyConfigured": KeychainSecretStore().containsSecret(for: KeychainSecretStore.chatAPIKeyAccount),
        ]
    }

    /// Counts only. Words and corrections never leave the file.
    private static func lexiconSummary(defaults: UserDefaults) -> [String: Any] {
        let lexicon = savedLexicon(defaults: defaults)
        let script = ChineseScript(rawValue: defaults.string(forKey: "chineseScript") ?? "") ?? .simplified
        let prompt = lexicon.transcriptionPrompt(language: defaults.string(forKey: "transcriptionLanguage"),
                                                 script: script)
        return [
            "terms": lexicon.terms.count,
            "corrections": lexicon.replacements.count,
            "promptTerms": lexicon.promptTerms().count,
            "promptTokensEstimate": prompt.map(Vocabulary.estimatedTokens) ?? 0,
        ]
    }

    /// Asks the running app for its timers, then samples its CPU, memory, and wakeups for two seconds.
    private static func runningAppSummary() -> [String: Any]? {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.vishesh.codex-dictation"
        var summary = RuntimeProbe.queryRunningApp() ?? [:]
        let ownPID = getpid()
        let pid = (summary["pid"] as? Int).map { pid_t($0) }
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first { $0.processIdentifier != ownPID }?.processIdentifier
        guard let pid else { return nil }
        summary["pid"] = Int(pid)
        if summary["phase"] == nil { summary["probe"] = "no answer" }
        if let usage = ProcessUsage.sample(pid: pid, seconds: 2) {
            summary.merge(usage) { _, new in new }
        }
        let idlePhases: Set<String> = ["idle", "finished", "failed"]
        if let phase = summary["phase"] as? String, idlePhases.contains(phase) {
            summary["idleQuiet"] = summary["meterTimerRunning"] as? Bool == false
                && summary["menuBarAnimationRunning"] as? Bool == false
                && summary["overlayVisible"] as? Bool == false
        }
        return summary
    }

    /// Merges a seed file into the word list. Refuses while Goice runs, because the app keeps the list
    /// in memory and would write its own copy back.
    static func importLexicon(path: String) -> Int32 {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.vishesh.codex-dictation"
        let ownPID = getpid()
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != ownPID && !$0.isTerminated }) {
            return usageError("Quit \(AppBrand.displayName) first, then run --import-lexicon again.")
        }
        let seed: LexiconSeed
        do {
            seed = try JSONDecoder().decode(LexiconSeed.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        } catch {
            return usageError("Could not read the seed file: \(error.localizedDescription)")
        }
        let defaults = UserDefaults.standard
        let store = LexiconStore(fileURL: LexiconLibrary.defaultFileURL(besides: TranscriptionHistory.defaultFileURL))
        var lexicon: Lexicon
        switch store.load(movingUnreadableAside: false) {
        case .loaded(let saved): lexicon = saved
        case .missing:
            lexicon = Lexicon.migrating(words: defaults.string(forKey: "vocabularyWords") ?? "",
                                        replacements: defaults.string(forKey: "vocabularyReplacements") ?? "")
        case .unreadable:
            return usageError("The saved word list could not be read. Open \(AppBrand.displayName) once to set it aside.")
        }
        let added = lexicon.merge(seed)
        do {
            try store.save(lexicon)
        } catch {
            return usageError("Could not save the word list: \(error.localizedDescription)")
        }
        let result: [String: Any] = [
            "addedTerms": added.terms, "addedCorrections": added.corrections,
            "terms": lexicon.terms.count, "corrections": lexicon.replacements.count,
        ]
        return printJSON(result, to: .standardOutput) ? 0 : 1
    }

    /// Read-only: the CLI never migrates or writes the word list.
    private static func savedLexicon(defaults: UserDefaults) -> Lexicon {
        let url = LexiconLibrary.defaultFileURL(besides: TranscriptionHistory.defaultFileURL)
        if case .loaded(let lexicon) = LexiconStore(fileURL: url).load(movingUnreadableAside: false) { return lexicon }
        return Lexicon.migrating(words: defaults.string(forKey: "vocabularyWords") ?? "",
                                 replacements: defaults.string(forKey: "vocabularyReplacements") ?? "")
    }

    /// Prints only the transcript to stdout. Failures go to stderr.
    static func transcribe(path: String) async -> Int32 {
        let url = URL(fileURLWithPath: path)
        do {
            let defaults = UserDefaults.standard
            let provider = TranscriptionProvider(rawValue: defaults.string(forKey: "transcriptionProvider") ?? "") ?? .codex
            let endpoint = OpenAICompatibleEndpoint(
                baseURL: defaults.string(forKey: "openAIBaseURL") ?? "https://api.openai.com/v1",
                model: defaults.string(forKey: "openAIModel") ?? "whisper-1",
                language: defaults.string(forKey: "transcriptionLanguage") ?? ""
            )
            let script = ChineseScript(rawValue: defaults.string(forKey: "chineseScript") ?? "") ?? .simplified
            let prompt = savedLexicon(defaults: defaults)
                .transcriptionPrompt(language: endpoint.languageHint, script: script)
            let apiKey = provider == .openAICompatible
                ? KeychainSecretStore().secret(for: KeychainSecretStore.apiKeyAccount) : nil
            let raw = try await TranscriptionService.transcribe(
                file: url,
                provider: provider,
                language: endpoint.languageHint,
                prompt: prompt,
                openAI: endpoint,
                apiKey: apiKey
            )
            let text = Vocabulary.stripPromptEcho(raw, prompt: prompt)
            FileHandle.standardOutput.write(Data((text + "\n").utf8))
            return 0
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            return 1
        }
    }

    /// Renews the shared sign-in through Codex CLI. Prints success or failure metadata only.
    static func refreshAuthCheck() async -> Int32 {
        do {
            let credentials = try await CodexAuthentication.refresh()
            _ = printJSON(["ok": true, "needsRefresh": credentials.needsRefresh], to: .standardOutput)
            return 0
        } catch {
            _ = printJSON(["ok": false, "error": error.localizedDescription], to: .standardError)
            return 1
        }
    }

    static func usageError(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 2
    }

    private static func microphoneName(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    private static func printJSON(_ object: [String: Any], to handle: FileHandle) -> Bool {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        data.append(0x0a)
        handle.write(data)
        return true
    }
}
