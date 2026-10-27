import SwiftUI

/// Environment key for the selected colorway, for views that need its ramps rather than one color.
struct AppAccentChoiceKey: EnvironmentKey {
    static let defaultValue: AccentChoice = .factoryDefault
}
