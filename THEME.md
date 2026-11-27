# theme.json (fork)

The colours of the browser's own chrome, from one file:

    ~/Library/Application Support/Search/theme.json

Search reads it at launch and again whenever it is saved; the window repaints
at once, no restart. No file, or an empty one, is stock Search. Web pages are
not touched by it.

```json
{
  "default": {
    "ground": "#32302f", "frame": "#32302f",
    "tab": "#504945", "hover": "#3c3836", "hairline": "#504945",
    "ink": "#ebdbb2", "inkLive": "#fbf1c7", "muted": "#d5c4a1", "faint": "#928374",
    "accent": "#d79921", "accentDim": "#504945",
    "stripe": true
  },
  "spaces": {
    "Work": { "ground": "#0d1c4d", "frame": "#0d1c4d", "tab": "#1b2f6b", "accent": "#f4b765" }
  }
}
```

- `default` is the palette everywhere.
- `spaces` is keyed by a space's name. While that space is the front
  window's, its keys lie over `default`; a key it leaves out is `default`'s.
- A key left out of both keeps Search's own grey.
- A colour is `"#RRGGBB"` (or `"#RRGGBBAA"`) for both modes, or
  `{"light": "#…", "dark": "#…"}` for one each.

| key | paints |
| --- | --- |
| `ground` | panels, the tab strip across the top, popovers, the page's card before a page draws |
| `frame` | the window round the page's card: the tab column, the bookmarks bar, the gaps |
| `tab` | the live tab's row, a selected row |
| `hover` | the row under the pointer, the address field |
| `hairline` | thin lines and separators |
| `ink` | text and icons |
| `inkLive` | the live tab's title (else `ink`) |
| `muted` | quieter text: titles of the other tabs, secondary labels |
| `faint` | the quietest text and marks |
| `accent` | the line round the focused page of a split, the live tab's stripe |
| `accentDim` | the line round the other pages of a split |
| `tile` | the box round a split's tabs in the sidebar |
| `pin` | a pinned tab's square at rest, behind its logo (else `tile`) |
| `tileLine` | that box's outline and the lines between its tabs (else `hairline`) |
| `stripe` | `true`: a 3-point `accent` bar down the left of the live tab |
| `wash` | `true`: keep Search's own colour wash for a space on top of the palette (off by default once a theme is loaded) |

One palette for the whole app: two windows on different spaces both wear the
front window's.

## Space pictures

A file named after a space in `spaceicons/` in the data folder
(`spaceicons/Work.png`, or `.svg`, `.pdf`) is shown for that space in the
sidebar in place of its symbol. Read at launch.
