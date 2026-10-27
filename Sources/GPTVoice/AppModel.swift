import AppKit
import ApplicationServices
import AVFoundation
import DictationCore
import ServiceManagement

/// Owns dictation, sign-in, permissions, shortcut, and preferences for every view.
@MainActor
final class AppModel: NSObject, ObservableObject {
    let preferences: AppPreferences
    let history: TranscriptionHistory

    @Published private(set) var phase: DictationPhase = .idle
    @Published private(set) var connection: ConnectionStatus = .checking
    @Published private(set) var cliAvailable = CodexAuthentication.cliAvailable
    @Published private(set) var authError: String?
    @Published private(set) var microphone = PermissionStatus(AudioCapture.microphoneStatus)
    @Published private(set) var accessibilityTrusted = AccessibilityPermission.check()
    @Published private(set) var hotkeyError: String?
    /// True when the last shortcut failed because a macOS shortcut, such as Spotlight, owns it.
    @Published private(set) var hotkeyBlockedBySystem = false
    /// True when the chosen shortcut is a modifier hold and Input Monitoring is missing.
    @Published private(set) var hotkeyNeedsInputMonitoring = false
    @Published private(set) var isCapturingShortcut = false
    @Published private(set) var shortcutTestStatus: ShortcutTestStatus = .idle
    @Published private(set) var launchAtLogin = LaunchAtLoginStatus.current()
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0
    /// The last successful transcript. Memory only.
    @Published private(set) var lastTranscript: String?
    @Published private(set) var practiceTranscript: String?
    @Published private(set) var isPracticeSession = false
    @Published private(set) var openAIKeyPresent = false
    @Published private(set) var connectionTest: ConnectionTestResult?
    @Published private(set) var isTestingConnection = false
    /// Settings opens this page when set, then clears it.
    @Published var preferredSettingsPage: SettingsPage?

    private let audio: AudioCapture
    private let paste: PasteCoordinator
    private let transcribeAudio: (@Sendable (URL) async throws -> String)?
    let secrets: SecretStore
    private var shortcut: GlobalShortcut?
    private var generation = 0
    private var operation: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?
    private var activeAudio: URL?
    private var failedAudio: URL?
    private var meterTimer: Timer?
    private var permissionRefresh: Task<Void, Never>?
    private var isPracticingInOnboarding = false
    /// This hold opened the current recording. Release stops it. A chord cancels it.
    private var modifierHoldOwnsSession = false
    /// The key was released while the microphone was still starting.
    private var stopModifierHoldWhenRecording = false
    /// Release already played its cue. The later stop must not click again.
    private var didPlayReleaseCue = false
    /// Chosen modifier hold waiting for Input Monitoring. Applied once the grant appears.
    private var pendingModifierHold: HotkeySpec?
    private var lastInputMonitoringGrant = InputMonitoringPermission.isGranted
    private let keychainQueue = DispatchQueue(label: "com.vishesh.codex-dictation.keychain", qos: .userInitiated)

    static let installCodexURL = URL(string: "https://developers.openai.com/codex/cli/")!

    init(preferences: AppPreferences? = nil, pasteboard: NSPasteboard? = nil,
         history: TranscriptionHistory? = nil,
         pasteEnvironment: PasteCoordinator.Environment = .live,
         secrets: SecretStore = KeychainSecretStore(),
         transcribeAudio: (@Sendable (URL) async throws -> String)? = nil) {
        self.preferences = preferences ?? AppPreferences()
        self.history = history ?? TranscriptionHistory()
        self.secrets = secrets
        self.transcribeAudio = transcribeAudio
        audio = AudioCapture()
        paste = PasteCoordinator(pasteboard: pasteboard ?? .general, environment: pasteEnvironment)
        super.init()
        audio.onMaximumDuration = { [weak self] url in self?.captureEnded(url: url) }
        audio.onFailure = { [weak self] error, url in self?.captureFailed(error, url: url) }
        shortcut = GlobalShortcut(onPress: { [weak self] in self?.receiveGlobalShortcut() },
                                  onHoldReleased: { [weak self] in self?.receiveGlobalShortcutRelease() },
                                  onModifierHoldBegan: { [weak self] in self?.beginModifierHold() },
                                  onModifierHoldEnded: { [weak self] in self?.endModifierHold() },
                                  onModifierHoldCancelled: { [weak self] in self?.interruptModifierHold() })
        refreshStatus()
    }

    // MARK: Derived state

    var statusText: String { phase.statusText }
    var canStart: Bool { !phase.isBusy && !paste.isLeasePending }
    var canRetry: Bool { failedAudio != nil && !phase.isBusy }
    var canChangeSettings: Bool { !phase.isBusy && !paste.isLeasePending }
    var hotkey: HotkeySpec { preferences.hotkey }
    var commandSpaceIsActive: Bool {
        hotkey == .commandSpace && shortcut?.current == .commandSpace && hotkeyError == nil
    }
    var leftOptionIsActive: Bool {
        hotkey == .leftOption && shortcut?.current == .leftOption && hotkeyError == nil
    }
    var isReadyToDictate: Bool {
        transcriptionIsReady && (microphone == .granted || microphone == .notRequested)
    }

    var transcriptionIsReady: Bool {
        switch preferences.transcriptionProvider {
        case .codex: return connection.isUsable
        case .openAICompatible: return preferences.openAICompatibleIsReady(hasAPIKey: openAIKeyPresent)
        }
    }

    /// Items still missing for onboarding. Accessibility is optional.
    var missingRequirements: [String] {
        var missing: [String] = []
        if !transcriptionIsReady {
            missing.append(preferences.usesOpenAICompatible ? "Configure transcription" : "Sign in with ChatGPT")
        }
        if microphone != .granted { missing.append("Allow microphone access") }
        if hotkeyError != nil || shortcut?.current == nil { missing.append("Choose a working shortcut") }
        return missing
    }

    // MARK: Lifecycle

    /// Registers the saved shortcut. Call once after launch.
    func activate() {
        if preferences.hotkey.isModifierHold, !InputMonitoringPermission.isGranted {
            _ = InputMonitoringPermission.request()
        }
        do {
            try shortcut?.replace(with: preferences.hotkey)
            hotkeyError = nil
            hotkeyBlockedBySystem = false
            hotkeyNeedsInputMonitoring = false
            pendingModifierHold = nil
        } catch {
            noteShortcutRegistrationFailure(error, spec: preferences.hotkey)
        }
    }

    /// Rechecks sign-in, permissions, and login item status without prompting.
    func refreshStatus() {
        cliAvailable = CodexAuthentication.cliAvailable
        if signInTask == nil { connection = ConnectionStatus.current() }
        refreshSecretFlags()
        microphone = PermissionStatus(AudioCapture.microphoneStatus)
        accessibilityTrusted = AccessibilityPermission.check()
        launchAtLogin = LaunchAtLoginStatus.current()
        retryPendingModifierHoldIfGranted()
        recheckPermissionsAfterReturn()
    }

    /// macOS can publish a permission change after its Settings window loses focus.
    /// Recheck briefly so the UI reflects the grant without another click.
    private func recheckPermissionsAfterReturn() {
        permissionRefresh?.cancel()
        permissionRefresh = Task { [weak self] in
            for delay in [300_000_000, 700_000_000, 1_500_000_000] as [UInt64] {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                guard let self, !Task.isCancelled else { return }
                let microphone = PermissionStatus(AudioCapture.microphoneStatus)
                let accessibility = AccessibilityPermission.check()
                if self.microphone != microphone { self.microphone = microphone }
                if self.accessibilityTrusted != accessibility { self.accessibilityTrusted = accessibility }
                self.retryPendingModifierHoldIfGranted()
            }
        }
    }

    /// Registers a modifier hold that was chosen before Input Monitoring was granted.
    private func retryPendingModifierHoldIfGranted() {
        let granted = InputMonitoringPermission.isGranted
        let becameGranted = granted && !lastInputMonitoringGrant
        guard becameGranted, let pending = pendingModifierHold else {
            lastInputMonitoringGrant = granted
            return
        }
        // Keep the edge while the recorder is open, and try again after it closes.
        guard !isCapturingShortcut else { return }
        lastInputMonitoringGrant = true
        pendingModifierHold = nil
        _ = setHotkey(pending)
    }

    private func noteShortcutRegistrationFailure(_ error: Error, spec: HotkeySpec) {
        hotkeyError = error.localizedDescription
        hotkeyBlockedBySystem = false
        hotkeyNeedsInputMonitoring = false
        guard let registration = error as? GlobalShortcut.RegistrationError else { return }
        switch registration {
        case .systemShortcut:
            hotkeyBlockedBySystem = true
        case .inputMonitoring where spec.isModifierHold:
            hotkeyNeedsInputMonitoring = true
            pendingModifierHold = spec
        default:
            break
        }
    }

    func completeOnboarding() {
        guard missingRequirements.isEmpty else { return }
        preferences.onboardingCompleted = true
    }

    /// Stops all work and deletes every owned audio file. Call on quit.
    func cleanup() {
        permissionRefresh?.cancel()
        permissionRefresh = nil
        endShortcutTest()
        isPracticingInOnboarding = false
        cancel()
        signInTask?.cancel()
        signInTask = nil
        audio.cleanup()
        failedAudio = nil
        practiceTranscript = nil
        shortcut?.unregister()
    }

    // MARK: Dictation

    /// Starts recording when idle. Stops and transcribes when recording.
    func toggleDictation() {
        if phase == .recording { stopDictation() } else { startDictation() }
    }

    func startDictation() {
        endShortcutTest()
        startCapture(practice: isPracticingInOnboarding)
    }

    func beginPractice() {
        endShortcutTest()
        isPracticingInOnboarding = true
    }

    func startPracticeDictation() {
        startCapture(practice: true)
    }

    func endPractice() {
        isPracticingInOnboarding = false
        guard isPracticeSession else { return }
        cancel()
        practiceTranscript = nil
    }

    private func startCapture(practice: Bool) {
        guard canStart, !isCapturingShortcut else { return }
        isPracticeSession = practice
        if practice { practiceTranscript = nil }
        // Stay on the cached sign-in and permission flags. A full refresh reads
        // auth.json and can wait on Accessibility, which delays the overlay.
        guard transcriptionIsReady else {
            if preferences.usesOpenAICompatible {
                fail(DictationFailure(message: "Add a transcription server URL and API key in Settings → Transcription, then start dictation.",
                                      recovery: .transcriptionSettings, overlayMessage: "Configure transcription"))
            } else {
                fail(DictationFailure(message: "Sign in with ChatGPT in Settings, then start dictation.",
                                      recovery: .signInThenRetry, overlayMessage: "Sign in to ChatGPT"))
            }
            return
        }
        if microphone == .denied || microphone == .restricted {
            fail(DictationFailure(captureError: .microphoneDenied, audioKept: false))
            return
        }
        discardFailedAudio()
        generation += 1
        let current = generation
        if !practice { paste.noteIntendedTarget() }
        phase = .preparing
        playStartCue()
        operation = Task {
            await paste.waitForLease()
            guard current == generation else { return }
            if !isPracticeSession { paste.beginSession() }
            do {
                try await audio.start()
            } catch let error as AudioCaptureError {
                guard current == generation else { return }
                microphone = PermissionStatus(AudioCapture.microphoneStatus)
                fail(DictationFailure(captureError: error, audioKept: false))
                return
            } catch {
                guard current == generation else { return }
                fail(DictationFailure(captureError: .startFailed, audioKept: false))
                return
            }
            guard current == generation else { audio.cancel(); return }
            microphone = .granted
            phase = .recording
            startMeter()
            if stopModifierHoldWhenRecording {
                stopModifierHoldWhenRecording = false
                stopDictation()
            }
        }
    }

    /// Starts dictation after a modifier key has been held on its own.
    func beginModifierHold() {
        switch shortcutTestStatus {
        case .listening, .received:
            shortcutTestStatus = .received
            return
        case .idle, .unavailable:
            break
        }
        guard canStart, !isCapturingShortcut else { return }
        modifierHoldOwnsSession = true
        stopModifierHoldWhenRecording = false
        startDictation()
    }

    /// Keeps recording this long after release so a syllable still leaving the mouth is not clipped.
    static let releaseTail: TimeInterval = 0.12

    /// Stops the recording started by the hold and sends it for transcription.
    func endModifierHold() {
        guard modifierHoldOwnsSession else { return }
        modifierHoldOwnsSession = false
        if phase == .recording {
            playReleaseCue()
            let current = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseTail) { [weak self] in
                guard let self, self.generation == current, self.phase == .recording else { return }
                self.stopDictation()
            }
        } else if phase == .preparing {
            stopModifierHoldWhenRecording = true
            playReleaseCue()
        }
    }

    /// Drops a hold that turned into a normal modifier chord. Nothing is pasted.
    func interruptModifierHold() {
        guard modifierHoldOwnsSession else { return }
        modifierHoldOwnsSession = false
        stopModifierHoldWhenRecording = false
        didPlayReleaseCue = false
        if phase == .preparing || phase == .recording { cancel() }
    }

    func stopDictation() {
        guard phase == .recording, let url = try? audio.stop() else { return }
        playReleaseCue()
        captureEnded(url: url)
    }

    /// Stop from the overlay or practice console. Works while the microphone is still opening.
    func requestStop() {
        if phase == .recording {
            stopDictation()
        } else if phase == .preparing {
            stopModifierHoldWhenRecording = true
            playReleaseCue()
        }
    }

    /// Cancels recording or transcription. Deletes the audio. A stale result never pastes.
    /// Paste delivery is short and cannot be cancelled, so it keeps its clipboard lease.
    func cancel() {
        modifierHoldOwnsSession = false
        stopModifierHoldWhenRecording = false
        didPlayReleaseCue = false
        let pasting = phase == .pasting
        if !pasting { generation += 1 }
        operation?.cancel()
        operation = nil
        stopMeter()
        audio.cancel()
        if let activeAudio { audio.remove(activeAudio) }
        activeAudio = nil
        discardFailedAudio()
        guard !pasting else { return }
        paste.endSession()
        paste.discardIntendedTarget()
        isPracticeSession = false
        phase = .idle
    }

    /// Sends the kept audio again.
    func retry() {
        guard canRetry, let url = failedAudio else { return }
        failedAudio = nil
        generation += 1
        let current = generation
        if !isPracticeSession { paste.noteIntendedTarget() }
        phase = .transcribing
        operation = Task {
            await paste.waitForLease()
            guard current == generation else { return }
            if !isPracticeSession { paste.beginSession() }
            transcribe(url)
        }
    }

    func copyTranscript(_ text: String) {
        guard !paste.isLeasePending else { return }
        paste.copy(text)
    }

    func copyLastTranscript() {
        guard let lastTranscript else { return }
        paste.copy(lastTranscript)
        if !phase.isBusy { phase = .finished(.copied(.automaticPasteOff)) }
    }

    /// Pastes the last transcript into the current frontmost app.
    func pasteLastTranscript() {
        guard let text = lastTranscript, canStart else { return }
        isPracticeSession = false
        generation += 1
        let current = generation
        paste.noteIntendedTarget()
        phase = .pasting
        operation = Task {
            await paste.waitForLease()
            paste.beginSession()
            let outcome = await paste.deliver(text: text, automaticPaste: true)
            if current == generation { phase = .finished(outcome) }
        }
    }

    /// Test path: transcribes a supplied audio file and delivers it like a recording. No microphone use.
    /// The supplied file is not owned, so it is never deleted.
    func transcribeFile(_ url: URL, forPractice: Bool = false) {
        guard canStart else { return }
        isPracticeSession = forPractice
        if forPractice { practiceTranscript = nil }
        discardFailedAudio()
        generation += 1
        let current = generation
        if !forPractice { paste.noteIntendedTarget() }
        phase = .transcribing
        operation = Task {
            await paste.waitForLease()
            guard current == generation else { return }
            if !isPracticeSession { paste.beginSession() }
            transcribe(url)
        }
    }

    /// Hides a finished or failed status. Failed audio stays available for Retry.
    func dismissStatus() {
        guard !phase.isBusy else { return }
        phase = .idle
    }

    var isPasteLeasePending: Bool { paste.isLeasePending }

    func waitForPasteLease() async { await paste.waitForLease() }

    func waitForDeliveryAndHistory() async {
        if phase == .pasting { await operation?.value }
        await paste.waitForLease()
        await history.waitForPendingChanges()
    }

    func openMicrophoneSettings() { SystemSettingsLink.microphone.open() }
    func openAccessibilitySettings() { SystemSettingsLink.accessibility.open() }

    func openTranscriptionSettings() {
        preferredSettingsPage = .transcription
        DistributedNotificationCenter.default().post(name: LaunchOptions.showSettingsNotification, object: nil)
    }

    /// Opens the System Settings pane or sign-in path that matches the current failure.
    func recoverFromOverlay() {
        switch phase {
        case .failed(let failure):
            switch failure.recovery {
            case .microphoneSettings:
                openMicrophoneSettings()
            case .signInThenRetry:
                signIn()
            case .retry:
                retry()
            case .transcriptionSettings:
                openTranscriptionSettings()
            case .none:
                break
            }
        case .finished(.copied(.accessibilityMissing)), .finished(.copied(.injectionFailed)):
            openAccessibilitySettings()
        default:
            break
        }
    }

    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    // MARK: Permissions

    /// Asks for microphone access the first time. Opens System Settings after a denial.
    func requestMicrophone() {
        switch AudioCapture.microphoneStatus {
        case .notDetermined:
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                microphone = PermissionStatus(AudioCapture.microphoneStatus)
            }
        case .authorized:
            microphone = .granted
        default:
            openMicrophoneSettings()
        }
    }

    /// Shows the macOS Accessibility prompt. The user grants access in System Settings.
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        accessibilityTrusted = AccessibilityPermission.check()
    }

    // MARK: Sign-in

    func signIn() {
        guard signInTask == nil else { return }
        cliAvailable = CodexAuthentication.cliAvailable
        guard cliAvailable else {
            authError = "Install Codex CLI, then select Sign in with ChatGPT."
            return
        }
        authError = nil
        connection = .signingIn
        signInTask = Task {
            do {
                try await CodexAuthentication.signIn { url in
                    await MainActor.run { _ = NSWorkspace.shared.open(url) }
                }
            } catch {
                if !Task.isCancelled {
                    authError = "Sign-in did not finish. Select Sign in with ChatGPT to try again."
                }
            }
            guard !Task.isCancelled else { return }
            signInTask = nil
            connection = ConnectionStatus.current()
            if connection.isUsable { authError = nil }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        connection = ConnectionStatus.current()
    }

    /// Renews the shared sign-in through Codex CLI.
    func reconnect() {
        guard signInTask == nil else { return }
        guard cliAvailable else { signIn(); return }
        authError = nil
        connection = .renewing
        signInTask = Task {
            do {
                _ = try await CodexAuthentication.refresh()
            } catch {
                if !Task.isCancelled {
                    authError = "Renewal failed. Select Sign in with ChatGPT to sign in again."
                }
            }
            guard !Task.isCancelled else { return }
            signInTask = nil
            connection = ConnectionStatus.current()
        }
    }

    func openInstallCodex() { NSWorkspace.shared.open(Self.installCodexURL) }

    // MARK: Shortcut

    /// Waits for the registered shortcut without starting the microphone.
    func beginShortcutTest() {
        guard canChangeSettings else { return }
        if isCapturingShortcut { endShortcutCapture() }
        guard shortcut?.current != nil, hotkeyError == nil else {
            shortcutTestStatus = .unavailable(hotkeyError ?? "Choose a working shortcut first.")
            return
        }
        shortcutTestStatus = .listening
    }

    func endShortcutTest() { shortcutTestStatus = .idle }

    func receiveGlobalShortcut() {
        switch shortcutTestStatus {
        case .listening, .received:
            shortcutTestStatus = .received
        case .idle, .unavailable:
            toggleDictation()
        }
    }

    /// Stops a recording started by holding a key-combination shortcut.
    /// A tap never reaches here, so the second press still toggles.
    func receiveGlobalShortcutRelease() {
        switch shortcutTestStatus {
        case .listening, .received:
            return
        case .idle, .unavailable:
            break
        }
        if phase == .recording {
            stopDictation()
        } else if phase == .preparing {
            stopModifierHoldWhenRecording = true
            playReleaseCue()
        }
    }

    /// Suspends the global shortcut so the recorder receives the keys.
    func beginShortcutCapture() {
        endShortcutTest()
        guard canChangeSettings else {
            hotkeyError = "Finish the current dictation, then change the shortcut."
            return
        }
        isCapturingShortcut = true
        shortcut?.unregister()
    }

    /// Restores the saved shortcut if the recorder did not save a new one.
    func endShortcutCapture() {
        isCapturingShortcut = false
        guard shortcut?.current != preferences.hotkey else { return }
        activate()
    }

    /// Registers a new shortcut and saves it only on success. The previous shortcut stays on failure.
    @discardableResult
    func setHotkey(_ spec: HotkeySpec) -> Bool {
        guard canChangeSettings else {
            hotkeyError = "Finish the current dictation, then change the shortcut."
            return false
        }
        endShortcutTest()
        if spec.isModifierHold, !InputMonitoringPermission.isGranted {
            if !InputMonitoringPermission.request() {
                hotkeyBlockedBySystem = false
                hotkeyNeedsInputMonitoring = true
                pendingModifierHold = spec
                hotkeyError = GlobalShortcut.RegistrationError.inputMonitoring.errorDescription
                return false
            }
        }
        do {
            hotkeyBlockedBySystem = false
            hotkeyNeedsInputMonitoring = false
            try shortcut?.replace(with: spec)
            pendingModifierHold = nil
            preferences.hotkey = spec
            hotkeyError = nil
            return true
        } catch {
            noteShortcutRegistrationFailure(error, spec: spec)
            if shortcut?.current == nil, !isCapturingShortcut { try? shortcut?.replace(with: preferences.hotkey) }
            return false
        }
    }

    func resetHotkey() { setHotkey(.default) }

    /// Tries Command–Space. The recorder cannot capture it while macOS owns it, so this preset exists.
    func useCommandSpace() { setHotkey(.commandSpace) }

    /// Records while the left Option key is held. Releasing it pastes the transcript.
    func useLeftOption() { setHotkey(.leftOption) }

    func openKeyboardShortcutsSettings() { SystemSettingsLink.keyboardShortcuts.open() }

    func openInputMonitoringSettings() { SystemSettingsLink.inputMonitoring.open() }

    /// Shows a recorder error, for example a reserved shortcut, without changing registration.
    func reportShortcutProblem(_ problem: HotkeySpec.Problem) {
        hotkeyError = problem.message
        hotkeyBlockedBySystem = false
        hotkeyNeedsInputMonitoring = false
    }

    // MARK: Behavior

    func setAutomaticPaste(_ value: Bool) {
        guard canChangeSettings else { return }
        preferences.automaticPaste = value
    }

    func setSoundCues(_ value: Bool) {
        guard canChangeSettings else { return }
        preferences.soundCues = value
    }

    func setHapticCues(_ value: Bool) {
        guard canChangeSettings else { return }
        preferences.hapticCues = value
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLoginError = enabled
                ? "Launch at login could not be turned on. Open Login Items and allow \(AppBrand.displayName)."
                : "Launch at login could not be turned off. Remove \(AppBrand.displayName) in Login Items."
        }
        launchAtLogin = LaunchAtLoginStatus.current()
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

    // MARK: Transcription settings

    func setTranscriptionProvider(_ provider: TranscriptionProvider) {
        guard canChangeSettings else { return }
        preferences.transcriptionProvider = provider
        connectionTest = nil
    }

    func applyGroqPreset() {
        guard canChangeSettings else { return }
        preferences.transcriptionProvider = .openAICompatible
        preferences.openAIBaseURL = "https://api.groq.com/openai/v1"
        preferences.openAIModel = "whisper-large-v3"
        if preferences.transcriptionLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preferences.transcriptionLanguage = "zh"
        }
        connectionTest = nil
    }

    func clearOpenAIKey() {
        guard canChangeSettings else { return }
        connectionTest = nil
        Task {
            await writeSecret(nil, for: KeychainSecretStore.apiKeyAccount)
            refreshSecretFlags()
        }
    }

    func testOpenAIConnection(apiKeyDraft: String) {
        guard canChangeSettings, !isTestingConnection else { return }
        let draft = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isTestingConnection = true
        connectionTest = nil
        let endpoint = preferences.openAIEndpoint
        Task {
            if !draft.isEmpty { await writeSecret(draft, for: KeychainSecretStore.apiKeyAccount) }
            refreshSecretFlags()
            let read = await readSecret(KeychainSecretStore.apiKeyAccount)
            let result: ConnectionTestResult
            if read == .unavailable {
                result = ConnectionTestResult(ok: false, message: DictationError.keychainUnavailable.localizedDescription)
            } else {
                result = await OpenAICompatibleClient().testConnection(endpoint: endpoint, apiKey: read.value)
            }
            guard !Task.isCancelled else { return }
            connectionTest = result
            isTestingConnection = false
        }
    }

    // MARK: Private

    private func refreshSecretFlags() {
        // Presence only. Reading the item here would put a Keychain sheet up while
        // the menu-bar menu is tracking, which eats password keystrokes.
        openAIKeyPresent = secrets.containsSecret(for: KeychainSecretStore.apiKeyAccount)
    }

    /// A read can wait on a SecurityAgent sheet. It runs off the main thread, one at a time, with the
    /// hold listener paused so the sheet gets every keystroke and the overlay stays responsive.
    private func readSecret(_ account: String) async -> SecretRead {
        let secrets = self.secrets
        shortcut?.setModifierHoldPaused(true)
        defer { shortcut?.setModifierHoldPaused(false) }
        return await withCheckedContinuation { continuation in
            keychainQueue.async { continuation.resume(returning: secrets.readSecret(for: account)) }
        }
    }

    private func writeSecret(_ value: String?, for account: String) async {
        let secrets = self.secrets
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            keychainQueue.async {
                try? secrets.setSecret(value, for: account)
                continuation.resume()
            }
        }
    }

    /// Codex never needs the OpenAI-compatible key, so it never touches the keychain.
    private func transcriptionAPIKey() async throws -> String? {
        guard preferences.usesOpenAICompatible else { return nil }
        switch await readSecret(KeychainSecretStore.apiKeyAccount) {
        case .value(let key): return key
        case .missing: return nil
        case .unavailable: throw DictationError.keychainUnavailable
        }
    }

    private func chatCleanupAPIKey(fallback: String?) async -> String? {
        if let key = await readSecret(KeychainSecretStore.chatAPIKeyAccount).value { return key }
        if let fallback { return fallback }
        guard !preferences.usesOpenAICompatible else { return nil }
        return await readSecret(KeychainSecretStore.apiKeyAccount).value
    }

    private func performTranscription(_ url: URL) async throws -> String {
        let apiKey = try await transcriptionAPIKey()
        let prompt = preferences.transcriptionPrompt
        let raw: String
        if let transcribeAudio {
            raw = try await transcribeAudio(url)
        } else {
            raw = try await TranscriptionService.transcribe(
                file: url,
                provider: preferences.transcriptionProvider,
                language: preferences.openAIEndpoint.languageHint,
                prompt: prompt,
                openAI: preferences.openAIEndpoint,
                apiKey: apiKey
            )
        }
        let chat: (model: String, baseURL: String, apiKey: String?)?
        if preferences.chatCleanup {
            let base = preferences.chatCleanupBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            chat = (
                preferences.chatCleanupModel,
                base.isEmpty ? preferences.openAIBaseURL : base,
                await chatCleanupAPIKey(fallback: apiKey)
            )
        } else {
            chat = nil
        }
        return await TranscriptPostProcessor.apply(
            raw,
            deterministicCleanup: preferences.deterministicCleanup,
            extraFilterWords: preferences.extraFilterWords,
            replacements: preferences.replacementList,
            chineseScript: preferences.effectiveChineseScript,
            prompt: prompt,
            chat: chat,
            session: HTTPClient.shared
        )
    }

    private func captureEnded(url: URL) {
        stopMeter()
        playReleaseCue()
        generation += 1
        transcribe(url)
    }

    private func captureFailed(_ error: AudioCaptureError, url: URL?) {
        stopMeter()
        generation += 1
        operation = nil
        failedAudio = url
        fail(DictationFailure(captureError: error, audioKept: url != nil))
    }

    /// Transcribes and delivers one file. Uses the current generation to reject stale results.
    private func transcribe(_ url: URL) {
        let current = generation
        activeAudio = url
        phase = .transcribing
        operation = Task {
            let text: String
            do {
                text = try await performTranscription(url)
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw DictationError.emptyTranscript
                }
            } catch {
                guard current == generation, !Task.isCancelled else { return }
                activeAudio = nil
                let failure = DictationFailure(transcriptionError: error)
                if failure.keepsAudio { failedAudio = url } else { audio.remove(url) }
                fail(failure)
                return
            }
            guard current == generation, !Task.isCancelled else { return }
            activeAudio = nil
            audio.remove(url)
            lastTranscript = text
            if isPracticeSession {
                practiceTranscript = text
                operation = nil
                paste.endSession()
                phase = .finished(.previewed)
                return
            }
            let completedAt = Date()
            phase = .pasting
            let outcome = await paste.deliver(text: text, automaticPaste: preferences.automaticPaste)
            await history.append(HistoryEntry(text: text, createdAt: completedAt, delivery: HistoryDelivery(outcome)))
            operation = nil
            if current == generation { phase = .finished(outcome) }
        }
    }

    private func fail(_ failure: DictationFailure) {
        modifierHoldOwnsSession = false
        stopModifierHoldWhenRecording = false
        didPlayReleaseCue = false
        operation = nil
        if !failure.keepsAudio { paste.endSession() }
        phase = .failed(failure)
        cue(.failure)
    }

    private func discardFailedAudio() {
        if let failedAudio { audio.remove(failedAudio) }
        failedAudio = nil
    }

    private func cue(_ sound: SoundCue) {
        if preferences.soundCues { sound.play() }
        if preferences.hapticCues { sound.haptic() }
    }

    private func playStartCue() {
        didPlayReleaseCue = false
        cue(.start)
    }

    private func playReleaseCue() {
        guard !didPlayReleaseCue else { return }
        didPlayReleaseCue = true
        cue(.stop)
    }

    private func startMeter() {
        meterTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, target: self, selector: #selector(meterTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        elapsed = 0
        level = 0
    }

    @objc private func meterTick() {
        guard audio.isRecording else { stopMeter(); return }
        elapsed = audio.elapsed
        level = audio.currentLevel()
    }
}
