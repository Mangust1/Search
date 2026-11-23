# Userscripts (fork)

Search runs your own scripts on pages, as Violentmonkey or Tampermonkey
would, with nothing to install. Put each script in:

    ~/Library/Application Support/Search/userscripts/

Any `*.js` file there is a script. A file saved or added is in the next
page that loads; no restart. Delete or rename it (say to `.js.off`) to stop.

```js
// ==UserScript==
// @name        Tag the tab
// @match       https://*.example.com/*
// @exclude     https://example.com/admin*
// @space       Work
// @run-at      document-start
// @grant       GM_addStyle
// ==/UserScript==
GM_addStyle("body { outline: 3px solid orange }");
```

| header | meaning |
| --- | --- |
| `@name` | what it is called (in errors on the console) |
| `@match` | a match pattern: `scheme://host/path`, `*` for any scheme (http, https), `*.` for any subdomain, `*` in the path for anything; `<all_urls>` for every page. Once per pattern. |
| `@include` | a glob (`*` is anything) or `/a regular expression/`. Once per pattern. |
| `@exclude`, `@exclude-match` | the same two, for pages to leave alone |
| `@space` | the fork's own: the name of a space. Once per space. The script then runs in those spaces only; without it, in every space. |
| `@run-at` | `document-start`, or when the page is read (`document-end`, `document-idle` and the default are the same here) |
| `@noframes` | the page itself only, not the frames in it |

A script with no `@match` and no `@include` runs nowhere.

Scripts run in the page's own world (what `@grant none` means). These are
there for the asking:

`GM_addStyle`, `GM_getValue`, `GM_setValue`, `GM_deleteValue`,
`GM_openInTab`, `GM_setClipboard`, `GM_info`, `unsafeWindow`, and the same
under `GM.` returning promises.

Not there: `GM_xmlhttpRequest` (no reaching another site past its rules),
`@require` and `@resource`, menus. Values kept with `GM_setValue` live in
the site's own local storage: per site, and the site could read them.
