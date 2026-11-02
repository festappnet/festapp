# Ticket scope browser verification - 2026-11-02

Local build at port 58631, served `main.dart.js` SHA-256 `3a2a7038d1bdb91ca4946a9dbb8143c243c5bff39e7b5d774f82e95ecf3b921f`, isolated headless browser and disposable local Supabase. Production endpoints blocked.

Eva order 7: expanded ticket PLES-4-1 has no holder-name suffix or synthetic participant/meal fields; its purchased Vstup do hlavního sálu displays Kč650. The existing Edit products dialog opened and was closed without changes. Czech screenshot: `ticket-scope-final.png`.

Petr order 5 still showed the menu product, Kč1600 total, Kč1450 received, phone +420 777 000 052 and existing note. No database writes in this browser pass. Browser closed; local services left running.
