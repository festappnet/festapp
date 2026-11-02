# Native cursor verification - 2026-11-02

On old local build `ddef52cdaba69fff2b5ba78c15994251697619a2f80365e3119b41d532b57a3c`, the divider was x679 in an isolated 1280x900 browser. Flutter set the body cursor to `ew-resize` across the target, but `elementFromPoint` hit a native range input with computed cursor `default` over x662-700, including the line. Only the thin left strip hit the resize cursor. The input had role `slider`, pointer-events `all`, and sat inside the `Resize order detail` semantics node.

After clean navigation to final build `ec83fe3382242c65dbe47c559c2d337b7fc3206cf228c7085670b55d4977efcd`, with no manual DOM style, the native range input retained role `slider` and had computed pointer-events `none`. The deepest hit cursor was `ew-resize` at x661, x679 and x697 at y160, y600 and y800; outside x657 was `auto` and x701 was `text`. Actual one-pixel drags at left, center and right moved the line 679->680->681->680; the original width was restored. Screenshot: `resize-native-cursor-final.png`.

No database writes. Isolated browser closed; local HTTP and Supabase remain running.
