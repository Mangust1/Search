import XCTest
@testable import Search

/// Userscripts (fork): the header, and which addresses a pattern takes.
@MainActor
final class UserScriptsTests: XCTestCase {
    private func takes(_ source: String?, _ url: String) -> Bool {
        guard let source, let regex = try? NSRegularExpression(pattern: source) else { return false }
        return regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
    }

    func testMatchPatterns() {
        let any = UserScripts.match("*://*.example.com/*")
        XCTAssertTrue(takes(any, "https://example.com/"))
        XCTAssertTrue(takes(any, "http://www.example.com/a/b?c"))
        XCTAssertFalse(takes(any, "https://notexample.com/"))
        XCTAssertFalse(takes(any, "https://example.com.evil.net/"))
        let path = UserScripts.match("https://example.com/foo/*")
        XCTAssertTrue(takes(path, "https://example.com/foo/bar"))
        XCTAssertFalse(takes(path, "https://example.com/bar"))
        XCTAssertFalse(takes(path, "http://example.com/foo/bar"))
        XCTAssertTrue(takes(UserScripts.match("<all_urls>"), "https://a.b/c"))
        XCTAssertNil(UserScripts.match("example.com"))
    }

    func testIncludeIsAGlobOrARegex() {
        XCTAssertTrue(takes(UserScripts.glob("https://*.example.com/*"), "https://a.example.com/x"))
        XCTAssertFalse(takes(UserScripts.glob("https://example.com/a.b"), "https://example.com/aXb"))
        XCTAssertTrue(takes(UserScripts.glob("/^https://ex(am)?ple\\.com//"), "https://example.com/"))
    }

    func testHeader() {
        let script = UserScripts.parse("""
        // ==UserScript==
        // @name        Tag
        // @match       https://example.com/*
        // @exclude     https://example.com/admin*
        // @space       Media
        // @space       Work
        // @run-at      document-start
        // @noframes
        // @grant       GM_addStyle
        // ==/UserScript==
        // @match https://not.this/*
        document.title = "x";
        """)
        XCTAssertEqual(script.name, "Tag")
        XCTAssertEqual(script.matches.count, 1)
        XCTAssertEqual(script.excludes.count, 1)
        XCTAssertEqual(script.spaces, ["Media", "Work"])
        XCTAssertTrue(script.atStart)
        XCTAssertTrue(script.mainFrameOnly)
        XCTAssertTrue(UserScripts.wrap(script, origin: "https://example.com").contains("document.title"))
    }

    /// Matched in the app: a script goes only to the address it is for, and
    /// its wrapper asks nothing of the page but its origin (audit 2026-11-27).
    func testAScriptIsOnlyForItsOwnAddresses() {
        let script = UserScripts.parse("""
        // ==UserScript==
        // @match https://console.example.com/*
        // @exclude https://console.example.com/public/*
        // ==/UserScript==
        secret();
        """)
        XCTAssertTrue(UserScripts.takes(script, "https://console.example.com/ec2"))
        XCTAssertFalse(UserScripts.takes(script, "https://console.example.com/public/x"))
        XCTAssertFalse(UserScripts.takes(script, "https://evil.example/?https://console.example.com/ec2"))
        XCTAssertEqual(UserScripts.origin(of: URL(string: "https://Console.Example.com:8443/a?b#c")!), "https://console.example.com:8443")
        XCTAssertNil(UserScripts.origin(of: URL(string: "file:///tmp/a.html")!))
        let wrapped = UserScripts.wrap(script, origin: "https://console.example.com")
        XCTAssertTrue(wrapped.contains(#"if (location.origin !== ["https:\/\/console.example.com"][0]) return;"#))
        XCTAssertFalse(wrapped.contains("RegExp"))
        XCTAssertFalse(wrapped.contains(".some("))
    }

    func testTextRoutesTakeTheLongestTextInTheAddress() {
        let rules = TextRoutes.rules(["Work": ["bitbucket.org/acme", "#space=work", "*.acme.example"], "Personal": ["bitbucket.org"], "Bad": [""]])
        XCTAssertEqual(TextRoutes.match("https://bitbucket.org/acme/repo", in: rules), "Work")
        XCTAssertEqual(TextRoutes.match("https://bitbucket.org/me/repo", in: rules), "Personal")
        XCTAssertEqual(TextRoutes.match("https://example.com/login#space=WORK", in: rules), "Work")
        XCTAssertEqual(TextRoutes.match("https://app.acme.example/", in: rules), "Work")
        XCTAssertNil(TextRoutes.match("https://example.com/", in: rules))
    }
}
