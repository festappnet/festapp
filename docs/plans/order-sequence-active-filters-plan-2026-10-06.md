# Pevné pořadí objednávky a filtry nestornovaných položek

Datum: 2026-10-06. Stav: vlny A-D dokončené; po následném výslovném schválení uživatele backend migrace a web nasazené pro prod/festapptickets, verze 0.20.124+608. Evidence: [implementace a residual ledger](evidence/order-sequence-active-filters-implementation-2026-10-06.md).
Výchozí shared revize: `0a5274c5ab8105607ac4a05ce83efd940e188f00`; nasazený `prod/festapptickets`: `cbd69bb725477da5403e0f87aecf72e407803b85`, verze `0.20.123+607`.
Ověřování implementace: **standard** - změna SQL kontraktu, souběhu a sdíleného gridu. Při plánování se nespouštějí testy/buildy.

## 1. Výsledek a schválená rozhodnutí

Uživatel dostane vedle veřejného symbolu krátké interní „Pořadí objednávky“. Je pevné pro konkrétní objednávku a čísluje se samostatně v každé události. Je vidět v objednávkách i u všech jejich vstupenek. Symbol zůstane dostupný, ale zabere méně místa.

**Výslovně potvrzeno uživatelem:** nová objednávka dostane `MAX + 1` ze všech právě existujících objednávek dané události, včetně stornovaných. Po úplném smazání nejvyšší objednávky se její číslo smí použít znovu. Souběžné objednávky a velký nápor musí být podporované. Nezavádět čítač nejvyššího čísla přiděleného v minulosti: odporoval by povolenému opětovnému použití čísla.

V aktuálních objednávkách i tabu Vstupenky bude checkbox **„Pouze nestornované (N)“**. Tento název je přesnější než „Pouze platné“: nestornovaná objednávka může být ještě nezaplacená nebo po splatnosti. Filtr nerozhoduje o oprávnění ke vstupu, platbě nebo kapacitě.

Příklad: objednávky mají pořadí 1, 2, 3. Storno čísla 2 ponechá při zapnutém filtru 1 a 3; další objednávka má 4. Smazání objednávky 4 dovolí nové objednávce znovu získat 4. Dvě vstupenky jedné objednávky mají stejné pořadí objednávky, ale své vlastní ticket symboly.

## 2. Rozsah

Zahrnout SQL přidělení a doplnění pořadí starších objednávek, existující autorizované read projekce, Dart modely, sloupce objednávek/vstupenek/historie objednávek, oba checkboxy, jejich počty, bezpečný výběr pro hromadné akce a export. Historie zobrazí stejné pořadí pro orientaci, ale nebude filtrovat minulé stornované stavy.

Neměnit `order_symbol`, jeho střídání číslic/písmen, ticket symboly/QR, ID/FK/RPC identity, bankovní reference, párování, idempotenci, email intent keys, sent snapshots ani veřejná potvrzení/PDF/e-mailové šablony. Pořadí je interní údaj administrace; není náhradou veřejného symbolu ani globálně unikátní identitou. Neměnit ostatní tenant větve nebo tenant branding. Tento plán sám neautorizuje commit/push, migraci ani nasazení nové změny; souhlas s předchozím order-symbol release se na ni automaticky nepřenáší.

## 3. Ověřené podklady

| Fakt | Zdroj | Dopad |
|---|---|---|
| Runtime má 3 287 objednávek v 78 událostech, největší událost má 559; žádná objednávka nemá NULL occasion. 342 objednávek a 628 vstupenek je stornovaných; žádný NULL stav v těchto tabulkách. | Nový read-only catalog/agregovaný dotaz přes `festapp-backend-access`, ověřený hostname/runtime/current DB `festapp_rehearsal_20260909220601`, 2026-10-06. | Počáteční převod je malý. Údaje před budoucí migrací znovu ověřit; nepracovalo se se zákaznickými řádky. |
| Runtime writer je `public.create_ticket_order_internal_v1`, symbolový insert má vlastní nejvýše 10 pokusů. | `database/functions/eshop/create_ticket_order.sql`, řádky 147-163; facade `database/functions/eshop_orders/create_ticket_order_client_sync_v1.sql`. | Pořadí přidělit jednou před symbolovou smyčkou, ve stejné transakci. Replay nesmí alokovat další číslo. |
| OrdersContent načítá get_orders_tab_data; TicketsTab používá DbTickets.getAllTickets -> get_orders a relatedOrder. | `lib/components/eshop/views/orders_content.dart`, `tickets_tab.dart`, `db_orders.dart`, `db_tickets.dart`. | Není třeba nový endpoint, nový dotaz pro každou vstupenku ani druhý výpočet pořadí. |
| Objednávky mají explicitní projekce v obou větvích get_orders; historie připojuje metadata živé objednávky. | `database/functions/eshop_orders/get_orders.sql`, `database/functions/eshop/get_order_history.sql`, `get_latest_order_history.sql`. | Doplnit skutečný sloupec do explicitních projekcí, ne do historického snapshot data. |
| Částečné storno ruší jednotlivé tickets a ponechává zbytek objednávky; úplné storno mění i order. | `database/functions/eshop_orders/storno_tickets_bulk.sql`, `internal_storno_tickets_221.sql`. | Orders filtr sleduje order.state; Tickets filtr ticket.state a stav rodiče. |
| Úplné smazání objednávky skutečně existuje. | `database/functions/eshop_orders/delete_order.sql`: `delete_order_221`. | MAX se musí počítat z existujících řádků. Nezaměnit storno se smazáním. |
| Symbolový sloupec má společnou definici a šířku 160. | `lib/components/eshop/eshop_columns.dart`: `orderSymbolColumn`. | Zmenšit jednu definici použitou v obou tabech. |
| Save tracking, tab refresh a column filters jsou součástí sdíleného controlleru. Reload clears tracking a HTML bindings. | `single_data_grid_controller.dart`: `loadDataOnly`, `applyDataToGrid`, `reloadIfClean`; `single_table_data_grid.dart`. | Přepnutí checkboxu nesmí reloadovat data ani obnovovat celý grid. |
| Hromadné akce obou tabů dnes berou checked z `refRows.originalList`, stejně jako header enablement. | `orders_content.dart:_getChecked`, `tickets_tab.dart:_getCheckedTickets`, `single_data_grid_header.dart`. | Skryté checked řádky je nutné odznačit a na mutation boundary pracovat pouze s viditelným výběrem. |
| Trina 2.3.0 podporuje `setFilterOnlyEvent`, `TrinaGridSetColumnFilterEvent`, eventManager.listener a FilterHelper.convertRowsToFilter. Běžný `stateManager.setFilter` zároveň resetuje row states. | `pubspec.lock`; instalovaný zdroj `trina_grid-2.3.0/lib/src/manager/state/filtering_row_state.dart`, `grid_state.dart`, `trina_grid_event_manager.dart`. | Použít podporovanou delegaci a jeden kombinovaný predikát. Neztratit dirty stav při přepínání. |
| CSV export používá aktuální `stateManager.refRows`. | `single_data_grid_controller.dart:downloadCsv`; Trina `lib/src/export/trina_grid_export_csv.dart`. | Jeden filtr gridu musí řídit i export. |

Reprezentativní cesta: send-ticket-order -> idempotentní facade -> internal writer -> orders; get_orders_tab_data/get_orders -> OrderModel -> aktuální objednávky nebo relatedOrder v TicketModel. Historie vrací pořadí joinem na stejný order. Všechny mutace nadále používají bigint ID.

## 4. Databázový kontrakt a souběh

### Vlastník

Nový `eshop.orders.order_sequence bigint`, v konečném schématu NOT NULL a kladný. Constrainty:

- `orders_order_sequence_key UNIQUE (occasion, order_sequence)`.
- `orders_order_sequence_positive_check CHECK (order_sequence > 0)`.

Sloupec nemá runtime default ani aplikační trigger. Přiděluje pouze canonical writer přes privátní `public.next_order_sequence(p_occasion bigint)`, PL/pgSQL VOLATILE SECURITY INVOKER, `search_path = public, extensions`, owner postgres. REVOKE všech API rolí včetně service_role a PUBLIC. Ponechat stávající read/row-lock práva, včetně service_role UPDATE(note_hidden), bez INSERT/UPDATE order_sequence.

### Algoritmus

1. Získat událost ze serverově ověřeného formuláře. Odmítnout klientské order_sequence/orderSequence na stejné vstupní hranici jako order_symbol, i uvnitř data; číslo nesmí zvolit klient.
2. Privátní helper odmítne NULL scope a získá transakční advisory lock: `pg_advisory_xact_lock(pg_catalog.hashtextextended('festapp:order-sequence:' || p_occasion::text, 0))`.
3. **V samostatném SQL příkazu až po získání locku** číst `COALESCE(MAX(order_sequence), 0) + 1` z `eshop.orders WHERE occasion = p_occasion`. Nezabalit lock a MAX do jednoho SELECT/CTE: snapshot vytvořený před čekáním by mohl být zastaralý. Helper musí zůstat VOLATILE.
4. Writer uloží kandidát do lokální proměnné a použije ho při insertu. Symbolová smyčka mění jen symbol; pořadí se nepřiděluje desetkrát. Lock se drží až do commit/rollback celé tvorby včetně platby, tickets a intentu. Úspěšný konkurent pro stejnou událost potom vidí nově uložené maximum.
5. UNIQUE je poslední pojistka i proti neočekávanému bypassu. Konflikt pořadí se nesmí spolknout v symbolovém retry ani vrátit zdánlivý úspěch. Zachovat stávající atomický error/rollback kontrakt.

Používat READ COMMITTED kontrakt skutečného PostgREST/RPC runtime. U REPEATABLE READ/SERIALIZABLE může pevný snapshot vyžadovat retry celé transakce; neslibovat automatické bezpečné přepočítání uvnitř stejného snapshotu. V žádné izolaci nesmí projít dvě duplicitní čísla. Neimplementovat retry po chybě ve stejné neplatné transakci a neměnit request payload/hash; případná pozdější podpora vyšší izolace vyžaduje retry celé command transakce se stejnou identitou. Ověřit a zaznamenat izolaci skutečného gateway před release, bez globální změny nastavení.

### Výkon

Unique B-tree `(occasion, order_sequence)` umožní indexový přístup k MAX v jedné události. Ověřit EXPLAIN v disposable DB s reprezentativním i větším datasetem. Není to scan všech tenantů ani `COUNT(*) + 1`.

Stejná událost se pro přidělení serializuje až do commit; různé události mají samostatné locky. To je vědomá cena přesného MAX+1 bez trvalého high-watermark čítače. Žádný globální mutex, session lock, klientský MAX, spin polling nebo neomezený retry. Při případné hash kolizi se jen zbytečně serializují dvě scope, správnost zůstává zachovaná. Storno ani hard delete nepotřebují další allocator: jejich commit je existující změna sady objednávek. MAX pod READ COMMITTED smí vidět předchozí stav dosud necommitnutého smazání; tehdy může vzniknout mezera, nikoliv duplicita. Po potvrzeném smazání musí další allocator použít nové zbývající maximum.

Nedržet během tohoto locku síťové volání/PDF/odeslání e-mailu. Stávající SQL writer tvoří durable email intent; nezavádět side effect před commit. Případný budoucí multi-occasion batch musí nabírat locky v jednotném pořadí, jinak hrozí deadlock. Pro velký nápor doložit throughput/latence a neprohlašovat neomezenou propustnost.

### Starší data a neměnnost

Při prvním převodu očíslovat všechny existující objednávky v události vzestupně podle `(created_at, id)`, včetně stornovaných a všech formulářů. Shodný timestamp rozhodne ID. Po přidělení se číslo nemění při platbě, stornu, změně údajů, třídění ani filtrování. Všechny tickets čtou pořadí své objednávky. Přesun již očíslované objednávky do jiné události není podporovaný nový write path.

Opakovaný/residual převod mění jen NULL pořadí a přidává je za existující MAX, deterministicky podle `(created_at, id)`. Nikdy nepřečíslovat již vydané hodnoty. Zachovat ID, symbol, timestamps, data, state, ceny, reference i snapshots; do ordinality nepočítat jen viditelné nebo nestornované řádky.

## 5. Modely a administrace

- `OrderModel.orderSequence` je čtená hodnota z order_sequence; generické write toJson ji neodesílá. `toBasicString` zůstává veřejný symbol. TbEshop doplnit konstantu.
- `OrderHistoryModel` nese stejnou hodnotu z live-order projekce; synthetic current-state history ji kopíruje z OrderModel. Neměnit order/history ID.
- `TicketModel.toTrinaRow` vezme pořadí z `relatedOrder`, ne z ID ticketu, symbolu nebo pozice řádku. Přidat referenci na rodičovský model pro filtr stavu rodiče, použít existující ORDER_MODEL_REFERENCE.
- Nový readonly numerický ORDER_SEQUENCE, titul „Pořadí objednávky“, šířka přibližně 80-90 px, tooltip/help vysvětlí scope události. Numeric sort i CSV musí být 2 před 10. Žádná editace/renumber action.
- V OrdersContent a TicketsTab umístit pořadí před order symbol. Historii dát stejné pořadí k symbolu pro orientaci; nestornované checkboxy tam neaplikovat.
- Runtime upřesnění během implementace: `DataGridColumnHeader.install` rezervuje pro interaktivní help/menu/filter nejméně 160 px. Tyto dvě úzké identity použijí veřejný Trina titleRenderer s tooltipem, původním context menu a indikátorem filtru; ostatní hlavičky beze změn.
- Společný orderSymbolColumn zmenšit ze 160 na výchozích **120 px**. Zachovat všech 10 znaků čitelných a kopírovatelných, plný význam názvu dostupný v header help/tooltip. Ověřit reálné měření i pro široká písmena; při nedostatečném prostoru volit nejmenší šířku, která celý symbol zobrazí, ne jeho ořezávání. Nezmenšovat ticket symbol nebo zákaznické sloupce náhodně.
- Aktualizovat CS/EN katalogy a synchronizované web kopie podle konvence, ne tenant overlay translations. Čerstvý canonical orders response bez pořadí po contract je chyba kontraktu; staré samostatné/replay DTO mohou field nemít. Nepřidávat lookup či nové aliasy kvůli starému anonymnímu replay, protože interní pořadí na veřejném potvrzení nezobrazujeme. Staré stored receipts/sent payloady se nepřepisují.

## 6. Filtr a počty

### Definice

| Tab | Nestornovaná položka | Jednotka počtu |
|---|---|---|
| Aktuální objednávky | `order.state != 'storno'` | Objednávka/přihláška, ne součet tickets |
| Vstupenky | `ticket.state != 'storno'` a rodičovský `order.state != 'storno'` | Vstupenka |

Paid, ordered, sent, used i expired se ponechají. Pouhá nezaplacenost nic nevylučuje. Neznámý/NULL stav není důkaz storna a nesmí položku potichu skrýt. Při částečném stornu zůstane jedna objednávka a jen nestornované tickets. U nekonzistentního storno rodiče se jeho tickets při aktivním filtru schovají i pokud mají dosud jiný stav.

**N v závorce:** počet nestornovaných položek vyhovujících ostatním sloupcovým filtrům, počítaný před aplikací checkboxu. Je vidět i při vypnutém checkboxu. Příklad: celkem 10 objednávek, 2 storno -> checkbox `(8)`, grid vypnutý 10 / zapnutý 8. Vyhledání zákazníka najde 3, z toho 1 storno -> checkbox `(2)`, grid 3 / 2. Počet tickets se stejným postupem počítá z ticket rows. Stávající „Zobrazeno řádků“ nadále ukazuje skutečný výsledek; nulový count zobrazit bez spinneru.

Výchozí checkbox je **vypnutý** pro zachování dnešní viditelnosti. Stav je samostatný pro každý tab a po návratu do stejné mounted administrace zůstává zachovaný; nová událost má vlastní výchozí stav. Nepřidávat databázové preference/localStorage ani sdílený globální flag. To je návrhové rozhodnutí, ne výslovně potvrzená preference uživatele.

### Jeden gridový filtr

Přidat minimální volitelnou hranici do stávajícího SingleDataGridController pro dodatečný row predicate a jeho přepnutí bez reloadu. Jen oba cílové controller instances si zapnou tento režim; ostatní grids běží dosavadní cestou. Sdílený header dostane volitelný builder pro checkbox, ostatní akce a vizuál se zachovají. Nezavádět framework faceted filters.

Pro opt-in instances při onLoaded použít veřejné `setFilterOnlyEvent(true)` a subscribe přes `eventManager.listener` na `TrinaGridSetColumnFilterEvent`. Spojit `FilterHelper.convertRowsToFilter` (včetně stávajících contains/no-diacritics filtrů) s domain predikátem; výsledkem nastavit public `stateManager.refRows.setFilter` a oznámit změnu. Nevolat zde běžný `stateManager.setFilter`, který resetuje row states. Event subscription se zruší při dispose/replacement; potlačit reentrant notification smyčku.

Zachovat originální row/cell objekty, dirty/deleted/new sets, HTML draft bindings, sloupcové filterRows a numeric sort. Po případném normálním/auto reloadu znovu aplikovat kombinovaný filtr, checkbox neresetovat. Count vychází z nefiltrované `stateManager.refRows.originalList` po native predicate, bez dodatečného predicate; nepřepočítává pořadí. Neopakovat plný scan řádků při každém hoveru/focus/selection notify: přepočet invalidovat změnou native filters, relevantní buňky, reload/row add/remove. Checkbox jen přepne view; cached candidate count je nezávislý na jeho hodnotě.

Na změnu jakéhokoliv filtru v těchto dvou gridech odznačit checked řádky, které nově nejsou viditelné. `_getChecked` a `_getCheckedTickets` zároveň vybírají checked pouze z `refRows.filterOrOriginalList`, ne originalList. Tím i stávající requiresSelection enablement nezůstane zapnutý kvůli skrytému výběru. Vyhodnotit výběr znovu těsně před vytvořením mutation seznamu. Nadále volat existující storno/send command boundaries s ID, nepřidávat jiné mutace.

Přepnutí není save/discard. Již rozpracované změny hidden rows se uchovají a zůstávají v existujícím save tracking; uživatel je po vypnutí filtru znovu uvidí. CSV obsahuje stejné řádky jako filtrovaný grid a zachovává numerické pořadí i veřejný symbol. U OrdersContent zatím nepřidávat nové export UI, pokud ho dosud nemá; upravit sdílenou export cestu a existující ticket export.

## 7. Implementační vlny

### A. SQL alokace a převod

**Cíl:** pevné pořadí přidělené atomicky a bezpečně při souběhu.

- Přidat canonical helper `database/functions/eshop/next_order_sequence.sql`, aktualizovat `create_ticket_order.sql`, canonical `database/tables/tables.sql` a explicitní read projekce výše. Rozlišit skutečné INSERT do orders od INSERT orders_history při bounded writer auditu.
- Nová expand migrace: nullable column, pojmenované constrainty, private helper/grants. V jedné transakci pod omezeným table lockem doplnit historické NULL pořadí a vyměnit canonical writer/reader. Nový writer se nesmí stát aktivním před inicializací historického maxima. Počáteční převod pod table lockem použije přímo owner SQL, ne helper čekající na advisory lock; migrace nesmí držet table lock a zároveň čekat na advisory lock writeru. Starý in-flight writer může ještě dokončit NULL insert; column proto v této první fázi ponechat nullable.
- Pro krátké dokončení těchto in-flight rows připravit dočasný owner-only residual helper/batch: advisory lock dané události první, potom row locks na NULL orders, nové hodnoty MAX+1; existing numbers neměnit. Stejná zámková disciplína jako writer. Před uložením dalšího čísla započítat i dosud přidělené řádky téže dávky.
- Contract je samostatná migrace: ověřit nulový počet NULL, validovat CHECK/NOT NULL, odstranit residual helper. V contract pod table lockem už pořadí nepřepočítávat ani nevolat helper s advisory lockem: nevyrobit zámkový cyklus s writerem držícím advisory lock před insertem.
- Aktualizovat owner SQL fixtures: explicitní helper a scope, nikdy runtime default umožňující bypass. Pořadí nenastavovat v klientských payloads.

**Selhání/kompatibilita:** 5s lock_timeout, celý schema/writer/data/ledger krok atomický. Na chybě rollback, žádné částečně vystavené nové UI. Před contract nechat doběhnout transakce původního writeru zahájené před expand; nepřerušovat cizí sessions. Ostatní staré klienty dál pracují s ID. Neočekávaný NULL occasion, nový writer bypass nebo velký nárůst objemu zastaví migraci a vyžaduje úpravu této vlny; neschovávat data.

**Ověření/exit:** disposable DB testy historického převodu, rerun, nulových/kladných hodnot, UNIQUE scope, ACL, concurrency, replay a rollback. Snapshot order fields kromě nového čísla identický. Žádný veřejný allocator/residual RPC.

### B. Modely a sloupce

**Cíl:** každá interní prezentace stejné objednávky používá stejné pořadí.

Upravit OrderModel, OrderHistoryModel, TicketModel, TbEshop, EshopColumns a column lists OrdersContent/TicketsTab/orders_history_content. Otestovat backend projection obou get_orders větví, history a relatedOrder; numeric sorting/serialization a tři tickets s jedním parent number. Zmenšit společný symbolový sloupec a zachovat kopírování. Doplnění uživatele během realizace: kliknutí otevře kompaktní popover s plným symbolem a tlačítkem Kopírovat, sdílený pro objednávky, vstupenky a historii. Nezasahovat email renderer ani přepisovat public label.

**Exit:** 2 a 10 se řadí numericky; číslo je stejné ve všech příslušných gridech, nevejde do write payload a nechybí na čerstvém serverovém read.

### C. Filtry, count, výběr a refresh

**Cíl:** checkbox bezpečně filtruje aktuální řádky, ne data/příkazy.

- Nová malá domain hranice `lib/components/eshop/order_grid_filters.dart` pro raw-state predicates a checkbox text/count; žádné odvozování storna z přeloženého titulku.
- Minimální opt-in row-filter/header seam ve stávajícím grid controlleru/headeru/onLoaded/dispose. Napojit oba taby. Parent state u TicketModel číst z parent reference; raw ticket state je první část existujícího state cell formátu, ne jeho localized suffix.
- Zachovat drafts, filters, sorting, refresh; odznačit newly hidden checked rows. Upravit výběr obou mutation handlerů na viditelné rows. Tickets scan a product edit dál použijí existující RPC; po reloadu se count a filtr aktualizují.

**Ověření/exit:** widget testy přes skutečný checkbox, native column filter, selection/actions a dirty note. Žádný nový RPC při toggle. Export souhlasí. Po částečném stornu count orders stejný a tickets klesne; po úplném stornu klesnou oba.

### D. Integrované ověření a předání

Po dokončení A-C dát targeted testy do jednoho batch, potom povinný repo `automation/test_all.sh` na finální změně; nepovažovat tolerovaný exit 0/skips za pass. Chybějící HTTP testy řešit vlastním disposable REST/Auth backendem, ne produkčními fixtures. Plný web E2E obou tabů s jedním active/storno/partially-storno order, reálným clickem, reloadem a dvěma událostmi. Skills/browser jen izolovaně headless; OneSignal může mít explicitní mocked boundary.

**Exit:** invarianty i absence obsolete výpočtu jsou prokázané, source/migration digests a pending operational steps zaznamenané. Teprve potom případný samostatně autorizovaný release.

## 8. Testovací matice

| Riziko | Nejlevnější správná hranice |
|---|---|
| Dvě stejné objednávky současně | Dva reálné pg clients a explicitní held transaction: B čeká před MAX, A commit -> B získá další číslo; po A rollback B použije nevydané číslo. |
| Velký nápor | Vlastní loopback DB, alespoň 16 paralelních clients a 100 reálných commandů do jedné události; bez duplicity, ztráty order/ticket/payment/intent, neomezeného retry či deadlocku. Zaznamenat total throughput a p50/p95 časů, ne odhad SLA. |
| Nezávislé události | A drží allocation lock, B do jiné události dokončí před A commit. Nepoužívat sleep jako jediný důkaz; wait/barrier/pg_stat_activity. |
| Idempotence a symbol collision | Stejný commandId vrací stejný order a pořadí; další order má MAX+1. Deterministický symbol conflict nezvýší pořadí dvakrát, exhaustion celý request rollbackuje. |
| Storno/smazání/gap | Storno nejvyššího -> další MAX+1; smazání nejvyššího -> povolené reuse; smazání prostředního nepřečísluje zbytek. Dva formuláře stejné události sdílejí sequence. |
| Migrace | Všechny states a timestamps ties; žádné přepsané symbols/history data; rerun zachová issued; residual NULL append; contract fail pokud NULL; nové orders během residual backfill. |
| ACL/tenant | Direct column writes i helper calls API rolí odmítnuté; no cross-tenant projection; service_role note lock privilege zachované; spoofed client number odmítnutý. |
| Grid | Count při off/on/column search, 0, unknown state, paid/expired/used; parent storno; pořadí po sort/filter stejné; dirty note zachovaná a save/discard stále funguje. |
| Destruktivní akce | Checked visible+hidden, toggle a column filter: hidden není v RPC argumentech ani selected count. Existující ticket/order commands mají pořád ID a stejnou idempotenci. |
| CSV a šířky | Filtered CSV skutečné rows; ordinal numeric, symbol plný; 10 širokých glyphů, header controls, větší text a úzký viewport. |
| Návrat/reload/dispose | Checkbox a native filters zachované při tab return a explicit reload; nová událost nesdílí state; žádné duplicitní event subscriptions/reentrant updates. |

Relevantní existující test seams: `database/tests/eshop/create_ticket_order_test.sql`, `create_ticket_order_errors_test.sql`, `order_symbol_test.sql`, `database/tests/get_orders_tab_data_tenant_scope_test.sql`; `web_client/scripts/test_order_symbol_database.js` jako vzor disposable concurrency harness. Rozšířit/nově vytvořit `order_sequence_test.sql` a `test_order_sequence_database.js` v těchto stejných runners. Dart model test `test/components/eshop/models/order_email_cell_test.dart`, command tests, permissions test, `test/components/single_data_grid/tab_refresh_test.dart`, `data_grid_dirty_actions_test.dart`; nové domain grid tests pokryjí skutečný caller, nikoli kopii predicate. Cílený `fvm dart analyze` na upravené soubory.

## 9. Ledger odstranění a omezeného ponechání

| Cesta | Výsledná akce |
|---|---|
| Klientské row index / COUNT(active) jako pořadí | Nevytvářet; jediný canonical zdroj je persisted order_sequence. |
| MAX bez transakčního locku | Zakázaný bypass, i uvnitř generického serializeru. |
| High-watermark counter / global ordinal | Nevytvářet, uživatel výslovně dovolil reuse po smazání. |
| Kopie pořadí na tickets nebo history.data | Nevytvářet; používat parent/live-order read metadata. |
| OriginalList selection v obou target mutation handlers | Nahradit visible checked rows; handler test prokáže absence hidden IDs. |
| Filtrování loadData pomocí where nebo reload při toggle | Nevytvářet; uchovat všechny source rows/drafts a jeden kombinovaný grid predicate. |
| Temporary residual backfill RPC | Owner-only, contract ho odstraní; API ACL a to_regprocedure absence proof. |
| ID, public order symbol, legacy replay symbol adapter | Ponechat: jiná jasně vymezená identita/retention hranice, ne nový fallback pro pořadí. |
| Staré migrace, baseline, sent receipts, email templates | Nepřepisovat. Nové canonical SQL + nové ledgerované migrace. |

## 10. Rollout a rollback

Samostatně autorizovat další publish/release. Před publikací fetch authoritative main a vybraný tenant; při posunu upstreamu aktualizovat base a relevantní validaci. Main je chráněný požadavkem PR/review; nepoužít znovu administrátorský bypass z předchozího release. Tenant scope při případném nasazení zůstává pouze `prod/festapptickets`, pokud uživatel nenamenuje jiný.

Znovu ověřit aktivaci tenant/org3, canonical runtime DB, skutečné writers/grants, row count/no NULL occasion, migration ledger a lock budget. Chráněná záloha a id->order_sequence mapping, kontrola ostatních order fields před/po. Expand s inicializací a writerem, doběh starých transactions, residual pouze NULL, contract, až pak nové UI. Neprovádět produkční load testy, nevytvářet testovací objednávky ani neposílat testovací emaily.

Rollback aplikace může vrátit předchozí UI, ale nesmí přepsat order symbols nebo již přidělené pořadí. Zachovat nový writer po NOT NULL; starý writer bez pole by selhal. Nestornované je view-only, lze vypnout/vrátit UI bez změny stavů. Nekorigovat mezery nebo povolené reuse zpětným přečíslováním.

## 11. Podmínky dokončení a zbývající rozhodnutí

- Canonical creation, replay, concurrency i selhání respektují per-occasion MAX+1 a povolené reuse po smazání.
- Orders, tickets a historie používají číslo stejného parent order, readonly a numeric.
- Oba checkboxy/count/export/selection mají sjednocený scope; storno rodiče/částečné storno i drafts jsou otestované.
- Symbol je čitelný v užším sloupci; jeho generátor/format/value se nemění.
- Schema/consumer rollout je prokázaný lokálně a skutečné provozní kroky označené jako provedené nebo pending; žádné falešné pass pro skips.

Zásadní produktové otázky scope/MAX/reuse jsou potvrzené. Default checkbox off a přesný text „Pouze nestornované“ jsou zdůvodněné návrhové volby, které lze změnit bez změny SQL architektury. Požadavek vysokého náporu nemá číselné SLA; implementace musí ukázat měření a cenu serializace stejné události. Hlavní zbytkové riziko je délka transakce canonical writeru při velkém počtu tickets, nikoli správnost unikátnosti při běžném souběhu.
