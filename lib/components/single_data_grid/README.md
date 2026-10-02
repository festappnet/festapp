# Column help

Pass localized plain text to `SingleDataGridController.columnHelp`, keyed by
`TrinaColumn.field`:

```dart
columnHelp: {
  UserColumns.EMAIL: UserStrings.emailHelp,
},
```

This is an illustrative example: `UserStrings.emailHelp` is not an existing
getter. The caller supplies the text/getter appropriate to the column through
its feature's `*_strings.dart`. No production explanations are enabled by default.

The controller stores an immutable copy for its lifetime. Recreate the
controller when changing localized titles/help. Missing fields and blank text
keep the standard header untouched; keys for temporarily absent columns are
allowed. Help does not change titles or CSV exports. HTML/Markdown are not parsed.

The shared wrapper installs the header before grid creation, including after
`forceReload` replaces columns. Installation is idempotent. A configured column
with another `titleRenderer` throws `StateError`; `titleSpan` is preserved.
Mutable columns belong to one controller and must not be shared concurrently.

The info button supports hover, click, touch and Tab followed by Enter/Space.
When entering the table from surrounding page controls, Tab visits help buttons
before the grid. Tab within data cells keeps the grid's cell navigation.
Escape while focused on the button, tapping outside, scrolling, and removal
close the tooltip. Explicit activation lasts at most 10 seconds. Only columns
with help acquire a control-dependent minimum width; checkbox, filter, sort,
menu and resize controls remain available alongside an ellipsized title.
