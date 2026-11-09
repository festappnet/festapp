# Implementace zásadního zrychlení testů Festapp

Stav: původní vlny 0-7 a release1053 jsou dokončené. Navazující nativní browser
a opravy alertů305/307 jsou implementované a ověřené proti main #774; publikace
respektuje povinné review. Aktuální výsledky, rozsahy benchmarků a receipts jsou
v `test-runtime-speedup-RESULT-2026-11-09.md` a JSON vedle tohoto dokumentu.
Následující text je původní implementační zadání, neopakujte dokončené vlny.

Pracujte v čistém worktree repozitáře `/Users/miakh/source/festapp` z aktuálního `main`. Přečtěte AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md, CONTRIBUTING.md a celý autoritativní plán:

`docs/plans/test-runtime-speedup-plan-2026-11-09.md`

Podklady: `docs/plans/test-runtime-speedup-evidence-2026-11-09.json`. Historické časy různých revizí nejsou kontrolovaný benchmark.

Implementujte vlny 0-7 v pořadí plánu s verification: standard. Cíl je rychlejší skutečné provedení shodných sad: menší provider-compatible SQL runtime, ověřený čistý testovací základ a izolované clone DB, průběžný SQL scheduler a rychlejší fixture, seskupené Flutter vstupy i zrychlená těla, méně browser build/start/CLI režie a společná resource DAG. Targeted selection přijde až potom a její přínos se vykazuje odděleně.

Respektujte jeden Flutter task na workstation a --concurrency=1. Browser operace delegujte na Terra podle AGENTS. Neodstraňujte skutečný upgrade gate, provider/ACL parity, concurrency scénáře, negativní browser aserce nebo osm exact-SHA release checků. Žádný skipped check jako SUCCESS, žádné snížení velikosti fixture místo optimalizace. Nepřebírejte cizí rozpracované změny.

Dokončení vyžaduje finální srovnání při stejném inventáři a prostředí, oddělené cold/warm výsledky, structured timings a memory, odstranění všech nahrazených cest podle ledgeru a aktualizaci CONTRIBUTING.md. Pokud naměřené důkazy vyvrátí předpoklad, nejprve aktualizujte autoritativní plán a příslušnou vlnu. Nevymýšlejte paralelní registr, bootstrap, skryté fallbacky ani neověřené cache.

Nevykonávejte produkční migraci/deploy a nepublikujte zdroje bez samostatné autorizace. Zadání implementace opravňuje lokální implementaci a potřebné testy, ne nákup runnerů/služeb. Handoff: výsledky před/po pro plné stejné sady, dodané změny, odstraněné cesty, skutečné kontroly a přesný zbývající deficit.
