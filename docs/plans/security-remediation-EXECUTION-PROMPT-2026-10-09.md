# Provedení bezpečnostních oprav Festapp

Pracuj v `/Users/miakh/source/festapp`. Přečti celý autoritativní plán `docs/plans/security-remediation-plan-2026-10-09.md`, AGENTS.md, CLAUDE.md a `docs/architecture/ai_context.md`. Ověření je standard, protože jde o autorizaci a databázovou migraci.

Implementuj všechny čtyři vlny lokálního balíku: NULL kontroly scan/attendance, XSS formulářů, objektovou autorizaci vybraných RPC a společnou dopřednou migraci s regresními testy. Zachovej platný anonymní scan s tajným kódem, role vlastníka/editora/companions, návratové kontrakty a rich formátování. Uživatel výslovně dovolil pomoc GPT-6.1 Sol Medium agenta; drž oddělené vlastnictví souborů a respektuj existující rozpracované změny.

Žádné placeholdery, paralelní business implementace nebo nechráněné retained overloady. Pokud kód vyvrátí premisu, oprav plán a dolož rozhodnutí. Používej samostatnou lokální databázi a izolovaný headless browser. Nové testy musí odmítat exploit, nikoli pouze potvrzovat současný zranitelný stav.

Dokončení znamená kanonický kód, migraci, zelené cílené testy a audit s přesným stavem. Sdílení souborů, participant counts a jednorázové pozvánky mají samostatné migrační hranice uvedené v plánu. Commit, push, produkční migrace a tenantový deploy nejsou autorizované tímto implementačním zadáním. Při předání uveď výsledky testů, zbytková rizika a skutečnost, zda je změna nasazená.
