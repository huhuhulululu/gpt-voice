import AppKit
import SwiftUI

/// Accessibility row for automatic paste. Optional, so it never uses a warning tone.
/// Recovery stays visible even when macOS still reports a grant, because a Developer ID
/// reinstall can leave a stale switch that no longer matches this build.
struct AccessibilityCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: AppPreferences
    var offersManualPaste = false
    var onAdjustPaste: (() -> Void)?

    @State private var recoveryExpanded = false
    @FocusState private var recoveryFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, offersManualPaste: Bool = false, onAdjustPaste: (() -> Void)? = nil) {
        self.model = model
        self.preferences = model.preferences
        self.offersManualPaste = offersManualPaste
        self.onAdjustPaste = onAdjustPaste
    }

    var body: some View {
        if model.accessibilityTrusted {
            VStack(alignment: .leading, spacing: 0) {
                StatusRow(tone: .good, symbol: "checkmark.circle.fill", title: "Accessibility",
                          detail: trustedDetail, value: "Allowed") {
                    if !preferences.automaticPaste {
                        Button("Turn on paste") { model.setAutomaticPaste(true) }
                            .buttonStyle(AppButtonStyle(kind: .secondary, small: true))
                    }
                    if let onAdjustPaste {
                        Button("Paste settings") { onAdjustPaste() }
                            .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
                    }
                }
                if preferences.automaticPaste {
                    recovery(title: "Paste not working after an update?")
                        .padding(.leading, 26)
                        .padding(.top, -4)
                        .padding(.bottom, 12)
                }
            }
        } else if !preferences.automaticPaste {
            StatusRow(tone: .neutral, symbol: "doc.on.clipboard", title: "Manual paste",
                      detail: "Text is copied. You press ⌘V.") {
                Button("Use automatic paste") { model.setAutomaticPaste(true) }
                    .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
                if let onAdjustPaste {
                    Button("Paste settings") { onAdjustPaste() }
                        .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                StatusRow(tone: .neutral, symbol: "circle.dashed", title: "Accessibility",
                          detail: "Needed to paste into the focused field. Optional if you prefer ⌘V.") {
                    Button("Allow") { model.requestAccessibility() }
                        .buttonStyle(AppButtonStyle(kind: .secondary, small: true))
                        .accessibilityLabel("Allow Accessibility")
                    Button("Open Settings") { model.openAccessibilitySettings() }
                        .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
                        .accessibilityLabel("Open Accessibility settings")
                    QuietIconButton(symbol: "arrow.clockwise", label: "Check Accessibility again") {
                        model.refreshStatus()
                    }
                }
                recovery(title: "Already turned on?")
                    .padding(.leading, 26)
                    .padding(.top, -4)
                    .padding(.bottom, offersManualPaste ? 4 : 12)
                if offersManualPaste {
                    Button("Skip and use manual paste") { model.setAutomaticPaste(false) }
                        .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
                        .padding(.leading, 16)
                        .padding(.bottom, 10)
                }
            }
        }
    }

    private var trustedDetail: String {
        preferences.automaticPaste
            ? "Pastes into the focused field, then restores your clipboard."
            : "Automatic paste is off. Text is copied for ⌘V."
    }

    /// Same look and semantics as `InfoDisclosure`, with one action inside.
    private func recovery(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                recoveryExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(recoveryExpanded ? 90 : 0))
                    Text(title).font(AppType.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($recoveryFocused)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                    .padding(-3)
                    .opacity(recoveryFocused ? 1 : 0)
            )
            .accessibilityValue(recoveryExpanded ? "Expanded" : "Collapsed")

            if recoveryExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AccessibilityGuidance.staleGrant)
                        .font(AppType.detail)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 520, alignment: .leading)
                    Button("Show this app") { model.revealAppInFinder() }
                        .buttonStyle(AppButtonStyle(kind: .quiet, small: true))
                        .accessibilityLabel("Show GPT Voice in Finder")
                        .padding(.leading, -10)
                }
                .padding(.leading, 14)
                .transition(.opacity)
            }
        }
        .animation(AppMotion.control(reduceMotion), value: recoveryExpanded)
    }
}
