import AppKit
import DictationCore
import XCTest
@testable import GPTVoice

final class TranscriptionHistoryTests: XCTestCase {
    @MainActor
    func testRestoresExactTextDatesDestinationsAndDeletions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let older = HistoryEntry(text: "Use URLSession, then await the retry.\nKeep the newline.",
                                 createdAt: Date(timeIntervalSince1970: 1_000), delivery: .pasted(appName: "T3 Code"))
        let newer = HistoryEntry(text: "A copied thought.", createdAt: Date(timeIntervalSince1970: 2_000),
                                 delivery: .copied(reason: .targetChanged))
        let history = TranscriptionHistory(fileURL: url)
        await history.append(older)
        await history.append(newer)
        await history.append(newer)
        XCTAssertNil(history.errorMessage)
        XCTAssertEqual(history.entries, [newer, older])
        let restored = TranscriptionHistory(fileURL: url)
        await restored.waitForPendingChanges()
        XCTAssertEqual(restored.entries, [newer, older])
        await restored.remove(id: newer.id)
        let afterDelete = TranscriptionHistory(fileURL: url)
        await afterDelete.waitForPendingChanges()
        XCTAssertEqual(afterDelete.entries, [older])
        await afterDelete.clear()
        let afterClear = TranscriptionHistory(fileURL: url)
        await afterClear.waitForPendingChanges()
        XCTAssertTrue(afterClear.entries.isEmpty)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    @MainActor
    func testUnreadableHistoryIsNotOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.json")
        let original = Data("not a valid history document".utf8)
        try original.write(to: url)
        let history = TranscriptionHistory(fileURL: url)
        await history.waitForPendingChanges()
        XCTAssertNotNil(history.errorMessage)
        await history.append(HistoryEntry(text: "Keep the original file.", delivery: .copied(reason: .noTarget)))
        await history.clear()
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertNotNil(history.errorMessage)
    }

    @MainActor
    func testFailedWriteCanBeRetriedWithoutLosingTheEntry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory)
        let url = directory.appendingPathComponent("history.json")
        let history = TranscriptionHistory(fileURL: url)
        let entry = HistoryEntry(text: "Retry this save.", delivery: .clipboardPreserved)
        await history.append(entry)
        XCTAssertEqual(history.entries, [entry])
        XCTAssertNotNil(history.errorMessage)
        try FileManager.default.removeItem(at: directory)
        await history.retrySave()
        XCTAssertNil(history.errorMessage)
        let restored = TranscriptionHistory(fileURL: url)
        await restored.waitForPendingChanges()
        XCTAssertEqual(restored.entries, [entry])
    }

    func testCopiedDeliveryPersistsManualReasonAndReadsLegacyEmptyCopied() throws {
        let encoder = JSONEncoder()
        let withReason = try JSONSerialization.jsonObject(
            with: encoder.encode(HistoryDelivery.copied(reason: .targetChanged))
        ) as? [String: Any]
        XCTAssertEqual((withReason?["copied"] as? [String: Any])?["reason"] as? String, "targetChanged")
        XCTAssertEqual((withReason?["copied"] as? [String: Any])?.count, 1)

        let pasted = HistoryDelivery.pasted(appName: "Notes")
        XCTAssertEqual(try JSONDecoder().decode(HistoryDelivery.self, from: encoder.encode(pasted)), pasted)

        let legacy = Data(#"{"copied":{}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(HistoryDelivery.self, from: legacy), .copied(reason: nil))
        XCTAssertEqual(HistoryDelivery(.copied(.injectionFailed)), .copied(reason: .injectionFailed))
        XCTAssertEqual(HistoryDelivery(.pasted(appName: "Orca")), .pasted(appName: "Orca"))

        XCTAssertEqual(HistoryDelivery.pasted(appName: "Notes").historyCaption, "Pasted into Notes")
        XCTAssertEqual(HistoryDelivery.pasted(appName: nil).historyCaption, "Pasted")
        XCTAssertEqual(HistoryDelivery.copied(reason: .targetChanged).historyCaption, "Copied · app changed")
        XCTAssertEqual(HistoryDelivery.copied(reason: .injectionFailed).historyCaption, "Copied · paste failed")
        XCTAssertEqual(HistoryDelivery.copied(reason: nil).historyCaption, "Copied")
        XCTAssertEqual(HistoryDelivery.clipboardPreserved.historyCaption, "Clipboard kept")
        XCTAssertTrue(HistoryDelivery.copied(reason: .injectionFailed).historyGuidance?.contains("Developer ID") == true)

        let secret = "sk-live-not-a-real-secret"
        let deliveries: [HistoryDelivery] = [
            .pasted(appName: "Notes"),
            .copied(reason: .automaticPasteOff),
            .copied(reason: .accessibilityMissing),
            .copied(reason: .targetChanged),
            .copied(reason: .noTarget),
            .copied(reason: .injectionFailed),
            .copied(reason: nil),
            .clipboardPreserved
        ]
        for delivery in deliveries {
            XCTAssertFalse(delivery.historyCaption.contains(secret))
            XCTAssertFalse(delivery.historyCaption.contains("token"))
            XCTAssertFalse((delivery.historyGuidance ?? "").contains(secret))
        }
    }

    @MainActor
    func testActualTranscriptionsAreSavedOnceButPracticeAndNoSpeechAreNot() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = TranscriptionHistory(fileURL: directory.appendingPathComponent("history.json"))
        let suite = "history-flow-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.automaticPaste = false
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        let model = AppModel(preferences: preferences, pasteboard: clipboard, history: history) { url in
            if url.lastPathComponent == "empty.wav" { throw DictationError.emptyTranscript }
            return "Make the webhook handler idempotent."
        }
        defer { model.cleanup() }
        model.transcribeFile(URL(fileURLWithPath: "/practice.wav"), forPractice: true)
        try await waitUntil { model.phase == .finished(.previewed) }
        await history.waitForPendingChanges()
        XCTAssertTrue(history.entries.isEmpty)
        model.transcribeFile(URL(fileURLWithPath: "/actual.wav"))
        try await waitUntil { model.phase == .finished(.copied(.automaticPasteOff)) }
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.delivery, .copied(reason: .automaticPasteOff))
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("history.json"))) as? [String: Any]
        let first = (saved?["entries"] as? [[String: Any]])?.first?["delivery"] as? [String: Any]
        XCTAssertEqual((first?["copied"] as? [String: Any])?["reason"] as? String, "automaticPasteOff")
        model.copyLastTranscript()
        model.copyTranscript(history.entries[0].text)
        XCTAssertEqual(clipboard.string(forType: .string), history.entries[0].text)
        XCTAssertEqual(history.entries.count, 1)
        model.transcribeFile(URL(fileURLWithPath: "/empty.wav"))
        try await waitUntil { if case .failed = model.phase { return true }; return false }
        XCTAssertEqual(history.entries.count, 1)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let limit = Date().addingTimeInterval(3)
        while !condition(), Date() < limit { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition())
    }
}
