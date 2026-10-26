# Proveď rychlé dotažení lifecycle plánku

Pracuj v `/Users/miakh/source/festapp-blueprint-cutover-release-20261019`.
Přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý plán:

`docs/plans/blueprint-post-cutover-architecture-review-2026-10-20.md`

Autoritativní pro tento úkol je sekce „Následné dotažení podle aktuální kontroly“.
Předchozí batch cancellation je hotová, znovu ji neimplementuj. Proveď obě
zbývající vlny: bezpečné slučování async image/text resources a jediný přechod
editace -> prohlížení po dokončení textového vstupu. Zachovej nativní editaci,
kanonické uložené vektory, captured save/retry a SQL autoritu.

Verification: standard. Zachovej dirty diff a skutečné vendored dependencies.
Při vyvrácení premise aktuálním kódem oprav plán s konkrétní evidencí. Žádné
placeholdery, nové frameworky, aliasy nebo preventivní veřejné package změny.

UI/widget práci a její regrese deleguj `gpt-6-astra`, reasoning_effort medium,
fork_turns none, s ui-ux-pro-max skillem podle plánu. Primární agent vlastní
helper. Dohodni souborové vlastnictví; žádný další review agent. Nedostupnost
Astry oznam a UI nepřiděluj potichu jinému modelu.

Dokonči coherent diff a proveď jeden targeted analyzer + owning session batch
podle plánu. Jeden Flutter task na workstation, test concurrency 1. Bez buildů,
browseru a distribučního QA, pokud konkrétní gate plánu nevyžaduje jinak.

Bez produkčních změn, deploye, publikace, commitu a pushe. V závěru uveď opravené
callery, odstraněné nebezpečné větve, skutečné výsledky kontrol a omezení.
