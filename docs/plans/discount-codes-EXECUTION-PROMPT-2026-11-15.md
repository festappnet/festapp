# Implementace slevových kódů

Pracuj v `/Users/miakh/source/festapp`. Nejdříve přečti platné `AGENTS.md`,
`CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/discount-codes-plan-2026-11-15.md`

Cíl: pořadatel spravuje slevové kódy a zákazník je použije ve Flutteru i webovém
checkoutu. SQL atomicky vlastní nárok, výpočet, rozpad ceny a limit použití.
Objednávka, platební metoda, fakturace, e-maily, report a měření musí souhlasit.
Součástí implementace je aktualizace uživatelské CZ/EN nápovědy v
automation/release/help/: zapnutí feature, správa a použití kódů, zobrazení
v přehledu objednávky, limity a refundace. Aktualizuj související návody,
navigaci a vyhledávání; ověř odkazy a shodu se skutečným UI. Nové screenshoty
musí mít light mode a UI i příklady v jazyce návodu. Bez nápovědy není hotovo.
Slevové kódy jsou samostatná occasion extra feature `discount_codes`, výchozí
vypnutá; server ji vynucuje a vypnutí zachovává již přiznané slevy a historii.

Postupuj po etapách plánu v režimu `verification: standard`. Nezaváděj druhý
cenový nebo platební engine, fallbacky ani veřejné výpisy kódů. Zachovej známé
hranice záloh, čekací listiny, předtištěných vstupenek a editace objednávek.
Pokud aktuální důkaz vyvrátí předpoklad plánu, oprav plán i příslušnou etapu.

Hotovo vyžaduje cílené SQL/Edge/JS/Flutter kontroly včetně souběhu a retry,
odstranění dočasných cest a připravenou migraci se zdokumentovanými omezeními.
Respektuj jediný souběžný Flutter task na workstationu. Bez další autorizace
neprováděj commit, push, produkční migraci, release ani aktivaci funkce.
