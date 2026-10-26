import SwiftUI

/// Keeps one surface while the window resizes and the content cross-fades.
struct DictationPanelView: View {
    @ObservedObject var presentation: OverlayPresentation
    let actions: DictationOverlayActions
    let timing: OverlayTiming
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { _ in
            ZStack {
                content
                    .id(presentation.state.transitionID)
                    .transition(OverlayContentTransition.transition(reduceMotion: reduceMotion))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(AppMotion.overlay(reduceMotion, duration: timing.resize, reduced: timing.reducedFade),
                       value: presentation.state.transitionID)
            .scaleEffect(surfaceScale)
            .animation(AppMotion.overlay(reduceMotion, duration: scaleDuration, reduced: timing.reducedFade),
                       value: surfaceScale)
            .modifier(OverlaySurface(shape: RoundedRectangle(cornerRadius: presentation.state.isHelp ? 14 : 20,
                                                              style: .continuous)))
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation status")
    }

    private var surfaceScale: CGFloat {
        if reduceMotion { return 1 }
        if presentation.exiting { return AppMotion.overlayExitScale }
        return presentation.settled ? 1 : AppMotion.overlayEntranceScale
    }

    private var scaleDuration: TimeInterval {
        presentation.exiting ? timing.exit : timing.entrance
    }

    @ViewBuilder private var content: some View {
        if case .notice(let notice) = presentation.state {
            OverlayHelpContent(notice: notice, dismiss: actions.dismiss,
                               action: notice.actionTitle == nil ? nil : actions.recover)
        } else {
            HStack(spacing: 10) {
                OverlayCapsuleContent(state: presentation.state, actions: actions)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 40)
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}
