import Foundation

/// Reads and writes `lexicon.json`. Local file only: no Keychain, no sync.
public struct LexiconStore: Sendable {
    public enum Load: Equatable, Sendable {
        case loaded(Lexicon)
        case missing
        /// The file could not be decoded. It was moved aside to `preserved` so nothing is overwritten.
        case unreadable(preserved: URL?)
    }

    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() -> Load {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return .missing }
        if let data = try? Data(contentsOf: fileURL),
           let lexicon = try? Self.decoder.decode(Lexicon.self, from: data),
           lexicon.version == Lexicon.currentVersion {
            return .loaded(lexicon)
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = fileURL.deletingLastPathComponent()
            .appendingPathComponent("lexicon-unreadable-\(stamp).json")
        let moved = (try? manager.moveItem(at: fileURL, to: aside)) != nil
        return .unreadable(preserved: moved ? aside : nil)
    }

    public func save(_ lexicon: Lexicon) throws {
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let data = try Self.encoder.encode(lexicon)
        let temporary = directory.appendingPathComponent(".lexicon-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporary.path, contents: data,
                                 attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary.path, fileURL.path) == 0 else {
            try? manager.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
