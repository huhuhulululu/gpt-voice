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

    private static func chatSettings(_ defaults: UserDefaults) -> (enabled: Bool, baseURL: String, model: String) {
        (defaults.bool(forKey: "chatCleanup"),
                defaults.string(forKey: "chatCleanupBaseURL")?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? AppPreferences.defaultChatCleanupBaseURL,
                defaults.string(forKey: "chatCleanupModel")?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? AppPreferences.defaultChatCleanupModel)
    }

    /// Settings and key presence only; the key is never read.
    private static func chatCleanupSummary() -> [String: Any] {
        let settings = chatSettings(.standard)
        return [
            "enabled": settings.enabled,
            "host": URL(string: settings.baseURL)?.host ?? "",
            "model": settings.model,
            "configured": !settings.baseURL.isEmpty && !settings.model.isEmpty,
            "chatKeyConfigured": KeychainSecretStore().containsSecret(for: KeychainSecretStore.chatAPIKeyAccount),
        ]
    }

    /// Live acceptance check: runs recorded mishears and an ordinary line through local cleanup, the
    /// saved word list, and the configured chat server. Reads the chat key; never prints it.
    static func checkChatCleanup() async -> Int32 {
        let defaults = UserDefaults.standard
        let settings = chatSettings(defaults)
        guard !settings.baseURL.isEmpty, !settings.model.isEmpty else {
            return usageError("Set Chat base URL and Chat model in Settings → Transcription → Chat cleanup first.")
        }
        guard case .value(let key) = KeychainSecretStore().readSecret(for: KeychainSecretStore.chatAPIKeyAccount),
              !key.isEmpty else {
            return usageError("No chat key is saved. Add it in Settings → Transcription → Chat cleanup.")
        }
        var lexicon = savedLexicon(defaults: defaults)
        lexicon.merge(LexiconSeed(terms: ["锄禾日当午", "汗滴禾下土", "采菊东篱下", "悠然见南山"]))
        let context = ChatCleanupContext(terms: lexicon.promptTerms(),
                                         corrections: Array(lexicon.replacementList.prefix(ChatCleanupContext.maxCorrections)))
        let cases: [(input: String, mustContain: String, mustKeep: Bool)] = [
            ("彩鞠动篱下,悠然见南山。", "采菊东篱下", false),
            ("出禾日当午,汗滴禾下土,", "锄禾日当午", false),
            ("锄禾日当午,棺中有老虎。", "汗滴禾下土", false),
            ("老板,帮我把鸟花拿过来。", "鸟花", true),
        ]
        var results: [[String: Any]] = []
        var passed = true
        for sample in cases {
            let started = Date()
            let local = await TranscriptPostProcessor.apply(
                sample.input, deterministicCleanup: true, extraFilterWords: [], replacements: lexicon.replacementList,
                chineseScript: .simplified, chat: nil, session: HTTPClient.shared)
            var chatError: String?
            var output = local
            do {
                output = ChineseScript.simplified.convert(try await ChatCleanupClient.clean(
                    local, model: settings.model, baseURL: settings.baseURL, apiKey: key, context: context,
                    session: HTTPClient.shared))
            } catch {
                chatError = error.localizedDescription
            }
            let ok = output.contains(sample.mustContain) && (!sample.mustKeep || output == local) && chatError == nil
            passed = passed && ok
            var row: [String: Any] = ["input": sample.input, "output": output, "pass": ok,
                                      "seconds": (Date().timeIntervalSince(started) * 100).rounded() / 100]
            if let chatError { row["chatError"] = chatError }
            results.append(row)
        }
        let report: [String: Any] = ["host": URL(string: settings.baseURL)?.host ?? "", "model": settings.model,
                                     "pass": passed, "cases": results]
        return printJSON(report, to: .standardOutput) && passed ? 0 : 1
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
