import AppKit

/// Download rules (fork): open a download instead of keeping it, and
/// remember which, per site and kind of file. `downloads.json` in the data
/// folder (see DOWNLOADS.md):
///
///     { "ci.example.com": { "txt": { "do": "open", "with": "Some Viewer" },
///                           "zip": "save" } }
///
/// By the host of the page the download was started on, then by the file's
/// extension ("" for none): "open" or "save", or both that and the app to
/// open with. With no app named, it is the Mac's own choice for the file.
@MainActor
enum DownloadRules {
    enum Act: String { case open, save, cancel }

    static var url: URL { Store.file("downloads.json") }

    /// Files to open when they are down, and the app for each, if named.
    private static var opening: [URL: String?] = [:]

    private static func read() -> [String: Any] {
        (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
    }

    private static func kind(_ name: String) -> String { (name as NSString).pathExtension.lowercased() }

    /// The rule for a file of this name from this site, if there is one.
    static func rule(_ name: String, from host: String, in rules: [String: Any]) -> (act: Act, with: String?)? {
        let found = (rules[host.lowercased()] as? [String: Any])?[kind(name)]
        let pair = found as? [String: Any]
        guard let act = (found as? String ?? pair?["do"] as? String).flatMap(Act.init), act != .cancel else { return nil }
        return (act, pair?["with"] as? String)
    }

    /// What to do with this download: its rule, or else the question when
    /// Settings says to ask, or else kept as ever.
    static func decide(_ name: String, from host: String, asking: Bool) -> Act {
        if let known = rule(name, from: host, in: read()) { return known.act }
        guard asking else { return .save }
        let kind = kind(name)
        let alert = NSAlert()
        alert.messageText = name
        alert.informativeText = "From \(host)"
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Always do this for \(kind.isEmpty ? "such" : ".\(kind)") files from \(host)"
        let answer = alert.runModal()
        guard answer != .alertThirdButtonReturn else { return .cancel }
        let act: Act = answer == .alertFirstButtonReturn ? .open : .save
        if alert.suppressionButton?.state == .on {
            var rules = read()
            var site = rules[host.lowercased()] as? [String: Any] ?? [:]
            site[kind] = act.rawValue
            rules[host.lowercased()] = site
            if let data = try? JSONSerialization.data(withJSONObject: rules, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url, options: .atomic)
            }
        }
        return act
    }

    /// Where a file to be opened is kept: a folder macOS empties itself.
    static func place(_ name: String, from host: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Search Opened", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
        // Yesterday's are done with: gone, without waiting for macOS.
        let old = Date().addingTimeInterval(-86400)
        for kept in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        where ((try? kept.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()) < old {
            try? FileManager.default.removeItem(at: kept)
        }
        let file = Browser.free(name, in: folder)
        opening[file.standardizedFileURL] = .some(rule(name, from: host, in: read())?.with)
        return file
    }

    /// A download is down: opened, if that was what it was for.
    static func finished(_ file: URL) {
        guard let app = opening.removeValue(forKey: file.standardizedFileURL) else { return }
        let named = app.flatMap { name in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: name)
                ?? ["/Applications", NSHomeDirectory() + "/Applications"]
                    .map { URL(fileURLWithPath: "\($0)/\(name).app") }
                    .first { FileManager.default.fileExists(atPath: $0.path) }
        }
        if let named {
            NSWorkspace.shared.open([file], withApplicationAt: named, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(file)
        }
    }
}
