# Realizační prompt

Implementuj vlny 1-3 podle celého autoritativního plánu `docs/plans/order-email-recovery-plan-2026-10-24.md`, zejména jeho „Úsporného realizačního kontraktu“. Nejdřív přečti platné `AGENTS.md`, `CLAUDE.md` a `docs/architecture/ai_context.md`. Použij `focused-development`, verification: standard.

Výsledek: upozornění otevře konkrétní objednávku a zvýrazní řádek bez změny výběru; varování vedle stavu a jeden sdílený opravný dialog nabídnou opravu kontaktu, opakované odeslání a existující zrušení objednávky. Jeden autorizovaný idempotentní RPC mění kontakt a volitelně atomicky enqueueuje do současné fronty. Historická chyba zůstane dohledatelná; varování řeší jen prokázané doručení explicitně navázaného pokusu stejného druhu. Zachovej pravidla suppression, sending/unknown, souběhu a ACL z plánu, platby a inventář beze změny.

Pracuj sériově bez subagentů. Udělej jeden cílený průchod po uvedených vlastnících, potom implementuj souvislý celek. Použij současné commands/receipts, reporting, renderery, AppDialog a probouzení workeru. Žádná nová infrastruktura, obecný incident systém, globální verzování ani nesouvisející refaktor. Existující hotovou vlnu 0 neopakuj. Při prokázaném rozporu oprav jen dotčený fakt a krok plánu.

Proveď jeden cílený závěrečný soubor kontrol podle plánu: SQL pro ACL, atomičnost, replay, souběh a životní cyklus varování; command/widget testy; analýzu změněných Dart souborů; jeden izolovaný lokální integrační průchod s falešným e-mailovým transportem. Ověř skutečný výběr testů. Jeden Flutter proces, `--concurrency=1`; opakuj jen zneplatněné kontroly. Žádný plošný build, plná suite nebo nezávislý audit, pokud je nevyžádá konkrétní nález či pravidlo repozitáře.

Dokonči implementaci a lokální ověření. Tento prompt nepovoluje produkční migraci, nasazení ani zákaznické odesílání. Na konci stručně uveď změny, provedené kontroly a případné neověřené hranice.
