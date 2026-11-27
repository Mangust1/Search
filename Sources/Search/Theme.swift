import AppKit
import SwiftUI
import Combine

/// Themes (fork): the chrome's colours from `theme.json` in the data folder
/// (see THEME.md). `default` is the palette everywhere; `spaces`, by name,
/// lays a space's own keys over it while that space is the front window's.
/// A key left out keeps Search's own grey, so no file is stock Search.
/// Read at launch and again whenever the file changes.
///
/// One palette for the app, not one per window: Palette's colours are the
/// app's, so two windows on different spaces both wear the front one's.
@MainActor
enum Theme {
    typealias Shade = (light: NSColor, dark: NSColor)

    /// What is painted now. Read from colour providers, which AppKit may
    /// call from wherever it draws; written on the main thread only.
    nonisolated(unsafe) private static var now: [String: Shade] = [:]
    nonisolated(unsafe) private static var flags: [String: Bool] = [:]
    private(set) static var base: [String: Any] = [:]
    private(set) static var spaces: [String: [String: Any]] = [:]
    private static var space: String?
    private static var read: Date?
    private static var watch: DispatchSourceFileSystemObject?
    private static var inner: DispatchSourceFileSystemObject?
    private static var following: [ObjectIdentifier: AnyCancellable] = [:]

    static var url: URL { Store.file("theme.json") }

    /// The colours handed out since the palette last changed, by key.
    nonisolated(unsafe) private static var made: [String: (ns: NSColor, colour: Color)] = [:]
    private static let lock = NSLock()

    /// The chrome's colour of this name: the file's, or else Search's own
    /// grey (`light` in a light window, `dark` in a dark one). The same
    /// object until the palette changes, then a new one.
    nonisolated static func ns(_ key: String, _ light: CGFloat, _ dark: CGFloat) -> NSColor {
        paint(key, NSColor(white: light, alpha: 1), NSColor(white: dark, alpha: 1)).ns
    }

    nonisolated static func colour(_ key: String, _ light: CGFloat, _ dark: CGFloat) -> Color {
        paint(key, NSColor(white: light, alpha: 1), NSColor(white: dark, alpha: 1)).colour
    }

    nonisolated static func paint(_ key: String, _ light: NSColor, _ dark: NSColor) -> (ns: NSColor, colour: Color) {
        lock.lock(); defer { lock.unlock() }
        if let kept = made[key] { return kept }
        let shade = now[key] ?? (light, dark)
        let ns = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? shade.dark : shade.light
        }
        let both = (ns, Color(nsColor: ns))
        made[key] = both
        return both
    }

    /// The file's colour of this name, or nil where it has none.
    nonisolated static func own(_ key: String) -> Color? {
        now[key] == nil ? nil : paint(key, .clear, .clear).colour
    }

    /// The one colour that isn't a grey: the line round the page with the
    /// keys, the stripe on the live tab. Zen's orange unless the file says.
    nonisolated static var accent: (ns: NSColor, colour: Color) {
        let orange = NSColor(srgbRed: 0xff / 255, green: 0xa0 / 255, blue: 0x28 / 255, alpha: 1)
        return paint("accent", orange, orange)
    }

    /// The line round the pages without the keys.
    nonisolated static var accentDim: NSColor {
        let grey = NSColor(srgbRed: 0x66 / 255, green: 0x5c / 255, blue: 0x54 / 255, alpha: 1)
        return paint("accentDim", grey, grey).ns
    }

    nonisolated static func flag(_ key: String) -> Bool { flags[key] ?? false }

    /// A theme is loaded: the space's own colour wash stays off unless the
    /// file asks for it ("wash": true), as a tint over a painted palette is
    /// no longer that palette.
    nonisolated static var hidesWash: Bool { !now.isEmpty && !flag("wash") }

    // MARK: - loading

    /// At launch: read the file, and watch its folder (an editor replaces
    /// the file rather than writing into it, so the file itself can't be).
    private static func start() {
        load()
        let handle = open(Store.folder.path, O_EVTONLY)
        guard handle >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: handle, eventMask: .write, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { changed() } }
        source.setCancelHandler { close(handle) }
        source.resume()
        watch = source
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { sync() }
        }
    }

    /// A window's browser, to follow its space.
    static func follow(_ browser: Browser) {
        if watch == nil { start() }
        following[ObjectIdentifier(browser)] = browser.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in MainActor.assumeIsolated { sync() } }
    }

    /// The file was written from Settings (ThemeColours.swift): read it and
    /// paint, without waiting for the watcher.
    static func edited() {
        if watch == nil { start() } else { load() }
        repaint()
    }

    private static func changed() {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard stamp != read else { return }
        load()
        repaint()
    }

    /// The file itself, for a write into it; made again on every read, as
    /// a replaced file is another file.
    private static func watchFile() {
        inner?.cancel()
        inner = nil
        let handle = open(url.path, O_EVTONLY)
        guard handle >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: handle, eventMask: [.write, .extend], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { changed() } }
        source.setCancelHandler { close(handle) }
        source.resume()
        inner = source
    }

    private static func load() {
        watchFile()
        read = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let json = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        base = json?["default"] as? [String: Any] ?? [:]
        spaces = (json?["spaces"] as? [String: Any] ?? [:]).compactMapValues { $0 as? [String: Any] }
        mix()
    }

    /// The front window's space changed, perhaps.
    private static func sync() {
        let front = Browsers.front
        let name = front.flatMap { $0.prefs.usesSpaces ? $0.washSpace.name : nil }
        guard name != space else { return }
        space = name
        guard !spaces.isEmpty else { return }
        mix()
        repaint()
    }

    private static func mix() {
        let raw = base.merging(space.flatMap { spaces[$0] } ?? [:]) { _, own in own }
        lock.lock()
        now = raw.compactMapValues(shade)
        flags = raw.compactMapValues { $0 as? Bool }
        made = [:]
        lock.unlock()
    }

    /// "#RRGGBB" for both, or {"light": …, "dark": …}; one side alone is both.
    static func shade(_ value: Any) -> Shade? {
        if let text = value as? String { return hex(text).map { ($0, $0) } }
        guard let pair = value as? [String: Any] else { return nil }
        let light = (pair["light"] as? String).flatMap(hex), dark = (pair["dark"] as? String).flatMap(hex)
        guard let one = light ?? dark else { return nil }
        return (light ?? one, dark ?? one)
    }

    /// "#RRGGBB" or "#RRGGBBAA".
    static func hex(_ text: String) -> NSColor? {
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let rgba = digits.count == 6 ? value << 8 | 0xFF : value
        func part(_ shift: UInt64) -> CGFloat { CGFloat(rgba >> shift & 0xFF) / 255 }
        return NSColor(srgbRed: part(24), green: part(16), blue: part(8), alpha: part(0))
    }

    // MARK: - painting

    /// Every window drawn again with the palette as it now is. The colours
    /// are the same objects answering differently, so nothing knows to ask
    /// them again: AppKit's views are told their appearance changed, which
    /// is when they take their layers' colours afresh.
    private static func repaint() {
        // SwiftUI resolves a colour again when the view holding it is
        // evaluated again, and nearly all the chrome watches one of these.
        for browser in Browsers.all {
            browser.objectWillChange.send()
            browser.prefs.objectWillChange.send()
        }
        for window in NSApp.windows {
            Browsers.browser(for: window)?.paintGround(window)
            guard let root = window.contentView?.superview ?? window.contentView else { continue }
            var views = [root]
            while let view = views.popLast() {
                view.viewDidChangeEffectiveAppearance()
                view.needsDisplay = true
                view.needsLayout = true
                views.append(contentsOf: view.subviews)
            }
        }
    }
}

/// Themes (fork): a space's own picture in the sidebar, in place of its
/// symbol: `spaceicons/<space name>.png` (or .svg, .pdf) in the data folder.
struct SpaceIcon: View {
    let name: String?
    let symbol: String
    let size: CGFloat

    // ponytail: read once per name, so a new picture shows after a restart.
    private static var kept: [String: NSImage?] = [:]

    private static func picture(_ name: String) -> NSImage? {
        if let known = kept[name] { return known }
        let folder = Store.folder.appendingPathComponent("spaceicons")
        let image = ["png", "svg", "pdf"].lazy
            .compactMap { NSImage(contentsOf: folder.appendingPathComponent("\(name).\($0)")) }.first
        kept[name] = .some(image)
        return image
    }

    var body: some View {
        if let image = name.flatMap(SpaceIcon.picture) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size + 5, height: size + 5)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: symbol).font(.system(size: size, weight: .medium))
        }
    }
}
