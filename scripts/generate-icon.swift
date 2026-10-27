// Renders the Goice app icon, direction A: a dark rounded tile with five coral-to-violet voice bars.
// At 32 px and below the mark drops to three wider bars so it stays legible in lists and the Dock's
// smallest sizes. The tile is a superellipse on the macOS icon grid (824 of 1024 px) over a soft shadow;
// the rest of the canvas stays transparent. Original paths only, no assets.
// Usage:
//   swift scripts/generate-icon.swift --iconset DIR      every size iconutil expects, each drawn at its size
//   swift scripts/generate-icon.swift OUTPUT.png [SIZE]  one PNG, 1024 px by default
import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                           CGFloat(hex & 0xFF) / 255, alpha])!
}

func white(_ alpha: CGFloat) -> CGColor { color(0xFFFFFF, alpha) }
func black(_ alpha: CGFloat) -> CGColor { color(0x000000, alpha) }

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
}

func lerp(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> UInt32 {
    func channel(_ shift: UInt32) -> UInt32 {
        let from = CGFloat((a >> shift) & 0xFF), to = CGFloat((b >> shift) & 0xFF)
        return UInt32((from + (to - from) * t).rounded()) << shift
    }
    return channel(16) | channel(8) | channel(0)
}

/// Superellipse (n = 5), close to the macOS icon shape.
func squircle(center: CGPoint, half: CGFloat, steps: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let exponent: CGFloat = 2 / 5
    for step in 0...steps {
        let t = 2 * CGFloat.pi * CGFloat(step) / CGFloat(steps)
        let c = cos(t), s = sin(t)
        let point = CGPoint(x: center.x + half * (c < 0 ? -1 : 1) * pow(abs(c), exponent),
                            y: center.y + half * (s < 0 ? -1 : 1) * pow(abs(s), exponent))
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

let barStops: [UInt32] = [0xFF8A5B, 0xFF4F7B, 0x9B6BFF]

func barColor(at t: CGFloat) -> UInt32 {
    let clamped = max(0, min(1, t))
    return clamped < 0.5 ? lerp(barStops[0], barStops[1], clamped * 2) : lerp(barStops[1], barStops[2], clamped * 2 - 1)
}

/// Draws the icon into a `size` px square context. `small` picks the three-bar mark.
func draw(in context: CGContext, size: CGFloat, small: Bool) {
    let body = size * 824 / 1024
    let half = body / 2
    // Slightly above center, like Apple's template, leaving room for the shadow below.
    let center = CGPoint(x: size / 2, y: size / 2 + size * 0.006)
    let tile = squircle(center: center, half: half, steps: size < 64 ? 240 : 720)
    let top = center.y + half, bottom = center.y - half

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: max(1.2, size * 0.036), color: black(0.32))
    context.addPath(tile)
    context.setFillColor(color(0x121216))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    context.drawLinearGradient(gradient([color(0x3A3A43), color(0x121216)], [0, 1]),
                               start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
    context.drawLinearGradient(gradient([white(0.16), white(0)], [0, 1]),
                               start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: center.y - half * 0.2), options: [])
    context.restoreGState()

    if size >= 64 {
        context.saveGState()
        context.addPath(squircle(center: center, half: half - max(0.5, size * 0.003)))
        context.setLineWidth(max(1, size * 0.004))
        context.replacePathWithStrokedPath()
        context.clip()
        context.drawLinearGradient(gradient([white(0.22), white(0.04), black(0.12)], [0, 0.5, 1]),
                                   start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
        context.restoreGState()
    }

    let profile: [CGFloat] = small ? [0.62, 1.0, 0.5] : [0.42, 0.72, 1.0, 0.58, 0.30]
    let barWidth = body * (small ? 0.13 : 0.085)
    let gap = body * (small ? 0.09 : 0.062)
    let maxHeight = body * (small ? 0.58 : 0.56)
    let total = CGFloat(profile.count) * barWidth + CGFloat(profile.count - 1) * gap
    let left = center.x - total / 2
    let bars: [CGRect] = profile.enumerated().map { index, share in
        let height = maxHeight * share
        return CGRect(x: left + CGFloat(index) * (barWidth + gap), y: center.y - height / 2, width: barWidth, height: height)
    }
    let barsPath = CGMutablePath()
    for bar in bars {
        barsPath.addRoundedRect(in: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2)
    }

    // Each bar glows in its own color from the ramp.
    for bar in bars {
        let tint = barColor(at: (bar.midX - left) / total)
        context.saveGState()
        context.setShadow(offset: .zero, blur: max(1, size * 0.07), color: color(tint, 0.55))
        context.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        context.setFillColor(color(tint))
        context.fillPath()
        context.restoreGState()
    }

    context.saveGState()
    context.addPath(barsPath)
    context.clip()
    context.drawLinearGradient(gradient(barStops.map { color($0) }, [0, 0.5, 1]),
                               start: CGPoint(x: left, y: 0), end: CGPoint(x: left + total, y: 0), options: [])
    let barTop = center.y + maxHeight / 2
    context.drawLinearGradient(gradient([white(0.22), white(0)], [0, 1]),
                               start: CGPoint(x: 0, y: barTop), end: CGPoint(x: 0, y: barTop - maxHeight * 0.45), options: [])
    context.restoreGState()
}

func makeContext(_ pixels: Int) -> CGContext {
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("Could not create a \(pixels) px bitmap.")
    }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    return context
}

/// Small sizes are drawn four times larger and scaled down, so the glow and curves stay smooth.
func render(pixels: Int) -> CGImage {
    let small = pixels <= 32
    let factor = pixels <= 64 ? 4 : 1
    let large = makeContext(pixels * factor)
    draw(in: large, size: CGFloat(pixels * factor), small: small)
    guard let drawn = large.makeImage() else { fail("Could not render \(pixels) px.") }
    if factor == 1 { return drawn }
    let target = makeContext(pixels)
    target.draw(drawn, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    guard let image = target.makeImage() else { fail("Could not scale \(pixels) px.") }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("Could not write \(url.path).")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Could not encode \(url.path).") }
}

let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "--iconset" {
    let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        fail("Could not create \(directory.path): \(error.localizedDescription)")
    }
    for points in [16, 32, 128, 256, 512] {
        writePNG(render(pixels: points), to: directory.appendingPathComponent("icon_\(points)x\(points).png"))
        writePNG(render(pixels: points * 2), to: directory.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
    }
} else if arguments.count >= 2, !arguments[1].hasPrefix("-") {
    let pixels = arguments.count >= 3 ? Int(arguments[2]) ?? 1024 : 1024
    writePNG(render(pixels: pixels), to: URL(fileURLWithPath: arguments[1]))
} else {
    FileHandle.standardError.write(Data("Usage: generate-icon.swift --iconset DIR | OUTPUT.png [SIZE]\n".utf8))
    exit(2)
}
