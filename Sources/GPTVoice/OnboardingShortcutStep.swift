import SwiftUI

struct OnboardingShortcutStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(title: "Choose a shortcut",
                             summary: model.preferences.hotkey.usageInstruction)
            ShortcutPanel(model: model)
        }
    }
}
