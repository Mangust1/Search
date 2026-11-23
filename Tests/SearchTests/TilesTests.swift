import XCTest
@testable import Search

/// Tiles (fork): columns of pages in a split, as TabSplit keeps them. The
/// model only: no window, no browser.
final class TilesTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    func testARowIsAllOnes() {
        let row = TabSplit(tabs: [a, b, c])
        XCTAssertEqual(row.stacks, [1, 1, 1])
        XCTAssertFalse(row.isTiled)
        XCTAssertEqual(row.sizes, TabSplit.even(3))
    }

    func testStacksThatDontAddUpAreARow() {
        XCTAssertEqual(TabSplit(tabs: [a, b, c], stacks: [2, 2]).stacks, [1, 1, 1])
        XCTAssertEqual(TabSplit(tabs: [a, b, c], stacks: [3, 0]).stacks, [1, 1, 1])
    }

    private func walk(_ split: TabSplit, _ steps: [(UUID, TabSplit.Way)]) -> TabSplit {
        steps.reduce(split) { $0.moved($1.0, $1.1) ?? $0 }
    }

    func testAPageAloneJoinsTheColumnBesideIt() {
        let row = TabSplit(tabs: [a, b, c])
        XCTAssertNil(row.moved(a, .left))
        XCTAssertNil(row.moved(a, .up))
        let split = walk(row, [(c, .left)])
        XCTAssertEqual(split.tabs, [a, b, c])
        XCTAssertEqual(split.stacks, [1, 2])
        // Two columns of equal width, the second one's pages of equal height.
        XCTAssertEqual(split.sizes, [0.5, 0.25, 0.25])
        XCTAssertEqual(walk(row, [(a, .right)]).tabs, [b, a, c])
        XCTAssertEqual(walk(row, [(a, .right)]).stacks, [2, 1])
    }

    func testLeftWalksAPageAcrossTheSplit() {
        // c under b, then out to b's left, then under a.
        var split = walk(TabSplit(tabs: [a, b, c]), [(c, .left), (c, .left)])
        XCTAssertEqual(split.tabs, [a, c, b])
        XCTAssertEqual(split.stacks, [1, 1, 1])
        split = walk(split, [(c, .left)])
        XCTAssertEqual(split.tabs, [a, c, b])
        XCTAssertEqual(split.stacks, [2, 1])
    }

    func testUpAndDownChangePlacesInAColumn() {
        let split = walk(TabSplit(tabs: [a, b, c], stacks: [1, 2]), [(c, .up)])
        XCTAssertEqual(split.tabs, [a, c, b])
        XCTAssertEqual(split.stacks, [1, 2])
        XCTAssertNil(split.moved(c, .up))
        XCTAssertEqual(split.moved(c, .down)?.tabs, [a, b, c])
    }

    func testAGridAndBackToARow() {
        var split = walk(TabSplit(tabs: [a, b, c, d]), [(b, .left), (d, .left)])
        XCTAssertEqual(split.tabs, [a, b, c, d])
        XCTAssertEqual(split.stacks, [2, 2])
        XCTAssertEqual(split.sizes, [0.25, 0.25, 0.25, 0.25])
        split = walk(split, [(b, .right), (d, .right)])
        XCTAssertEqual(split.tabs, [a, b, c, d])
        XCTAssertFalse(split.isTiled)
    }

    func testTwoPagesOneAboveTheOther() {
        let split = walk(TabSplit(tabs: [a, b]), [(b, .left)])
        XCTAssertEqual(split.stacks, [2])
        XCTAssertEqual(split.sizes, [0.5, 0.5])
    }

    func testFocusGoesToThePageOnThatSide() {
        // a | b over c
        let split = TabSplit(tabs: [a, b, c], stacks: [1, 2])
        XCTAssertEqual(split.beside(a, .right), b)
        XCTAssertEqual(split.beside(b, .down), c)
        XCTAssertEqual(split.beside(c, .left), a)
        XCTAssertNil(split.beside(c, .down))
        XCTAssertNil(split.beside(a, .up))
        // In a row, left and right are the neighbours, as before.
        let row = TabSplit(tabs: [a, b, c])
        XCTAssertEqual(row.beside(b, .left), a)
        XCTAssertEqual(row.beside(b, .right), c)
        XCTAssertNil(row.beside(c, .right))
    }

    func testRemoveAndInsertKeepTheColumns() {
        var split = TabSplit(tabs: [a, b, c], stacks: [1, 2])
        // A page coming in beside a stacked one gets a column after that whole column.
        XCTAssertTrue(split.insert(d, beside: b))
        XCTAssertEqual(split.tabs, [a, b, c, d])
        XCTAssertEqual(split.stacks, [1, 2, 1])
        XCTAssertTrue(split.remove(b))
        XCTAssertEqual(split.stacks, [1, 1, 1])
        XCTAssertEqual(split.sizes.reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertTrue(split.remove(a))
        XCTAssertEqual(split.stacks, [1, 1])
    }
}
