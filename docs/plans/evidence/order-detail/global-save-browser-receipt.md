# Global save and divider browser verification - 2026-11-01

Final local release at port 58631 served `main.dart.js` SHA-256 `c77401aa2a1f0d1c2aaef423d4f97bf41db4c52b83e2f93281239fa96f5c70f0`. Isolated headless browser and disposable local Supabase; production endpoints blocked.

- On the preceding functional build `afc69ad1308a015ffa6325f32e60525def29290fefec24d988160eec2d705a94`, one global Save changes persisted three local fixture drafts across tabs: Petr order 5 phone +420 777 000 032 to +420 777 000 052, note appended `Global test.`, and Host 2 meal Vegetariánská to Bez omezení. Full reload confirmed all three; total Kč1600 and paid Kč1450 remained unchanged. No email, payment or cancellation was submitted.
- A second note and meal draft triggered the Escape discard guard. Continue retained drafts; global Discard restored both saved values. On the final build a temporary unsaved note showed the sticky Save/Discard bar and English native tab labels without the former Czech suffix; global Discard removed the draft without a write. See `global-save-final.png` and `global-save-sticky.png`.
- Divider showed only its line, with no handle. Browser cursor was `ew-resize` on the line and 20px to either side at upper and lower positions; drags from both sides moved the divider. See `divider-final.png`.

Browser closed; local HTTP and Supabase remain running. Only the three authorized fixture changes above were saved.
