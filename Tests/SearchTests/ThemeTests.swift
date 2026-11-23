import XCTest
@testable import Search

/// Themes (fork): what theme.json's values read as.
@MainActor
final class ThemeTests: XCTestCase {
    func testHex() {
        let c = Theme.hex("#d79921")
        XCTAssertEqual(c?.redComponent ?? 0, 0xd7 / 255, accuracy: 0.001)
        XCTAssertEqual(c?.blueComponent ?? 0, 0x21 / 255, accuracy: 0.001)
        XCTAssertEqual(Theme.hex("#00000080")?.alphaComponent ?? 0, 0x80 / 255, accuracy: 0.001)
        XCTAssertNil(Theme.hex("#fff"))
        XCTAssertNil(Theme.hex("orange"))
    }

    func testOneColourIsBothAndOneSideIsBoth() {
        let one = Theme.shade("#102030")
        XCTAssertEqual(one?.light, one?.dark)
        let two = Theme.shade(["light": "#ffffff", "dark": "#000000"])
        XCTAssertEqual(two?.light.redComponent, 1)
        XCTAssertEqual(two?.dark.redComponent, 0)
        let half = Theme.shade(["dark": "#000000"])
        XCTAssertEqual(half?.light, half?.dark)
        XCTAssertNil(Theme.shade(true))
        XCTAssertNil(Theme.shade(["light": "nope"]))
    }
}
