import Combine

@MainActor
final class OverlayPresentation: ObservableObject {
    @Published var state: DictationOverlayState = .hidden
    @Published var exiting = false
    /// False for the first frame of an entrance so the pill can scale from 0.96.
    @Published var settled = true
}
