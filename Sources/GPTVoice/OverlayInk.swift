import SwiftUI

/// Neutral ink for the glass bar: soft charcoal on light glass, soft white on dark glass, never pure black or white.
/// Error marks use one soft coral in every colorway, so a problem never borrows the accent.
enum OverlayInk {
    static let primary = AppPalette.dynamic(light: 0x2E2E35, dark: 0xECECF1)
    static let secondary = AppPalette.dynamic(light: 0x707078, dark: 0xA7A7B1)
    static let controlGlyph = AppPalette.dynamic(light: 0x6A6A73, dark: 0xC4C4CC)
    static let controlFill = AppPalette.dynamic(light: 0x000000, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let warningMark = AppPalette.dynamic(light: 0xE46F52, dark: 0xFFA68E)
    static let warningFill = AppPalette.dynamic(light: 0xFF8A6B, lightAlpha: 0.16, dark: 0xFF9A7E, darkAlpha: 0.2)
}
