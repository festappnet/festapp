# Pokračování implementace vstupu pořadatele

Schválený rozsah je lokálně implementován a ověřen. Přečti celý `docs/plans/cro-audit-plan-2026-10-26.md`, především první sekci a výsledek implementace; `cro-audit-evidence-2026-10-26.json` zachycuje předchozí audit, `organizer-entry-verification-2026-10-26.json` novou kontrolu.

Pracovní stromy: Festapp `/Users/miakh/source/festapp-login-cta-release-20261026`, katalog `/Users/miakh/source/plesuj-organizer-entry-20261026`. Přečti příslušné repository instrukce. Před publikací aktualizuj canonical main, zachovej místní změny a zkontroluj aktuální produkční stav.

Výsledkem je zachovaný záměr vytvoření přes email a Google, jeden sdílený creation helper a viditelné katalogové vstupy. Formulář, cenový obsah, nové měření a databázové atribuce nejsou schválené. Nevytvářej další wizard, obecný redirect parametr, tracker ani duplicitní moderaci.

Doložené kontroly už neopakuj, pokud se jejich pokrytý kód nezměnil. Při změnách autentizace používej standardní targeted ověření; Flutter úlohy sériově a testy --concurrency=1. Browser pouze izolovaný headless. Skutečný Google provider a doručitelnost emailu nebyly ověřené živou registrací; neoznačuj fixture za takový důkaz.

Nasazení proveď až při samostatném zadání. Festapp web sestav lokálně a nasaď přes automation/deploy_direct.sh pouze pro vybraný tenant se všemi ancestry/drift/backend manifest/build/live gates; routine release deleguj podle AGENTS. Katalog má vlastní release pravidla. Neměň systémovou DNS blokaci analytiky kvůli lokálním kontrolám.
