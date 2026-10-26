# Implementuj ploché centrum upozornění a změny dostupnosti formulářů

Pracuj v `/Users/miakh/source/festapp`. Nejprve přečti aktuální `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/notification-center-feed-plan-2026-10-26.md`

Ověřování: **standard**. Výsledek je skutečný SQL -> osobní feed -> Flutter tok: jednotlivé chronologické události pod akcí bez typ/den accordionů a symbolů objednávky, společný kontakt fallback a smysluplné počty, ruční i naplánované otevření/uzavření formuláře. Vizuální reference je `docs/plans/notification-center-feed-evidence-2026-10-26/preview.html`, nikoli samostatná produkční implementace.

Proveď vlny v pořadí závislostí. Zachovej jeden SQL owner časové dostupnosti, existující publication/recipient/activation/ack infrastrukturu a jeden maintenance cron. Nezaměňuj kapacitní recovery za otevření formuláře. Změna přečtení zůstává pouze v explicitním open; feed pagination, hydration a mute neackují.

Odstraň nahrazené Flutter group modely, expand/cursor logiku a UI. Kompatibilitu starších skutečně vydaných klientů drž pouze jako pojmenovaný externí serializační adaptér podle plánu, nikdy jako nový client fallback nebo druhou business implementaci. Jeho případné odstranění vyžaduje doložené vyřazení klientů. Dodrž celý deletion ledger, žádné placeholdery, spekulativní aliasy nebo další inbox/frontu.

Zachovej cizí rozpracované změny. Neměň aplikovanou migration historii; zaveď novou forward migraci s explicitními prerequisites a tichým baseline. Pokud aktuální důkaz vyvrací premisu, oprav plán a navazující vlnu s konkrétním odůvodněním, neměň potichu uživatelský výsledek.

Spusť cílené skutečné SQL/concurrency/core/Flutter/E2E kontroly uvedené v plánu a ověř nenulové discovery. Dodrž jediný Flutter task na workstation a `--concurrency=1`, pnpm 11.24.0 a izolovaný headless browser. Nespouštěj nezadaný nezávislý audit/subagent review. Dřívější `image/archive` compile blocker ověř z aktuálního stavu, neobcházej testy ani globálně neupravuj cache.

Bez samostatného pokynu neprováděj produkční připojení/migraci, aktivaci, rollout flag změnu, release, commit ani push. Na konci uveď implementovaný kontrakt, odstraněné cesty, skutečné test receipts, stav migrační rehearsal, případnou zachovanou externí hranici a dosud neprovedené produkční kroky. Udržuj plán a evidence v souladu se skutečným výsledkem.
