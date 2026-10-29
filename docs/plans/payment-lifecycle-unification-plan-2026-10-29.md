# Jeden přepočet platebního stavu objednávky a vstupenek

Datum: 2026-10-29
Stav: Implementováno a ověřeno lokálně; produkční aplikace neprovedena
Ověřování: `standard` - finance, souběh a veřejné databázové kontrakty
Výchozí revize průzkumu: `f724f4aea103cb66fad65eb381db8fb15b6f2b17` (`main`)

## Výsledek a rozsah

Změna produktů a nové bankovní platební skutečnosti musí používat stejnou
rozhodovací logiku pro platební způsobilost objednávky a vstupenek. Zaplacená
záloha nezmizí pouhou editací produktu. Vznikne-li skutečný nedoplatek pod
příslušným prahem, běžné `paid/sent` vstupenky se vrátí do `ordered` stejně
jako při odpojení bankovní platby. Použité a zrušené vstupenky se nepřepisují.

Součástí je ochrana současné historie, atomických příkazů, opakování požadavků,
emailových intentů a veřejných odpovědí. Původní příprava doplnila testy a dokumentaci. Navazující implementace již
sjednotila aplikační SQL a připravila forward migraci. Lokální výsledek a přesné
brány jsou v [záznamu realizace](payment-lifecycle-unification-RESULT-2026-10-29.md).
Produkční nasazení není tímto plánem provedeno ani autorizováno.

Mimo rozsah jsou mazání/retence objednávek, veřejná neatomická příprava výměny
míst, změna granularit zámků pro výkon, nový účetní model, přepočet refundů,
historická oprava produkčních dat a redesign UI. Stripe si zachovává autoritu
provider faktů, refund/admission rozhodnutí i zákaz ruční změny ceny.

## Ověřený současný stav

| Fakt | Zdroj | Důsledek |
|---|---|---|
| Bankovní párování obnoví totals a zavolá přepočet objednávky. | `database/functions/eshop_transactions/apply_transaction_pairing.sql:61-72` | Zachovat atomický movement/pairing/transition commit. |
| Hlavní přepočet porovnává `paid` se zálohou, nebo s cenou bez zálohy. | `eshop_orders/recalculate_order_payment_status.sql:27-61` | Toto je výchozí význam zaplacené zálohy. |
| Editace produktů má vlastní výpočet proti celé ceně a synchronizuje vstupenky pouze směrem do `paid`. | `eshop_orders/update_ticket_products_ws.sql:195-232` | Tři reprodukované chyby v regresním testu. |
| Receipted příkaz i starší RPC dosahují stejného product-edit owneru. | `eshop_orders/update_ticket_products_client_sync_v1.sql:24`, `update_ticket_products_ws.sql:274-283` | Nestačí opravit pouze transport nebo UI. |
| Ruční označení jako zaplacené mění pouze stav; odeslání vlastní explicitní akce. | `eshop_orders/update_order_and_tickets_to_paid_ws.sql:20-21` | Ruční operaci nepřeměnit na automatické párování ani automatické odeslání. |
| Paid primitive chrání použité/zrušené vstupenky a Stripe provider guard. | `eshop_orders/mark_order_and_tickets_paid_internal_v1.sql` | Znovu použít tuto ochranu; nerozšířit zápisy na všechny stavy. |
| Přijetí emailu projektuje `sent` pouze pro aktuální `email_payment_version`. | `emails/email_domain.sql:72-94` | Starý email nesmí obnovit odvolanou platnost vstupenky. |
| Product edit drží form/order před platebním zápisem; pairing bere payment před pozdějším form/order přepočtem. | `eshop_waitlist/tickets.sql:15-20`, `update_ticket_products_ws.sql:34,186`, `apply_transaction_pairing.sql:47-66`, `eshop_transactions/payment_totals.sql:37` | Kandidát inverze zámků; povinný test se dvěma spojeními před nasazením. Nejde zatím o reprodukovaný deadlock. |

Zdroje v tabulce bez prefixu leží v `database/functions/`.

### Kontrakt historie, který je nutné zachovat

- Vytvoření zapíše jeden snapshot `ordered`, cenu/měnu a envelope
  `data.input_data` + `data.tickets`. Tento zavedený záznam není totéž jako
  současné `orders.data`; ani bezplatnou objednávku zpětně nepřepisovat.
  Owner: `eshop/finalize_ticket_order.sql:418-430`.
- Skutečná změna produktů zapíše právě jeden snapshot celého nového
  `orders.data`, finálního stavu, ceny a měny. Stejný command UUID ani nový
  příkaz s totožnými produkty nezapisuje další řádek.
  Owner: `eshop_orders/update_ticket_products_ws.sql:77-95,257-266`.
- Automatický přechod na `paid` a odpojení bankovní platby nyní nepřidávají
  snapshot do `orders_history`. Párování má svůj `transaction_pairing_events`.
  Zachovat tento rozdíl; nepřidávat při refaktoru pomocné mezistavy do historie.
- Přijetí ticket emailu přidá jeden snapshot `sent`. Opakování projekce další
  řádek nepřidá. Owner: `emails/email_domain.sql:72-103`.
- Zrušení přidá jeden snapshot `storno`, cenu 0 a prázdné `data.tickets`.
  Zachovat i dosavadní nullable měnu, autora a čas; neprovádět souběžný
  normalizační backfill. Owner: `eshop_orders/update_order_and_tickets_to_storno.sql:62-78`.
- Starší řádky se nikdy nepřepisují ani nemažou. `get_orders` zachová pole
  `id`, `order`, `order_symbol`, `order_sequence`, `created_at`, `created_by`,
  `data`, `state`, `price`, `currency_code` a stávající oprávnění.
  Pole historie v odpovědi nemá garantované pořadí; testy porovnávají podle ID.

## Rozhodnutí cílové architektury

**D1 - Jeden owner rozhodnutí.** Rozšířit současný modul přepočtu
`recalculate_order_payment_status.sql` o neveřejný
`reconcile_order_payment_internal_v1(p_order_id bigint, p_reason text)`.
Povolené důvody jsou přesně `payment_fact` a `product_edit`, ověřované uvnitř.
Veřejné podpisy se nemění: stávající `recalculate_order_payment_status(bigint)`
zůstane tenký adaptér pro `payment_fact`; product-edit owner zavolá stejný
interní owner s `product_edit`. Interní helper nemá klientské EXECUTE granty
a používá `SECURITY INVOKER`, `search_path=public,extensions`.

Owner vrátí interní strukturovaný výsledek obsahující předchozí/finální stav,
změnu způsobilosti a finální emailovou verzi. Není to nové veřejné RPC ani
nový stav uložený v tabulce. Selhání side effectu musí vyvolat výjimku,
aby vnější příkaz necommitnul částečnou změnu.

**D2 - Peníze zůstávají fakty stávajícího ledgeru.** Refaktor nepočítá nové
`paid` z payloadu ani z UI a nepřepisuje `paid_externally`, `returned` nebo
provider pohyby. Pro běžné bankovní objednávky zůstává vstupem existující
`payment_info.paid`. Stripe se tímto automatickým bankovním přepočtem neřídí.

**D3 - Práh a snapshot zálohy.** Při ceně <= 0 je objednávka bezplatná.
Jinak použít zaplacenou zálohu, pokud existuje, nejvýše však aktuální celkovou
cenu; bez zálohy použít celkovou cenu. Tím editace zachová způsobilost zálohy
i již fungující slevu pod původní zálohu. Uloženou `deposit_amount` při změně
ceny automaticky nepřepisovat podle dnešního katalogu. Změna obchodní dohody
o záloze není vedlejší efekt tohoto refaktoru.

**D4 - Stav vstupenky není totéž jako finanční stav.** `used` a `storno` jsou
chráněné. Obnovení platby převádí pouze současné povolené stavy, nikdy použité
nebo zrušené vstupenky. Existující `sent` při zachované způsobilosti bezdůvodně
nevracet do `paid`. Odvolání způsobilosti převádí běžné `paid/sent` do
`ordered`; spot assignment ani identita vstupenky se tím nemění.

**D5 - Jedna invalidace a jedna sada intentů na účinnou změnu.** Změna produktů
invaliduje staré připravené emaily i tehdy, když finanční způsobilost zůstane
stejná. V jednom commandu nesmí existovat zvláštní bump z product-edit a druhý
z paid primitive. Nové intenty mají finální verzi a aktuální obsah. Bez změny,
receipt replay a opakované pairing skutečnosti nevytvářejí nové efekty.
Provider acceptance zůstává samostatnou skutečností a stále vlastní `sent`.

**D6 - Historii vlastní původní události.** Nový reconciliation helper
nezapisuje `orders_history`. Product edit převezme finální stav z owneru
a uloží jeden zavedený snapshot po všech účincích. Creation, email acceptance
a cancellation si ponechají své historické záznamy. Zachová se formát a počet,
opraví se pouze chybný finální stav nových product-edit snapshotů.

**D7 - Ruční a provider hranice zůstávají explicitní.** Sdílené mutační
primitivy mohou zůstat samostatné; nesmějí znovu rozhodovat odlišný finanční
práh. Ruční mark-paid má dnešní oprávnění a neposílá email. Stripe guard,
admission/refund rozhodnutí a immutable price zůstávají beze změny. Žádné
persistentní aplikační triggery, nový ledger nebo kompatibilní druhý výpočet.

## Testy připravené nyní

Všechny čtyři soubory jsou standardně sbírané `*_test.sql`; žádné tiché skipy.
Společná fixture je pouze v `pg_temp`, používá skutečný checkout a
product-edit command pod rolí `authenticated`. Bankovní platby procházejí
skutečným `apply_transaction_pairing`. Provider acceptance a chyba vytvoření
emailového intentu jsou označené test doubles; skutečný provider se nevolá.

| Soubor v `database/tests/eshop_orders/` | Co chrání | Výchozí očekávání |
|---|---|---|
| `payment_lifecycle_history_test.sql` | Creation -> edit -> payment -> accepted delivery -> cancellation; neměnnost, autor/čas, opakování a skutečné čtení přes `get_orders`. | Zelený. |
| `payment_lifecycle_boundaries_test.sql` | 299/300 hranice zálohy, odpojení/opětovné spárování, ochrana `used/storno`, idempotence, odmítnutí záporné ceny a pozdní acceptance starého emailu po odpojení platby. | Zelený. |
| `payment_lifecycle_atomicity_test.sql` | Selhání email-intent owneru po změně peněz/stavů vrátí pairing i editaci zpět, včetně historie, fronty a command receipt. | Zelený. |
| `payment_product_transition_regression_test.sql` | Zachování zaplacené zálohy po editaci; zvýšení ceny u `paid` i `sent` vstupenky. | Červený: tři známé nekonzistence. |

Fixture: `database/tests/helpers/payment_lifecycle_fixture.sql`.
Červený test je výslovná brána před implementací, ne schválená výjimka v CI.
Tuto přípravnou sadu nepublikovat jako hotovou zelenou změnu.

### Výsledek lokálního ověření 2026-10-29

- Vlastní nově bootstrappovaný projekt `festapp-payment-plan-20261029`,
  loopback port `57642`, baseline + všechny aktuální forward migrace
  (poslední při bootstrapu `20261029180000_operator_order_summaries.sql`).
  Nepoužila se produkce ani existující databáze jiného rozpracovaného úkolu.
- Všech 15 vybraných existujících SQL souborů ze sady níže prošlo.
- Tři nové charakterizační soubory prošly, včetně skutečné administrátorské
  projekce historie a rollbacku po vynucené chybě enqueue. Finální změny
  affected testů byly znovu ověřeny; žádný passing výsledek není z jiné verze.
- Jeden nový regresní soubor selhal na všech třech očekávaných tvrzeních:
  zálohová objednávka po editaci `ordered` místo `paid`; po zdražení vstupenka
  `paid` místo `ordered`; po zdražení dříve odeslaná vstupenka `sent` místo
  `ordered`. Nešlo o chybu setupu ani přeskočené testy.
- Souhrn unikátních souborů: **18 zelených, 1 záměrně červený**.
  Nová concurrency matice a upgrade budoucí migrace zatím neexistují;
  zůstávají implementačními branami, ne splněným důkazem.

## Efektivní provedení a více agentů

Uživatel výslovně povolil více agentů pro tuto implementaci. Koordinátor
nejprve přečte tento plán, zkontroluje změny od výchozí revize pouze v dotčených
cestách a potvrdí kontrakt D1-D7. Neopakovat celý architektonický audit.
Pracovat na aktuálním `main`; cizí rozpracované změny ponechat beze změn.

### Rozdělení práce bez souběžných zápisů do stejných souborů

| Role | Vlastnictví | Konkrétní výstup |
|---|---|---|
| Koordinátor a implementátor SQL | Aplikační SQL z vln 2-3, tento plán a závěrečná integrace. | Jeden přepočet, upravené adaptéry, intenty a případná oprava pořadí zámků. Jediný rozhoduje o změně společného kontraktu. |
| Agent T - SQL kontrakty | `database/tests/helpers/payment_lifecycle_fixture.sql`, čtyři zde uvedené `payment_*_test.sql` a případné nové SQL soubory téže přechodové matice. | Dokončená vlna 1, očekávání historie a replay/failure testy; neopravuje aplikační SQL, aby nemohl přizpůsobit implementaci svým testům. |
| Agent C - souběh | `database/tests/eshop/payment_product_transition_concurrency.test.mjs` a jeden předem určený registrační bod existující testovací lane. | Deterministické scénáře vlny 3, konečné timeouty a prokazatelný sběr; nalezené lock problémy předává koordinátorovi. |
| Agent M - migrační balíček, až po zmrazení SQL | Nový scoped assembler, nová forward migrace a stručná aktualizace `lib/components/eshop/README.md`. | Instalační pořadí, granty a podklady fresh/upgrade ověření; nemění finální SQL ani historické migrace. |

Začít koordinátorem a dvěma pracovními agenty T/C. Roli M převzít koordinátor
nebo ji předat dokončenému agentovi T; čtvrtý souběžný agent má smysl jen při
skutečně nezávislé zbývající práci. Nezakládat další auditní/review tým.
Samostatný agent pro každý test nebo krátkou změnu by pouze přidal režii.

Každý handoff obsahuje jen cíl, přesné vlastněné cesty, relevantní rozhodnutí
plánu, závislosti, povolené příkazy a hotový výstup. Subagentům bez historie
předat také repo pravidla a odkaz na celý plán. Zakázat jim úpravy cizích cest,
produkční přístup, samostatný commit/push a další delegování. Potřebnou změnu
sdílené fixture nebo runneru nejprve předat jejímu vlastníkovi. Modely zdědit
z implementační session, není zde požadavek na opakované audity Astrou.

### Kritická cesta a integrační brány

1. **Kontrakt a start:** koordinátor potvrdí D1-D7, seznam souborů a vlastníka
   databázového ověřování. Agent T nejprve stabilizuje společnou fixture
   a pošle její rozhraní agentovi C. Koordinátor založí jednu vlastní lokální
   disposable instanci; dřívější `festapp-payment-plan-20261029` byla po
   přípravných testech odstraněna a není připravenou běžící službou.
2. **Paralelní příprava:** T doplňuje SQL kontrakty, C píše souběhový harness,
   koordinátor připravuje společného ownera na dohodnutém kontraktu. Vlna 1
   musí prokázat očekávání před instalací opraveného SQL do testovací DB;
   nové testy nesmějí odvozovat správné výsledky z právě napsané implementace.
   Základní červený důkaz již existuje, není nutné znovu dokazovat celý audit.
3. **První integrace:** po předání testů a SQL spustí jediný vlastník cílenou
   sadu. Potvrzený lock problém opravuje koordinátor; C upravuje jen harness.
   Selhání rozlišit na fixture/setup, známou chybu a novou regresi. Nesnižovat
   očekávání testu, aby odpovídala chybné implementaci.
4. **Zmrazení vstupů:** koordinátor označí finální seznam SQL/test/runner
   souborů a jejich revize nebo SHA-256. M z nich jednou vygeneruje migraci.
   Od tohoto okamžiku ostatní do těchto vstupů nepíší. Nutná další změna
   vyžaduje zprávu koordinátorovi, nové vygenerování a opakování pouze
   zneplatněných důkazů.
5. **Finální ověření:** jeden vlastník provede fresh instalaci, SQL sadu,
   souběhovou sadu a upgrade s existujícími fixtures. SQL runner a souběhový
   harness neběží současně nad stejnou DB: runner resetuje sekvence a testy
   mohou transakčně nahrazovat funkce při fault injection. Upgrade má vlastní
   izolovanou DB; nepřepisuje běžící fresh instanci uprostřed testů.
6. **Předání:** koordinátor zkontroluje absence podle deletion ledgeru,
   výsledky testů a shodu migrace s finálním SQL. Předá jeden souhrn, nikoli
   nesjednocené zprávy agentů. Produkce zůstává samostatným neprovedeným krokem.

Závislosti: kontrakt -> souběžně SQL implementace / SQL testy / concurrency
harness -> integrace -> zmrazení -> migrace -> fresh a upgrade důkazy -> předání.
Příprava harnessu může běžet současně s implementací; jeho úspěšný běh závisí
na integrovaných změnách. Pořadí vln níže vyjadřuje tyto závislosti, ne zákaz
nezávislé souběžné přípravy.

### Jak omezit zbytečnou práci při zachování bran

- Jeden bootstrap během vývoje; instalovat jen právě měněné kanonické SQL
  v pořadí závislostí. Čistý rebuild je až fresh migrační brána nebo reakce
  na skutečně neplatný fixture stav. Nepoužívat migraci opakovaně pod stejným
  záznamem v migračním ledgeru.
- Každý agent dokončí souvislý balík změn před validací. První integrační běh
  použije nové čtyři SQL soubory a concurrency scénáře; navazující 15souborovou
  sadu spustit nad finálním SQL, bez testování po každé drobné editaci.
- Zachovat výsledky vázané na konkrétní SQL/test/runner vstupy. Samotná změna
  dokumentace nebo opakované vygenerování stejného migračního obsahu
  nezneplatňuje nezměněné SQL testy. Fresh a upgrade jsou odlišné povinné
  důkazy, nelze jeden vydávat za druhý.
- Závislosti instalovat jen pokud chybí nebo se změnil lockfile:
  `pnpm install --frozen-lockfile` v příslušném balíčku, pnpm `11.24.0`.
  Pro tento SQL zásah nespouštět Flutter, web build ani browser testy bez
  nového konkrétního důvodu. Případný Flutter úkol podléhá globálnímu limitu.
- Jediný vlastník testovacího prostředí řídí bootstrap, změny schématu, běhy
  i úklid. Paralelní DB validace je přípustná jen nad samostatnými disposable
  databázemi se stabilními vstupy, pokud skutečně zkrátí kritickou cestu.
  Další plný stack pro každého agenta není výchozí postup.
- Průběžně zapisovat jen rozhodnutí, překážku a přesný výsledek příkazu.
  Na konci stačí kompaktní evidence obsahující vstupy, počty testů, očekávané
  versus nečekané chyby, migration parity a stav produkčního kroku.

## Implementační vlny

### 1. Doplnit cílové hraniční kontrakty před změnou owneru

- Rozšířit regresní matici o slevu pod zálohu, nulovou cenu se zálohou,
  přeplatek, cenu bez změny a druhou platbu po odeslání vstupenek.
- Ověřit `expired` bankovní objednávku s pozdní platbou podle současného
  kontraktu, zrušenou objednávku a waitlist bez obnovení admission.
- Doplnit zachování ručního mark-paid bez automatického emailu a Stripe
  odmítnutí product-edit. Existující Stripe scénáře znovu použít.
- Pro product-edit nedoplatek doplnit kontrolu neplatnosti starého emailového
  source version a zkusit jeho pozdní acceptance: žádné obnovení vstupenek,
  žádný falešný snapshot `sent`.
- Doplnit přesnou kontrolu výsledného stavu/ceny/data nového historického
  snapshotu v každém ze tří červených scénářů a identity míst/OPT/ticketů.

Výstup: reprodukované chyby a konkrétní cílové kontrakty; historické zelené
testy zůstávají zelené. Nezavádět očekávání typu "chybné chování je správné".

### 2. Sjednotit přepočet, efekty a zápis finálního snapshotu

- Implementovat D1-D7 v `recalculate_order_payment_status.sql` a přesměrovat
  `update_ticket_products_wsv2` na společného ownera. Smazat jeho samostatný
  CASE pro paid/ordered a jednostrannou synchronizaci vstupenek.
- Zachovat product JSON merge, ceny, metadata míst, odpovědi, identity,
  allocations a receipt fingerprint. Historie se zapíše jednou po owneru
  s finálním stavem, ne s lokálním starým `v_new_state`.
- Sladit version bump a intenty s `mark_order_and_tickets_paid_internal_v1`
  a `update_order_and_tickets_to_paid`; nesmí vzniknout kruhové volání.
  Oddělit rozhodnutí o způsobilosti od nízkoúrovňového zápisu a ruční akce.
- V této vlně neměnit pravidla `set_payment_deadline` nebo reminder defaults.
  Pokud se objeví nezávislá chyba termínů, zaznamenat ji mimo tento zásah.

Výstup: všechny nové SQL kontrakty jsou zelené, stejná finanční situace vede
ke stejné způsobilosti přes bankovní i product-edit cestu.

### 3. Ověřit souběh a dokončit pořadí zámků

- Přidat skutečný dvouspojový test
  `database/tests/eshop/payment_product_transition_concurrency.test.mjs`
  se stejnými loopback/disposable guardy jako ostatní SQL integrační testy.
- Scénáře: pairing proti editaci ceny v obou pořadích; unpairing proti editaci;
  zrušení proti platebnímu přepočtu; email acceptance staré verze proti editaci.
- Synchronizovat přes skutečné PostgreSQL blockery, nikoli náhodné čekání.
  Nastavit konečné `statement_timeout`/`lock_timeout`; deadlock není úspěch.
- Pokud se potvrdí inverze z tabulky evidence, předělat acquisition hranici
  v `apply_transaction_pairing`/reconciliation na jednotné pořadí před
  prvními platebními zápisy. Při přesunu párování uzamknout oba původní i nové
  order/form scope deterministicky a po zamknutí znovu ověřit uložené vazby.
  Nesmí se odvozovat autorita z klientského seznamu objednávek.
- V každém výsledku ověřit finální peníze/stavy, neměnné starší snapshoty,
  počet nových snapshotů, receipt replay a nejvýše jednu platnou aktuální
  sadu ticket intentů. Zachovat společné blueprint/capacity ochrany.
- Zapojit `.test.mjs` do existující SQL/concurrency testovací lane explicitně;
  samotná existence souboru není důkaz sběru nebo spuštění.

Výstup: deterministické testy projdou bez deadlocku/timeoutu; při selhání se
vrátí celá operace. Neprovádět v této vlně optimalizaci hrubosti zámků.

### 4. Forward migrace a ověření instalace

- Nový scoped assembler s explicitním `--output` a nová dosud nepoužitá
  timestamp migrace; zahrnout pouze změněný kanonický owner a jeho skutečné
  závislosti. Staré deploynuté migrace a baseline se nepřepisují.
- Migrace transakčně nainstaluje helper před adaptéry, upraví granty
  a ověří, že interní helper není spustitelný pro anon/authenticated.
- Žádné nové tabulky, triggery, hromadný recompute nebo UPDATE historie.
- Spustit stejnou sadu na čistém baseline + všech forward migracích.
  Vedle toho ověřit upgrade z předchozího migračního bodu na novou migraci
  s již existujícími syntetickými ordered/paid/sent/zálohovými objednávkami;
  instalace sama jejich stav ani historii nezmění.
- Aktualizovat `lib/components/eshop/README.md` stručným kontraktem společného
  owneru a historie; přidat odkaz, nevytvářet druhý popis stavového automatu.

Výstup: zelená fresh i upgrade cesta, stejné veřejné podpisy/odpovědi,
odstraněná nezávislá rozhodovací logika a připravená migrace bez backfillu.

## Deletion ledger

| Artefakt | Akce | Důkaz |
|---|---|---|
| Lokální `v_paid >= v_price` a CASE v product-edit | Smazat, rozhoduje společný owner. | Scoped hledání + přechodová matice. |
| Product-edit `UPDATE tickets` pouze směrem do paid | Smazat, obě projekce vlastní sdílená hranice. | Paid/sent price-rise testy. |
| Duplicitní invalidace/bump po přesměrování | Smazat; owner nebo jeho primitive provede účinek právě jednou. | Version/intent/replay testy. |
| `recalculate_order_payment_status(bigint)` | Zachovat podpis jako adaptér. | Pairing i checkout testy. |
| Starší product-edit a mark-paid RPC | Zachovat externí podpis/autorizační kontrakt, interně sdílet owner/primitivy. | Oprávnění a ruční no-send scénář. |
| Stávající historie a historické migrační zdroje | Zachovat; žádná normalizace/delece. | Snapshot/API/fresh-upgrade testy. |

## Ověřování a produkční postup

Pro SQL použít podporovaný runner s explicitním loopback `DATABASE_URL` na
vlastní disposable DB. Ověřit počet vybraných souborů a SUMMARY; runner s nulou
testů vrací úspěch. Nové testy se spouštějí takto:

```sh
DATABASE_URL='<vlastní lokální disposable URL>' pnpm --dir web_client exec node scripts/run_db_tests.js \
  database/tests/eshop_orders/payment_lifecycle_ \
  database/tests/eshop_orders/payment_product_transition_regression_test.sql
```

Navazující sada zahrnuje `eshop/deposit/`, `eshop/orders/update_ticket_products_ws_test.sql`,
`eshop/orders/cancelled_order_read_only_test.sql`,
`eshop/transactions/payment_pairing_contract_test.sql`,
`eshop_orders/orders_history_bundle_test.sql`,
`eshop_orders/customer_order_overview_test.sql`,
`eshop_orders/customer_order_access_test.sql`,
`emails/order_ticket_intents_test.sql`,
`eshop/stripe/payment_totals_test.sql` a `eshop/stripe/admission_test.sql`.
Před nasazením přidat concurrency vlny 3 a dotčené bank-webhook/Edge testy,
pokud se kvůli lock ordering změní jejich hranice. Flutter/build není potřeba
pro tuto přípravnou práci bez klientských změn.

Produkční krok provést až po samostatném pověření: určit vybraného tenanta,
ověřit canonical backend activation a aplikované migrace, připravit rollback
artefakt a použít schválenou backend release cestu. Nenasazovat ostatní tenanty.
Bez Edge změny nerestartovat Functions a nerozesílat ověřovací emaily.
Před/po instalaci porovnat anonymizované počty stavů a historie, email health,
chyby přechodů a lock waits; skutečný zkušební prodej vyžaduje zvlášť schválená
testovací data a postup. Nezveřejňovat tokeny ani zákaznická data.

Rollback má obnovit předchozí definice dotčených funkcí a grantů; nepřepisuje
objednávky ani nové historické řádky. Obnova staré vadné logiky je nouzové,
dočasné provozní opatření, nikoli dokončený cílový stav. Je-li potřeba opravovat
již nekonzistentní objednávky, připravit samostatný seznam konkrétních ID,
dry-run rozdíl a pověření. Plošný přepočet není součástí migrace.

## Předpoklady a zbytková rizika

- Repozitář neprokazuje aktuální produkční definice. Před nasazením je musí
  release krok porovnat; lokální fresh DB je důkaz pro repozitářový stav.
- Paid/sent historie nemusí sama vysvětlit všechny bankovní události. Zachování
  dnešního kontraktu je záměr; rozšíření timeline je samostatné rozhodnutí.
- Provozní bezpečnost nelze zaručit pouze unit testy. Fresh/upgrade ověření,
  souběh a oddělený produkční krok jsou nepřeskočitelné brány.
- Test acceptance simuluje provider acknowledgement; test atomického selhání
  nahrazuje pouze SQL enqueue hranici v rollbackované transakci. Nejde o
  ověření reálného poskytovatele nebo jeho doručování.

## Dokončeno až tehdy, když

- [x] Jeden owner rozhoduje způsobilost pro pairing i editaci produktů.
- [x] Celá přechodová matice včetně tří reprodukcí je zelená bez skipů.
- [x] Historie zachovává předchozí řádky, formát, autorství a počty událostí.
- [x] Replay, invalidace, failure rollback a concurrency mají skutečné testy.
- [x] Ruční no-send a Stripe hranice se nezměnily.
- [x] Fresh i upgrade migrace projdou; žádný data/history backfill.
- [x] Nezávislé výpočty z deletion ledgeru jsou pryč a zachované API jsou adaptéry.
- [x] Produkční aplikace je doložena, nebo je výslovně uvedena jako neprovedená.
