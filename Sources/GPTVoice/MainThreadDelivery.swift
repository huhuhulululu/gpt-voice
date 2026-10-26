import Foundation

/// Runs `@MainActor` work from AppKit event monitors without an extra hop.
///
/// NSEvent callbacks already arrive on the main thread. Calling the actor
/// function directly is a hard `#ActorIsolatedCall` on Swift 6, even when
/// `Thread.isMainThread` is true. `assumeIsolated` is the supported handoff.
enum MainThreadDelivery {
    static func run(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                work()
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    work()
                }
            }
        }
    }
}
