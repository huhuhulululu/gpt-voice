import AppKit
import XCTest
@testable import GPTVoice

final class MenuBarGlyphTests: XCTestCase {
    private let styles: [MenuBarGlyph.Style] = [.idle, .listening, .working(frame: 0), .working(frame: 1),
                                                .working(frame: 2), .attention]

    func testEveryStateIsAnEighteenPointTemplateWithAName() {
        for style in styles {
            let image = MenuBarGlyph.image(style, accessibilityDescription: "Goice, working")
            XCTAssertTrue(image.isTemplate, "\(style)")
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18), "\(style)")
            XCTAssertEqual(image.accessibilityDescription, "Goice, working")
            XCTAssertNotNil(image.cgImage(forProposedRect: nil, context: nil, hints: nil), "\(style)")
        }
    }

    func testEveryStateDrawsDifferently() {
        let renders = styles.map { MenuBarGlyph.image($0, accessibilityDescription: "Goice").tiffRepresentation }
        XCTAssertEqual(Set(renders.compactMap { $0 }).count, styles.count)
    }

    func testListeningFollowsTheAccentButGraphiteKeepsRecordingRed() {
        XCTAssertEqual(AccentChoice.graphite.listeningTint, NSColor.systemRed)
        for choice in AccentChoice.allCases where choice != .graphite {
            XCTAssertNotEqual(choice.listeningTint, NSColor.systemRed, "\(choice)")
        }
    }
}
