# Download rules (fork)

With **Ask where to save** on, a download first asks: **Open**, **Save…** or
Cancel, with a tick box to always do that for that kind of file from that
site. Open keeps the file in a temporary folder, not in Downloads, and opens
it when it is down; files opened more than a day ago are deleted at the next
one.

The answers live in `downloads.json` in the data folder, and can be written
by hand. A rule applies whether or not Search asks:

```json
{
  "ci.example.com": {
    "txt": { "do": "open", "with": "Some Viewer" },
    "zip": "save"
  }
}
```

- First the host of the page the download was started on, then the file's
  extension (`""` for a name without one).
- `"open"` or `"save"`, or `{ "do": …, "with": … }` to also name the app
  that opens it: as it is named in Applications, or its bundle id. With no
  app named, the Mac's own app for the file opens it.

Read at each download, so an edit applies at once.
