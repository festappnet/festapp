# Implementuj čisté Dart jádro a rychlé testy klienta

Pracuj v `/Users/miakh/source/festapp`. Přečti `AGENTS.md`, `CLAUDE.md`,
`docs/architecture/ai_context.md` a celý autoritativní plán:

[flutter-test-architecture-plan-2026-10-15.md](flutter-test-architecture-plan-2026-10-15.md)

Implementuj jeho vlny v pořadí s ověřováním `standard`. Výsledek musí mít
jednu produkčně používanou implementaci čisté logiky v `packages/festapp_core`,
Dart testy bez Flutteru, explicitní platformní adaptéry, scoped fixture,
úplný klientský runner a odstraněné staré cesty podle ledgeru.

Začni vlnou 0: respektuj rozsáhlé cizí rozpracované změny, obnov aktuální
baseline a vyřeš známý pád testu odloženého mazání zpětné vazby. Historická čísla
185/108/84/74 sekund jsou jednotlivá měření, nikoli garantovaný benchmark.
Při přesunech zachovej semantický inventář všech testů, aserce a scénáře.

Změň skutečná produkční volání, ne pouze importy testů. Nenechávej druhé modely,
forwarding shimy, test-only produkční přepínače, globální DI/reset framework ani
placeholdery. Neměň SQL autoritu, wire/storage kontrakty, identity fencing,
atomické aktivace, retry, ceny, timezone či offline chování.

Dodrž povolený směr závislostí mezi core moduly. Čistá doména neimplementuje
`ITrinaRowModel`; konkrétní aplikační grid records připojí existující grid
a command moduly, bez přepisování celého grid frameworku. Vyřeš vlastnictví
snapshotů a draftů, cyklus produkt/type a nemutující wire codec. Nezaváděj
paralelní mutable reprezentace, které vyžadují vzájemnou synchronizaci.

Úplný runner a první purity/inventory guard zaveď ve vlně 1 ještě před přesunem
prvního testu. Vlnu 3 proveď po vertikálních řezech 3a-3d; každý přepojí skutečné
produkční spotřebitele a odstraní starou cestu. Samotný čistý Dart/IO adaptér
nepotřebuje Flutter; jeho případný root `test_dart` musí být zahrnut v `all`.

Pokud aktuální kód vyvrátí fakt v plánu, uprav autoritativní plán s konkrétním
důkazem a přizpůsob dotčenou vlnu při zachování výsledku. Neprováděj nový audit
celého projektu a nespouštěj nezávislý review nebo subagenty bez výslovného zadání.

Ověřuj koherentní řezy cílenými kontrakty; úplnou sadu a opakovaný benchmark
spusť na finálních vstupech podle plánu. Celý příkaz musí zahrnovat všechny Dart
i Flutter test roots a propagovat selhání každého. Cíle jsou warm medián do 40 s pro celek a do 5 s
pro core na referenčním stroji; nedosažení reportuj, neskrývej vynecháním testů.

Neprováděj produkční operace, migrace, deployment, commit ani push bez dalšího
zadání. Při předání stručně uveď produkční změny, odstraněné staré implementace,
pokrytí, výsledky, benchmark a zbývající konkrétní překážky.
