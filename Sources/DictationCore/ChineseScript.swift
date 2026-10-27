import Foundation

/// Which Chinese script to deliver. Whisper can answer zh in Traditional even for Mainland speech.
public enum ChineseScript: String, CaseIterable, Identifiable, Sendable {
    case simplified
    case traditional
    case unchanged

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .simplified: return "简体"
        case .traditional: return "繁體"
        case .unchanged: return "As heard"
        }
    }

    public static func isChinese(_ language: String?) -> Bool {
        guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return language == "zh" || language.hasPrefix("zh-") || language.hasPrefix("zh_")
    }

    /// ICU transforms. Returns the input when the transform is unavailable.
    public func convert(_ text: String) -> String {
        let identifiers: [String]
        switch self {
        case .unchanged: return text
        case .simplified: identifiers = ["Hant-Hans", "Traditional-Simplified"]
        case .traditional: identifiers = ["Hans-Hant", "Simplified-Traditional"]
        }
        for identifier in identifiers {
            if let converted = text.applyingTransform(StringTransform(rawValue: identifier), reverse: false) {
                return converted
            }
        }
        return text
    }
}
