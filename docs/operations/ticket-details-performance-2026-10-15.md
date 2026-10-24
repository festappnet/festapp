# Výkon get_tickets_with_details na různých událostech

Aktualizace po release: jediný index `eshop.spots_order_product_ticket_idx`
je nasazený, validní a publikovaný v main (`36228be39`). Produkční objednávka
700 vstupenek klesla z 1 927-1 982 ms na 547-569 ms; 14 vstupenek ze 153-164 ms
na 8-11 ms. Podrobný před/po doklad:
`docs/operations/spots-ticket-index-release-2026-10-15.json`.

Datum: 2026-10-15. Výsledek: současná pomalost je reprodukovatelná na velké
objednávce; nejde pouze o neurčitou historickou statistiku. Neznáme ale
objednávky, které vytvořily původní agregát 3 539 volání s průměrem 1,8 s.

## Produkční měření

Přístup přes ověřený SSH alias, canonical endpoint a databázi; tenant
`festapptickets` má v `origin/prod/festapptickets:automation/project.conf`
organization 3 a živý `https://vstupenky.online/backend-activation.json`
potvrdil canonical generation 1. Organization byla ověřena v databázi.
Čtení v explicitních read-only transakcích s timeoutem, sekvenčně, bez HTTP,
odesílání e-mailů nebo vracení zákaznického JSON do logu.

Pro každou z šesti událostí byla zvolena objednávka s nejvyšším počtem
vstupenek; dva přímé SQL běhy. Nejde o průměr všech objednávek ani o p95.
Každé volání opravdu vrátilo níže uvedený počet vstupenek.

| Událost (occasion ID) | Vstupenky | Produkty celkem | SQL první / druhý běh |
|---|---:|---:|---:|
| Farní ples (92) | 8 | 8 | 20,43 / 16,93 ms |
| Skautský ples 2025 (13) | 14 | 42 | 152,84 / 166,22 ms |
| Archiv - Ples obce Větřkovice 2025 (19) | 14 | 28 | 55,94 / 55,49 ms |
| Skautský ples 2026 (82) | 14 | 42 | 81,86 / 80,44 ms |
| Sportovní ples Větřkovice 2026 (111) | 14 | 28 | 54,64 / 65,24 ms |
| r48vetrkovice (877055) | 700 | 700 | **1 820,74 / 1 894,39 ms** |

Událost r48vetrkovice má jednu objednávku obsahující všech 700 vstupenek.
Odpověď RPC je 188 893 B JSON. Snapshot objednávky má uloženou velikost
11 646 B (komprimovaná hodnota, nikoli velikost rozbaleného JSON).
Malé dříve zkontrolované objednávky organization 1 vracely jednu vstupenku
za 3,89-8,28 ms. Velikost a struktura objednávky vysvětlují rozdílné chování
lépe než samotný název události.

Přímé SQL nezahrnuje síť, PostgREST wrapper, PDF přílohy ani dobu odesílání.
Neprokazuje proto celkovou latenci emailového workflow.

## Prokázaná práce v plánu

Tělo živé funkce odpovídá `origin/main` (`6d92dc29a`), md5 prosrc
`499b71423300179037129d731d58d9f4`. Produkční PostgreSQL 17.6, JIT zapnutý,
`jit_above_cost=100000`. SQL definice neobsahuje zápisy.

- r48vetrkovice: vnitřní SELECT pod EXPLAIN ANALYZE prochází celou tabulku
  `eshop.spots` s 18 569 řádky **700krát**, přibližně 13 milionů zpracovaných
  řádků. Tento scan trvá přibližně 1,503 ms na opakování v instrumentovaném
  plánu. Opakují se i průchody JSON objednávky a blueprintu.
- Skautský ples 2025: 14 vstupenek, 42 produktových vazeb, dva blueprinty na
  události. Scan téže tabulky sedadel běží **84krát**; Unique nakonec vrátí
  jen 14 vstupenek. Produktové vazby a join blueprintů násobí práci před
  konečným odstraněním duplicit.
- Na produkci existuje index `order_product_ticket(ticket,id)` a vnitřní
  lookup jej používá. Indexy na `spots(order_product_ticket)` a
  `order_product_ticket("order")` nebyly nalezeny.
- Instrumentovaný vnitřní SELECT trval 3 434 ms u 700 vstupenek a 293 ms u
  Skautského plesu 2025. Nezaměňovat s běžnými SQL časy výše: EXPLAIN ANALYZE
  přidává měřicí režii, zejména při množství malých opakovaných uzlů. JIT se
  v zaznamenaném plánu 700 vstupenek neobjevil.

## Izolovaná simulace

Reprodukce: `python3 automation/benchmarks/ticket_details_scaling.py`.
Skript vytvoří vlastní databázi s náhodným jménem v existujícím lokálním
PostgreSQL kontejneru a po skončení ji odstraní. Ostatní databáze nemění.
Používá přesnou funkci z origin/main a redukované tabulky pouze s jejími
čtenými sloupci. Nejde o plnou integrační simulaci RLS, celé aplikace či HTTP.

Pozadí: 10 000 produktových vazeb jiných objednávek, 18 569 jiných sedadel,
48 jiných blueprintů. Mění se velikost jedné objednávky, počet jejích produktů,
velikost blueprintu a počet blueprintů na události. Každá varianta má první
volání a tři další měření; tabulka uvádí medián těch tří. První volání není
garantovaně diskově studené. Výsledky nejsou přímo přenositelné na produkční
hardware: lokální PostgreSQL je 15.8, JIT on, stejný práh 100000.

Závěrečný experiment rozlišuje oba lookup indexy jednotlivě i společně,
bez změny SQL funkce. Před každou variantou se experimentální indexy odstraní;
vstupní data jsou stejná. Níže je poslední úplný běh, který nahrazuje dřívější
zkušební běh se 16 variantami.

| Vstupenky | Produkty na vstupenku | Objekty blueprintu | Blueprinty na události | Dnešní indexy | Jen order lookup | Jen spot lookup | Oba |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1 | 0 | 1 | 0,93 ms | 0,72 ms | 0,45 ms | 0,26 ms |
| 14 | 1 | 0 | 1 | 8,15 ms | 7,91 ms | 0,57 ms | 0,51 ms |
| 14 | 3 | 0 | 1 | 22,77 ms | 22,29 ms | 1,33 ms | 1,12 ms |
| 14 | 3 | 250 | 1 | 23,15 ms | 23,04 ms | 1,71 ms | 1,54 ms |
| 14 | 3 | 250 | 2 | 44,82 ms | 44,34 ms | 2,48 ms | 2,26 ms |
| 100 | 1 | 700 | 1 | 56,11 ms | 56,01 ms | 5,66 ms | 5,49 ms |
| 700 | 1 | 0 | 1 | 428,85 ms | 434,44 ms | 74,96 ms | 75,80 ms |
| 700 | 1 | 700 | 1 | 474,95 ms | 487,13 ms | 121,23 ms | 112,09 ms |

Samotný `spots(order_product_ticket)` řeší dominantní práci. Samotný
`order_product_ticket("order")` nezlepšuje naměřený problém velkých objednávek;
rozdíl 475 vs 487 ms zde není důkaz regrese, protože jde o tři vzorky na
sdíleném vývojovém stroji. Přidávat tento druhý index jen kvůli této funkci
není naměřeným přínosem odůvodněné. Varianta pro 700 míst má spot index
417 792 B, přibližně 408 KiB; to je lokální syntetická velikost, nikoli
změřená velikost dosud neexistujícího produkčního indexu.

Strojové výsledky včetně prvních a všech dalších měření:
`docs/operations/ticket-details-synthetic-2026-10-15.json`.
Poslední běh dokončil všech 32 variant a po dokončení nezůstala žádná
`ticket_perf_*` databáze.

### Shoda výsledků a architektonické omezení

Ve všech variantách zůstal počet vstupenek i obsah všech JSON polí shodný.
U více produktů změna plánu po přidání indexů změnila pořadí vnořeného pole
`order_product_ticket`, které dnes nemá ORDER BY. Benchmark proto výslovně
zaznamenává shodu obsahu zvlášť od shody pořadí, neoznačuje tyto výstupy za
bajtově totožné. První běh benchmarku tuto odlišnost zachytil striktní kontrolou.

Renderer `supabase/functions/_shared/ticketRenderData.ts: normalizeTicketData`
v aktuálním origin/main tyto položky před použitím řadí podle ID. Dohledaný
produkční caller RPC je větev `order_tickets` v `emailRenderer.ts`, která volá
`prepareTicketRenderer` a následně tentýž `normalizeTicketData`.

Nový regresní test v `ticketRenderData_test.ts` ověřil všech šest permutací
tří produktových vazeb včetně konfliktu dvou produktů stejného typu a dvou
skupin sedadel. Normalizovaná tisková data jsou shodná, vybraná skupina sedadel
i historický produkt jsou stabilní podle ID a vstupní pole se nemění.
Příkaz `deno test --allow-env --allow-net --allow-read supabase/functions/_shared/ticketRenderData_test.ts`
skončil `6 passed, 0 failed`, včetně existujícího testu skutečného PDF renderu.
Test i benchmark jsou zatím pracovní změny, nikoli publikace do main.
Nejde o důkaz všech možných externích konzumentů veřejně dostupného RPC.

## Doporučený další krok

1. Připravit nejmenší změnu: index na `eshop.spots(order_product_ticket)`.
   Samostatný přínos je již doložen. Před produkcí ověřit běžným lokálním
   integračním postupem dopad na zápisy/rezervace a naplánovat schválenou
   migraci s opětovnou kontrolou aktuálního produkčního schématu. Neukládat
   duplicitní index, pokud jej mezitím přidá jiná změna.
2. Zachovat funkci a renderer. Vnitřní pořadí produktů SQL negarantuje,
   současný renderer již používá stabilní ID a nový test to ověřil.
   Výběr názvu stolu u více blueprintů se tímto nemá nově definovat;
   případný pozdější SQL přepis jej musí řešit vědomě.
3. Teprve pokud zbývající čas velkých objednávek nestačí cíli, upravit stejnou
   kanonickou SQL funkci: nejprve vybrat unikátní vstupenky a poté vypočítat
   jejich detaily; rozložit objednávkový JSON jednou pro celou objednávku.
   Zachovat uložené ceny a měny, žádný nový cache ani paralelní RPC.

V diagnostické fázi nebyl na produkci vytvořen žádný index, změněna funkce
ani odeslán email. Následný autorizovaný release přidal pouze spot index;
funkce zůstala bitově shodná. U 700 vstupenek je shodný i obsah odpovědi.
U Skautského plesu 2025 se liší pouze `table_title`: force_generic_plan nyní
reprodukuje původní hash, force_custom_plan nový. Ostatní obsah je shodný.
Toto pole se dvěma blueprinty nemá jednoznačný výběr již v původním SQL
a současný tiskový renderer jej nečte. Nejde o důvod přidávat další změnu
do release indexu; při případném budoucím SQL přepisu se musí jeho význam
definovat explicitně.
Historický průměr 1,8 s nyní máme čím vysvětlit jako možný velikostní případ,
ale stále jej nelze forenzně připsat konkrétní události bez per-request historie.
