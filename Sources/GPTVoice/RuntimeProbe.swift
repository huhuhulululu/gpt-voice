import AppKit
import Darwin

/// Lets `--diagnose` ask the running app whether anything is ticking. The app's idle cost is one
/// distributed-notification observer; it only wakes when a diagnose run asks.
enum RuntimeProbe {
    static let request = Notification.Name("com.vishesh.codex-dictation.diagnose.request")
    static let reply = Notification.Name("com.vishesh.codex-dictation.diagnose.reply")

    /// Plist-safe state. Never includes transcript text, words, or credentials.
    @MainActor
    static func snapshot(model: AppModel, statusMenu: StatusMenuController?,
                         panel: DictationPanelController?) -> [String: Any] {
        [
            "pid": Int(getpid()),
            "phase": phaseName(model.phase),
            "meterTimerRunning": model.isMeterRunning,
            "menuBarAnimationRunning": statusMenu?.isWorkingAnimationRunning ?? false,
            "overlayVisible": panel?.isVisible ?? false,
            "overlayHideTimerPending": panel?.isHideTimerPending ?? false,
        ]
    }

    static func phaseName(_ phase: DictationPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .preparing: return "preparing"
        case .recording: return "recording"
        case .transcribing: return "transcribing"
        case .pasting: return "pasting"
        case .finished: return "finished"
        case .failed: return "failed"
        }
    }

    /// Posts a request and spins the run loop until the app answers or `timeout` passes.
    static func queryRunningApp(timeout: TimeInterval = 1.5) -> [String: Any]? {
        final class Answer: @unchecked Sendable { var value: [String: Any]? }
        let center = DistributedNotificationCenter.default()
        let answer = Answer()
        let observer = center.addObserver(forName: reply, object: nil, queue: nil) { note in
            answer.value = note.userInfo as? [String: Any]
        }
        defer { center.removeObserver(observer) }
        center.postNotificationName(request, object: nil, userInfo: nil, deliverImmediately: true)
        let deadline = Date().addingTimeInterval(timeout)
        while answer.value == nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return answer.value
    }
}

/// Resident memory, CPU time, and idle wakeups for one process, from `proc_pid_rusage`.
struct ProcessUsage {
    var residentBytes: UInt64
    var cpuNanoseconds: UInt64
    var idleWakeups: UInt64

    static func current(pid: pid_t) -> ProcessUsage? {
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard status == 0 else { return nil }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = info.ri_user_time + info.ri_system_time
        let nanoseconds = timebase.denom == 0 ? ticks : ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
        return ProcessUsage(residentBytes: info.ri_resident_size, cpuNanoseconds: nanoseconds,
                            idleWakeups: info.ri_pkg_idle_wkups + info.ri_interrupt_wkups)
    }

    /// CPU percent and wakeups per second over `seconds`, for an idle-cost check.
    static func sample(pid: pid_t, seconds: TimeInterval) -> [String: Any]? {
        guard let start = current(pid: pid) else { return nil }
        Thread.sleep(forTimeInterval: seconds)
        guard let end = current(pid: pid) else { return nil }
        let cpu = Double(end.cpuNanoseconds &- start.cpuNanoseconds) / (seconds * 1_000_000_000) * 100
        let wakeups = Double(end.idleWakeups &- start.idleWakeups) / seconds
        return [
            "residentMB": (Double(end.residentBytes) / 1_048_576 * 10).rounded() / 10,
            "cpuPercent": (cpu * 100).rounded() / 100,
            "wakeupsPerSecond": (wakeups * 10).rounded() / 10,
            "sampleSeconds": seconds,
        ]
    }
}
