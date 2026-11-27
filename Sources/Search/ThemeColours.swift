import SwiftUI

/// Themes (fork): Settings › Appearance › Colours. theme.json's palette
/// (see THEME.md) edited in place: everywhere, or one space's own keys over
/// it. A colour chosen is written to the file and on the window at once;
/// Reset takes the key out, and the palette under it shows again.
/// ponytail: one colour per key. A {"light", "dark"} pair written by hand
/// is shown by its dark side and becomes one colour when changed here.
struct ThemeColours: View {
    /// nil: the palette everywhere. Else a space's name.
    @State private var scope: String?
    /// Counted up after each write, so the rows read the file's values again.
    @State private var written = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $scope) {
                Text("Everywhere").tag(String?.none)
                ForEach(Theme.spaceNames, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            ForEach(Theme.keys, id: \.key) { item in
                row(item.key, item.paints)
            }
            ForEach(Theme.switches, id: \.key) { item in
                Toggle(isOn: Binding(
                    get: { Theme.value(item.key, in: scope) as? Bool ?? (Theme.value(item.key, in: nil) as? Bool ?? false) },
                    set: { Theme.set($0, item.key, in: scope); written += 1 }
                )) {
                    label(item.key, item.paints)
                }
                .toggleStyle(.switch)
            }
        }
        .id(written)
    }

    private func row(_ key: String, _ paints: String) -> some View {
        let own = Theme.value(key, in: scope)
        let shown = Theme.shade(own ?? Theme.value(key, in: nil) ?? "")?.dark
        return HStack(spacing: 10) {
            ColorPicker("", selection: Binding(
                get: { shown.map { Color(nsColor: $0) } ?? Color.gray.opacity(0.25) },
                set: { Theme.set(Theme.hexText(NSColor($0)), key, in: scope); written += 1 }
            ), supportsOpacity: true)
            .labelsHidden()
            label(key, paints)
            Spacer(minLength: 8)
            Text(own.flatMap { Theme.shade($0)?.dark }.map(Theme.hexText) ?? (scope == nil ? "Search's own" : "as everywhere"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Button("Reset") { Theme.set(nil, key, in: scope); written += 1 }
                .disabled(own == nil)
        }
    }

    private func label(_ key: String, _ paints: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(key).font(.system(size: 12, design: .monospaced))
            Text(paints).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

extension Theme {
    /// The keys, in THEME.md's order, with what each paints.
    static let keys: [(key: String, paints: String)] = [
        ("ground", "panels, the tab strip, popovers, the page's card before a page draws"),
        ("frame", "the window round the page: the tab column, the bookmarks bar, the gaps"),
        ("tab", "the live tab's row, a selected row"),
        ("hover", "the row under the pointer, the address field"),
        ("hairline", "thin lines and separators"),
        ("ink", "text and icons"),
        ("inkLive", "the live tab's title"),
        ("muted", "quieter text: the other tabs' titles"),
        ("faint", "the quietest text and marks"),
        ("accent", "the line round the focused page of a split, the live tab's stripe"),
        ("accentDim", "the line round the other pages of a split"),
        ("pin", "a pinned tab's square, behind its logo"),
        ("tile", "the box round a split's tabs in the sidebar"),
        ("tileLine", "that box's outline and the lines between its tabs"),
    ]

    static let switches: [(key: String, paints: String)] = [
        ("stripe", "a bar in the accent colour down the left of the live tab"),
        ("wash", "keep Search's own colour wash for a space on top of the palette"),
    ]

    /// Every space there is, and any the file names that is gone or renamed.
    static var spaceNames: [String] {
        Array(Set(Spaces.known.values.map(\.name)).union(spaces.keys)).sorted()
    }

    /// What the file says for `key`: a space's own, or (nil) everywhere's.
    static func value(_ key: String, in space: String?) -> Any? {
        if let space { return spaces[space]?[key] }
        return base[key]
    }

    /// Write `value` for `key` (nil: take the key out), and paint with it.
    /// The file is read again first: whatever else is in it stays.
    static func set(_ value: Any?, _ key: String, in space: String?) {
        var json = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
        if let space {
            var all = json["spaces"] as? [String: Any] ?? [:]
            var one = all[space] as? [String: Any] ?? [:]
            one[key] = value
            all[space] = one.isEmpty ? nil : one
            json["spaces"] = all
        } else {
            var everywhere = json["default"] as? [String: Any] ?? [:]
            everywhere[key] = value
            json["default"] = everywhere
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              (try? data.write(to: url, options: .atomic)) != nil else { return }
        edited()
    }

    /// "#RRGGBB", or "#RRGGBBAA" for a colour that isn't solid.
    static func hexText(_ colour: NSColor) -> String {
        guard let c = colour.usingColorSpace(.sRGB) else { return "#000000" }
        func byte(_ part: CGFloat) -> Int { Int((min(max(part, 0), 1) * 255).rounded()) }
        let solid = String(format: "#%02x%02x%02x", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
        return byte(c.alphaComponent) == 255 ? solid : solid + String(format: "%02x", byte(c.alphaComponent))
    }
}
