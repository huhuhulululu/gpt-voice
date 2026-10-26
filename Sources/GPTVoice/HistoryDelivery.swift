import Foundation

enum HistoryDelivery: Equatable, Sendable {
    /// The app sent paste keystrokes. The destination can still reject them.
    case pasted(appName: String?)
    /// Automatic paste did not run. `reason` is nil only for rows written before reasons were stored.
    case copied(reason: PasteOutcome.ManualReason?)
    case clipboardPreserved

    init(_ outcome: PasteOutcome) {
        switch outcome {
        case .pasted(let name): self = .pasted(appName: name)
        case .preservedNewerClipboard: self = .clipboardPreserved
        case .copied(let reason): self = .copied(reason: reason)
        case .previewed: self = .copied(reason: nil)
        }
    }
}

extension HistoryDelivery: Codable {
    private enum CodingKeys: String, CodingKey {
        case pasted, copied, clipboardPreserved
    }

    private enum PastedKeys: String, CodingKey {
        case appName
    }

    private enum CopiedKeys: String, CodingKey {
        case reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.pasted) {
            let nested = try container.nestedContainer(keyedBy: PastedKeys.self, forKey: .pasted)
            self = .pasted(appName: try nested.decodeIfPresent(String.self, forKey: .appName))
        } else if container.contains(.copied) {
            let nested = try container.nestedContainer(keyedBy: CopiedKeys.self, forKey: .copied)
            self = .copied(reason: try nested.decodeIfPresent(PasteOutcome.ManualReason.self, forKey: .reason))
        } else if container.contains(.clipboardPreserved) {
            _ = try container.nestedContainer(keyedBy: CopiedKeys.self, forKey: .clipboardPreserved)
            self = .clipboardPreserved
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unknown history delivery"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pasted(let appName):
            var nested = container.nestedContainer(keyedBy: PastedKeys.self, forKey: .pasted)
            try nested.encode(appName, forKey: .appName)
        case .copied(let reason):
            var nested = container.nestedContainer(keyedBy: CopiedKeys.self, forKey: .copied)
            try nested.encodeIfPresent(reason, forKey: .reason)
        case .clipboardPreserved:
            _ = container.nestedContainer(keyedBy: CopiedKeys.self, forKey: .clipboardPreserved)
        }
    }
}
