# Note polish browser verification - 2026-11-02

Local build at port 58631, served `main.dart.js` SHA-256 `57389512749180927bfde5341a7aa11784ca8eae508255d050635e6c2149b051`. Isolated headless browser, disposable local Supabase, production endpoints blocked.

Order 5 shows a bold heading, no source-form label for the single form, and a directly editable Czech `Skrytá poznámka` without a pencil. The initial clean detail has no global draft bar. Typing an unsaved dummy directly showed Save/Discard; Discard restored the existing note. Order 9 also loaded cleanly without note autofocus. See `note-polish-final.png`.

No database writes. Owned browser closed; local HTTP and Supabase remain running.
