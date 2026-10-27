import AppKit
import SwiftUI

/// Accent colors. Each colorway has a three-stop ramp for the recording bar and one solid fill for app controls.
extension AccentChoice {
    /// Recording bar ramps, left to right: light mode, dark-mode waveform and live dot, dark-mode fills.
    private var ramps: (light: [UInt32], darkWave: [UInt32], darkFill: [UInt32]) {
        switch self {
        case .coralViolet:
            return ([0xFF9172, 0xF2739A, 0x9F84FF], [0xFFA48C, 0xFF8AAA, 0xB8A3FF], [0xF7907A, 0xE97A9F, 0x9F88F5])
        case .softBlue:
            return ([0x86B8FF, 0x6F93F2, 0x8A80EE], [0xA3C8FF, 0x93ABFF, 0xA9A0FF], [0x78A6F2, 0x6A86E6, 0x8276E2])
        case .sage:
            return ([0x9CCBA6, 0x74AC8E, 0x5F9A90], [0xB5DCBD, 0x9BCBAD, 0x8DC0B6], [0x8BBE97, 0x6EA486, 0x5E9389])
        case .amber:
            return ([0xFFC77E, 0xF6A762, 0xEC8C5C], [0xFFD496, 0xFFBA80, 0xF9A378], [0xF2B467, 0xE99A55, 0xDC8452])
        case .graphite:
            return ([0xA4A4AF, 0x85858F, 0x6E6E79], [0xD0D0D9, 0xB8B8C3, 0xA5A5B2], [0x8E8E99, 0x777782, 0x64646F])
        }
    }

    /// Waveform bars and the live dot.
    func waveRamp(dark: Bool) -> [Color] {
        (dark ? ramps.darkWave : ramps.light).map(AppPalette.color)
    }

    /// Wide fills behind white text, such as the Retry pill.
    func fillRamp(dark: Bool) -> [Color] {
        (dark ? ramps.darkFill : ramps.light).map(AppPalette.color)
    }

    /// Round fills behind white symbols (stop, success check, swatches). The full ramp reads as a bruise
    /// on a 28 pt circle, so the last stop sits partway to violet.
    func buttonRamp(dark: Bool) -> [Color] {
        let stops = dark ? ramps.darkFill : ramps.light
        return [stops[0], stops[1], AppPalette.mix(stops[1], stops[2], 0.45)].map(AppPalette.color)
    }

    /// Fill role for AppKit painting: primary buttons, switch tracks, selected rows.
    /// Each is dark enough for white labels; Graphite flips between near-black and near-white.
    var nsColor: NSColor {
        switch self {
        case .coralViolet: return AppPalette.nsColor(0xC93D6E)
        case .softBlue: return AppPalette.nsColor(0x3F6FD8)
        case .sage: return AppPalette.nsColor(0x3E7B5E)
        case .amber: return AppPalette.nsColor(0xB45309)
        case .graphite: return AppPalette.dynamicNS(light: 0x1C1C1E, dark: 0xECECEC)
        }
    }

    /// Fill role: primary buttons, switch tracks, selected swatch.
    var color: Color { Color(nsColor: nsColor) }

    /// Text and symbols placed on the fill.
    var onFill: Color {
        self == .graphite ? AppPalette.dynamic(light: 0xFFFFFF, dark: 0x1C1C1E) : .white
    }

    /// Foreground role: small selected icons and meter bars on app surfaces.
    var foreground: Color {
        switch self {
        case .coralViolet: return AppPalette.dynamic(light: 0xC93D6E, dark: 0xFF8AAA)
        case .softBlue: return AppPalette.dynamic(light: 0x3F6FD8, dark: 0x93ABFF)
        case .sage: return AppPalette.dynamic(light: 0x3E7B5E, dark: 0x9BCBAD)
        case .amber: return AppPalette.dynamic(light: 0xB45309, dark: 0xFFBA80)
        case .graphite: return AppPalette.dynamic(light: 0x1C1C1E, dark: 0xECECEC)
        }
    }

    /// Tint for the few remaining system controls, such as progress spinners. Graphite keeps the system tint.
    var tint: Color? { self == .graphite ? nil : color }
}
