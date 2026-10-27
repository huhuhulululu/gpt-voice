import Foundation

/// Accent colorways. The accent marks selection, the main action, and the live parts of the recording bar
/// (waveform, live dot, stop and Retry). It never means error. Glass, text and quiet controls never change.
/// Colors live in `AccentChoice+Palette.swift`; this file stays Foundation-only so the mapping is easy to test.
enum AccentChoice: String, CaseIterable, Identifiable {
    case coralViolet
    case softBlue
    case sage
    case amber
    case graphite

    /// Matches app icon A.
    static let factoryDefault: AccentChoice = .coralViolet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coralViolet: return "Coral-Violet"
        case .softBlue: return "Soft Blue"
        case .sage: return "Sage"
        case .amber: return "Amber"
        case .graphite: return "Graphite"
        }
    }

    var chineseTitle: String {
        switch self {
        case .coralViolet: return "珊瑚紫"
        case .softBlue: return "雾蓝"
        case .sage: return "鼠尾草绿"
        case .amber: return "暖琥珀"
        case .graphite: return "石墨灰"
        }
    }

    /// Reads a saved preference, including values from the earlier seven-accent picker.
    /// Rose and Violet become Coral-Violet, Green and Teal become Sage, Blue, Amber and Graphite carry over.
    /// Nothing saved, or a value this build does not know, gives the factory default.
    init(storedValue: String?) {
        switch storedValue {
        case "system": self = .graphite
        case "blue": self = .softBlue
        case "violet", "rose": self = .coralViolet
        case "green", "teal": self = .sage
        case let value?: self = AccentChoice(rawValue: value) ?? .factoryDefault
        case nil: self = .factoryDefault
        }
    }
}
