# Osobní přehled objednávky - follow-up kapacity formuláře

Datum: 2026-10-13. Stav: naplánováno, bez implementace a nasazení.
Revize po dokončení původní lokální realizace: 2026-10-13.
Ověřování budoucí implementace: **standard** (osobní odkazy, oprávnění, platební údaje).
Navazuje na [kapacitu a náhradníky](form-capacity-waitlist-plan-2026-10-13.md)
a její [rozpracovanou realizaci](form-capacity-waitlist-implementation-2026-10-13.md).
Tento dokument vlastní follow-up; nemění implementovaný lifecycle kapacity.

## Skutečný stav původní realizace

**Fakt:** evidence původní realizace nyní uvádí implementované vlny 1-6, migraci
aplikovanou v disposable DB, cílené backendové/klientské kontroly a skutečné
Flutter i anonymní JS UI ověření. Produkční migrace, commit, push a deploy provedeny
nebyly. Starší status v hlavičce původního návrhu není aktuální implementační evidence.

Přečtená [UI evidence](form-capacity-waitlist-evidence-2026-10-13/web-client-e2e.json)
dokládá předvyplnění Waiting One/Two, partial child za 100 CZK, fyzický reload
zbývající nabídky, následné full přijetí za 100 CZK a konečný stav Přijato.
Původní manage odkaz po dokončení bezpečně odmítá přístup bez osobních údajů.
Nejde o nově spuštěné ověření v této plánovací relaci: původní browser, dev servery
a disposable projekt byly podle evidence ukončeny. Níže uvedený současný vzhled
je ověřen čtením aktuálních rendererů a jejich zaznamenaným lokálním průchodem.
Evidence přiznává neověřený skutečný in-tab hashchange kvůli CDP reload selhání;
deterministická router regrese prošla. Follow-up musí tuto konkrétní hranici ověřit.

| Dnešní místo | Skutečné chování | Změna v tomto follow-upu |
| --- | --- | --- |
| JS `FormPage.init`, aktivní offer | Přímo načte předvyplněný formulář | Nad stejným formulářem souhrn přihlášky a již vzniklých objednávek |
| JS `renderWaitlistControls` | Termín, počet míst, checkboxy osob, produkty, Přijmout/Odmítnout | Zachovat výběr i jeho omezení; přehled není druhý výběr osob |
| JS `renderWaitlistManagement` | Titulek a checkboxy čekajících; manage umožní withdrawal | Přehled přidá read-only osoby a objednávky; withdrawal zůstane zvláštní potvrzenou akcí |
| JS success po acceptance | `init(link)` načte zbytek, potom result overlay | Pod overlayem aktuální přehled; zavření výsledku vrací přehled, ne nový submit |
| Flutter `_loadData` / `_waitlistMessage` | Terminal bundle s form=null končí samotným textem Přijato | View scope má vlastní větev čtení nezávislou na form=null |
| Flutter `_buildWaitlistPeople` | Stejný výběr osob, termín, původní akce | Souhrn a karty výsledných objednávek kolem stejného formuláře |
| `get_waitlist_offer_form`, terminal | Žádné osoby, platba nebo tickets; bezpečný konečný stav | Zachovat; trvalý přehled čte odlišné oprávnění |

Není třeba znovu implementovat registraci, návrh/odeslání nabídek, konverzi,
finalizer, kapacitní zámky, Fakturoid recovery, historii ani gated email queue.

## Výsledek a rozsah

Příjemce osobního odkazu má dostupný přehled své přihlášky a vzniklých objednávek.
Ze stejné obrazovky může otevřít existující přijetí nebo odmítnutí nabídky.
Po přijetí se vrátí do přehledu a později vidí aktuální platbu i využití vstupenek.
Pouhé otevření a obnovení stránky nic nepotvrzuje ani nemění.

První realizace pokrývá náhradnickou přihlášku, in-place conversion i všechny její
částečně přijaté objednávky. Flutter i veřejný JS klient používají stejný SQL read
kontrakt a své stávající formuláře. Přehled není další editor objednávky.
Plošné zavedení zákaznických účtů a přehledu pro všechny nezávislé běžné objednávky
je mimo tento follow-up; komponentu lze později využít i pro ně.
Jde o pracovní vymezení první vlny podle požadavku navázat na náhradníky,
nikoli technické tvrzení, že běžné objednávky nelze zobrazit.

**Storno zákazníkem zatím nepodporovat**, ani jako nefunkční tlačítko. Existující
odmítnutí nabídky a ukončení čekání nejsou storno přijaté objednávky. Administrátorem
stornovanou objednávku či vstupenku přehled umí přečíst. Budoucí storno musí mít
samostatný write kontrakt, oprávnění a pravidla vratek a kapacity.

## Výchozí evidence

- `database/functions/eshop_waitlist/capabilities.sql`: `get_waitlist_offer_form`
  vrací formulář a osoby; konečná nabídka vrací jen bezpečný terminal bundle.
  `check_waitlist_scope_internal` dnes rozlišuje manage/offer token; manage čtení
  využívá operaci withdraw a vyžaduje `waitlisted`. Samotný existující odkaz tedy
  nedává trvalý přístup k platbě po konverzi.
- Tentýž soubor: `get_waitlist_order_detail` je administrátorský detail, obsahuje
  participants a linkedOrders. Jeho obecná data se nesmějí převzít do veřejného DTO.
- `web_client/src/components/forms/waitlist_commands.js`: fragment
  `#waitlist?token=...&order_id=...` nebo `offer_id=...`, read RPC a receipted writes.
  `web_client/src/components/forms/form_page.js` a
  `lib/components/forms/views/form_page.dart` vlastní veřejný formulář.
- `web_client/src/components/forms/order_result.js` a Flutter
  `order_finish_screen.dart` vlastní potvrzení odeslání, nikoli průběžný stav.
- `PaymentInfoModel` má amount, paid, returned, currencyCode, deadline i zálohy.
  `database/functions/eshop_transactions/apply_transaction_pairing.sql` zapisuje
  součty paid/returned. Platební fakta a přechody zůstávají ve stávajícím backendu.
- `TicketModel` má ticket state. `update_ticket_to_used.sql` nastaví `used` a
  `updated_at`; updated_at není spolehlivý čas použití. Přehled ho tak neoznačí.
- `recalculate_order_payment_status.sql`: práh `paid` je
  `COALESCE(deposit_amount, order.price)`. Záloha tedy může přepnout order do paid
  před plnou úhradou. Projekce nesmí z tohoto stavu udělat „vše zaplaceno“.
- `schema.sql`: participants mají origin_order_id, current_order_id a ticket_id;
  accepted slots mají resulting_order_id. `accept_offer.sql` při split nastavuje
  source_waitlist_order_id a při full ponechá původní ID. To jsou skutečné vazby,
  nepoužívat odhady podle pořadí jmen či produktových řádků.
- `supabase/functions/_shared/orderOverview.ts` je HTML souhrn pro e-mail,
  nikoli živé čtení objednávky. `delivery_receipt` v send-ticket-order patří jen
  k potvrzovacímu e-mailu: `email_reporting.sql` ho omezuje na 15 minut a 15 čtení.
  Ani jedno nelze použít jako dlouhodobý osobní přehled nebo autorizaci platby.

Evidence je z rozpracovaného checkoutu. Před implementací ověřit aktuální diff
u uvedených souborů a konečný kontrakt původní realizace. Nejde o produkční evidenci.

## Chování přehledu

### Konkrétní obrazovka a navigace

Pořadí obsahu: název akce a symbol původní přihlášky, souhrn osob (čekají / nabídnuto /
přijati), aktivní nabídka s termínem, výsledné objednávky. Čekající přihláška nemá
celkovou cenu 0 Kč ani platební výzvu. U nabídky pokračuje existující formulář;
přehled všech původních osob je read-only, checkboxy existují jen uvnitř jeho výběru.
Akce „Ukončit čekání“ otevře existující výběr zbývajících osob a potvrzení.

Každá vzniklá objednávka má vlastní symbol, konkrétní osoby, položky, cenu a měnu,
platební blok a seznam vstupenek. Nevytvářet společný variabilní symbol, součet
zbývajícího čekání s cenou přijatých lidí ani souhrnný stav úhrady více objednávek.
Na mobilu karty pod sebou, dlouhé seznamy lze rozbalit. Stav vyjádřit textem i barvou.
Skryté formulářové odpovědi a doklady totožnosti do read-only přehledu nekopírovat.

Po acceptance zachovat dnešní potvrzení, platební QR a doručovací observer. Přidat
primární „Přehled objednávky“; sekundární „Pokračovat ve zbývající nabídce“ pouze
při stále platných pending místech. Back/zavření overlaye vrací přehled. Obnovení
view URL znovu načte backend; nikdy znovu neprovede acceptance. Chyba načtení přehledu
po úspěšném potvrzení nesmí objednávku označit za neúspěšnou nebo vyvolat nový submit.

| Situace | Zobrazení a povolená akce |
| --- | --- |
| Čekání | Osoby a stav čekání; platba zatím nevznikla, ne „nezaplaceno“ |
| Platná nabídka | Počet míst, termín, otevření existujícího výběru osob/produktů; přijmout nebo odmítnout explicitně |
| Částečné přijetí | Zbývající čekání/nabídka a samostatná karta každé vzniklé objednávky |
| Celé přijetí | Běžná objednávka se stejným ID/symbolem, bez falešné duplicity přihlášky |
| Platba | Cena, měna, evidovaná úhrada, zbývá uhradit, termín a existující platební instrukce |
| Záloha / částečná platba | Rozlišit zaplacenou zálohu od úplné úhrady; další termín podle současných pravidel |
| Bezplatná objednávka | „Bez platby“; netvrdit, že dorazil bankovní převod |
| Vstupenky | Jednotlivé položky: čeká na úhradu, platná/nepoužitá, použitá, zrušená; vydání/doručení není použití |
| Formulář uzavřen nebo funkce vypnuta | Existující přehled zůstává čitelný; akce podle aktuálních serverových pravidel |
| Neplatný/odvolaný přístup | Bez osobních údajů; bezpečná zpráva o nedostupném odkazu |

Platba vyjadřuje **evidovanou úhradu** v systému, nikoli důkaz právě provedeného
převodu. Zobrazit čas načtení a tlačítko Obnovit; po úspěšné akci přehled znovu
načíst. Při chybě nahradit stav jasným „Nepodařilo se aktualizovat“, nepředstírat
aktuálnost starých dat. Automatický polling není nutný pro první verzi.
Vstupenky bez ticket feature nevymýšlet; stav přihlášky stačí. QR a nové stahování
PDF nejsou součástí této vlny, zachovat stávající doručování vstupenek.

## Kanonické čtení a bezpečnost

### Přesný veřejný read kontrakt

Navržený `get_customer_order_overview(p_token text, p_order_id bigint)` vrátí
stávající code/errorCode envelope a následující allowlist. Order ID musí odpovídat
root scope tokenu; endpoint nevyhledává cizí root podle dodaného child ID.

| Pole | Obsah a vlastník |
| --- | --- |
| `root` | id, symbol, bezpečný titulek události, formLink; údaje z původní přihlášky |
| `serverTime`, `accessExpiresAt` | Čas snapshotu a expirace konkrétního přístupu |
| `people` | Stabilní id, veřejné jméno, effectiveLifecycle, currentOrderId; origin_order_id=root |
| `offers` | id, effectiveStatus, pendingPlaces, expiresAt; žádný token ani ciphertext |
| `orders` | Každá výsledná běžná objednávka právě jednou: id, symbol, state, personIds, veřejné položky, total, currency |
| `orders[].payment` | nullable pro chybějící platbu; amount, received, returned, totalOutstanding, depositAmount, depositDeadline, finalDeadline, status, dueNow, dueAt, reference, publicAccount, instructionsAvailable |
| `orders[].tickets` | distinct ticket id, personId pokud je prokazatelný, bezpečný label, rawState, displayStatus, usageStatus |
| `actions` | Jen zákaznické možnosti, nikdy admin allowedActions; view token má pouze refresh a navigaci |

Položky objednávky číst přes order_product_ticket, cenu použít uloženou objednanou,
nikoli aktuální cenu produktu v katalogu. Ticket více produktů nesmí být víckrát
v seznamu. Ticket symbol/QR do read DTO této vlny nepřidávat. Vazbu participant/ticket
číst přes ticket_id; chybějící vazbu neodvozovat z pořadí. U nesouladu tenant/form/
occasion vazeb odmítnout dotčené čtení bezpečnou chybou, ne rozšířit scope.

### Platba a použití nejsou stav objednávky

`amount` vychází z payment_info.amount, `received` z paid, `returned` z returned;
peněžní porovnání dělá SQL numeric. `totalOutstanding=max(amount-received,0)` odpovídá
současnému prahu párování; returned je samostatný fakt a nepřičítá se automaticky
do nové platební výzvy. Storno má přednost a skryje pokyny k zaplacení.
Pokud existuje paid_externally nebo jiný nejednoznačný manuální stav bez potvrzené
sémantiky, vrátit status `unknown` a instructionsAvailable=false. Nevyrobit novou
bankovní úhradu ani sčítat paid_externally s paid bez ověření existujícího writeru.
Stejně postupovat při ručně potvrzeném paid/sent s nenulovou cenou a nulovou
evidovanou částkou: zobrazit potvrzený stav objednávky, úhradu jako neověřenou a
nevyzývat automaticky k další platbě. Nesoulad nesmí změnit order ani bankovní fakta.

Pořadí platební projekce: preparing_payment -> preparing; storno -> cancelled;
waitlisted bez payment -> not_required_yet; běžná nulová cena -> free; nenulová
cena bez použitelného payment_info -> unknown; jinak received=0 -> unpaid,
0<received<depositAmount -> partially_paid, depositAmount<=received<amount ->
deposit_paid, bez zálohy 0<received<amount -> partially_paid,
received>=amount -> fully_paid. Přeplatek a vratka jsou zvláštní částky/indikátory,
ne důvod tvrdit „nezaplaceno“. Order.state se zobrazuje odděleně.

Záloha nezaplacená: dueNow=max(depositAmount-received,0), dueAt=depositDeadline.
Záloha splněná nebo bez zálohy: dueNow=totalOutstanding, dueAt=finalDeadline.
Po termínu přidat příznak overdue, neměnit úhradu. CZK používá VS, EUR RF reference
podle `paymentPresentation.ts`; účet a reference z veřejné platební projekce,
nikoli ze secret bank config. Existující QR na success ponechat; průběžné přehledové
QR v první vlně nevytvářet, aby starý QR nevyzýval k původní plné ceně po částečné úhradě.

Ticket mapping podle CHECK constraintu v tables.sql:
`ordered` -> čeká na úhradu + usageStatus=unused;
`paid`/`sent` -> nepoužitá + usageStatus=unused;
`used` -> použitá + usageStatus=used;
`storno` -> zrušená + usageStatus=cancelled;
NULL/jiná hodnota -> stav není dostupný. Sent neznamená použití a může předcházet
doplatku při záloze. „Platná“ zobrazit pouze při ověření současných scan pravidel,
ne pouze podle této prezentační tabulky. Doručení e-mailu není použití ticketu.

**Rozhodnutí:** přidat úzce omezené read oprávnění `order_view` do stávajícího
capability mechanismu. Je oddělené od manage/offer oprávnění. Odkaz nabídky dál
respektuje svou expiraci a terminal bundle; neodvolávat bezpečnostní omezení proto,
aby mohl zobrazit následnou platbu. Na aktivní nabídce a v jejím potvrzení je
dostupný odkaz na přehled, doručený současně přes existující e-mailovou frontu.

Nový read endpoint, pracovně `get_customer_order_overview`, vlastní SQL projekci
nad orders, participants, offer slots, payment_info a tickets. Použije explicitní
allowlist veřejných polí, ne to_jsonb celé objednávky, raw order.data ani admin DTO.
Zahrne symbol, veřejné položky/osoby, stav objednávky, nabídky a jejich povolené
akce, samostatnou platbu a tickets každé propojené objednávky, serverTime.
Nevrací skryté poznámky, transakční protistrany, audit, token hashes ani cizí osoby.

Read scope je původní přihláška ve správném tenant/form kontextu a pouze její
ověřené výsledné objednávky podle source_waitlist_order_id a skutečných vazeb
účastníků/slotů. Klientské order ID ani sdílený e-mail scope nerozšiřují. In-place
conversion zachová vazbu. Partial children nejsou oprávněním číst další objednávky.

Token alespoň 256 bitů, uložený jen jako hash; raw delivery přes existující
šifrovaný payload a email_messages. URL fragment, POST čtení, no-store/no-referrer,
žádné tokeny v logu, historii, analytice či browser storage. Explicitní revokace
view tokenu musí odmítnout i read, na rozdíl od minimálního terminal čtení nabídky.
Expirace nabídky ani zánik čekání samy neodvolají samostatný přehled.

**Předpoklad pro životnost:** view token má samostatnou expiraci, výchozí návrh je
max(90 dní po occasions.end_time, 30 dní od vydání). End_time v modelu události
existuje; u poškozených dat bez konce odmítnout vydání s interním diagnostickým
důvodem. Hodnotu uložit při vydání, změna data akce ji automaticky neprodlužuje.
Interval je návrhová produktová volba, nikoli původní uživatelský požadavek.
Prodloužení musí být explicitní a auditované, nikoli neomezené zachování offer tokenů.

Read endpoint kontroluje scope v SQL, fixed search_path a ACL/RLS podle repository
pravidel. Případný service-role transport nesmí kontrolu přeskočit. Nezíská grant
na interní tabulky nebo finalizer. View token nikdy neopravňuje k accept/decline,
withdraw, platbě, skenování, editaci ani stornu. UI dostane jen povolené akce;
mutace nadále používají původní offer/manage auth a stávající command receipts.

**Předpoklad produktu:** odkaz patří objednateli skupiny, který může vidět osoby a
všechny výsledné objednávky své přihlášky. Přístup jednotlivých účastníků pouze k
jejich údajům by vyžadoval další rozdělení scope a není implicitně slíben.

### Jak se přehled skutečně dostane do současného flow

Zvolená URL zůstane pod `/form/<formLink>` a použije nový explicitní fragment
`#order?order_id=<root>&token=<view>`. Parsery i router musí znát oba typy fragmentů.
Nesmí jen poslat nový token do dnešního `get_waitlist_offer_form` a čekat, že uspěje.
V jedné tab/history entry je vždy jeden primární capability fragment; offer/manage
scope pro rozpracovanou akci je jen v paměti, nikdy v browser storage.

Nové registrace připraví zároveň manage a view token. Hash, scope, expirace a
šifrovaný delivery source view odkazu se uloží v téže registration transakci.
Rozšířit encrypted waitlist source a renderer o order_overview_url/button. Offer
e-mail přidá odkaz na tentýž přehled ze source původní přihlášky. Neodvozovat token
z order ID; nespoléhat na to, že SQL umí z hash získat raw token.

Pro aktivní původní offer/manage odkaz použít omezený Edge POST resolver, pracovně
`customer-order-access`: SQL ověří **aktivní, nerevokovaný** zdrojový scope a vrátí
jen service-role šifrovaný view source; Edge ověří kontext/hash a vrátí view URL
do paměti klienta. Řeší tedy i přímé otevření nabídky, bez nutnosti druhého kliknutí
v emailu. View link samotný nikdy nevydává offer/manage token ani nové write právo.
View UI otevře nabídku odkazem doručeným v původním emailu; pokud klient již drží
aktivní offer scope, může pokračovat přímo ve stejném formuláři. Nevymýšlet write
oprávnění pouze ze seznamu offer IDs ve view DTO.

Legacy registrace bez view source: resolver smí vytvořit source pouze po téže
aktivní autorizaci, pod root-order lockem, s command identity a šifrovaným receipt
bez raw tokenu. Souběžné bootstrap requesty musí vrátit stejný existující source;
nevytvářet novou generaci při každém otevření. Editor může samostatně reissue pro
objednatele a odvolat starou generaci; viewer role to nesmí. Terminal/revokovaný
offer nebo dokončený manage link nesmí tuto bootstrap cestu využít. U staré již
dokončené přihlášky je nutné autorizované nové doručení editorem, ne anonymní
obnova podle e-mailu. Žádný hromadný backfill plaintext tokenů.

Šifrovaný source musí přežít retention email_messages. Navržená privátní tabulka
`eshop.order_overview_sources` má token_hash FK na capability, sealed payload,
content_hash, created_at a expires_at, bez přímých anon/authenticated grants.
Použije současný sealEmail/openEmail a klíč; není novou frontou ani senderem.
Čištění vypršelých sources připojit do existujícího bounded cleanup jobu.
View expirace a revokace se ověřují při každém resolve i read.

Aktivní offer UI získá view přístup před acceptance a načte souhrn jako doplněk.
Failure tohoto doplňku nesmí zablokovat původní přijetí: zobrazit retry a zachovat
formulář. Po úspěchu s view přístupem nahradit URL fragment view fragmentem přes
router history API a načíst přehled; zbývající offer scope udržet v paměti pro
pokračování. Bez view přístupu ponechat dnešní úspěch a odkaz na přehled v e-mailu,
ne přehodit celé potvrzení na error. Reload view stránky nabízí původní offer
email pro pokračování, ne skryté rozšíření view oprávnění.

## Implementační vlny

### 1. Read scope a projekce

Navázat na nyní implementovanou realizaci. Rozšířit `eshop_waitlist/schema.sql`
o kind=order_view, odpovídající CHECK constraint (offer_id NULL, expiry NOT NULL)
a privátní sources tabulku. Nový `eshop_waitlist/order_overview.sql` vlastní read
DTO a oddělenou kontrolu view scope; nabídky/withdrawal se nepřesměrují na nové ACL.
Nepoužít admin `get_waitlist_summary_internal.allowedActions` ve veřejném UI.
Konkrétní SECURITY DEFINER read nastaví search_path=public,extensions, explicitně
ověří capability a přidělí anon/authenticated jen EXECUTE nad tímto read; interní
resolver sources a issuance zůstanou service-role s explicitním principal/scope checkem.
Změnu schématu přidat následnou migrací; nepřepisovat
již aplikovanou migraci kapacity. Platební stav projektovat z existujících pravidel
včetně záloh, vratek a přeplatků; netvořit druhý matcher nebo nový výpočet v UI.
Při neznámém stavu bezpečně vrátit „stav nelze určit“, ne odhad paid podle order.state.
Řešit čtení z konzistentního snapshotu při souběhu přijetí, párování a skenování.
Původní assembler vlastní historickou waitlist migraci; nezměnit jej tak, aby nový
follow-up přepsal aplikovanou verzi. Pro nový SQL source zavést samostatný scoped
assembler s novým migration targetem a porovnáním obsahu při validaci.

Ověření: nový SQL test `database/tests/eshop_orders/customer_order_overview_test.sql`
v disposable DB; valid/invalid/revoked/expired/cross-tenant token, manipulované ID,
in-place/partial scope, výslovné odmítnutí write operací. Exit: veřejný DTO dává
správná fakta a žádná širší oprávnění.

### 2. Vydání odkazu a návrat z nabídky

Rozšířit `supabase/functions/waitlist-commands/index.ts`,
`_shared/waitlistEmail.ts`, `_shared/waitlistEmailRenderer.ts`, SQL
`offers.sql` (enqueue source), `commands.sql` (registration commit),
`email_render_context.sql`, `email_templates.sql` a `email_preview.sql`.
Zachovat zděděné occasion/unit/organization templates, jejich existující proměnné
i encrypted source version; nový writer/reader payload version nasadit kompatibilně.
Starý queued source bez view pole se vyrenderuje původním rendererem bez odkazu,
neodpadne na context mismatch; toto je ohraničená kompatibilita immutable emailů.
Nový resolver a issuance SQL implementují výše popsaný aktivní bootstrap/reissue.
Acceptance/finalizer/Fakturoid recovery kvůli přehledu neměnit.
Neodesílat přímý email. Retry nedvojí účinky a nemění platnost již vydaného odkazu.
Zaniklý offer token nestačí pro vydání trvalého view přístupu.

Ověření: cílené Deno testy delivery a SQL issuance, bez skutečného odesílání.
Exit: příjemce má samostatný opakovaně použitelný přehled a acceptance zůstala
beze změny; starý neplatný odkaz neodemyká citlivá data.

### 3. Veřejná obrazovka v JS a Flutter

Navázat na oba form_page a waitlist_commands, JS `order_result.js`, Flutter
`order_finish_screen.dart`. Přidat JS `order_overview.js` a Dart read model/widget
pod `lib/components/forms/`; transport nebude uložen do OfflineDataService ani sync feedu.
Upravit `web_client/src/services/router_service.js` (normalizace, hashchange,
preview/result history), Flutter známý capability fragment ve startup URL strategii
a FormPage._loadData. Oba fragmenty musí přežít cold open, overlay i reload.
Jeden read model pro oba klienty; renderer přehledu
oddělit od formuláře, znovu použít nabídku a form builders. Fragment parser výslovně
rozliší view od offer/manage odkazu. Přijetí vrací přehled i zbývající místa.
Lokalizace, mobilní rozložení, keyboard focus, loading/error/refresh.

Ověření: rozšířit `web_client/tests/forms/waitlist_flow.test.js`, přidat cílený
Flutter widget test pro přehled; targeted `fvm dart analyze` dotčených souborů.
Exit: všechny scénáře tabulky fungují v obou klientech a žádné storno tlačítko
ani write transport pro view token neexistuje.

### 4. Sjednocení a cílená acceptance

Ponechat order_result/finish jako potvrzení odeslání s přechodem do přehledu.
Nahradit nové klientské odhady plateb/ticket stavu společným DTO; administrátorský
detail a bezpečný terminal bundle nabídky mají vlastní zachované účely.
Aktualizovat feature README a evidenci realizace. Neodstraňovat jiné rozpracované flow.

Ověření: SQL matice pro čekání bez platby, ordered, zálohu, část/full úhradu,
free order, přeplatek, vratku/storno a tickets ordered/paid/sent/used/storno; JS/Flutter pro
partial acceptance, návrat, reload, síťovou chybu a uzavřený formulář. Pokud je
potřeba reálný UI smoke, repository local-e2e skill a izolovaný headless browser.
Exit: jeden průběžný přehled skutečných backendových faktů a oddělené původní akce.

### Konkrétní regresní případy a příkazy

1. Skupina 2: partial druhé osoby -> child 100 Kč, root stále čeká; následné full
   -> root 100 Kč. Přehled má dvě různé platby a každou osobu právě jednou.
2. Cena 1 000 Kč, záloha 300 Kč, received=300, order.state=paid: zobrazit zálohu
   zaplacenou a doplatek 700 Kč, nikoli úplnou úhradu. Received=1 000: doplatek 0.
3. Scan jednoho ticketu se dvěma produkty: jediná vstupenka se stavem used;
   následující refresh změní její stav, platby ostatních objednávek se nemění.
4. Used ticket administrátor vrátí na unused: projekce sleduje nový skutečný stav,
   neslibuje neexistující historický čas prvního použití.
5. Fakturoid preparing/recovery: read nezíská poloviční výslednou objednávku jako
   připravenou k úhradě; následný refresh korektně načte completed nebo obnovené čekání.
6. Zavření preview, result overlay a hard reload; změna offer -> view -> jiný view
   hash ve stejném tabu. Nedojde ke ztrátě scope, zobrazení staré cizí přihlášky nebo
   druhé acceptance. Skutečný in-tab průchod provést bez CDP network hooku, který
   v původní evidenci selhal; isolation domény držet jiným podporovaným způsobem.
7. Vypnutí waitlistu/zavření form: view čte historii, akce respektují původní SQL.
   Smazaná objednávka nebo událost: nedostupný přehled bez automatické nové registrace.
8. Expired/revoked offer, manage po full, podvržený root a cross-tenant source:
   nejde získat view source. View token při accept/withdraw/scan/storno neuspěje.
9. Dva bootstrap requesty a retry po ztrátě odpovědi: jeden aktivní source/generace;
   ciphertext není v public DTO, raw token není v receipt/log/history.
10. Pozastavená fronta, starý immutable source a nové zděděné šablony: původní
    queued email se nezneplatní, nový link má správný tenant a revocation/expiry.

Spustit cílený SQL test runner s `DATABASE_URL` ověřené vlastní disposable DB,
nikoli s produkčním tunelem; `node web_client/scripts/run_db_tests.js` a výslovný
seznam nového overview/issuance testu a dotčených waitlist capabilities/lifecycle/
Fakturoid sad. JS: `node --test` nad overview, waitlist_flow, order_result a router
testy; Deno nad novým resolverem a změněnými waitlistEmail/renderer testy; Flutter:
`fvm flutter test` s explicitními overview/widget/runtime/startup soubory a targeted
`fvm dart analyze`. Společný validační batch až po koherentní implementaci, ne po
každém editu. Žádná plošná testovací smyčka ani skutečný e-mailový provider.

## Rollout a hotovo

Implementace v rozpracovaném checkoutu zachová cizí změny. Ověřování jen proti
vlastní disposable DB dle CONTRIBUTING.md; porty ověřit, nekopírovat obecné DB URL.
Backend/schema/read ACL a email producer před novými klienty. Staré offer/manage
odkazy mají nadále původní omezenou funkci. Při návratu klienta na starší verzi
view granty nezvětšovat; případné stažení view flow provést revokací jeho tokenů.
Commit, push, produkční migrace, deploy ani rollout nejsou tímto plánem autorizované.

Hotovo znamená opakovaný přístup, správný scope při obou typech konverze, stav platby
a každé vstupenky z backendu, zachované přijetí/odmítnutí a průchozí cílené bezpečnostní
i UI testy. Žádné klientské storno, nový platební engine nebo nekontrolované čtení.
Zbytková rizika: rozpracované SQL/DTO se mohou změnit; historické vazby a platební
stavy je nutné ověřit při realizaci. Čas použití ticketu nelze slíbit z updated_at.
