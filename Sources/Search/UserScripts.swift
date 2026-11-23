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

    private static var kept: [String: (stamp: Date, meta: Script, script: WKUserScript)] = [:]

    /// The scripts for a page in `space` (nil with spaces off: only the
    /// scripts for every space). Each tests the address itself, in the
    /// page, so a frame and a page that changes address without loading
    /// are judged by where they are.
    static func scripts(space: String?) -> [WKUserScript] {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "js" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var live: [String: (stamp: Date, meta: Script, script: WKUserScript)] = [:]
        var out: [WKUserScript] = []
        for file in files {
            guard let stamp = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
            var entry = kept[file.path]
            if entry?.stamp != stamp {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let meta = parse(text, file: file.lastPathComponent)
                // The page's own world: what "@grant none" means, and where
                // a script changing the page's own objects has to be.
                let script = WKUserScript(source: wrap(meta), injectionTime: meta.atStart ? .atDocumentStart : .atDocumentEnd,
                                          forMainFrameOnly: meta.mainFrameOnly, in: .page)
                entry = (stamp, meta, script)
            }
            guard let entry else { continue }
            live[file.path] = entry
            if entry.meta.spaces.isEmpty || space.map(entry.meta.spaces.contains) == true { out.append(entry.script) }
        }
        kept = live
        return out
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

    /// The script inside a function that leaves at once on any other page,
    /// with the few GM_ names most scripts ask for.
    /// ponytail: values are kept in the page's localStorage, so per site and
    /// readable by the site; GM_xmlhttpRequest is the page's own fetch, so
    /// no reaching another site. Its own store and a native request when a
    /// script needs them.
    static func wrap(_ script: Script) -> String {
        func list(_ sources: [String]) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: sources)) ?? Data("[]".utf8)
            return String(decoding: data, as: UTF8.self)
        }
        let name = list([script.name])
        return """
        (function () {
          var here = location.href, is = function (s) { return new RegExp(s).test(here); };
          if (!\(list(script.matches)).some(is) || \(list(script.excludes)).some(is)) return;
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
