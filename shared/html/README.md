# App HTML content

`app-content-policy.json` owns the style contract for event descriptions, public
forms and other `appContent` HTML. Font family and foreground/background colors
come from the configured app/form theme. CSS emphasis is converted to semantic
HTML before removing font shorthands, so bold, italic, underline and strike remain
editable. Headings, lists, tables, alignment, links and media retain their structure.

The Dart codec and the public web DOM sanitizer are platform adapters of this
policy. Both run `app-content-cases.json`, including idempotent normalization.
The editor applies it on load, paste and export; the save coordinator applies it
even to unopened fields; renderers normalize existing stored content on read.
Cancellation and undo do not write to persistence. Existing rows need no bulk
rewrite: their next ordinary save stores normalized HTML.

Song and email profiles retain authored typography and layout. Every editor,
viewer and save binding must propagate its profile, rather than infer it from text.

Run `node automation/generate_html_content_policy.mjs` after policy changes.
Commit its generated Dart/JS adapters together. Tests check generation offline;
no runtime fetch or new asset loading is required. Content security remains owned
by the existing HTML codec/DOMPurify; SVG graphic sanitization is separate.
