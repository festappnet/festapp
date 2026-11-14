# Samostatná servisní relace: vyčištění Git historie Festapp

Pracuj v `/Users/miakh/source/festapp`, ale přepis připrav v odděleném klonu.
Nejdřív celý přečti autoritativní plán:

`docs/plans/git-artifact-history-cleanup-plan-2026-11-14.md`

Dodrž aktuální AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md.
Verification: standard; zachovat povinné canonical CI a release brány.

Tento prompt spustit až v samostatné servisní relaci, kdy vlastníci všech
worktree a publikačních automatizací potvrdí nečinnost a lze držet výlučný write
freeze. Pokud jiné práce běží, nic nepřepisuj, nezastavuj cizí procesy a úlohu
odlož. Tento dokument sám nevytváří naplánovanou automatizaci.

Cíl: přestat verzovat generované API kontrakty a HTML, zachovat vydané kontrakty
mimo Git, vyříznout artefakty ze schváleného historického grafu a doložit reálnou
úsporu v novém klonu i na lokálním disku. Zachovat rozpracovanou práci, API URL,
kompatibilitu, tenant ancestry a funkční metadata odkazující na commit SHA.

Postupuj podle vln 0-5. Před destruktivními kroky ověř obnovitelnou externí zálohu.
Před publikací uzavři konkrétní ref manifest a oprávnění všech dotčených prod
větví podle tenant scope pravidel; tento prompt neopravňuje k libovolnému
multi-tenant zápisu ani produkčnímu deploy. Neoslabuj ochrany ani CI. Publikuj
pouze konkrétní refs proti očekávaným starým SHA; žádný slepý mirror/force push.
Pokud gate brání dokončení, ulož ověřenou offline přípravu a přesný blokátor.

Současný pracovní strom je rozsáhle dirty a starší než origin/main. Nesmí být
zdrojem implementace místo aktuálního main ani cílem in-place filter-repo.
Aktualizuj plán, pokud se jeho doložené premisy změnily. Žádné placeholdery,
tiché přeskočení baseline kontrol ani ponechání staré historie pro pohodlí.

Dokončení dolož auditem všech schválených commit grafů, obnovou všech worktree,
čistým buildem a příslušnými canonical CI lanes, kontrolou immutable kontraktů,
readbackem refs a velikostí nového síťového klonu. Odliš dosažitelné odstranění
od dosud nepotvrzeného serverového GC a cizích forků. Závěrem stručně uveď
výsledek, úsporu, ověření a případné skutečně zbývající kroky.
