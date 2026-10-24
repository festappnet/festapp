# Prověření výkonu get_tickets_with_details

> Historical plan or dated evidence. Statuses, versions, authorization and pending steps below apply to the recorded phase, not automatically to today. Use [current documentation](../../README.md) for operating procedures; archiving does not close unverified gates.


Datum: 2026-10-15
Stav: diagnostika a autorizovaný release jediného spot indexu dokončeny
Verification: standard (produkční diagnostika a kontrakt SQL RPC)

Dokončeno v main `36228be39`, migrace `20261016010000` je na canonical
produkci zaznamenaná a index validní. Produkční výsledek 700 vstupenek
1,93-1,98 s před / 0,55-0,57 s po; 14 vstupenek 153-164 ms před / 8-11 ms po.
Úplný validační runner exit 0, 188 SQL a 1 484 Flutter testů prošlo;
27 externích integračních testů bylo dle konfigurace přeskočeno.
Funkce ani renderer se neměnily. Evidence a známá původní nejednoznačnost
pole table_title jsou zaznamenány v
`docs/operations/spots-ticket-index-release-2026-10-15.json`.
Následující vlny zachycují původní postup; neautorizují opakované nasazení.

## Výsledek a rozsah

Zjistit, zda historické sekundové časy `public.get_tickets_with_details(order_id BIGINT)`
stále popisují skutečný provoz, které velikosti objednávek
postihuje a jakou nejmenší změnou jej odstranit bez změny výsledného JSON,
oprávnění, cen a obsahu vstupenek. Výstupem diagnostiky budou srovnatelná
měření a prokázaná příčina, případně důkaz, že historická čísla již nepopisují
současnou implementaci. Tento dokument sám neautorizuje implementaci ani
produkční migraci, nasazení, commit nebo push.

Mimo rozsah jsou změny e-mailové fronty, nákup silnějšího serveru, plošné
indexování a publikace rozpracované optimalizace testů.

## Potvrzená evidence

- Produkční diagnostika 2026-10-15: queryid `-7775119372242789916`,
  3 539 volání, průměr 1 807,11 ms, maximum 3 027,43 ms. Normalizovaný
  SQL identifikuje PostgREST volání právě `get_tickets_with_details`.
- `extensions.pg_stat_statements_info.stats_reset` je 2026-08-27.
  To není měření dnešního provozu ani dnešní verze funkce a neobsahuje p95.
  Datum globálního resetu není datum prvního nebo posledního volání této položky.
- V okamžiku kontroly nebyly blokované relace; cache databáze měla 99,94 %.
  Tato jednorázová pozorování nevylučují zámky nebo I/O při starších voláních.
- `database/functions/eshop/get_tickets_with_details.sql`: korelované průchody
  `ord.data->'tickets'` a produktů pro cenu i měnu; pro sedadla další průchody
  JSON blueprintu. Join blueprintů podle occasion předchází `DISTINCT ON (t.id)`.
  Jsou to kandidáti, nikoli prokázané příčiny.
- `supabase/functions/_shared/emailRenderer.ts: renderQueuedEmail`, větev
  `order_tickets`, volá RPC přes `emailQueueClient.ts: emailRpc` a service client.
  Potom filtruje storno a případně renderuje PDF. SQL čas nezahrnuje PDF,
  síťové přenosy ani odeslání zprávy.
- `database/tables/tables.sql` již deklaruje index
  `order_product_ticket_ticket_id_idx (ticket, id)`; jeho existence i použití
  ve vnitřním SELECT byly ověřeny na produkci. Nepřidávat duplicitní index.
- Související test: `database/tests/eshop_orders/waitlist_ticket_action_guards_test.sql`
  ověřuje vyřazení čekajících vstupenek z tohoto RPC.
- Další historicky nákladný dotaz `-1523633682828245113` čte metadata typů
  a funkcí: 601 855 volání, průměr 36,96 ms. Jeho frekvenci sledovat ve stejném
  časovém okně, ale neplést s pomalým RPC. `COPY auth.audit_log_entries TO stdout`
  patří exportům, samo o sobě nedokazuje pomalost uživatelského požadavku.

## Výsledek opakované kontroly 2026-10-15

### Git a skutečně nasazená verze

Po novém fetch zůstává `origin/main` na `6d92dc29a`. Historie této funkce:

| Commit | Datum | Skutečná změna |
|---|---|---|
| `49e8e771b` | 2026-01-20 | Přidání původní funkce včetně dnešních JSON subdotazů. |
| `fa897ce4b` | 2026-02-14 | Nastavení search_path. |
| `100fda11f` | 2026-02-14 | Oprava search_path, nikoli přepis dotazu. |
| `280c70281` | 2026-10-13 | Vyřazení čekajících vstupenek a vstupenek bez symbolu. |

V této historii není samostatná výkonová oprava. To nevylučuje změnu plánu,
dat, indexů, PostgreSQL nebo navazujících volání. Index `(ticket,id)` byl
přidán do schématu commitem `72c5102414` dne 2026-08-05, tedy před globálním
resetem statistik. Není důkazem opravy těchto později zaznamenaných pomalých volání.

`md5(pg_proc.prosrc)` živé funkce je `499b71423300179037129d731d58d9f4` a
shoduje se s přesným tělem funkce z aktuálního upstream main. Funkce je
SECURITY INVOKER. Nejde tedy o zjevný drift těla SQL proti main.

### Historická statistika a čerstvá měření nejsou totéž

- Původní sonda přibližně 18:02 UTC: 3 539 PostgREST volání, průměr 1 807,11 ms.
- Kontrola 18:12:51 UTC a 18:14:10 UTC: stále 3 539 volání a shodný
  `total_exec_time = 6395348.84951101` ms. V tomto pozorovacím okně nepřibylo
  žádné přirozené volání tohoto queryid. Datum jeho posledního staršího volání
  z těchto agregátů nelze zjistit.
- Statistiky jsou pro celou kanonickou databázi, nikoli pouze organization 1.
  Původních 3 539 volání nelze připsat tenantovi Festapp ani malým objednávkám.
- Po ověření read-only těla funkce proběhla čtyři omezená SQL volání na dvou
  objednávkách organization 1, bez vrácení zákaznických údajů do logu:

| Výběr | Vstupenky / produkty | SQL první / druhý běh | Výstup |
|---|---|---|---|
| Nejnovější malá objednávka | 1 / 1 | 8,28 / 4,29 ms | 1 vstupenka, 258 B JSON |
| Objednávka s nejvyšším počtem vstupenek v tomto tenantovi | 1 / 1 | 3,89 / 3,91 ms | 1 vstupenka, 253 B JSON |

V organization 1 nebyl nalezen vzorek s 3-15 vstupenkami; ani největší místní
objednávka nemá více než jednu. Tyto vzorky neověřují velké objednávky,
sedadlové akce ostatních tenantů ani skutečnou latenci přes PostgREST.
Přímé SQL sondy navíc nepřidávají přirozená volání do původního wrapper queryid.

### Co již říká skutečný plán

Jednorázový `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` přesného vnitřního
SELECT na nejnovější vzorové objednávce: execution 5,139 ms, planning 1,747 ms.
Příprava byla read-only, s timeoutem 8 s; neproběhla žádná změna funkce/dat.

- Vnější `order_product_ticket`: sekvenční scan, 1 nalezený a 10 210
  vyřazených řádků, 0,687 ms.
- `spots`: sekvenční scan 18 569 řádků, 1,755 ms.
- Vnitřní `order_product_ticket`: používá index, 0,010 ms.
- `blueprints`: sekvenční scan 49 řádků, 0,102 ms.

To ukazuje kandidáty pro škálování, nikoli samo o sobě chybný plán nebo
sekundový problém. Scan může být pro malou tabulku levnější než index.
Na produkci jsou pro tyto tři tabulky pouze primární klíče a uvedený
`(ticket,id)` index; index na `order_product_ticket("order")` nebo
`spots(order_product_ticket)` nalezen nebyl. Jejich případný přínos je nutné
prokázat lokálním srovnáním v reálných velikostech, ne automaticky nasadit.

### Rozhodnutí po kontrole

Následné měření na šesti událostech organization 3 a izolovaná simulace
velikostí 1-700 vstupenek již doplnily reprezentativnější současné vzorky.
Podrobná autoritativní evidence je v
`docs/operations/ticket-details-performance-2026-10-15.md`, strojové výsledky
v sousedním `ticket-details-synthetic-2026-10-15.json` a reprodukce v
`automation/benchmarks/ticket_details_scaling.py`.

Malé ověřené objednávky nyní sekundové SQL časy nevykazují, ale objednávka
700 vstupenek na r48vetrkovice běží 1 820,74 / 1 894,39 ms. Nejde tedy jen
o hypotetickou minulost. Prokázány jsou opakované celé scany sedadel (700krát)
a u 14 vstupenek se 3 produkty a dvěma blueprinty dokonce 84 scanů.
Následný úplný experiment již porovnal 32 variant včetně každého indexu
samostatně: 700 vstupenek se sedadly 474,95 ms baseline, 487,13 ms pouze
order lookup, 121,23 ms pouze spot lookup, 112,09 ms oba. Nejde o příslib
produkční latence, protože lokální hardware i PG verze se liší.

Implementační rozhodnutí: nejmenší doložená změna je samotný index
`eshop.spots(order_product_ticket)`; druhý index není kvůli tomuto problému
odůvodněný. Změnu pořadí vnořených produktů test pokryl všemi šesti permutacemi
a ověřil stabilní tisková data, produkt i skupinu sedadel. Cílená Deno sada:
6 passed, 0 failed. Současný tiskový renderer řadí podle ID a nemá se měnit.
Před produkční migrací zbývá ověřit dopad na skutečný write/rezervační kontrakt
izolovaným integračním postupem. Migrace indexu má přednost před přepisem RPC;
případný druhý krok odstraní násobení práce a opakovaný rozklad JSON ve
stejné funkci. Historický agregát stále nelze připsat konkrétní události.

## Postup

### 1. Ověřit aktuální implementaci a čerstvá čísla

1. Přečíst pravidla repozitáře a skill `festapp-backend-access`. Přes projektovou
   konfiguraci a živý activation dokument ověřit canonical tenant, generaci,
   hostname a runtime databázi. Použít `ssh festapp-backend-agent`.
2. V `BEGIN READ ONLY` se `statement_timeout` získat definici funkce,
   její hash, režim security, grants a relevantní indexy. Porovnat s čerstvým
   `origin/main` i pracovní kopií. Nesrovnávat různé definice jako stejnou verzi.
3. Dvakrát zachytit pro daný queryid `calls`, `total_exec_time`, `rows`,
   bloky a dočasné zápisy v zaznamenaném provozním okně. Z rozdílu spočítat
   průměr nových volání; při nulovém přírůstku napsat „bez nových vzorků“.
   Globální statistiky neresetovat. p95 odvodit jen ze skutečných jednotlivých
   měření, ne z agregovaného průměru či maxima.
4. Zaznamenat stejné přírůstky pro dotaz metadat. Pokud běží nadměrně často,
   určit původ a důvod obnovování schema cache samostatně, bez zásahu do služeb.

Výstup: definice a verze skutečně měřeného SQL, časové okno, čerstvý počet
volání a oddělení historických a aktuálních dat. Produkční diagnostika nesmí
odeslat e-mail ani opakovaně spustit worker.

### 2. Rozlišit velikost vstupu a konkrétní náklad

1. Navázat na výše zaznamenané měření, neopakovat ho bez změny vstupů.
   Pro další tenant nejprve ověřit jeho canonical konfiguraci, activation a
   organization; povolení diagnostiky backendu neznamená povolení zápisů.
   Vybrat jen několik anonymně popsaných vzorků: běžná
   malá objednávka, více vstupenek/produktů, sedadla s velkým blueprintem a
   dostupný větší případ. Zapisovat počty a velikosti JSON, nikoli zákaznické údaje.
2. Již provedená bounded produkční sonda slouží jako základní ověření současnosti.
   Další velikostní experimenty a srovnání variant provést nejprve
   na izolované lokální databázi se syntetickými daty; změřit funkci
   a vnitřní SELECT zvlášť. Použít `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`
   a zaznamenat počet opakování subplánů, řádky před DISTINCT, sekvenční scany,
   náklady JSON a velikost výsledku. Vnější plán PL/pgSQL funkce nemusí vnitřek ukázat.
3. Produkčně případně doplnit pouze chybějící reprezentativní případy malým
   počtem sekvenčních read-only měření, pokud
   předchozí kontrola definice vyloučí vedlejší účinky; nastavit krátký timeout.
   Timeout je výsledek, nikoli důvod ke zvyšování limitů a bombardování serveru.
4. Oddělit SQL od serializace/HTTP a PDF. Pro HTTP použít bezpečný lokální
   ekvivalent nebo existující anonymizovanou telemetrii; neexportovat service key.
   Získat velikost odpovědi a čas bez spuštění skutečného odeslání.

Výstup: dominantní uzel plánu a škálování s velikostí vstupu, nebo výslovné
vyvrácení SQL hypotézy. Změnu nesmí odůvodňovat pouze vzhled zdrojového kódu.

### 3. Navrhnout nejmenší opravu podle důkazu

- Pokud dominuje opakovaný rozklad objednávky, připravit variantu s jedním
  rozkladem a agregací podle ticket ID, zachovat cenový snapshot v `orders.data`.
- Pokud dominuje blueprint JSON, omezit rozklad na skutečně použité blueprinty
  a sdílet výsledek mezi vstupenkami stejné objednávky.
- Pokud dominuje násobení řádků nebo chybějící index, prokázat přesný join/index
  plánem. U více blueprintů nejprve zjistit pravidlo výběru názvu stolu;
  dosavadní `DISTINCT ON` nesmí být nahrazen svévolným pravidlem.
- Porovnat nejprve minimální variantu indexu s přepisem SQL. Index musí mít
  doložený dopad na zápisy a místo; přepis musí mít doloženou shodu výstupů.
  Vybrat jednu nejmenší účinnou změnu, ne přidat všechny možné optimalizace.
- Pokud současné malé objednávky rychlé jsou, neprovádět preventivní refaktor.
  Zdokumentovat historický původ či velikostní mez a případné další měření.

Kandidát patří do stejné kanonické funkce. Žádné druhé RPC, cache finančních
údajů, nový trvalý trigger ani kopie logiky v Edge Function. Existující kontrakt
zahrnuje NULL/prázdné případy, pořadí podle ticket ID, identitu a stav vstupenek,
produkty, cenu, měnu a názvy sedadel. U vnořených polí bez ORDER BY nejprve
ověřit, zda jejich pořadí používá renderer.

Výstup: naměřené zdůvodnění konkrétní změny a přesný seznam souborů/migrace.
Před implementací je potřeba samostatné zadání; před produkcí schválený SQL
release postup, nikoli ruční editace databázové funkce.

### 4. Podmínky ověření případné implementace

- Doplnit SQL regresi skutečných rizik: více produktů, snapshot ceny a měny,
  sedadla, více blueprintů, NULL/prázdný výsledek, čekající/storno vstupenky
  a existující přístupová práva. Porovnat výstupy původní a nové verze lokálně.
- Na stejných datech, definici prostředí a opakováních porovnat medián,
  rozptyl, práci s bloky a růst s velikostí vstupu; oddělit cold/warm výsledky.
  Nezakládat běžný CI test na křehkém absolutním časovém limitu.
- Nestanovovat absolutní limit bez velikostního profilu a produktového důvodu;
  samotný takový limit neodůvodňuje refaktor. Ověřené malé produkční případy
  již mají jednotky ms. Pokud je jiný současný případ reprodukovatelně pomalý,
  před úpravou stanovit přiměřený velikostní cíl z jeho baseline a doložit
  zlepšení i žádnou materiální regresi ostatních velikostí.
- SQL test spustit podporovaným runnerem na disposable DB:
  `node web_client/scripts/run_db_tests.js database/tests/eshop_orders/ticket_details_contract_test.sql`.
  Jde o navržený nový soubor pro případnou implementaci. Při změně rendereru dohledat a
  spustit jeho existující cílené testy. Žádné produkční fixtures nebo odesílání.
- Po případném samostatně autorizovaném release zopakovat bounded read-only
  sondu, ověřit hash definice a čerstvé statistiky. Návrat znamená obnovu
  předchozí kanonické SQL definice schválenou migrací.

Hotovo je až při doložené příčině nebo jejím vyvrácení, funkčně shodném
výsledku případné opravy, srovnatelných měřeních a výslovném stavu nasazení.
Do dokončení zůstává nejistota historické verze funkce a skladby objednávek.

## Samostatné zjištění: optimalizace testů není v main

Ověřeno po `git fetch origin main` dne 2026-10-15 proti
`origin/main = 6d92dc29a`. Lokální větev `main` je starší a není podkladem závěru.
V upstream main nejsou `automation/test_client.sh`, `automation/test_client.py`,
`automation/client_test_inventory.py`, inventář/klasifikace ani
`test/support/register_client_suites.dart`. V pracovním stromu jsou untracked;
také `packages/festapp_core/pubspec.yaml` a runner contract test jsou untracked.
Aktuální upstream `test_all.sh` tento nový runner nevolá.

Předchozí optimalizaci tedy nelze označit za publikovanou. Její bezpečné
dokončení je samostatná práce: vymezit celou závislostně uzavřenou změnu včetně
core extrakce a změněných callerů, zachovat jiné rozpracované změny, porovnat
s čerstvým main, vyřešit souběžné opravy propagace selhání v `test_all.sh`,
ověřit úplný inventář skutečně spuštěných případů a spustit konečný runner
na finálních souborech. Teprve pak změnu publikovat podle pravidel repozitáře.
Tento plán ani tato kontrola nejsou důkazem, že celá lokální optimalizace prošla.

Také dřívější změna okamžitého úklidu záloh je nasazená na serveru a má
ověřený živý běh, ale při této kontrole ještě není v upstream main.
