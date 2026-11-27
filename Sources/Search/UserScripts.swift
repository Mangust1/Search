import Foundation
import WebKit

/// Userscripts (fork): every `*.js` in the data folder's `userscripts`
/// folder is run on the pages its header names, as Violentmonkey would
/// (see USERSCRIPTS.md). The usual header: @match, @include, @exclude,
/// @run-at, @noframes; and one of the fork's own, `@space Name`, once per
/// space, for a script that runs in those spaces only.
///
/// Read when a page is about to load, each file again only when it has
/// changed: a script saved is in the next page loaded, with no watcher.
@MainActor
enum UserScripts {
    struct Script {
        var name: String
        var matches: [String] = []
        var excludes: [String] = []
        var spaces: [String] = []
        var atStart = false
        var mainFrameOnly = false
        var grants: [String] = []
        var body: String
    }

    static var folder: URL { Store.file("userscripts") }

    private static var kept: [String: (stamp: Date, meta: Script)] = [:]

    /// The scripts for the page at `url` in `space` (nil with spaces off:
    /// only the scripts for every space).
    ///
    /// Matched here, in the app, and only a script the address is for goes
    /// to the page at all (audit 2026-11-27): matched in the page, with the
    /// page's own Array and RegExp, any site could read every script's text
    /// off the wrapper's caller, and make it run on itself.
    /// ponytail: the main frame only, judged by the address the load is for.
    /// A script for a frame's address, or for an address a page reaches
    /// without loading, does not run; a checker in Search's own world that
    /// asks the app to run the body in that frame, when one is needed.
    static func scripts(space: String?, url: URL?) -> [WKUserScript] {
        guard let url, let origin = origin(of: url) else { kept = [:]; return [] }
        let address = url.absoluteString
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "js" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var live: [String: (stamp: Date, meta: Script)] = [:]
        var out: [WKUserScript] = []
        for file in files {
            guard let stamp = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
            var entry = kept[file.path]
            if entry?.stamp != stamp {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                entry = (stamp, parse(text, file: file.lastPathComponent))
            }
            guard let entry else { continue }
            live[file.path] = entry
            let meta = entry.meta
            guard meta.spaces.isEmpty || space.map(meta.spaces.contains) == true, takes(meta, address) else { continue }
            // The page's own world: what "@grant none" means, and where
            // a script changing the page's own objects has to be.
            out.append(WKUserScript(source: wrap(meta, origin: origin), injectionTime: meta.atStart ? .atDocumentStart : .atDocumentEnd,
                                    forMainFrameOnly: true, in: .page))
        }
        kept = live
        return out
    }

    /// Whether `script` is for `address`: one of its matches, none of its excludes.
    static func takes(_ script: Script, _ address: String) -> Bool {
        func hit(_ source: String) -> Bool {
            guard let test = try? NSRegularExpression(pattern: source) else { return false }
            return test.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)) != nil
        }
        return script.matches.contains(where: hit) && !script.excludes.contains(where: hit)
    }

    /// scheme://host[:port], as the page's location.origin says it; nil for
    /// an address that has none (about:, data:, file:).
    static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(percentEncoded: true)?.lowercased(), !host.isEmpty else { return nil }
        return "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
    }

    /// The header between ==UserScript== and ==/UserScript==.
    static func parse(_ text: String, file: String = "") -> Script {
        var script = Script(name: file, body: text)
        var inside = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("// ==UserScript==") { inside = true; continue }
            if line.hasPrefix("// ==/UserScript==") { break }
            guard inside, line.hasPrefix("// @") else { continue }
            let parts = line.dropFirst(4).split(maxSplits: 1, whereSeparator: \.isWhitespace)
            let key = String(parts.first ?? ""), value = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            switch key {
            case "name": script.name = value
            case "match": match(value).map { script.matches.append($0) }
            case "include": script.matches.append(glob(value))
            case "exclude": script.excludes.append(glob(value))
            case "exclude-match": match(value).map { script.excludes.append($0) }
            case "space": script.spaces.append(value)
            case "run-at": script.atStart = value == "document-start"
            case "noframes": script.mainFrameOnly = true
            case "grant": script.grants.append(value)
            default: break
            }
        }
        return script
    }

    /// A match pattern (scheme://host/path, as extensions have them) as a
    /// regular expression's source, or nil when it isn't one.
    static func match(_ pattern: String) -> String? {
        if pattern == "<all_urls>" || pattern == "*" { return "^(https?|file|ftp)://" }
        guard let scheme = pattern.range(of: "://") else { return nil }
        let rest = pattern[scheme.upperBound...]
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        let host = String(rest[..<slash]), path = slash < rest.endIndex ? String(rest[slash...]) : "/"
        let schemes = pattern[..<scheme.lowerBound] == "*" ? "https?" : NSRegularExpression.escapedPattern(for: String(pattern[..<scheme.lowerBound]))
        let hosts: String
        if host == "*" {
            hosts = "[^/]*"
        } else if host.hasPrefix("*.") {
            hosts = "([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: String(host.dropFirst(2)))
        } else {
            hosts = NSRegularExpression.escapedPattern(for: host)
        }
        return "^" + schemes + "://" + hosts + star(path) + "$"
    }

    /// An @include: a glob where * is anything, or /a regular expression/.
    static func glob(_ pattern: String) -> String {
        if pattern.count > 2, pattern.hasPrefix("/"), pattern.hasSuffix("/") { return String(pattern.dropFirst().dropLast()) }
        return "^" + star(pattern) + "$"
    }

    private static func star(_ text: String) -> String {
        text.split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: ".*")
    }

    /// The script inside a function that leaves at once on any other site,
    /// with the few GM_ names most scripts ask for. The check is for a load
    /// that was sent on to another site after the script was chosen for it:
    /// location.origin and a comparison only, nothing of the page's that a
    /// page can have changed, so nothing there can ask who called it.
    /// ponytail: values are kept in the page's localStorage, so per site and
    /// readable by the site; GM_xmlhttpRequest is the page's own fetch, so
    /// no reaching another site. Its own store and a native request when a
    /// script needs them.
    static func wrap(_ script: Script, origin: String) -> String {
        func list(_ sources: [String]) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: sources)) ?? Data("[]".utf8)
            return String(decoding: data, as: UTF8.self)
        }
        let name = list([script.name])
        return """
        (function () {
          if (location.origin !== \(list([origin]))[0]) return;
          var unsafeWindow = window, key = "userscript:" + \(name)[0] + ":";
          var GM_info = { script: { name: \(name)[0] }, scriptHandler: "Search" };
          var GM_addStyle = function (css) { var s = document.createElement("style"); s.textContent = css; (document.head || document.documentElement).appendChild(s); return s; };
          var GM_getValue = function (k, d) { try { var v = localStorage.getItem(key + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } };
          var GM_setValue = function (k, v) { try { localStorage.setItem(key + k, JSON.stringify(v)); } catch (e) {} };
          var GM_deleteValue = function (k) { try { localStorage.removeItem(key + k); } catch (e) {} };
          var GM_openInTab = function (u) { return window.open(u, "_blank"); };
          var GM_setClipboard = function (t) { return navigator.clipboard.writeText(t); };
          var GM = { info: GM_info, addStyle: GM_addStyle, openInTab: GM_openInTab, setClipboard: GM_setClipboard,
            getValue: function (k, d) { return Promise.resolve(GM_getValue(k, d)); },
            setValue: function (k, v) { return Promise.resolve(GM_setValue(k, v)); },
            deleteValue: function (k) { return Promise.resolve(GM_deleteValue(k)); } };
          try {
        \(script.body)
          } catch (e) { console.error("userscript " + \(name)[0] + ":", e); }
        })();
        """
    }
}

extension Browser {
    /// The name of the space `tab` is in, here or parked; nil with spaces off.
    func spaceName(holding tab: Tab) -> String? {
        guard prefs.usesSpaces else { return nil }
        if tabs.contains(where: { $0.id == tab.id }) { return space.name }
        let home = parked.first { $0.value.tabs.contains { $0.id == tab.id } }?.key
        return spaces.first { $0.id == home }?.name ?? space.name
    }
}
