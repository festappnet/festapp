Implementujte zrychlení a škálování notifikačního centra ve Festapp.

Repozitář: `/Users/miakh/source/festapp`. Dodržujte AGENTS.md, CLAUDE.md a
`docs/architecture/ai_context.md`. Režim ověřování: `standard`.

Přečtěte celý autoritativní plán:
`docs/plans/notification-center-scalability-plan-2026-11-05.md`
a jeho podklady:
`docs/plans/notification-center-industry-research-2026-11-05.md`.

Proveďte lokální implementaci podle všech použitelných vln plánu. Začněte
vlnou 0: ověřte kontrakt, skutečné zapisující operace, konzistenci a algoritmus
malým spustitelným ověřením. Rozhodnutí doplňte do plánu a pokračujte
implementací; nekončete jen dalším návrhem. Před rozšířením na všechny typy
notifikací ověřte celý scénář objednávky včetně přečtení, storna, expirace,
změny viditelnosti, obnovení panelu a výběru souvisejících objednávek.

Výchozí řešení: průběžně udržované osobní souhrny v PostgreSQL, malé serverové
snímky panelu a aktuální kontrola oprávnění. Otevření nesmí znovu procházet
celou historii. Zachovejte přesné i neznámé počty, rozlišení viděno/přečteno,
vlastní aktivitu, částečné přečtení z více záložek a dnešní význam ztlumení.
Rozpracovaný přepočet má explicitní stav; nesmí vracet zastaralé soukromé údaje
ani potvrdit dosud nepřipravené notifikace. Starší vydané kontrakty zachovejte
pouze na výslovně zdokumentované hranici, bez fallbacku nového klienta.

Nejdřív zlepšete průběžné zpracování v krátkých transakcích, férovost a obnovu
po chybě. Paralelní workery přidejte podle měření. Nepřidávejte Redis, další
frontu ani aplikační triggery. Zachovejte předchozí opravu a cizí rozpracované
změny. Pokud důkazy ospravedlní jednodušší řešení, aktualizujte plán a pokračujte
s doloženým rozhodnutím.

Ověřte různé zákazníky, více příjemců, 1k/10k/100k doručení, souběh, vadnou
úlohu a trvalejší zátěž. Měřte cenu zápisů, čekání, připravenost souhrnů,
p95/p99 načítání a skutečný čas do zobrazení obsahu odděleně. Cíl 50 ms je
návrhový cíl, nikoli ověřený výsledek nebo průmyslová norma. Spusťte cílené
repozitářové kontroly, dodržte limit jedné Flutter úlohy a dokončete příslušné
SQL/parity/bezpečnostní kontrakty.

Výsledky a příkazy zapište do
`docs/plans/notification-center-scalability-RESULT-2026-11-05.md`.
Dokončete lokální změny a ověření bez potvrzování jednotlivých běžných kroků.
Neprovádějte produkční migraci, nasazení, commit, push ani šíření do dalších
tenantů. Na konci stručně uveďte změny, skutečná měření, testy, ponechané
starší kontrakty a přesné zbývající kroky k nasazení.
