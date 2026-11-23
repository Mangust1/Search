import Foundation

/// Tabs shown side by side, sharing one place in the row. The first tab is
/// the split's place among the others; the rest follow it, next to it.
///
/// Two to four pages, side by side (`most`). The shape is a list with an
/// axis, so one above the other needs no other file format later: the file
/// keeps these as they are (see Session.Split), and a file written with two
/// reads as it always did.
struct TabSplit: Identifiable, Equatable {
    enum Axis: String, Codable {
        /// Side by side, the first on the left.
        case horizontal
        /// One above the other, the first on top.
        case vertical
    }

    /// The most pages one split holds, as Arc's: past four side by side,
    /// each is too narrow to read in most windows.
    static let most = 4

    let id: UUID
    /// In the order they are shown.
    var tabs: [Tab.ID]
    var axis: Axis
    /// Each page's share of the stage, in the same order, adding up to 1.
    var sizes: [Double]
    /// The page last focused, to come back to.
    var focused: Tab.ID?
    /// Tiles (fork): how many pages each column holds, left to right, one
    /// above the other within a column; `tabs` runs column by column, top
    /// to bottom. All ones is the row of pages there always was. A column's
    /// width is its pages' shares added up, and a page's height in it is
    /// its share of that sum, so `sizes` stays one number per page.
    var stacks: [Int]

    init(id: UUID = UUID(), tabs: [Tab.ID], axis: Axis = .horizontal,
         sizes: [Double]? = nil, focused: Tab.ID? = nil, stacks: [Int]? = nil) {
        self.id = id
        self.tabs = tabs
        self.axis = axis
        self.stacks = TabSplit.valid(stacks, for: tabs.count)
        self.sizes = TabSplit.even(stacks: self.stacks)
        self.focused = focused.flatMap { tabs.contains($0) ? $0 : nil }
        if let sizes, sizes.count == tabs.count { self.sizes = TabSplit.clamp(sizes) }
    }

    init(left: Tab.ID, right: Tab.ID, fraction: Double = 0.5) {
        self.init(tabs: [left, right], sizes: [fraction, 1 - fraction])
    }

    /// The first page: the split's place in the row.
    var left: Tab.ID { tabs[0] }
    /// The last page.
    var right: Tab.ID { tabs[tabs.count - 1] }

    /// The first page's share.
    var fraction: Double {
        get { sizes.first ?? 0.5 }
        set { sizes = TabSplit.clamp([newValue, 1 - newValue]) }
    }

    /// No room for another page.
    var isFull: Bool { tabs.count >= TabSplit.most }

    func contains(_ tab: Tab.ID) -> Bool { tabs.contains(tab) }

    /// The page beside this one: the next to its right, or, for the last,
    /// the one to its left. Of two, the other one. Where the keys go when
    /// this one leaves.
    func partner(of tab: Tab.ID) -> Tab.ID? {
        guard let index = tabs.firstIndex(of: tab), tabs.count > 1 else { return nil }
        return index + 1 < tabs.count ? tabs[index + 1] : tabs[index - 1]
    }

    /// Whether `tab` stands before `other` in it (to the left, side by side).
    func isBefore(_ tab: Tab.ID, _ other: Tab.ID?) -> Bool {
        guard let other, let a = tabs.firstIndex(of: tab), let b = tabs.firstIndex(of: other) else { return false }
        return a < b
    }

    /// Every page but this one, in order.
    func others(than tab: Tab.ID) -> [Tab.ID] { tabs.filter { $0 != tab } }

    mutating func replace(_ old: Tab.ID, with new: Tab.ID) {
        tabs = tabs.map { $0 == old ? new : $0 }
        if focused == old { focused = new }
    }

    /// A page added beside `neighbour` (after it, or before it), or at the
    /// end. The pages are made even, as each one coming in is given an
    /// equal share. Nothing when full, or already in it.
    @discardableResult
    mutating func insert(_ tab: Tab.ID, beside neighbour: Tab.ID? = nil, before: Bool = false) -> Bool {
        guard !isFull, !contains(tab) else { return false }
        // A column of its own, beside the neighbour's whole column.
        let column = neighbour.flatMap { tabs.firstIndex(of: $0) }.map { self.column(of: $0) }
        let at = column.map { before ? start(of: $0) : start(of: $0) + stacks[$0] } ?? tabs.count
        tabs.insert(tab, at: at)
        stacks.insert(1, at: column.map { before ? $0 : $0 + 1 } ?? stacks.count)
        sizes = TabSplit.even(stacks: stacks)
        return true
    }

    /// A page out of it: the others keep their order, and its share goes
    /// to them in proportion. Whether two or more are left — one alone is
    /// no split, and the caller lets it go.
    @discardableResult
    mutating func remove(_ tab: Tab.ID) -> Bool {
        guard let index = tabs.firstIndex(of: tab) else { return tabs.count >= 2 }
        let column = self.column(of: index)
        stacks[column] -= 1
        if stacks[column] == 0 { stacks.remove(at: column) }
        tabs.remove(at: index)
        if sizes.count > index { sizes.remove(at: index) }
        if sizes.count != tabs.count { sizes = TabSplit.even(tabs.count) }
        let total = sizes.reduce(0, +)
        if !tabs.isEmpty, total.isFinite, total > 0 { sizes = TabSplit.clamp(sizes.map { $0 / total }) }
        if focused == tab { focused = nil }
        return tabs.count >= 2
    }

    // MARK: - tiles (fork)

    /// Some column holds more than one page.
    var isTiled: Bool { stacks.contains { $0 > 1 } }

    /// The place in `tabs` of a column's first page.
    func start(of column: Int) -> Int { stacks[..<column].reduce(0, +) }

    /// The column the page at `index` is in.
    func column(of index: Int) -> Int {
        var end = 0
        for (column, count) in stacks.enumerated() {
            end += count
            if index < end { return column }
        }
        return max(0, stacks.count - 1)
    }

    enum Way { case left, right, up, down }

    private var columns: [[Tab.ID]] {
        stacks.indices.map { Array(tabs[start(of: $0)..<start(of: $0) + stacks[$0]]) }
    }

    /// The page next to this one that way, as they are on screen: above
    /// or under it in its column, or in the column to its left or right at
    /// the same height (the last of a shorter column). Nil at an edge.
    func beside(_ tab: Tab.ID, _ way: Way) -> Tab.ID? {
        guard let index = tabs.firstIndex(of: tab) else { return nil }
        let columns = self.columns
        let column = self.column(of: index), row = index - start(of: column)
        switch way {
        case .up: return row > 0 ? columns[column][row - 1] : nil
        case .down: return row + 1 < columns[column].count ? columns[column][row + 1] : nil
        case .left, .right:
            let side = way == .left ? column - 1 : column + 1
            guard columns.indices.contains(side) else { return nil }
            return columns[side][min(row, columns[side].count - 1)]
        }
    }

    /// The split with this page moved one step, or nil when there is
    /// nowhere to go. Up and down, it changes places with the page above or
    /// under it. Left and right, a page sharing a column steps out into a
    /// column of its own on that side; one alone in its column joins the
    /// column on that side, under its pages. So the arrows walk a page
    /// across every shape. Every page is given an even share again, as
    /// when one comes in; up and down keep the shares where they are.
    func moved(_ tab: Tab.ID, _ way: Way) -> TabSplit? {
        guard let index = tabs.firstIndex(of: tab) else { return nil }
        var columns = self.columns
        let column = self.column(of: index), row = index - start(of: column)
        var next = self
        switch way {
        case .up, .down:
            let other = way == .up ? row - 1 : row + 1
            guard columns[column].indices.contains(other) else { return nil }
            next.tabs.swapAt(index, start(of: column) + other)
            return next
        case .left, .right:
            let side = way == .left ? column - 1 : column + 1
            if columns[column].count > 1 {
                columns[column].remove(at: row)
                columns.insert([tab], at: way == .left ? column : column + 1)
            } else {
                guard columns.indices.contains(side) else { return nil }
                columns[side].append(tab)
                columns.remove(at: column)
            }
        }
        next.tabs = columns.flatMap { $0 }
        next.stacks = columns.map(\.count)
        next.sizes = TabSplit.even(stacks: next.stacks)
        return next
    }

    /// The columns as given when they add up to `count` pages, else a row.
    static func valid(_ stacks: [Int]?, for count: Int) -> [Int] {
        if let stacks, stacks.allSatisfy({ $0 >= 1 }), stacks.reduce(0, +) == count { return stacks }
        return Array(repeating: 1, count: count)
    }

    /// Columns of equal width, the pages in each of equal height.
    static func even(stacks: [Int]) -> [Double] {
        stacks.flatMap { count in
            Array(repeating: 1 / Double(max(1, stacks.count)) / Double(count), count: count)
        }
    }

    /// The narrowest share a page has, of `count`: a fifth of the stage
    /// for two, as it always was; a tenth for three or four.
    static func least(_ count: Int) -> Double { count <= 2 ? 0.2 : 0.1 }

    /// No page narrower than its least share; shares that add up to 1.
    static func clamp(_ sizes: [Double]) -> [Double] {
        if sizes.count == 2 {
            let first = min(0.8, max(0.2, sizes[0].isFinite ? sizes[0] : 0.5))
            return [first, 1 - first]
        }
        let finite = sizes.map { $0.isFinite && $0 > 0 ? $0 : 1 }
        let total = finite.reduce(0, +)
        guard total > 0 else { return even(sizes.count) }
        var shares = finite.map { $0 / total }
        guard shares.count > 2 else { return shares }
        // Raise any page under its least share, taking the difference from
        // the pages above it in proportion to what they have over theirs.
        let least = least(shares.count)
        let short = shares.reduce(0) { $0 + max(0, least - $1) }
        guard short > 0 else { return shares }
        let spare = shares.reduce(0) { $0 + max(0, $1 - least) }
        shares = shares.map { share in
            share < least ? least : share - (share - least) / spare * short
        }
        return shares
    }

    static func even(_ count: Int) -> [Double] {
        Array(repeating: 1 / Double(max(1, count)), count: count)
    }
}
