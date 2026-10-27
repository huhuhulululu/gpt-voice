import SwiftUI

/// The soft top highlight on accent fills in the recording bar (stop, Retry, success check).
enum OverlayGloss {
    static let gradient = LinearGradient(stops: [.init(color: .white.opacity(0.22), location: 0),
                                                 .init(color: .white.opacity(0), location: 0.55)],
                                         startPoint: .top, endPoint: .bottom)
}
