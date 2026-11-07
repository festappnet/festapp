# Dokončení PR #749

Přečti celý autoritativní plán:
`docs/plans/mcp-connection-pr749-plan-2026-11-07.md`.

Dokonči podle něj implementaci stávajícího PR #749, odstranění nahrazených cest, dokumentaci, generované reference a požadované ověření. Nejprve načti `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a `CONTRIBUTING.md`. Pracuj v izolovaném worktree, zachovej cizí změny a checkouty. Režim ověření je `standard`, jde o autentizaci a souběh.

Aktualizuj PR proti současnému main, prohlédni intervenující commity a zachovej změny z PR #750. Očekávaný původní head PR je `0aa0654b0069ee2773bf00f880c5d026fd566187`; poslední zkoumaný main je `7e9a8ec6c21fa0a56dc985bb65479fd3acebe320`. Aktuální stav má přednost před těmito referencemi. Pokud nová evidence vyvrátí faktický předpoklad plánu, nejdříve oprav plán a jeho důsledky.

Výsledek: pending souhlas není aktivní připojení, první dokončená náhrada vyhrává, aktivace a odvolání jsou atomické a SQLite chyba nevrací úspěšný token response. Jedna policy vlastní platnost, refresh i oba consent vstupy. Dolož skutečný HTTP/OIDC průchod, rollback/restart, souběh, refresh replay, všechny nabízené délky, migraci existujícího úložiště a skutečný lokální browser flow. Připoj auth regrese do canonical CI kontraktu a spusť dotčené mirror lanes. Bez placeholderů, duplicitních V1/V2 cest, tichých fallbacků a skipů zastírajících neprovedené ověření.

Zachovej pnpm 11.24.0 a frozen lockfiles. Browser obsluhu deleguj Terra v izolované muted session, žádný produkční účet jako náhrada lokálního ověření. Neodstraňuj hodnotné testy jen pro čistý výstup.

Bez publikace, push, merge a produkčních zásahů. Ty vyžadují samostatné zadání a příslušné release gates. Na konci stručně uveď výsledný worktree a změny, přesné provedené checks, uzavření deletion ledgeru a případná skutečně nedokončená ověření. Neoznačuj práci za hotovou, pokud požadované ověření chybí.
