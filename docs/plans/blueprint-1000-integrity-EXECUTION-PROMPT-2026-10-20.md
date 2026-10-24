# Provedení: bezpečné a spolehlivé plánky do 1 000 lidí

> Navazující práce po provedení tohoto původního promptu: použij [nový exekuční prompt](blueprint-mcp-closure-EXECUTION-PROMPT-2026-10-20.md) a celý [plán dokončení](blueprint-mcp-closure-plan-2026-10-20.md). Již připravenou implementaci neopakuj; nový plán určuje zbývající opravy, integraci a kvalifikační gates.

Pracuj v `/Users/miakh/source/festapp` a dle potřeby v
`/Users/miakh/source/venue_seat_picker`.

Přečti celé AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a autoritativní
plán `docs/plans/blueprint-1000-integrity-plan-2026-10-20.md`.
Použij `verification: standard`. Výsledkem je skutečný save/reopen/prodej
plánku přibližně 1 000 míst s bezpečnými podklady, platnými rezervacemi,
stabilními identitami a ověřeným souběhem ve Flutteru i na webu.

Začni baseline a důkazy E01-E11. Jsou přiložené reprodukční skripty a sanitizované
výsledky, nikoli dokončené opravy. Nezaměňuj package demo za host integraci.
Před změnami sjednoť stav probíhající integrace B; její platná rozhodnutí a
akceptační parita zůstávají závazné. Již hotové části znovu neimplementuj.
Nezahrnuj stadionovou architekturu, nový inventory ledger ani obecný style framework.

Proveď vlny 0-5 v pořadí závislostí. Zachovej novější forward SQL guardy, původní
obchodní ownery, receipts a historické cenové snapshoty. Nepřidávej druhou
geometrickou/obchodní autoritu ani neplánované compatibility fallbacky.
Pokud aktuální evidence změní faktickou premisu, uprav autoritativní plán
s konkrétním důkazem a přizpůsob příslušnou vlnu bez tichého zmenšení výsledku.

Testuj jen v ověřeném task-owned lokálním prostředí; nikdy neresetuj sdílenou DB
podle portu. Flutter slot je nejvýše jeden na celé stanici, concurrency 1.
Browser kontroly mají vlastní headless profil a explicitní config; nepoužívej
globální Panerelay ani uživatelovu kartu. Pro full-app E2E načti festapp-local-e2e.
Další modelové požadavky na případné nové UI zachovej podle plánu B.

Dokončení vyžaduje negativní bezpečnostní testy, skutečné PG závody,
změřený host profil 1 000 míst a odstranění nebo explicitní omezení všech cest
z deletion ledgeru. Passing test bez změny vstupů neopakuj; ověř discovery/count.

Neaplikuj produkční migrace, nepřeváděj skutečné plánky/objednávky, nenasazuj,
nepublikuj balíčky, neposílej skutečné e-maily, necommituj ani nepushuj bez
samostatné autorizace. Na konci uveď finální kontrakt, opravené scénáře,
odstraněné cesty, skutečné výsledky a přesné neprovedené provozní kroky.
