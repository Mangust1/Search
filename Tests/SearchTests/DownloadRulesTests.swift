import XCTest
@testable import Search

@MainActor
final class DownloadRulesTests: XCTestCase {
    func testRulesBySiteAndKind() {
        let rules: [String: Any] = ["ci.example.com": ["txt": ["do": "open", "with": "Some Viewer"], "zip": "save", "": "open", "odd": "what"]]
        let text = DownloadRules.rule("plan.TXT", from: "CI.example.com", in: rules)
        XCTAssertEqual(text?.act, .open)
        XCTAssertEqual(text?.with, "Some Viewer")
        XCTAssertEqual(DownloadRules.rule("a.zip", from: "ci.example.com", in: rules)?.act, .save)
        XCTAssertEqual(DownloadRules.rule("raw", from: "ci.example.com", in: rules)?.act, .open)
        XCTAssertNil(DownloadRules.rule("raw", from: "ci.example.com", in: rules)?.with)
        XCTAssertNil(DownloadRules.rule("a.odd", from: "ci.example.com", in: rules))
        XCTAssertNil(DownloadRules.rule("a.pdf", from: "ci.example.com", in: rules))
        XCTAssertNil(DownloadRules.rule("a.txt", from: "other.example.com", in: rules))
    }
}
