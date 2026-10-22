# Implementuj lokální podklady náhledu vstupenek

Pracuj ve Festapp repozitáři. Přečti aktuální AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý autoritativní plán:

`docs/plans/ticket-preview-local-resources-plan-2026-10-22.md`

Cíl: galerie a canvas vznikají lokálně ze společných statických podkladů, nastavení načte pouze aktuální ticket, editor znovu použije session a backend nepřipravuje galerii ani zkušební PDF při běžném otevření. Vestavěné fonty připrav při build kroku, ostatní jednou při důvěryhodném importu do současného privátního R2 kontraktu. Zachovej věrnost jedinému PDF rendereru, oprávnění, schema 3, uložený vzhled, setup draft a staré distribuované klienty na výslovně popsané externí hranici.

Verification: standard. Postupuj po vlnách plánu. Nezaváděj ručně duplikované presety, další storage authority, klientský PDF renderer, placeholdery ani fallback nového klienta na těžký resolve. Dotčené save/`layout-text` hranice nesmaž pouze podle podobnosti názvů. Pokud se výchozí fakta změnila, aktualizuj plán konkrétním důkazem před změnou příslušné vlny.

Hotovo vyžaduje všechny invarianty a odstranění v deletion ledgeru, včetně cold/repeated runtime měření. Změna uživatele z 2026-10-22 výslovně povoluje ponechat zvýšený CPU limit; odstranění výjimky ani důkaz původního rozpočtu se nevyžadují. Samotný vyšší limit není dokončení. Respektuj jednu Flutter úlohu a `--concurrency=1`, pnpm 11.24.0, existující test suite owners a izolované headless browser checks. Nepouštěj nezávislý audit ani další agenty kromě výslovně povolené rutinní deployment delegace.

Tento prompt po výslovném zadání autorizuje implementaci a lokální ověření, nikoli produkční zápisy/nasazení ani commit/push. Pro release si vyžádej samostatný scope a dodrž místní release gates; tenant v plánu je jen festapptickets. Na konci stručně uveď změněný kontrakt, odstraněnou práci, výsledky ověření a přesný dosud neprovedený provozní krok.
