# Order detail focus browser verification - 2026-11-02

Local build on port 58631, served `main.dart.js` SHA-256 `a1be5019c6b39f4ff2e0c24024d072dbbea3dcfecb8c3c396cdc858de4b68823`; isolated headless browser, disposable local Supabase, production endpoints blocked.

- Petr order 5: clicking the Stůl 1 · 5 place row selected ticket 17 without scrolling the map out of view (`place-row.png`). Its crosshair opened the main Blueprint route with blueprintId 5 and node 74ddcf9c-f66f-4997-961a-e4b63dea2923; the place was centered and outlined. Back and a repeat crosshair click reopened the same focused place (`main-blueprint.png`).
- Payments showed the original Transactions content with one variable symbol 270102, Amount/Paid/Returned and the existing cash transaction, without an added compact ratio or duplicate account/reference section (`payments.png`).
- Email uses a static external label and box (`email.png`); focus, blur and the first unsaved edit did not move the field or animate a floating label/underline. The shared draft bar appeared below the scroll viewport; Discard restored the existing address. No save was performed.
- In a fresh profile at 1280px, detail was approximately 720px and the table 560px. Header color comparison in dark mode, malformed focus links and stored-width preservation were not independently verified in this browser pass; targeted widget tests cover those cases.

No database writes. Browser closed; local HTTP and Supabase remain running.
