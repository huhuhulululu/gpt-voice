import AppKit
import SwiftUI

/// Accent colorways. Each chip is a focusable button showing the colorway's ramp, with its English and
/// Chinese names below. The selected chip gets a ring and a bolder name, so selection never relies on color.
struct AccentSwatchPicker: View {
    @Binding var selection: AccentChoice
    @FocusState private var focused: AccentChoice?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(AccentChoice.allCases) { choice in
                Button {
                    selection = choice
                } label: {
                    swatch(choice)
                }
                .buttonStyle(PressScaleButtonStyle())
                .focused($focused, equals: choice)
                .help("\(choice.title) · \(choice.chineseTitle)")
                .accessibilityLabel("\(choice.title) accent")
                .accessibilityValue(choice == selection ? "Selected" : "")
                .accessibilityAddTraits(choice == selection ? .isSelected : [])
            }
        }
    }

    private func swatch(_ choice: AccentChoice) -> some View {
        let selected = choice == selection
        return VStack(spacing: 3) {
            ZStack {
                Circle()
                    .strokeBorder(selected ? choice.foreground : Color.clear, lineWidth: 1.5)
                    .frame(width: 32, height: 32)
                Circle()
                    .fill(LinearGradient(colors: choice.buttonRamp(dark: colorScheme == .dark),
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(AppPalette.hairline))
            }
            .frame(width: 32, height: 32)
            .modifier(KeyboardFocusRing(isFocused: focused == choice, shape: Circle()))
            Text(choice.title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .lineLimit(1)
            Text(choice.chineseTitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 66)
        .contentShape(Rectangle())
    }
}
