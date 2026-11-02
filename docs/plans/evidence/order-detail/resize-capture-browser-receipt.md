# Divider captured-drag verification - 2026-11-02

On prior local artifact `3a2a7038d1bdb91ca4946a9dbb8143c243c5bff39e7b5d774f82e95ecf3b921f`, holding a divider drag from x679 to x1200 clamped the line at x919 while the effective browser cursor became `auto`; the drag continued when reversed.

On final artifact `ddef52cdaba69fff2b5ba78c15994251697619a2f80365e3119b41d532b57a3c`, the same held drag kept both body and hit-element cursors `ew-resize`. One pixel of reverse movement changed the clamped line from x919 to x918; at the opposite clamp it changed x519 to x520. Releasing outside restored `auto`, and a new drag restored the original x679 divider. Pixel positions were measured from screenshots in an isolated 1280x900 headless browser. See `resize-capture-final.png`.

No database writes. Browser closed; local HTTP and Supabase remain running.
