import AppKit
import SwiftUI

/// The system frosted material behind the recording bar, masked to the bar's rounded shape.
/// The live panel blurs the desktop behind the window; the Settings preview blurs the window it sits in.
/// Forced active: Goice never becomes the active app, and an inactive material drops its blur.
struct OverlayGlassMaterial: NSViewRepresentable {
    let cornerRadius: CGFloat
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.state = .active
        view.blendingMode = blending
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        if view.blendingMode != blending {
            view.blendingMode = blending
        }
        if view.maskImage?.capInsets.top != cornerRadius {
            view.maskImage = Self.mask(cornerRadius: cornerRadius)
        }
    }

    /// A stretchable rounded rectangle, so the mask follows every frame of a resize without redrawing.
    static func mask(cornerRadius radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
