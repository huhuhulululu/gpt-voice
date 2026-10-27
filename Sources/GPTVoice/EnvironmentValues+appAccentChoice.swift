import SwiftUI

extension EnvironmentValues {
    /// The selected colorway. The recording bar reads its waveform, live dot and fill ramps from here.
    var appAccentChoice: AccentChoice {
        get { self[AppAccentChoiceKey.self] }
        set { self[AppAccentChoiceKey.self] = newValue }
    }
}
