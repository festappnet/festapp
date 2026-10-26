# Sjednoť canonical main a skutečné lokální změny, potom dokonči feed

Stav: provedeno lokálně 26. 10. 2026. Finální evidence: `notification-center-feed-evidence-2026-10-26/README.md`. Bez commitu, push nebo produkčního vydání.

Přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý autoritativní
`docs/plans/workspace-canonical-reconciliation-plan-2026-10-26.md`.
Ověřování: standard.

Nezaměňuj starý root HEAD za obsahový základ nové práce. Snapshot d4dc je již
na main; privátní 9ea uchovává další vrstvu. Nejprve zajisti obnovitelný aktuální
obsah a ověř změny od inventáře. Spoj lokální a čerstvý upstream main, pak přenes
pouze skutečný nový rozdíl po owning celcích a vyřeš všechny doložené konflikty.
Žádné hromadné ours/theirs, reset --hard, clean ani kopie celého starého stromu.
Zachovej cizí rozpracované změny, soukromé configy a živé worktree relace.

Nad sjednocenými canonical ownery dokonči původní notification feed. Neobnovuj
odstraněnou activation tabulku/setter ani rollout alias; zapoj skutečný shared
form constructor a zachovej canonical autorizaci. Aktualizuj forward manifest
podle skutečné main historie, neměň aplikované migrace. Zachovej vydané klienty
jen na pojmenované legacy SQL serializační hranici, žádný grouped client fallback.

Spusť požadované cílené SQL/concurrency/core/Flutter/nav/E2E a clean/upgrade
rehearsal nad konečnou kombinací s nenulovým discovery. Jeden Flutter task,
`--concurrency=1`, pnpm 11.24.0, izolovaný headless browser. Neodstraňuj produkční
data guardy kvůli lokálním testům. Pokud důkaz vyvrátí premisu, oprav plán.
Bez samostatného zadání žádná produkční operace, release ani push; původní zákaz
commitu respektuj a připrav necommitovaný výsledek. Na konci dolož inventář
přenesených/nahrazených cest, nulové konflikty, finální receipts a zbývající gates.
