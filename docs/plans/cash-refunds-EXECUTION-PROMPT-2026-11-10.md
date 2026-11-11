Implementujte celý autoritativní plán v /Users/miakh/source/festapp:

docs/plans/cash-refunds-plan-2026-11-10.md

Nejdříve přečtěte AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a plán v plném znění. Zkontrolujte aktuální větev a rozpracované změny; chraňte práci ostatních. Faktický omyl v plánu opravte podle kódu a pokračujte se zachováním cíle.

Cíl: sjednocená platební architektura pro příjem i vrácení peněz, jeden registr a capability kontrakt pro cash/bank/externí konektory, stejné mínusko vedle pluska, správné finanční projekce a odstraněné nahrazené interní cesty. Bankovní QR používá původní VS, EUR původní uloženou referenci. Nevydávejte další platební reference. Cash potvrzuje skutečný záporný ledger zápis, banka skutečný BankSync debit, externí adaptér ověřená fakta své původní platby. Příprava není potvrzený výdej.

Pracujte tokenově efektivně:

- Využijte důkazy a mapu souborů z plánu. Udělejte jeden cílený průchod aktuálním kódem; další čtení jen kvůli konkrétní nejasnosti. Používejte scoped rg a krátké výřezy, nezávislá čtení dávkujte. Neopakujte celou architektonickou rešerši.
- Postupujte podle závislostí plánu. Každou ucelenou změnu dokončete před ověřováním. Kontroly shromážděte do nejmenšího smysluplného počtu dávek, ne po každém editování. Passing check opakujte jen po změně jeho vstupů nebo novém důkazu problému. Úspěšný výstup stručný, úplné logy čtěte jen při chybě.
- Ověřování zůstává standard: finance, oprávnění, přesnost, souběh, idempotence, recovery, původní VS a společné contract tests. Použijte existující owning suites a přidejte pouze testy skutečných invariantů. Dodržte jediný Flutter task a --concurrency=1. Před případnou publikací platí povinné canonical CI lanes.
- Nezadávejte opakované obecné agent audity. Delegaci používejte podle AGENTS.md a skutečné potřeby; subagentům předávejte krátké konkrétní zadání. Browser kontroly izolované, ztlumené a světlé dle pravidel.
- Nezavádějte druhý engine/registry, spekulativní fallbacky, business triggery, fake capability ani obecný workflow framework. Rozšiřujte současné owners. Veřejnou kompatibilitu ponechte jako tenké adaptéry podle plánu; nahrazené interní cesty odstraňte.

Pokračujte autonomně přes všechny implementační vlny a potřebné ověření. Dokončení vyžaduje převod incoming i outgoing volajících, registrací a projekcí, důkaz odstranění starých cest a pravdivé vymezení nepodporovaných operací. Průběžné zprávy stručné, bez opakování plánu. Ptejte se pouze na skutečně chybějící rozhodnutí nebo oprávnění.

Rozsah této úlohy: lokální implementace a ověření. Neprovádějte commit/push, produkční migrace/deploy, aktivaci dalších tenantů ani skutečné vrácení peněz. V závěru nejvýše pět krátkých bodů: výsledek sjednocení, převedené/odstraněné cesty, ověření a přesné zbývající kroky či blokery. Úspornost nemění rozsah ani požadované finanční kontroly.
