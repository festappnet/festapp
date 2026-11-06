# Připravit/realizovat společný Commerce Connector, první adaptér Shoptet

Historický výzkum a návrh z 29. 10. 2026, začleněný 6. 11. 2026. Nejde o implementaci ani novou autorizaci realizace. Tehdejší záznamy o neodeslání jsou překonané [stavem potvrzeným vlastníkem 1. 11.](shoptet-partner-onboarding-2026-10-26.md): návrh byl odeslán, čeká se na odpověď a další podání se neposílá.

Pracovní checkout: `/Users/miakh/source/festapp-shoptet-research-20261029`. Respektuj AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md; verification standard. Nezasahuj do souběžného main checkoutu.

Přečti celé `docs/plans/commerce-connectors-plan-2026-10-29.md`, `docs/architecture/commerce-connectors.md` a `docs/architecture/shoptet.md`. První vlastní etapu určuje aktuální uživatelská autorizace, nikoli tento dokument.

Výsledek je jeden společný e-shopový konektor: generic checkout/offer/inbox/attempt/order-link/financial-facts, generic capacity reservation v existujícím inventory a Shoptet jako provider adaptér. Další e-shop musí přidat adapter+manifest+conformance evidence, nikoli kopii orders/tickets/plateb nebo vlastní frontu e-mailů. WP/Wix embed a Make/MCP read-only nejsou předmětem nuceného přepisu. Stripe provider je vzor oddělení HTTP a SQL, ne výmluva pro nahrazení jeho sémantiky.

Vlastník schválil společné jádro, pořadí ověřování, držení kapacity do vyjasnění a základní rozsah; záznam je `docs/plans/commerce-connectors-review-2026-10-29.md`. Před rozsáhlejšími SQL změnami proveď pouze oprávněnou etapu 1a s minimálním testovacím ledgerem. Nepřeskoč G1-G5 a S1-S10. Shared-reservation-v1 je vybraný směr; nevytvářej kvóty, redirect checkout ani webhook-only fallback. Unknown provider výsledek vždy chrání kapacitu; lease TTL ani browser timeout není release permission. Snapshot/revision/isolation a všechny domácí admission/maintenance/read cesty patří do téže realizace, ne do odloženého úklidu.

Trvá zákaz odesílání a podávání. Současný úkol je architektura a příprava, nikoli provedení migrací, sandboxových mutací, implementace, provozní aktivace, placených operací, commitu nebo push. Veřejné čtení a lokální dokumentace jsou přípustné. Případné další oprávnění musí skutečně pokrýt příslušnou etapu; přístupy samy nezaručují autoritu.

Až bude implementace výslovně zadaná, postupuj etapami a targeted checks plánu. Pokud skutečný kód/provider vyvrátí premisu, oprav autoritativní design i plán, neparalelizuj alternativní business paths. Bez požadavku nevytvářej subagenty. Handoff má oddělit připraveno, implementováno, testováno lokálně, ověřeno sandboxem a nasazeno.
