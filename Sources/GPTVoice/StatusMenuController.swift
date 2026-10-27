import AppKit
import Combine

/// The always-visible menu bar item. Rebuilds its menu from model state each time it opens.
/// Opening the menu does not activate the app, so the paste target stays frontmost.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let windows: WindowCoordinator
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var phaseObserver: AnyCancellable?
    private var accentObserver: AnyCancellable?
    private var workingTimer: Timer?
    private var workingFrame = 0
    private lazy var workingImages: [NSImage] = (0..<MenuBarGlyph.workingFrameCount).map {
        MenuBarGlyph.image(.working(frame: $0), accessibilityDescription: "\(AppBrand.displayName), working")
    }

    init(model: AppModel, windows: WindowCoordinator) {
        self.model = model
        self.windows = windows
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.isVisible = true
        updateIcon(for: model.phase)
        phaseObserver = model.$phase
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in self?.updateIcon(for: phase) }
        accentObserver = model.preferences.$accent
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateIcon(for: self.model.phase)
            }
    }

    /// Idle and finished: the plain mark. Recording: the taller mark in the listening tint. Working: three
    /// frames at 0.12 s, still under Reduce Motion. Failed: dimmed bars with an orange dot.
    private func updateIcon(for phase: DictationPhase) {
        let description: String
        switch phase {
        case .preparing, .recording:
            description = "\(AppBrand.displayName), listening"
            statusItem.button?.image = MenuBarGlyph.image(.listening, accessibilityDescription: description)
        case .transcribing, .pasting:
            description = "\(AppBrand.displayName), working"
            startWorkingAnimation()
        case .failed:
            description = "\(AppBrand.displayName), needs attention"
            statusItem.button?.image = MenuBarGlyph.image(.attention, accessibilityDescription: description)
        case .idle, .finished:
            description = AppBrand.displayName
            statusItem.button?.image = MenuBarGlyph.image(.idle, accessibilityDescription: description)
        }
        if phase != .transcribing && phase != .pasting {
            stopWorkingAnimation()
        }
        statusItem.button?.toolTip = description
        switch phase {
        case .recording:
            statusItem.button?.contentTintColor = model.preferences.accent.listeningTint
        case .failed:
            statusItem.button?.contentTintColor = .systemOrange
        default:
            statusItem.button?.contentTintColor = nil
        }
    }

    private func startWorkingAnimation() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            stopWorkingAnimation()
            statusItem.button?.image = workingImages[MenuBarGlyph.restingWorkingFrame]
            return
        }
        statusItem.button?.image = workingImages[workingFrame]
        guard workingTimer == nil else { return }
        let timer = Timer(timeInterval: MenuBarGlyph.workingFrameInterval, target: self,
                          selector: #selector(advanceWorkingFrame(_:)), userInfo: nil, repeats: true)
        workingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopWorkingAnimation() {
        workingTimer?.invalidate()
        workingTimer = nil
        workingFrame = 0
    }

    @objc private func advanceWorkingFrame(_ timer: Timer) {
        guard timer === workingTimer else { return }
        workingFrame = (workingFrame + 1) % MenuBarGlyph.workingFrameCount
        statusItem.button?.image = workingImages[workingFrame]
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Status only. Must not unlock Keychain — a sheet during menu tracking
        // steals the keyboard from SecurityAgent.
        model.refreshStatus()
        menu.removeAllItems()

        let status = NSMenuItem(title: model.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if let error = model.hotkeyError {
            let problem = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            problem.isEnabled = false
            menu.addItem(problem)
            if model.hotkeyNeedsInputMonitoring {
                menu.addItem(item("Input Monitoring Settings…", #selector(openInputMonitoring), enabled: true))
            }
        }
        if case .failed(let failure) = model.phase {
            switch failure.recovery {
            case .microphoneSettings:
                menu.addItem(item("Microphone Settings…", #selector(openMicrophone), enabled: true))
            case .signInThenRetry:
                menu.addItem(item("Sign In to ChatGPT…", #selector(signIn), enabled: true))
            case .transcriptionSettings:
                menu.addItem(item("Transcription Settings…", #selector(openTranscription), enabled: true))
            case .retry, .none:
                break
            }
        } else if case .finished(.copied(let reason)) = model.phase,
                  reason == .accessibilityMissing || reason == .injectionFailed {
            menu.addItem(item("Accessibility Settings…", #selector(openAccessibility), enabled: true))
        }
        menu.addItem(.separator())

        let recording = model.phase == .recording
        let toggle = item(recording ? "Stop Dictation" : "Start Dictation", #selector(toggleDictation),
                          enabled: recording || model.canStart)
        if let key = model.hotkey.menuKeyEquivalent {
            toggle.keyEquivalent = key
            toggle.keyEquivalentModifierMask = model.hotkey.cocoaModifiers
        } else {
            toggle.title += "  (\(model.hotkey.displayLabel))"
        }
        menu.addItem(toggle)
        if model.phase.canCancel {
            menu.addItem(item("Cancel", #selector(cancel), enabled: true))
        }
        if model.canRetry {
            menu.addItem(item("Retry", #selector(retry), enabled: true))
        }
        menu.addItem(.separator())
        let hasTranscript = model.lastTranscript != nil
        menu.addItem(item("Paste Last Transcript", #selector(pasteLast), enabled: hasTranscript && model.canStart))
        menu.addItem(item("Copy Last Transcript", #selector(copyLast), enabled: hasTranscript))
        menu.addItem(.separator())
        let settings = item("Settings…", #selector(showSettings), enabled: true)
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(item("Run Setup Again…", #selector(showOnboarding), enabled: true))
        menu.addItem(.separator())
        let quit = item("Quit \(AppBrand.displayName)", #selector(quit), enabled: true)
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func toggleDictation() { model.toggleDictation() }
    @objc private func cancel() { model.cancel() }
    @objc private func retry() { model.retry() }
    @objc private func pasteLast() { model.pasteLastTranscript() }
    @objc private func copyLast() { model.copyLastTranscript() }
    @objc private func showSettings() { windows.showSettings() }
    @objc private func openInputMonitoring() { model.openInputMonitoringSettings() }
    @objc private func openMicrophone() { model.openMicrophoneSettings() }
    @objc private func openTranscription() { model.openTranscriptionSettings() }
    @objc private func openAccessibility() { model.openAccessibilitySettings() }
    @objc private func signIn() { model.signIn() }
    @objc private func showOnboarding() { windows.showOnboarding() }
    @objc private func quit() { NSApp.terminate(nil) }
}
