# Czech cancellation wording preflight - 2026-11-02

Local review build at port 58631, served `main.dart.js` SHA-256 `83a5e1460b6691bdb055d45bc27c8f47da8d458de6f4608579a1b798ced3e0c7`, isolated headless browser and disposable local Supabase. Production endpoints blocked.

After selecting Czech and reloading order 5, the grid action reads `Stornovat` and detail action reads `Stornovat objednávku`. Its confirmation title and confirm action read `Stornovat`; it explains that the order cannot be edited after cancellation and payment is not automatically refunded. `Zpět` dismissed the dialog without cancellation. The expanded ticket action reads `Stornovat vstupenku`. See `storno-final.png`.

The contact email answer pencil accepted an unsaved dummy in place, and global Discard restored `host2@example.invalid`. No database writes. Browser closed; local HTTP and Supabase remain running.
