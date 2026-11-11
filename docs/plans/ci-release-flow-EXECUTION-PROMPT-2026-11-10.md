# Realizace sjednoceného CI a release toku Festapp

Pracuj v `/Users/miakh/source/festapp`, v čistém worktree z aktuálního `origin/main`. Před změnami přečti `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/ci-release-flow-plan-2026-11-10.md`

Verification: standard. Výsledek: cílené lokální ověření, jedno autoritativní GitHub execution pro totožné vstupy, bezpečné předání důkazu PR/main a tenant build bez opakované plné zdrojové sady. Zachovej osm aktuálních zelených check names na přesném main SHA, skutečné upgrade testy, tenant ancestry, produkční gate a ověření hotového/nasazeného artefaktu.

Tento prompt není samostatná autorizace ke změně závazné politiky. Před realizací musí navazující zadání výslovně přijmout nahrazení povinného plného lokálního mirroru cílenými lokálními testy a autoritativním GitHub ověřením podle vlny 1. Potom postupuj po vlnách bez opakovaného dotazování na již schválené kroky. Dokud není změna přijata a účinná, platí současné publikační gates.

Použij existující `checks.json`, runner, selector, immutable receipts a deploy skripty. Nevytvářej nový CI framework, druhou mapu vstupů, status-only reuse, řetězené receipts, obecné skip příznaky ani implicitní GitHub dispatch. Splň deletion ledger a dolož zachování sjednoceného test inventory. Pokud aktuální kód vyvrátí předpoklad plánu, oprav přímo plán a příslušnou vlnu.

Každou koherentní vlnu ověř jednou relevantní dávkou podle plánu a účinných repository pravidel. Před publikací fetch a integrace aktuálního upstreamu; respektuj branch protection. Browser interakce deleguj Terra, release monitoring levnějšímu agentovi podle AGENTS; zachovej izolaci, mute a jeden Flutter task na workstation.

Bez samostatného pověření neprováděj commit/push, skutečný PR merge, změnu branch protection ani produkční build/deploy. V závěru uveď hotové vlny, odstraněné duplicity, výsledky a skutečné celkové časy; odhady odděl od měření a přesně označ dosud neprovedené provozní ověření.
