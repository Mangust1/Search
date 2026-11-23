# routes.json (fork)

Search's own "Send links to a space" knows a rule by its site only. This
file sends an address to a space by any text in it: a path, a query, the
part after the `#`.

    ~/Library/Application Support/Search/routes.json

```json
{
  "Work":     ["bitbucket.org/acme", "acme.awsapps.com", "123456789012-", "#space=work"],
  "Personal": ["youtube.com", "*.example.org"]
}
```

- Each key is a space's name; each text under it sends an address holding
  that text to that space. Letter case doesn't matter.
- When several texts are found in one address, the longest wins.
- A leading `*` is dropped: `*.example.org` is the text `.example.org`.
- A space that doesn't exist is passed over, and the link opens as usual.
- Read again whenever the file is saved. The file being there is the
  switch; it needs spaces on. The rules in Settings still work, after these.

It sends what Search's own rules send: a link from another app, and a link
a page opens in a new tab from a page in another space. A link followed in
its own tab, and an address typed, stay where they are.
