# Veřejný symbol objednávky napříč vstupenky.online

Datum: 2026-10-06. Stav: implementace a navazující autorizovaný release; aktuální průběh nasazení je v evidenci. Evidence a zbývající gates jsou v `docs/plans/evidence/global-order-symbol-implementation-2026-10-06.md`.
Výchozí revize pro průzkum: `45c512db1cfe916d2e3459155c12df76e033d743`.
Ověřování při realizaci: **standard**, včetně povinných release kontrol repozitáře před publikací.

## 1. Výsledek a hranice

Každá objednávka dostane samostatný, neměnný, veřejný `eshop.orders.order_symbol`. Zákazník a obsluha ho uvidí jako „Symbol objednávky“. Symbol bude unikátní napříč organizacemi a akcemi v kanonické databázi vstupenky.online, nikoliv pouze v jedné akci.

**Výslovné zadání uživatele:** interní `eshop.orders.id` zůstává bigint primárním klíčem. Veškeré vazby, příkazy, změny stavu, platby, autorizace, fronty, idempotence a interní API nadále používají ID. Symbol je prezentační údaj a případný vyhledávací vstup. Po vyhledání se pracuje opět s ID.

Součástí jsou nové i historické objednávky, administrace Flutter, veřejný JS klient, e-maily, náhledy, historie a výstupy, kde se objednávka veřejně označuje. Součástí nejsou změny číslování vstupenek, variabilních symbolů, bankovního párování, ticket QR, bezpečnostních tokenů ani záruka detekce otevření e-mailu v Gmailu. Tato práce nenahrazuje dřívější opravy storna a e-mailů.

## 2. Zjištěný stav a důkazy

Průzkum vychází z repozitáře, nikoliv z nového auditu produkčního katalogu. Historická baseline je doklad původu schématu; aktuální granty, rozměry tabulek a instalované funkce se musí před migrací ověřit.

| Oblast | Ověřený fakt a místo | Důsledek |
| --- | --- | --- |
| Sloupec | `lib/components/eshop/models/tb_eshop.dart` již má název `order_symbol`, ale `order_model.dart` nemá odpovídající vlastnost. Baseline `supabase/baseline/20260805230000_production_schema.sql`, definice `eshop.orders`, sloupec nemá; v prohledaných migracích se nevyskytuje. | Existující Dart konstanta není hotová podpora v databázi. |
| Zobrazení | `OrderModel.toTrinaRow()` mapuje `ORDER_SYMBOL` na `id`; `toBasicString()` vrací `Order #$id`. | Oddělit zobrazovaný symbol od identity řádku. |
| Další plochy | `orders_history_model.dart` mapuje `HISTORY_ORDER_SYMBOL` na `orderId`; `email_delivery_model.dart` obdobně; `ticket_model.dart` používá `relatedOrder.toBasicString()`. | Nestačí opravit tabulku objednávek. |
| Dialogy/formuláře | `order_history_dialog.dart` a `transactions_dialog.dart` používají ID v nadpisu; `lib/components/forms/models/form_response_model.dart` skládá `OrderModel` z vlastního kontraktu. | Upravit prezentační argumenty a projekce, ponechat číselné ID pro načítání/akce. |
| Vstupenky | `database/functions/eshop/generate_ticket_symbol.sql`: poslední dvě číslice organizace a akce, nuly změněné na X, potom tři dvojice číslice/písmeno. Číslice `123456789`, 20 písmen `ACEFGHIJKLMNPQRUVWXY`. Kontrola kandidáta přes `NOT EXISTS` je omezena na akci. | Převzít čitelnost a abecedu, nikoliv rozsah unikátnosti nebo samotný předběžný dotaz jako záruku při souběhu. |
| Zápis | `database/functions/eshop/create_ticket_order.sql` vkládá objednávku a vrací `order.id`; následně tvoří vstupenky, platbu a odpověď. | Symbol musí vzniknout ve stejné transakci před vytvořením odpovědi a e-mailového payloadu. |
| Obal příkazu | `supabase/migrations/20260802234000_client_sync_v1_expansion.sql` přejmenovává implementaci na `create_ticket_order_internal_v1`; `create_ticket_order_client_sync_v1` řeší replay a volá implementaci. `supabase/functions/send-ticket-order/index.ts` používá tento příkaz. | Instalace nesmí přepsat veřejnou facade starou holou implementací ani obejít idempotenci. |
| Čtení | `database/functions/eshop_orders/get_orders.sql` skládá objednávky explicitně ve větvi pro formulář i pro akci. `get_order_details_for_email.sql` používá `to_jsonb(o.*)`. | Explicitní projekce doplnit; automatické rozšíření JSON také smluvně otestovat. |
| Historie e-mailů | `database/functions/emails/email_reporting.sql` vrací `order_id`; agregace stavů je klíčována ID. | Přidat prezentační symbol přes oprávněný join, neměnit klíč agregace ani význam fajfek. |
| E-mail | `getTicketOrderConfirmationTemplate.ts` čte neměnný `task.data.ticket_order`; ostatní order renderery používají `getBaseOrderData` v `send-email/shared.ts`. `_shared/orderOverview.ts` generuje přehled. | Nestačí přidat údaj jen do živého dotazu. Zahrnout čekající payloady a centrální vykreslení. |
| Šablony | `lib/components/email_templates/email_template_model.dart` registruje substituce včetně `variableSymbol` a `fullOrder`. | Přidat samostatné `orderSymbol`, nezměnit význam staré substituce. |
| Platby/dokumenty | `generate_payment_variable_symbol.sql`, `eshop_transactions/payment_reference.sql`, `_shared/paymentPresentation.ts`, `send-ticket-order/fakturoidPayload.ts`; `generate-order-agreement/index.ts` používá VS nebo ID pro název souboru. | Veřejný symbol oddělit od CZK VS, EUR RF reference, fakturačního čísla a klíče Fakturoidu. |
| Veřejný klient | `web_client/src/components/eshop/db_orders.js` drží identitu pending příkazu a volá `send-ticket-order`. | Nerozbít retry; případné předání symbolu do potvrzení nesmí zpřístupnit celý soukromý order payload. |

## 3. Navržený kontrakt

### Čtyři různé identifikátory

| Název | Účel | Cílové chování |
| --- | --- | --- |
| `orders.id` / `order_id` / `orderId` | Interní identita | Beze změny typu, vazeb a významu. |
| `orders.order_symbol` / Dart `orderSymbol` | Veřejné označení objednávky | Nový uložený textový atribut, nikoliv výpočet z ID. |
| `tickets.ticket_symbol` | Identita konkrétní vstupenky | Beze změny, včetně již vydaných QR. |
| `payment_info.variable_symbol`, creditor reference | Platební reference | Beze změny generování, formátu a párování. |

### Formát a diktování

**Rozhodnutí podle upřesnění uživatele:** souvislý symbol bez oddělovačů, například **`7G4K9M2R6A`**. Uživatel schválil délku 10 náhodných znaků tvořených pěti dvojicemi číslice/písmeno. Jde o kompromis podle požadavku uživatele na co nejkratší praktický symbol se zaručenou unikátností. Uložení, běžné zobrazení, e-maily i kopírování používají tentýž tvar bez pomlček a mezer, aby šel celý symbol pohodlně označit dvojklikem. Ani prezentační vrstva nesmí vkládat oddělovače nebo rozdělovat symbol do samostatných textových bloků. Použít stejnou sadu `123456789` a `ACEFGHIJKLMNPQRUVWXY` jako u vstupenek. Zachová se známé střídání a nevznikne nula ani písmeno O; do návrhu nepřidávat nové podobně vypadající znaky. Písmena nejsou všechna foneticky nezaměnitelná, proto neslibovat bezchybné rozpoznávání řeči.

Formát nenese ID organizace, akce ani pořadové číslo. Unikátnost má být globální, takže organizační prefix nepřináší záruku. Prostor je `180^5 = 188 956 800 000` kandidátů, tedy 180krát větší než u osmi znaků. Při 100 milionech uložených objednávek má jednotlivý nový rovnoměrně náhodný kandidát přibližně 0,0529 % pravděpodobnost kolize. Kolize během provozu očekáváme a řešíme opakováním insertu; nejsou důvodem vydat duplicitní symbol. Deset znaků je uživatelem schválený kompromis mezi krátkostí a dlouhodobou kapacitní rezervou. Sledovat počet pokusů přidělení a vyčerpání retry limitu. Při dosažení 1 % obsazenosti prostoru (přibližně 1,89 miliardy uložených objednávek) nebo neočekávaně zvýšené míře kolizí vyhodnotit kapacitu a zdraví generátoru; tato hranice sama nevyžaduje změnu formátu. Již vydané symboly se nemění. Samotná velikost prostoru není důkaz unikátnosti; definitivní ochrana je databázový unikátní constraint.

Abeceda se definuje jednou v DB generátoru, indexování používá skutečnou délku řetězce. Náhodné indexy generovat rovnoměrně pomocí dostupného `extensions.gen_random_bytes`, s rejection sampling pro rozsahy 9 a 20. Nepřidávat externí službu ani samostatný generátor v Dart/JS. Stávající ticket generátor v tomto úkolu neměnit ani neregenerovat staré ticket symboly.

Zobrazení/kopírování vždy používá kanonický tvar. Vyhledávání může normalizovat malá písmena na velká a odstranit okolní whitespace, poté porovnat přesnou hodnotu. Žádný alternativní formát s pomlčkami se nezavádí. Neprovádět automatické záměny odhadovaných písmen a číslic. Symbol není heslo ani oprávnění ke čtení objednávky.

### Uložení, tvorba a neměnnost

- Jediný zdroj pravdy: `eshop.orders.order_symbol text`, po dokončení `NOT NULL`, globální pojmenovaný `UNIQUE (order_symbol)` a CHECK formátu. Žádný složený unikátní index s organizací či akcí, žádný duplicitní autoritativní symbol v `orders.data`.
- Kandidáta vytváří jedna privátně používaná SQL funkce v `public`. Přidělení a `INSERT` vlastní existující doménová implementace vytvoření objednávky. Nepřidávat druhou cestu pro vytváření celé objednávky.
- Pouze konflikt konkrétního constraintu symbolu vede k novému kandidátu. Použít omezený retry, například 10 pokusů; ostatní integritní chyby okamžitě propagovat. Retry obaluje samotný insert, nikoliv tvorbu vstupenek, platbu či enqueue. Vyčerpání limitu vrací stávající strukturované selhání a rollback celé tvorby.
- Žádný nový persistentní aplikační trigger. Sloupec nemá klientem dodávanou hodnotu ani fallback `id.toString()`. Vstupní `order_symbol` v klientském příkazu explicitně odmítnout; zamezit také jeho propašování do snapshotu. Import musí používat autoritativní tvorbu nebo výslovně kontrolovanou migrační cestu.
- Běžné změny objednávky symbol nemění. Auditovat skutečné table/column granty a RLS: zákaz zápisu ve formuláři nestačí. Odebrat případná přímá oprávnění pro změnu symbolu, ponechat pouze potřebné sloupce a existující autorizované RPC. Tabulkový `UPDATE` grant nesmí obcházet column restrikci. Administrativní SQL vlastník zůstává důvěryhodnou migrační hranicí.
- Replay stejného příkazu vrací stejnou objednávku a stejný symbol, bez nové platby či e-mailu. Příkazy pro update/storno stále přijímají ID.
- Symbol zůstává při stornu, plné úhradě i změně produktů. Kopie akce/nová objednávka dostane nový symbol. Hard delete se tímto úkolem neruší; záruka unikátnosti platí mezi uloženými objednávkami. Symboly se úmyslně nerecyklují. Absolutní zákaz opětovného náhodného přidělení po hard delete by vyžadoval trvalý registr vydaných symbolů a není součástí tohoto návrhu.

## 4. Konkrétní postup realizace

### Pracovní checklist pro realizátora

Tato část určuje pracovní pořadí a uzavírá rutinní volby. Detailní vlny níže vysvětlují kontrakty a rizika. Neprovádět nový celorepozitářový návrh. Průzkum omezit na neověřené runtime hranice z vlny A a změny od výchozí revize.

**Pevné volby:** `order_symbol`, 10 znaků, pět dvojic číslice/písmeno, bez prefixu organizace a bez oddělovačů. Generátor pojmenovat `public.generate_order_symbol()`, nový canonical soubor `database/functions/eshop/generate_order_symbol.sql`. Constrainty pojmenovat `orders_order_symbol_key` a `orders_order_symbol_format_check`. CHECK používá přesný vzor `^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$`. Limit přidělení je 10 pokusů celkem. Pro čitelnost nezavádět další třídu symbolu ani veřejnou generovací API službu.

| Krok | Přesná práce | Hotovo, když |
| --- | --- | --- |
| 1 | Splnit vlnu A; zapsat skutečné writery, granty a způsob instalace internal funkce. | Není neznámý aktivní writer a je určen správný migrační owner. |
| 2 | Přidat generátor a schema expand. Upravit insert v canonical `create_ticket_order.sql` a jeho instalaci do `create_ticket_order_internal_v1`. | Nová objednávka vrací uložený symbol, wrapper/replay zůstal zachován. |
| 3 | Připravit resumable backfill, oprávnění a NOT NULL krok z vlny B. | Disposable databáze projde migrací i opakováním bez změny již přidělených symbolů. |
| 4 | Doplnit response tvorby, obě větve `get_orders.sql`, history/form/email reporting projekce. | Každá relevantní response obsahuje `order_symbol` i původní ID. |
| 5 | Upravit Dart modely a jejich konkrétní konzumenty vyjmenované ve vlně C; veřejné JS potvrzení. | UI zobrazuje symbol a test zachytí, že write command stále posílá ID. |
| 6 | Přidat substituci a společný order přehled, pak jednotlivé order renderery a dokumenty z vlny D. | Všechny druhy sdělení používají stejný uložený symbol a zachované platební reference. |
| 7 | Ošetřit starý pending/replay payload v jedné sdílené read hranici; připravit konkrétní diff efektivních šablon. | Starý payload nevyvolá nový příkaz ani nový snapshot a nemá fallback na ID. |
| 8 | Dokončit testovací matici a ledger, jednou spustit společný verification batch; až s oprávněním provést release. | Jsou doloženy všechny exit podmínky vln, ne pouze happy path. |

**Recept přidělení při tvorbě:** ve smyčce nejvýše 10krát vytvořit kandidáta a provést původní insert rozšířený o symbol pomocí `ON CONFLICT ON CONSTRAINT orders_order_symbol_key DO NOTHING RETURNING id, order_symbol`. Pokud insert vrátil řádek, opustit smyčku; jinak další kandidát. Po vyčerpání limitu vyvolat chybu ve stávajícím transakčním/error kontraktu. Další unique/integrity chyby tento konkrétní conflict target nepolyká. Teprve po úspěšném insertu pokračovat původní tvorbou tickets/platby. Neměnit idempotency key ani retry celého příkazu. Backfill používá UPDATE a musí zachytit jen kolizi tohoto pojmenovaného constraintu.

**Recept generátoru:** pro každou z pěti dvojic vybírat byte `b` z `gen_random_bytes`; pro číslici odmítnout `b >= 252`, jinak použít index `(b % 9) + 1`; pro písmeno odmítnout `b >= 240`, jinak index `(b % 20) + 1`. V kódu limity odvodit jako `256 - (256 % length(alphabet))`, nikoli udržovat druhou kopii délek. Zpracovávat blok náhodných bytů a při spotřebování doplnit; toto je lokální detail jediné SQL funkce, ne nová obecná random knihovna.

**Kam přidat testy:** rozšířit `database/tests/eshop/create_ticket_order_test.sql` a přidat cílený `database/tests/eshop/order_symbol_test.sql`; využít existující email/tenant testy z `database/tests/emails/` a `database/tests/get_orders_tab_data_tenant_scope_test.sql`. Pro Flutter rozšířit `test/components/eshop/order_commands_test.dart`, `test/components/eshop/models/order_email_cell_test.dart`, `test/components/email_delivery/email_delivery_history_test.dart` a `test/components/forms/order_finish_screen_test.dart`; čisté parsování lze testovat samostatně vedle modelových testů. Deno navázat na existující `send-email/deposit_templates_test.ts`, `send-ticket-order/commandIdentity_test.ts` a `fakturoid_test.ts`. Nezavádět nový test runner. Souběh musí otestovat dvě skutečné transakce, ne dvě po sobě jdoucí volání.

**Pravidla rychlé realizace:** implementovat související změny po uvedených blocích, neprovádět build/test po každém souboru. Cílené kontroly seskupit na DB kontrakt a na konzumenty; plný repo gate spustit jednou na finální změně a opakovat jen po relevantní opravě. Reuse existujících rendererů/modelů/runnerů má přednost před novou abstrakcí. Neřešit nový formát ticketů, nový vyhledávací produkt, registry již smazaných symbolů ani předčasné rozšíření na více než 10 znaků. Pro retry metriky použít existující observability cestu, nevytvářet dashboard projekt.

**Stop podmínky:** neočekávaný druhý writer, neřešitelný přímý write grant, rozpor v runtime facade, nepřístupná custom šablona či překročený rozpočet produkčního zámku se zapíše jako konkrétní blocker příslušné vlny. Nepřeklenovat jej odhadem, generátorem na klientovi ani fallbackem na ID. Ostatní nezávislé lokální kroky lze dokončit. Časové zrychlení nesmí vynechat unikátní constraint, migraci starých dat, idempotenci nebo tenant ochranu.

### Vlna A: uzavření skutečných zápisových cest

**Cíl:** znát všechny způsoby zápisu a správnou instalovanou doménovou implementaci.

1. Pro aktuální main ověřit použitelný canonical SQL/migration assembler a živou signaturu `create_ticket_order_internal_v1`. Zkontrolovat novější migrace, které implementaci předefinovaly. V novém scoped migračním artefaktu instalovat upravené tělo do doménového owneru, zachovat facade, replay, enqueue i sync důsledky.
2. Vyhledat `INSERT INTO eshop.orders`, schema-qualified i klientské `.from('orders').insert/upsert`, duplicating/import funkce, test fixtures a dynamické SQL. Rozlišit runtime writer od baseline a historické migrace. Každý aktivní writer musí přidělovat symbol stejným vlastníkem; jinak před další vlnou odstranit bypass.
3. V disposable DB a před nasazením read-only v aktuálním kanonickém katalogu ověřit grants/RLS, dependencies, skutečné indexy, počet objednávek, délku zámku a možnost použití pgcrypto. Zkontrolovat API výstupy a registry client sync; rozšířit jen projekce, které skutečně přenášejí veřejné označení objednávky. Identity sync zůstávají bigint.

**Výstup:** přesný seznam aktivních writerů, readerů a migračního pořadí v tomto plánu. Pokud existuje neočekávaný další writer nebo externí kontrakt, aktualizovat plán před změnou schématu. Neodhadovat produkční stav z baseline.

### Vlna B: databáze a převod dat

**Cíl:** všechny nové i existující objednávky mají stabilní globální symbol.

1. Expand migrace: nullable sloupec, generátor, CHECK a unikátní constraint; ve stejné koordinované změně aktualizovat všechny potvrzené writery. Staré klienty obsluhuje již aktualizované serverové RPC. Není potřeba klientský generátor ani dočasná nulová/číselná náhrada.
2. Na kopii dat nacvičit backfill všech stavů a organizací. Použít omezené dávky podle ID a zamykání řádku, generovat pouze pro `IS NULL`, na konflikt konkrétního unique constraintu opakovat kandidáta. Opětovné spuštění zachová již přidělené hodnoty. Změna metadat nesmí měnit `orders.data`, finanční údaje, sémantickou verzi objednávky ani vytvářet doménovou historii/e-maily. Zkontrolovat účinek existujících timestamp triggerů.
3. Pro velkou tabulku předem zvolit postup tvorby indexu a časový rozpočet zámku podle měření. Pokud je nutný `CREATE UNIQUE INDEX CONCURRENTLY`, provést explicitní samostatný netransakční krok s kontrolou validního indexu a navázáním constraintu, nikoliv jej schovat do běžné transakční migrace.
4. Po nulovém počtu NULL a duplicit validovat constrainty a nastavit `NOT NULL`. Dokončit column/table privilegia. Aktualizovat canonical SQL a vlastní novou migraci, nepřepisovat staré migrační soubory či baseline.
5. Zajistit protokol mapování `id -> order_symbol` a checkpointy backfillu v chráněném operačním výstupu. Nezveřejňovat zákaznická data do git evidence.

**Ověření/exit:** SQL testy generátoru, vynucené kolize, souběh, rerun backfillu a write permissions; všechny řádky mají správný tvar a globálně unikátní hodnotu. Nevznikly nové doménové vedlejší účinky.

### Vlna C: kontrakty a prezentační modely

**Cíl:** údaj se dostane na každou plochu bez změny interní identity.

- Doplnit `order_symbol` do výsledku tvorby, obou větví `get_orders`, `get_orders_tab_data`, potřebných form response projekcí, `get_order_history` a `get_latest_order_history`/history seznamu tam, kde se skládá označení objednávky. `to_jsonb(o.*)` ověřit kontraktovým testem místo duplicitního ručního pole.
- V `OrderModel` přidat `String? orderSymbol` pro přechodné čtení starých payloadů; mapovat snake_case JSON. Null nesmí vyvolat pád ani se vydávat za symbol pomocí ID. U nově načtených dat po backfillu je absence chyba kontraktu. Identita řádku, vztahy a serializace příkazů nadále používají `id`; read-only symbol nepřidávat do generického write payloadu.
- `OrderHistoryModel`, `EmailDeliveryModel` a related ticket/form modely získají prezentační symbol z autorizovaného order joinu. Historická `data` nepřepisovat jen kvůli označení. Smazaná objednávka bez dostupného symbolu dostane poctivý prázdný stav/„Smazaná objednávka“, nikoli vymyšlený symbol.
- Změnit `ORDER_SYMBOL`, `HISTORY_ORDER_SYMBOL`, `toBasicString`, nadpisy historie/plateb, tabulku vstupenek, e-mailovou historii, form response přehledy a exporty těchto tabulek. Veřejný label nesmí zůstat `Order #<id>`. Upravit šířku sloupce, kopírování a lokální filtrování pro 10 souvislých znaků.
- Prověřit všechny používající `OrdersStrings.toBasicString`, `transactionsForOrder` a obdobné lokalizace; synchronizovat podporované locales. Interní číslo lze zobrazit jen výslovně jako „Interní ID“ v technickém detailu, ne v hlavním označení.
- Dohledávání běží v existujícím oprávněném rozsahu. Nevytvářet veřejný globální endpoint „symbol -> objednávka“. Pokud seznam nemá všechna data, rozšířit existující autorizovaný list/search filtr a po načtení používat ID. Vyhledání cizího symbolu nesmí odhalit existenci cizí objednávky.
- `web_client/src/components/eshop/db_orders.js`, Edge response a navazující potvrzení mají dostat jen potřebný `order_symbol`; zachovat anonymní command ID, client ID a bezpečnost existující odpovědi. Staré pending požadavky neopouštět ani neresetovat.

**Ověření/exit:** SQL kontrakty, Dart model/widget a JS testy potvrzení. Zákaznické a obslužné popisky zobrazují symbol; všechny vykonané příkazy a výběry řádků stále posílají původní bigint ID.

### Vlna D: e-maily, šablony a dokumenty

**Cíl:** stejný symbol ve všech sděleních o jedné objednávce, bez přepisování platebních referencí a původního vizuálního stylu.

1. Přidat `orderSymbol` do registru substitucí a všech order rendererů: potvrzení, změna, storno, vstupenky/úhrada a připomínka včetně zálohy. Centralizovat načtení/prezentaci identity v existující sdílené cestě; neduplikovat formátování v pěti šablonách. `fullOrder` musí mít symbol ze skutečného `order.order_symbol`, ne z volného zákaznického `data`.
**Upřesnění uživatele během realizace:** `orderSymbol` zpřístupnit v registru substitucí a použít v globálních defaultních šablonách. Vlastní šablony bez placeholderu zpětně nerozšiřovat, již odeslané zprávy neměnit. Společný `fullOrder` při budoucím renderování obsahuje skutečný symbol.

2. V defaultních order šablonách použít symbol v těle a předmětu, např. `Změna objednávky 7G4K9M2R6A - Ples se sálem`. Zachovat původní barvy, layout a jazyk/tón. Vlastní org/unit/event šablony ponechat beze změny podle nového výslovného zadání. Podporují explicitní `{{orderSymbol}}` a společný `{{fullOrder}}`; šablony bez těchto substitucí automaticky nerozšiřovat. Globální defaulty upravit bez změny jejich původního layoutu a barev.
3. Staré čekající `ticket_order` payloady a dokončené command replay odpovědi mohou symbol postrádat. Přidat jedno přechodné serverové doplnění výhradně z existující objednávky podle ID a stejného tenant scope. Obohatit jen metadata identity při čtení/renderování, nepřegenerovat ceny, vstupenky ani snapshot, nevytvářet nový příkaz a nepřepisovat původní hash. Pro aktuální payloady nulové dodatečné dotazy. Odstranění této větve řídit skutečnou retention fronty a replay cache; pokud se staré odpovědi uchovávají trvale, ponechat pojmenovanou read adapter hranici s testem, nikoli skrytý fallback na ID.
4. Již přijaté/odeslané MIME, PDF a historii neregenerovat, neopakovat odeslání. Neexistující/smazaná objednávka nesmí způsobit vygenerování nového symbolu ani změnu pravidel rušení čekajících e-mailů. Ponechat dosavadní terminal/superseded zacházení.
5. V `generate-order-agreement` prověřit veřejné označení v dokumentu a názvu souboru. Nové soubory mohou použít symbol objednávky; pole označená VS, RF reference či číslo faktury zůstávají platebními/fakturačními údaji. Attachment RPC stále přijímá `orderId`. Totéž platí pro Fakturoid `custom_id`, retry klíče a již vystavené faktury.

**Ověření/exit:** Deno renderer testy a MIME/HTML snapshoty všech druhů v podporovaných jazycích, vlastní i globální šablony, starý pending payload a replay. Symbol je shodný s DB, platební QR/VS/RF a původní styl jsou zachované. Odlišení předmětů mezi objednávkami může pomoci orientaci v Gmailu; není zárukou změny threadingu ani měření otevření.

### Vlna E: dokončení, nasazení a provozní ověření

**Cíl:** odstraněné zaměňování veřejného symbolu a ID, bezpečně nasazený jednotný kontrakt.

1. Dokončit audit prezentačních výskytů `ORDER_SYMBOL`, `HISTORY_ORDER_SYMBOL`, `toBasicString`, `order.id`, `orderId`, `order_id`, názvů dokumentů a substitucí. Výsledek klasifikovat podle ledgeru níže; žádný mechanický globální rename.
2. Spustit cílenou sadu, potom povinný `bash automation/test_all.sh` s reálně aktivní disposable DB a potřebné Deno testy/analyzér podle repo gate. Přeskočená SQL sada není splněný gate. Browser smoke provést izolovaně v pozadí přes repo postup, bez ovládání uživatelova Chrome a bez lokálního Dockeru.
3. Po samostatném povolení publikace postupovat přes aktuální canonical main a tenant release dle `docs/architecture/tenant_overlays.md` a backend-access postupu. Databáze/backfill/constrainty před novými čtenáři; následně kompatibilní backend renderery, šablony, Flutter a JS. Při mezeře mezi backendem a frontendem jsou staré klienty funkční a operují dál nad ID.
4. Provozní kontrola: NULL/duplicate count, několik starých a nových objednávek z různých akcí, starý klient, replay, symbol v UI/exportu/e-mailu, nezměněné bankovní reference. Testovací e-maily jen na výslovně povolený vlastní účet a testovací akci; produkční zákazníky migrací nekontaktovat.

**Exit:** splněné invarianty a testovací matice, explicitní evidence nasazené revize a migrace, žádná nevysvětlená stará prezentační cesta. Samotná kompilace není dokončení.

## 5. Testovací matice

| Úroveň | Povinné scénáře |
| --- | --- |
| SQL generátor | Přesně 10 znaků, abeceda, absence pomlček a mezer; vynucená kolize a další pokus; retry limit; jiná unique chyba se nepohltí. Použít izolovanou fixture/test harness, žádný produkční přepínač seed nebo veřejný test RPC. |
| SQL integrace/souběh | Dvě transakce se stejným kandidátem; dvě různé organizace/akce se stejným kandidátem; constraint platí globálně. Rollback po selhání nezanechá platbu/ticket/e-mail. Náhodný bulk test sám o sobě nestačí. |
| Migrace | Ordered, paid, sent, storno, nulová cena, žádné tickets, staré neúplné data; všechny organizace; rerun/interruption, souběžná tvorba, zachování již přiděleného symbolu a obchodních dat. |
| Auth/write | Neoprávněné vytvoření/čtení, spoofed symbol v requestu, přímý table update a upsert, známý cizí symbol; žádný nový bypass tenant scope. |
| Idempotence | Opakované vytvoření po timeoutu, stará uložená response bez symbolu, stejné ID/symbol, jedna platba a jeden email intent. |
| Doménové regrese | Odebrání produktu, storno jedné i poslední vstupenky, platba, vrácení platby, změna poznámky, kopie/nová objednávka: symbol stabilní kromě nové objednávky. QR zbývající vstupenky beze změny. |
| Dart model/widget | Orders, tickets, history, email history, form response, dialogy, export, long symbol, copy/search, výběr celého souvislého symbolu dvojklikem, starý payload; akce používají ID i když je symbol viditelný. |
| JS/API | Checkout bez úniku soukromých polí, retry, guest i přihlášený klient, stejný symbol v potvrzení a následném e-mailu. |
| Deno/e-mail/PDF | Všechny order druhy, default i custom šablona, CS/EN, stará fronta, záloha, CZK/EUR, Fakturoid, attachment filename; interní `orderId` a platební reference zachované. |
| E2E | Vytvořit dvě objednávky stejné akce, ověřit různé symboly napříč UI/email; dohledat vlastní, odmítnout cizí, částečně stornovat, upravit a plně stornovat, ověřit stejný symbol a správnou identitu provedených změn. |

## 6. Ledger odstranění a ponechání

| Cesta | Rozhodnutí / důkaz dokončení |
| --- | --- |
| `ORDER_SYMBOL <- id`, `HISTORY_ORDER_SYMBOL <- orderId`, `Order #id` | Odstranit z veřejné prezentace; testovat skutečný symbol. |
| Symbol jako výpočet z ID nebo `symbol ?? id` | Nevytvářet; žádné takové fallbacky po dokončení. |
| Interní ID v FK, RPC, row identity, idempotency, queue, log correlation, scan vazbách | Záměrně ponechat; žádná migrace interních klíčů na text. |
| Numeric interní URL/parametry a existující externí integrační ID | Ponechat kontrakt a autorizaci. Tento plán nepřepisuje routy na symboly. |
| VS, RF reference, Fakturoid custom_id / číslo faktury | Ponechat význam a všechny externí kompatibilní kontrakty. |
| Staré odeslané e-maily, PDF, snapshoty a existující ticket symboly | Ponechat beze změny; nejsou novým zdrojem order symbolu. |
| Starý čekající/replay payload bez symbolu | Jediný omezený serverový read adapter z vlny D; odstranit podle prokázané retention, ne podle odhadu. |
| Migrační backfill writer a případná přechodná oprávnění | Po backfillu odstranit/odebrat; žádný obecný veřejný setter symbolu. |
| Historické migrace a baseline | Nepřepisovat. Nová migrace a canonical zdroje musí být konzistentní. |

## 7. Rollback a zbývající předpoklady

Rollback nového UI nebo rendereru může dočasně vrátit starou prezentaci, ale **nesmí** smazat sloupec, constrainty nebo již vydané symboly. Zachovat nový DB writer: stará implementace bez symbolu by po `NOT NULL` selhávala. Opravit dopředně, případně vrátit kompatibilní předchozí aplikační release se zachovaným DB přidělováním. Backfill rerun pokračuje jen na NULL. Úspěšně odeslané e-maily se při rollbacku neposílají znovu.

- Předpoklad: celý požadovaný systém používá jednu kanonickou DB. Globální constraint nezajišťuje koordinaci nezávislých databází; runtime owner to před migrací ověří přes aktivaci tenantů.
- Formát o 10 znacích je schválená volba uživatele se známou abecedou pro diktování. Absence oddělovačů je výslovný požadavek uživatele. Délku ani oddělovače realizátor svévolně nemění; po vydání je formát veřejným kontraktem a symboly se neregenerují.
- Skutečné počty řádků, aktuální přímé granty, retention replay a vlastní efektivní šablony se ověřují ve vlně A/D. Jejich neznalost neospravedlňuje obcházení idempotence, tichou ztrátu šablon či neomezené prodloužení migrace.
- Tento dokument pouze plánuje práci. Implementace a produkční kroky vyžadují navazující zadání; dřívější souhlas s nasazením opravy e-mailů se automaticky nerozšiřuje na tento nový projekt.

## 8. Definice hotovo

Po samostatně autorizovaném backfillu a nasazení má každá uložená objednávka právě jeden uložený globálně unikátní veřejný symbol; symbol se během jejího života nemění. Všechny uživatelské order plochy používají tento údaj, interní operace stále bigint ID. Platby, QR vstupenek, historie, retry a tenant oprávnění se chovají jako před změnou. Testy prokazují i kolize/souběh a absenci starých zaměňujících prezentačních cest. Implementace má doložený backfill, kompatibilitu čekajících efektů a bezpečný rollout.

## 9. Skutečné hranice ověřené při realizaci

- Checkout zůstává na výchozím SHA `45c512db1cfe916d2e3459155c12df76e033d743`, branch `fix/order-ticket-change-overview-20261006`; původně pouze dva untracked plánové soubory. Hlavní workspace s cizími změnami není upravován.
- Read-only kanonický katalog po ověření SSH hostname/runtime database a aktivace `prod/festapptickets` potvrzuje organizaci 3 a jediný runtime insert writer `create_ticket_order_internal_v1`, owner `postgres`. Facade `create_ticket_order_client_sync_v1` zůstává owner `postgres`; granty a idempotence zůstávají.
- Tabulka obsahovala 3 287 řádků, celková velikost byla 6 979 584 bytů. Na `eshop.orders` nebyly aplikační ani timestamp triggery. Backfill tedy nemění `updated_at`; není třeba dočasně vypínat triggery. Produkční délka zámku dosud nebyla změřena; expand/contract mají 5s lock timeout a samostatné release povolení zůstává nutné.
- Runtime má table i column INSERT/UPDATE granty pro anon/authenticated/service_role. Expand odebírá oba granty, TRUNCATE a TRIGGER; service_role zachovává pouze UPDATE(note_hidden), potřebné pro SELECT FOR UPDATE v existujícím invoker email produceru. Symbol samotný zůstává nezapisovatelný.
- Canonical `get_orders.sql` zaostával za tenant ochranou z `20260910080000_scope_admin_occasion_links_to_user_organization.sql`. Nový canonical reader ji nyní explicitně zachovává v obou větvích; regresní test duplicate links prochází.
- Rozšíření se instaluje atomicky do správného internal ownera, bez nahrazení facade holým writerem. Privátní `read_order_identity` je SECURITY INVOKER, execute pouze service_role a owner; není veřejný globální lookup. Facade používá stejnou read hranici pro staré replay response, Edge/confirmation sdílí metadata adapter v existujícím orderOverview. Retention není prokázaná jako konečná, proto je adapter záměrně ponechán.
- Migrační pořadí: `20261006130000_order_symbol_expand.sql`, owner-only dávky `automation/order-symbol/backfill.sql`, `20261006131000_order_symbol_contract.sql`, `20261006132000_order_symbol_email_defaults.sql`, potom kompatibilní čtenáři/renderery. Contract odmítne zbývající NULL a odstraní dočasný setter. Rerun expand/backfill/contract zachovává vydané hodnoty.
- Globální defaulty byly inventarizovány read-only. Nový seed obnovuje chybějící defaulty původním obecným obsahem a rozšiřuje pouze jejich subject/body identity. Scope organizace/unit/occasion se neupravuje. Dřívější požadavek upravovat všechny vlastní šablony je výslovným novým zadáním zrušen.
