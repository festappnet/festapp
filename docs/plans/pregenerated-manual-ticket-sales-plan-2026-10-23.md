# Předgenerované vstupenky a ruční prodej

Datum: 2026-10-23. Stav: lokálně implementováno a cíleně ověřeno; produkční nasazení není součástí zadání.
Plný release check: [release zastaven kvůli neúspěšné plné sadě](pregenerated-manual-ticket-sales-release-check-2026-10-23.md).
Výsledky a hranice ověření: [realizační evidence](pregenerated-manual-ticket-sales-evidence-2026-10-23.md).
Ověřování implementace: **standard**. Návrh vznikl společným průzkumem hlavního
agenta a výslovně vyžádaného subagenta **gpt-6-astra**, reasoning high.
Autoritativní dokument; realizační zadání je v
[připojeném promptu](pregenerated-manual-ticket-sales-EXECUTION-PROMPT-2026-10-23.md).

## Realizační upřesnění 2026-10-23

- Dodatečný požadavek uživatele: kompletní dávku stáhnout jako jedno tiskové PDF
  s více kusy na A4 podle skutečné plochy a rozměrů vstupenky, nebo jako ZIP
  jednotlivých původních PDF. Export vychází výhradně z neměnných uložených
  dokumentů; nevytváří další ticket/render/sale autoritu. Canonical forward
  migrace `20261024020000_pregenerated_ticket_batches.sql` přidává autorizovaný manifest.

- Uživatel při realizaci výslovně zúžil kompatibilitu: nepřidávat zvláštní
  podporu starších klientů. Společné serverové stock/admission guardy zůstávají.
- Současné `delete_occasion` odmítá každou akci s objednávkami včetně storno
  (`database/functions/others/delete_occasion.sql:19`). Zůstává tento auditní
  zákaz; nová funkce nevytváří alternativní teardown ani neodstraňuje PDF.
- Veřejný `select_spot` má omezení kupujícího. Blueprint batch command proto
  pod existujícími form/product zámky atomicky získá nejvýše 200 vybraných
  volných míst, respektuje cizí aktivní hold a používá stejný spot secret.
- Příprava 200 jednotlivých dokumentů potřebuje vlastní `batch-document`
  provozní budget. Obsahové/stránkové/bytové limity přebírá z `document.output`;
  běžné `ticket.document` ani veřejný checkout se nezvyšují.
- Starší source-parity migrace zůstávají neměnné. Nový explicitní forward
  manifest zaznamenává nástupce změněných zdrojů a efektivní katalog se ověřuje
  přes současnou baseline + všechny forward migrace.

## 1. Výsledek a produktové předpoklady

Pořadatel vytvoří například 200 skutečných vstupenek, stáhne tiskové PDF a prodává
vytištěné kusy ručně. Všechny jsou od vytvoření v současné sekci Vstupenky.
V Objednávkách mají vlastní panel dávky. Zápis prodeje konkrétních kusů zachová
QR, produkty i sedadla a vytvoří běžnou objednávku s dohledatelnou úhradou.

**Požadavky uživatele:** předgenerování, ruční prodej, viditelnost ve Vstupenkách,
upravená forma objednávkového panelu, stažení a začlenění do existující architektury.

**Zvolené předpoklady, které uživatel výslovně neurčil:**

- Předgenerování je zásoba: blokuje kapacitu, ale není prodejem, pohledávkou ani
  úhradou. QR začne platit až po zapsání prodeje. Před prodejem jej nelze vpustit
  ani přes potvrzení nezaplacené vstupenky.
- První verze zapisuje prodej online, za hotové, za plnou vytištěnou cenu.
  Kupující může být anonymní. Záznam prodeje musí proběhnout před použitím QR.
- Dávka má jeden formulář a měnu. Prodávat lze několik kusů jedné dávky najednou.
  Prodej bez připojení, slevy, dluhy, provize a přesuny mezi prodejci jsou rozšíření.
- Již vytištěné kusy nelze měnit na jiné produkty/sedadla. Oprava znamená storno
  a nový QR; vrácený prodaný lístek se nevrací se stejným QR do zásoby.

Při zadání implementace podle tohoto plánu použít tyto předpoklady, pokud nové
zadání neurčí jinak. Změna na platnost při tisku/výdeji prodejci vyžaduje změnit
lifecycle a akceptační scénáře, nikoli pouze text tlačítka.

### Uživatelský průchod

1. Objednávky -> Předgenerované -> Vytvořit dávku. Název, formulář, produkty,
   množství nebo výběr konkrétních sedadel v Blueprintu.
2. Náhled ukáže serverovou cenu, měnu, blokovanou kapacitu a omezení tiskové šablony.
3. Potvrzení vytvoří zásobu. Panel ukáže přípravu tisku; chyba tisku nabízí Obnovit,
   nevytváří druhou dávku. Kapacita zůstává rezervována, dokud ji explicitně neuvolním.
4. Stáhnu jeden nebo několik tiskových PDF. Kusy vidím také ve Vstupenkách.
5. Zapsat prodej -> výběr kusů / zadání symbolu / načtení QR -> souhrn a hotovost.
   Volitelně zadám kontakt a zvlášť zvolím zaslání. Načtení QR nic neprodává.
6. Potvrzení atomicky vytvoří prodejní objednávku, přesune původní řádky položek
   a zapíše hotovost. Po nejasném výsledku se obnoví stejný příkaz.
7. Neprodané kusy zůstávají v zásobě; Zneplatnit je zneplatní a uvolní kapacitu.
   Prodané kusy mají standardní storno/vratku, se zachováním historie původu.

## 2. Doložená architektura a její důsledky

Průzkum je nad lokálním pracovním stromem, nikoli nad produkcí. Při zahájení byl
HEAD `353394511`, větev `feat/occasion-setup-wizard-20261007`, s rozsáhlými cizími
rozpracovanými změnami. Před realizací ověřit aktuální stav dotčených souborů.
Nebyly načteny produkční údaje ani spuštěny aplikační testy.

| Potvrzený fakt | Přesný vlastník / důsledek |
| --- | --- |
| SQL vlastní zápisy; klienti jsou adaptéry. | `lib/components/eshop/README.md`; batch příkazy patří do SQL, ne do série klientských RPC. |
| Jeden lístek je `eshop.tickets`, položky/objednávku propojuje `eshop.order_product_ticket`, sedadla odkazují na ID položky. | `database/tables/tables.sql`, `eshop/order_seating.sql`; prodej musí zachovat ticket.id/symbol, opt.id, spot.id i spot.resource/resource_slot a inventory_context. |
| Checkout finalizer normalizuje odpovědi, vyžaduje email, čte nynější ceny, generuje symboly, vytváří payment_info a volá apply_allocations i auto-import. | `eshop/finalize_ticket_order.sql: finalize_ticket_order_internal_v1`; nelze jej zavolat pro prodej již vytištěných kusů. |
| Identita order se přiděluje samostatně. | `eshop_waitlist/tickets.sql: allocate_ticket_order_identity_internal`, `eshop/next_order_sequence.sql`, `generate_order_symbol.sql`; používat i pro stock a nové prodeje, nevymýšlet vlastní číslování. |
| Form capacity počítá DISTINCT tickets přes orders/opt, odděleně offers a waitlist. | `eshop_waitlist/form_capacity.sql`; zásoba obsazuje kapacitu jednou, prodej pouze mění vlastníka. |
| Pool allocation může přidělit fyzické resource. | `inventory/apply_allocations.sql`; při prodeji jej znovu nevolat. |
| Změna product inventory contexts přepočítává existující objednávky. | `inventory/update_product_inventory_contexts.sql`; je nutný i nepřímý dependency guard pro předtištěné kusy. |
| Vstupenky se v Dart načítají přes objednávky. | `DbTickets.getAllTickets` -> `DbOrders.getAllOrdersBundle`; globální odfiltrování stock v get_orders by odstranilo lístky ze sekce Vstupenky. |
| Práva UI jsou také serverová projekce, klient má fallback. | `eshop_waitlist/capabilities.sql`, `models/order_model.dart: allows`; stock vyžaduje explicitní allowedActions, read_only nesmí spadnout do běžného fallbacku. |
| Moderní scanner má projekci, fingerprint, snapshot a receipted admission; existují retained native/admin cesty. | `scanning/projection.sql`, `admission.sql`, `snapshots.sql`, `eshop_orders/scan_ticket.sql`, `update_ticket_to_used*.sql`; chránit všechny. |
| Scanner při změně ticket parent vyhazuje serialization_failure. | `scanner_lock_ticket_internal`; legitimní race s prodejem se zpracuje bounded retry stejného příkazu, nesmí být přijetím podle staré projekce. |
| Payment method je nyní jen bank nebo stripe; hotovost je manuální pohyb na CASH účtu. | `eshop_stripe/schema.sql`, `eshop_transactions/insert_manual_transaction.sql`; nepřidávat metodu cash bez změny celé veřejné smlouvy. |
| Paid transition volá enqueue_paid_order_tickets; ten kontroluje přítomnost email klíče, ne volbu zaslání. | `eshop_orders/update_order_and_tickets_to_paid.sql`, `emails/email_domain.sql`; samotný kontakt by jinak spustil nechtěné zaslání. |
| PDF se dnes generuje na vyžádání z aktuálního occasion/catalogu, nikoli z hotového archivního PDF. | `download-ticket/index.ts`, `_shared/ticketGeneration.ts`, `ticketRenderData.ts`; stabilní dávkový tisk potřebuje explicitní snapshot a privátní artefakty. |
| Layout má schemaVersion 3 a binding orderName, ale nemá orderSymbol. | `lib/components/ticket_layout/README.md`, `_shared/ticketLayout.ts`; neměnit globální binding schema kvůli této funkci. |
| Report valid zahrnuje non-storno/non-waitlisted orders a ticket_days používá tickets.created_at. | `eshop/get_report_ws.sql`; stock by zkreslil platné počty a datum prodeje. Nutný odlišný scope a datum skutečné prodejní objednávky. |
| Fakturoid má prepare/complete/abort workflow mimo SQL transakci. | `send-ticket-order/index.ts`, `emails/fakturoid_email_gate.sql`; hotovostní příkaz jej nesmí tiše obejít. |
| Checkout limit je 20, PDF policy default 20 stran a 16 MiB. | `eshop/ticket_order_limit.sql`, `abuse/seeds.sql`, `_shared/documentLimits.ts`; 200 kusů nesmí znamenat rozšíření veřejného checkoutu nebo jednu neomezenou odpověď. |
| Bootstrap obsahuje následné ALTER rozšiřující tickets o waitlisted. | `database/tables/tables.sql` okolo ř. 1394; posuzovat celý výsledný kontrakt, ne první CREATE TABLE. |

Cesty v tabulce bez prefixu jsou relativní k `database/functions/`, pokud nejde
výslovně o Dart/Edge. Kontrakt nevychází z názvu funkce, ale z jejího těla.

## 3. Zvolený model a odmítnuté alternativy

**Rozhodnutí:** jedna dávka s jednou technickou stock objednávkou. Jednotlivé
vstupenky zůstávají v dnešním ticket modelu. Při prodeji se jejich již existující
položky přesunou do nové běžné objednávky. Jde o rozšíření eshop domény,
nikoli samostatný skladový systém.

| Varianta | Závěr |
| --- | --- |
| Označit předem běžnou objednávku paid/sent | Zamítnuto: nepravdivé finance, platnost QR a e-mailové efekty. |
| Stock objednávka pro každý kus | Zamítnuto: stovky technických objednávek, zbytečné identity a komplikované skupinové platby. |
| Tickets bez order/product vazeb | Zamítnuto: obchází současné kapacity, Blueprint, scanner a dokumentové čtení. |
| Druhá tabulka s QR a vlastním sold/used lifecycle | Zamítnuto: dvě autority pro stejný vstup. |
| Přidat p_stock/p_manual do monolitického checkout finalizeru | Zamítnuto: skryté větvení cen, e-mailů, form validací a opětovné alokace. |
| Jedna stock order + existující tickets/opt + specializovaný sale command | Zvoleno: zachovává dnešní relační graf i atomické obchodní operace. |

### 3.1 Navržená perzistence

Nové tabulky v eshop schématu, všechny funkce v public. Konkrétní DDL patří do
`database/functions/eshop_ticket_batches/schema.sql` a odpovídající forward migrace.

- `ticket_batches`: UUID, occasion/form FK, jedinečný stock_order_id FK, title,
  created_by/created_at, currency_code, immutable commercial/print snapshot.
  Stock order.state='stock', price/payment_info NULL, žádný VS/deadline/deposit.
  Má normální order_symbol/sequence a data.tickets snapshot pro dosavadní čtení.
- `ticket_batch_items`: batch_id, ticket_id UNIQUE FK RESTRICT, ordinal UNIQUE
  v dávce a immutable `sale_order_id` NULL nebo FK na skutečný první prodej.
  Zápis sale_order_id se provede právě jednou s prodejem. Je to historická
  událost původu, nikoli kopie aktuálního ticket/order state. Čas prodeje se
  odvozuje ze sale order.created_at; její smazání je zakázané.
- `ticket_batch_document_parts`: batch_id, stabilní part key, typ single/print,
  manifest hash, private object key, content digest, počet stran/bajtů a technický
  stav pending/rendering/ready/failed s lease tokenem, expirací a chybovým kódem.
  Žádné kopie QR v logu nebo druhý admission ledger.

Foreign keys a unique constraints vyjadřují jedinečnost přímo v DB. Scope shodu
batch/form/order/ticket zajišťuje transakční SQL s composite FK tam, kde ji lze
vyjádřit; klient nesmí přímo zapisovat žádnou z těchto tabulek. FK RESTRICT
nenahrazuje doménové rozhodnutí o storno/delete. RLS/granty ponechají tabulky
nedostupné anonymně; operátorské reads/writes jsou permission-checked RPC.

### 3.2 Odvozený životní cyklus

| Stav kusu | Ticket/order | Kapacita | Finance a vstup |
| --- | --- | --- | --- |
| Neprodáno | ticket ordered, owner stock, sale_order_id NULL | Blokuje | Bez finance, vstup zakázán |
| Zneplatněno před prodejem | ticket storno, owner stock | Uvolněná | Bez finance, QR trvale neplatný |
| Prodáno | stejný ticket, owner sale order, sale_order_id nastaven | Stále tatáž alokace | Skutečný pohyb, běžná platnost |
| Použito | ticket used ve stejné sale order | Dle dosavadních pravidel | Další vstup dle současného scanneru |
| Storno po prodeji | ticket storno, historie sale zůstává | Uvolněná | Běžná vratka; QR se nevrací do zásoby |

Počty dávky: available, soldActive, voidedUnsold, cancelledAfterSale. Jejich součet
je total; used je podmnožina soldActive. Cumulative sold není počet platných kusů.
Nevést kopie těchto počtů. Dávka je vyřízená, když available=0; pro první verzi
není potřeba přidávat nezávislý open/closed lifecycle.

Stock není anonymní přihláška a nevytváří occasion_users, companions ani skupiny.
Batch prodej s nepovinným kontaktem také automaticky nevytváří účastníky.
Členské/eventové produkty vyžadující osobní odpovědi nejsou v první verzi způsobilé.
Předgenerování přijímá jen serverově ověřené admission produkty podporující tento
anonymní ruční režim; required field online formuláře se tím globálně neuvolňuje.

## 4. Kanonické příkazy a transakční hranice

Semantic operation IDs jsou nové navržené rodiny, nikoli tvrzení o existujících RPC.
Transporty jsou staticky vázané, žádný univerzální JSON dispatcher.

| Operace / navržené RPC | Vstupy a výsledek | Authority |
| --- | --- | --- |
| ticket-batches.preview / preview_ticket_batch | Form, normalizovatelný výběr, max 200; server ceny/kapacita/template compatibility; nezakládá identitu | Order editor + occasion writable |
| ticket-batches.create / create_ticket_batch_client_sync_v1 | Command UUID, occasion/form, title, selection a spot secrets; batch ID, stock order ID, count, print preparation state | Order editor, scope a mutation admission |
| ticket-batches.inspect / get_ticket_batch_detail | Batch ID, bounded cursor; counts, položky, sale orders, allowedActions, export stav | Order-view právo pro skutečnou occasion |
| ticket-batches.sell / sell_ticket_batch_items_client_sync_v1 | Command UUID, batch ID, 1-20 explicit ticket IDs, volitelný kontakt, sendTickets boolean; sale order/transaction IDs a amount/currency | Order editor A SOUČASNĚ manager jednotky |
| ticket-batches.void / void_ticket_batch_items_client_sync_v1 | Command UUID, explicit unsold IDs, důvod; affected IDs a revision | Order editor |
| ticket-batches.export / prepare-ticket-batch-document | Batch/part ID; bounded práce a ready/pending/failed; žádný prodejní side effect | Order-view právo a document admission |

Při sell nejsou vstupem cena, měna, payment_info, seller ID ani symboly určené
klientem. Server je odvodí ze snapshotu a přihlášeného actor. Kontrola requestSecret
nebo service role není oprávnění uživatele k prodeji. Batch RPC nejsou anonymní.
Read projekce nepřebírají finance-edit authority z pouhého view práva.

### 4.1 Sdílená produktová operace a výslovná identita, nikoli druhý checkout

Z `finalize_ticket_order_internal_v1` oddělit privátní produktovou operaci pro již
normalizovaný výběr: serverové ceny/měna, validace form-product scope,
visibility/max, tvorba opt, propojení Blueprint spot a snapshot.
Výchozí oblast dnešního kódu je produktový/ticket blok přibližně ř. 185-403;
před extrakcí rozlišit odpovědi kupujícího, určení identity a produktovou validaci.

Identitní hranice musí být explicitní: checkout/batch vytvoří nové ticket IDs;
waitlist adapter zachová existující čekající ticket IDs a teprve jim přidělí
první admission symbol. Společná produktová operace pracuje s již určenými IDs.
Vyjímaný blok obsahuje p_offer větev aktualizující waitlisted ticket, proto jej
nelze mechanicky přesunout do helperu, který vždy vytváří novou vstupenku.
Regrese musí prokázat zachování identit při full i partial waitlist acceptance.

Běžný checkout zachová normalize_form_ticket_answers_internal,
validate_waitlist_answers_internal, limit20, payment/Fakturoid/reminder/auto-import.
Batch wrapper používá tentýž produktový primitive, vlastní bounded limit200,
žádné kupujícího odpovědi/finance/email/auto-import. Obě cesty sdílejí skutečnou
kapacitní autoritu, nikoli kopie SELECT count nebo ceníku.

Znovupoužít `allocate_ticket_order_identity_internal`, `generate_ticket_symbol`,
`lock_order_capacity_scope_internal`, `lock_ticket_order_products_internal`,
`order_tickets_with_seating_internal` a `apply_allocations` při vytvoření zásoby.
Nevyužívat waitlist p_offer jako bypass. Zkontrolovat ticket symbol collision
policy současného finalizeru a zachovat ji, nevymyslet oslabený generátor.

Admin max200 zavést v abuse policy se samostatným názvem batch-create.items;
veřejný ticket_order_limit=20 nezměnit. Mutation admission počítá skutečné položky,
nikoli jeden kus za dávku. Více než200 odmítnout před zápisem; UI umožní vytvořit
další explicitní dávku, neskrývá částečný úspěch pod jedním potvrzením.

### 4.2 Specializovaná materializace prodeje

V jedné SQL transakci:

1. Autorizovat actor, vyřešit occasion/unit z batch, check_occasion_writable,
   ověřit Fakturoid/produktovou způsobilost i nově zapnuté konfigurace.
2. begin_client_mutation_v1 se stabilním command name a canonical hash. Při replay
   znovu ověřit scope/práva; vrátit receipt bez nového finance admission/platby.
3. V existujícím pořadí admission a doménových zámků uzamknout form, stock order,
   dotčené závislosti a tickets. Znovu ověřit jednoznačného stock vlastníka,
   ordered state, sale_order_id NULL, shodu manifestu a připravenost tisku.
4. Přidělit novou order identitu stávajícím allocator. Sestavit sale order.data
   ze zmrazených kusů a volitelného kontaktu, nikoli z živého katalogu/form payloadu.
5. Jedním konzistentním přesunem změnit pouze opt.order u VŠECH produktových řádků
   vybraných tickets. Zachovat opt.id, product, ticket, spot.id/order_product_ticket, inventory_context
   a resource/resource_slot. Nastavit immutable sale_order_id; aktualizovat stock data.tickets.
6. Vytvořit non-Stripe payment_info s amount/currency bez bank_account, VS,
   deadline/deposit/creditor_reference. Vložit plnou hotovostní transakci přes
   společnou manuální platební autoritu a `apply_transaction_pairing`.
7. Ověřit návratový code paid transition; JSON chyba nesmí dovolit částečný commit.
   Uložit obě historie a Client Sync invalidace se source i destination order IDs.
8. Commit výsledek s order/transaction IDs a peněžními hodnotami; e-mailový worker
   se budí až po commitu, je-li explicitně vytvořen delivery intent.

**Zakázáno při prodeji:** create_ticket_order_internal_v1, běžný finalizer,
apply_allocations, generate_ticket_symbol, normalizace výběru podle nynějšího
formuláře, nové ověřování veřejně zbývající kapacity jako u nového checkoutu.
Dokončený prodej je možný i tehdy, když je remainingPublic=0.

### 4.3 Finance a e-mail

Současný payment_method='bank' je zde historická non-Stripe větev. Hotovost
prokazuje transactions.transaction_type/ingest_source='manual' na CASH účtu,
nikoli nový payment enum. Projekce vrací odvozený paymentChannel='cash',
nenabízí bankovní instrukce a platbu nikdy nesměruje podle VS.

`insert_manual_transaction` dnes používá double/int, vrací void a zakládá CASH
účet líně bez koordinace. Extrahovat privátní helper s numeric/bigint, vracející
transaction_id, se serializací unit+currency při hledání/založení CASH účtu.
Současný veřejný wrapper zachová signaturu, manager check a pairing sémantiku;
nový sell wrapper ověří obě potřebná práva a předá přesná canonical money.
Nevytvářet druhý výpočet paid/returned ani nepoužívat paid_externally.

Zvolená e-mailová politika musí být uložená před paid transition. Doplnit do
canonical order source metadata explicitní manual-delivery intent: kontakt sám
není souhlas se zasláním. enqueue_paid_order_tickets použije tuto politiku jen
pro batch-origin prodej, ordinary checkout zachová chování. Email klíč v anonymní
sale data nepřidávat jako prázdný/null. Explicit sendTickets vyžaduje platný email.
Ruční resend používá existující send-tickets a globální public.email_messages.
Pozdější storno/update producers musí prázdného příjemce bezpečně přeskočit;
kontaktní email bez volby zaslání může sloužit jen k oprávněnému pozdějšímu kontaktu.

V první verzi **FAKTUROID unit není způsobilá**: preview/create i sell vrací
CASH_SALE_INVOICE_WORKFLOW_REQUIRED. Jde o neimplementovanou integraci, nikoli
právní tvrzení o nutnosti faktury. Odpovídá principu explicitní nekompatibility,
který již používá Stripe form availability. Tvorba dávky nesmí vydat papíry,
pro které server předem ví, že je neumí prodat. Pozdější zapnutí Fakturoid sale
odmítne a panel vysvětlí důvod; storno neprodané zásoby zůstává dostupné.

### 4.4 Zámky, retry a efekty

Základní pořadí stávajících helpers je form -> orders -> products -> pools ->
contexts -> spots/tickets. Nespoléhat na tento seznam jako na globální důkaz:
implementace musí sladit konkrétní nové příkazy s retained scan/cancel a inventory
writers. Zvlášť `select_spot` zamyká spot přímo: create znovu uzamkne konkrétní
spot FOR UPDATE a ověří form.blueprint, hold secret, expiraci a nedostupnost.

Pro sale přidělovat target identity pod zámkem stejného form; nový neviditelný
target není soupeřící starší order. Rodiče ostatních tickets číst a uzamykat
v konzistentním ID pořadí. scanner_lock_ticket_internal ponechá parent recheck.
serialization_failure/deadlock -> bounded retry celé transakce se stejným command
ID; vyčerpání vrátí retryable outcome, ne částečnou účtenku nebo nové ID příkazu.

Dva prodejci stejného ticket: jen jeden commit, druhý ITEM_NOT_IN_STOCK. Sale proti
void: právě jeden výsledek. Scan před sale: tvrdé odmítnutí; po sale: běžné přijetí.
Mutation receipts a export leases nejsou druhý ticket ledger. Nedávat ticket
secrets ani kontakty do safeLabel/activity nebo veřejných sync artefaktů.

## 5. Integrace do existujících writerů a čtení

### 5.1 Zákazy změn tištěných kusů včetně nepřímých závislostí

Nový privátní guard pro batch-origin tickets chrání i PRODANÉ kusy, dokud nejsou
storno. Běžný `check_order_is_mutable` odmítne stock, ne všechny sale orders.
Akce podle konkrétního ticket dovolují hidden note, běžné použití/reset a storno;
zakazují změnu produktu, ceny, veřejné tiskové poznámky a sedadla.

| Místo / rodina | Povinná integrace |
| --- | --- |
| update_ticket_products_ws / update_ticket_products_client_sync_v1 | Odmítnout batch-origin změnu produktu/ceny, nikoli až po klientském save. |
| swap_spot_tickets, replace_blueprint_order_client_sync_v1 | Odmítnout výměnu, pokud kterákoli aktivní strana je batch-origin. |
| update_product_inventory_contexts_internal_v1 | Před apply_allocations odmítnout změnu mapování/quantity zasahující aktivní batch alokace. |
| Blueprint/update_spots_assignments, pool/resource edit/delete | Zachovat skutečnou identitu/resource a vytištěné fyzické místo; změnu závislého obsazeného místa odmítnout. |
| product/form deletion | Rozšířit dependency policy o zásobu; zabránit ztrátě reálné vazby, kterou potřebují capacity/cancel/scan. |
| ordinary cancel/delete, paid/sent, update email/responses, reminders/cron | Stock nemá běžné akce; nesmí dostat finance, auto-expiraci nebo zákaznickou delivery. |
| sale order delete / occasion teardown | Batch audit a sale_order FK chránit; ordinary order delete odmítne batch historii, occasion teardown explicitně zpracuje nové FK/artefakty. |
| auto-import / import_users_from_tickets | Stock nevytváří lidi; pro batch-origin anonymní sale zůstává v první verzi explicitně bez auto-importu. |

Guardy jsou úzké podle změněných závislostí. Budoucí cena/název produktu se může
změnit; staré tiskové a prodejní snapshoty se nepřepíší. Nový layout neovlivní
již vydané PDF. Změna data/místa celé akce zachová původní PDF jako historický
artefakt a panel upozorní na rozdíl; nová verze tisku je samostatné rozšíření,
ne tiché přegenerování dokončeného exportu.

### 5.2 Orders, Tickets, Blueprint a report

`get_orders` zůstane úplným autorizovaným relačním read bundle; stock z něj
neodfiltrovat globálně. Doplnit stock/batch metadata a skutečné serverové akce.
`get_orders_tab_data` a OrdersContent filtrují stock v prezentačním order list
scope; `DbTickets.getAllTickets` jej stále načte a sestaví tickets. Alternativní
nový ticket endpoint není v této vlně potřeba. get_order, history a Blueprint read
musí umět explicitní stock projekci. Zákaznické order scopes stock odmítají.

OrdersTab získá typovaný subtab **Předgenerované**, ne druhou aplikační navigaci:
`/:occasionLink/reservations/orders/pregenerated` a detail
`.../pregenerated/:batchId`. Přidat NavigationPaths, @RoutePage, AutoRoute a
RoutedTabDefinition; používat nearest router a validovat batch occasion před
mountem detailu. Regenerovat app_router.gr.dart, neupravovat ručně.

TicketsTab zůstává jediným seznamem: sloupec Původ (běžný / předgenerovaný),
Dávka a obchodní označení Neprodáno/Prodáno/Zneplatněno. Used/platební/delivery
stav zobrazovat podle jejich skutečného významu. Původ není stav a prodaný batch
lístek se nezmění na „online“. Detail odkazuje na dávku i sale order.

Panel dávky obsahuje odvozené counts, hodnotu zásoby odděleně od skutečně přijatých
peněz, neprodané kusy, prodeje a stav tisku. Akce Stáhnout PDF, Zapsat prodej,
Zneplatnit neprodané. Žádné „Označit zaplaceno“ pro celou stock order.
Prodejní dialog používá AppDialog, čerstvé serverové allowedActions a existující
command transport s durable intent. Při odpojení uchová výběr i command ID;
nový click po reloadu nesmí vyvolat druhý prodej stejného záměru.

`get_report_ws` zachová schema_version=1 a význam dosavadních keys:

- stock vyloučit z orders/sale totals, valid orders/tickets, order money,
  prodejních timeline a missing_order_price warning;
- všechny vytvořené tickets lze vykázat zvlášť v novém stock/batch rozkladu,
  stock však není potvrzený prodej produktu;
- kapacita/spots nadále zahrnují stock; vlastní kapacitní autoritu neměnit;
- datum batch prodeje v ticket sales timeline vychází ze sale order.created_at,
  nikoli z data předgenerování; běžné ticket timeline zachová dosavadní význam;
- platby/vratky výhradně z existujících finančních faktů, deduplikované po payment_info.

Model a formatter v `packages/festapp_core/lib/src/eshop/occasion_report_model.dart`
a Flutter report UI zpracují additive breakdown bez nové paralelní kalkulace.

### 5.3 Client Sync a operační katalog

Použít existující `begin_client_mutation_v1` a `complete_*_mutation_v1` podle
skutečně dotčených projekcí, v návaznosti na create/storno wrappers. Stock nesmí
pouze předstírat membership změnu; pokud completion helper zahrnuje zbytečný
profile import, vyčlenit sdílenou inventory-only completion bez kopií protokolu.

`eshop_ticket_batches/client_sync.sql` registruje nové relation sources do
`public.client_sync_component_sources` pro private_inventory, jejich canonical
writers a tracked columns. Rozšíří i zdroje orders/opt/tickets; stock sale publikuje
source i target a změnu parent, void invaliduje kapacitu a scanner eligibility.
Bez QR/kontaktů ve veřejné projekci. Export lease/status invaliduje pouze private
batch detail, ne katalog a membership. Doplnit bounded read/replacement payloads
pro nová UI data; nevkládat 200 PDF/QR do receipts.

Respektovat současnou canonical operations foundation, její source manifest a
source-parity testy při změnách existujících SQL vlastníků. Neupravovat historické
migrace. Nový forward migration musí sestavit aktuální závislosti a registry.
Semantic catalog `docs/architecture/operations/README.md` eviduje novou rodinu
jako plánovanou; runtime inventory regenerovat až po přidání reálných callers/SQL.
CLI/MCP nebo hosted write grants nejsou tímto plánem automaticky zpřístupněny.

## 6. Stabilní PDF ve stávajícím rendereru

Základ je současný schemaVersion3 layout a `_shared/generateTicket.ts`, nikoli
nový PDF engine. `_shared/ticketGeneration.ts` dostane explicitní snapshot
resource/catalog adapter. Pro dávku se nesmí při pozdějším downloadu ptát na
živý get_products_and_types ani měnit orderName podle nového vlastníka.

Create SQL zmrazí commercial i tiskové textové vstupy, layout config a odkazy
na zdroje. Následná request-driven příprava načte konkrétní font/background/logo
bajty bezpečnou existující resource cestou, ověří limity a uloží jejich immutable
hash/bytes. Dokud příprava neuspěje, stock blokuje kapacitu, ale nejde prodávat.
Nedostupný artwork je viditelná opravitelná chyba, ne důvod k nové dávce.

Před prvním renderem uzavřít přes SQL compare-and-set jeden resource manifest
celé dávky: přesná sada font/background/logo digestů a privátních immutable keys,
layout a katalogový snapshot, render contract version. Manifest se označí sealed
teprve po ověření všech uložených objektů. Žádný single ani print render nesmí
začít před sealed. Každá část potom čte výhradně stejné uložené bajty, ne živé
URL nebo právě upravený katalog. Dva souběžní přípravci nemohou uzavřít dvě různé
verze; vítězí jediný fenced commit, nepoužité uploady jsou technické orphan objekty.
Retry nedokončené přípravy nesmí přepsat již uzavřený manifest.

Preview odmítne aktivní layout s viditelným orderName pro anonymní dávku;
nevytváří fiktivní jména a nemění saved layout. Uživatel vybere kompatibilní
uloženou šablonu bez zákaznického jména. Datum/místo, product labels, price,
spot/table text a veřejná poznámka jsou snapshot. Hidden note není součástí tisku.
Validátory QR/quiet-zone/font IDs/geometry zůstávají stejné v Dart/TS/SQL.

**Nová nutná infrastruktura:** privátní Supabase Storage bucket
`ticket-batch-documents` pro immutable zdroje a PDF. Současné ticket-fonts je vzor
privátního storage adapteru, nikoli důkaz existence PDF archivu. Dokumenty se
neposílají do veřejného image Workeru ani do public Client Sync bucketu.
Nový bucket musí být v migrační/release konfiguraci i lokálním E2E setupu.

Příprava je bounded a obnovitelná po částech přes jedinou Edge hranici, s SQL
claim/complete/fail a lease token fencing. Žádný trvale běžící nový worker ani
neautorizovaný cron není potřeba. Otevření panelu může nabídnout pokračování;
prostý read detail nic nevytváří. Objekt se zapisuje pod immutable manifest/part
key bez overwrite, ready se publikuje až po ověření digestu a metadat.
Pád mezi upload/complete lze bezpečně zopakovat; zastaralý lease nesmí přepsat ready.

Uložit individuální ticket PDF a tiskové části se stejným stabilním pořadím.
Současný download-ticket pro batch-origin vrátí/obalí uložený single PDF po stejné
autorizaci; ordinary ticket zůstává na současné cestě. prepareTicketDelivery pro
batch-origin využije tytéž bytes při explicitním e-mailu, nikoli čerstvý živý render.
Tím se shoda papíru zachová i po prodeji a změně katalogu.

Tiskové části mají nejvýše současný policy limit stran (default20), input/assets
limity a output byte limit; při velkých zdrojích může být část menší. Rozdělení
je jednou zapsané v manifestu. Jeden příliš velký lístek skončí vysvětlenou chybou,
ne vypnutím limitu. Malá dávka stáhne jediné PDF, velká explicitní očíslované části.
Nový export vrací metadata a krátký autorizovaný download, ne neomezené base64.

Opakovaný hotový download vrací stejné bytes/digest i po prodeji. Starý export po
void/storno stále obsahuje neplatné QR; UI při novém stažení upozorní na počet
zneplatněných kusů. Artefakt není autoritou vstupu. Neprodávat jen podle toho,
že browser obdržel soubor - download nesmí změnit obchodní stav.

První verze neodstraňuje dokončené PDF/zdroje, dokud existuje aktivní batch-origin
vstupenka. Částečné orphan objekty po neúspěšném claim lze uklidit explicitním
fenced cleanup; kompletní occasion deletion musí odložit privátní object cleanup
jako trvalý intent, ne smazat DB a zapomenout bytes. Dlouhodobá archivace po
ukončení akce naváže na schválenou retenční politiku, ne tichý krátký TTL.

## 7. Skenování a offline hranice

Stock odmítají scanner_ticket_projection_internal a scanner_admit_ticket_internal,
lookup/search, get_scanner_summary, sync_scanner_operations, scan_ticket, get_all_tickets_for_scan,
update_ticket_to_used a jeho admin wrappers. Nejnižší sdílený mutability/admission
guard zabrání obejití přes retained klienta. Stock není requires_unpaid_confirmation.

Prodej mění parent a eligibility fingerprint ve stejné transakci. Změnit
projection/fingerprint tak, aby parent/stock eligibility nebylo neviditelnou změnou.
Fingerprint již obsahuje parent IDs/stavy; nevytvářet jeho druhou verzi bez
potřeby. Legacy get_all_tickets_for_scan stock zcela vynechá, protože starý
klient nezná stock state; moderní projekce může zobrazit důvod odmítnutí.
Snapshot pořízený před prodejem zůstává odmítavý; aby jej zařízení přijalo offline,
musí získat nový povolený snapshot. Neexistuje offline aktivace papíru bez sync.

Po prodeji platí dosavadní offline grant/revocation omezení: starý kladný snapshot
nemůže okamžitě vědět o novém storno. Neprohlašovat, že všechny offline kopie QR
lze okamžitě odvolat. Tato funkce nesmí prodloužit stávající grant nebo vynechat
serverový recheck při synchronizaci. Prodejní QR lookup je autorizované načtení
výběru, nikoli vstupní confirm a nepotřebuje scanner secret místo prodejních práv.

## 8. Implementační vlny a rozhodovací brány

### Vlna 1 - sdílený základ a bezpečná nedostupná zásoba

**Změny:** extrakce privátní product/ticket creation primitive z finalizeru,
beze změny ordinary checkout/waitlist contracts; nové schema, read projekce,
private_inventory registry, stock guardy všech ordinary writers/scanneru,
report scopes a indirect allocation dependency guardy. Create RPC zatím nemá
authenticated execute grant, UI ještě nevytváří zásobu. Forward migration je
source-parity kompatibilní, žádné přepisování historických migrací/backfill.

**Ověření:** současné create/errors/seating/waitlist SQL sady + nové dependency,
stock visibility/report/admission testy. Zdrojový audit callers je bounded podle
tabulky v sekci 5.1. **Exit:** nový stock graf je bezpečný i pro staré klienty,
ordinary checkout má stejný výsledek a neexistuje veřejná cesta k vytvoření stock.

### Vlna 2 - atomické vytvoření dávky a skutečný prodej

**Změny:** batch create/sell/void wrappers, private materializer, numeric cash
helper a serializace CASH účtu, delivery intent policy, form capacity revision,
obě historie, mutation receipts, privacy-safe completion/replacements.
Fakturoid a nezpůsobilé form/products odmítnout už v preview/create.

**Ověření:** níže uvedené SQL a dvousession concurrency scénáře; injekce chyby
po převodu opt a po pairing i při sync commit. **Exit:** stejná ticket/opt/spot/resource
identita, jeden platební fakt, retry bez druhé objednávky, sale při plné kapacitě.
Příkazy zůstávají bez produkčního zpřístupnění, dokud nemají PDF předpoklad.

### Vlna 3 - snapshot, privátní PDF a obnova

**Změny:** nový storage bucket/ACL, schema pro parts, resource adapter stávajícího
rendereru, Edge bounded claim/render/complete; batch dispatch v download-ticket
A prepareTicketDelivery. Hranici zaregistrovat v self-hosted function runtime
policy/bundle a Edge test inventory podle existujícího formátu, ne jen přidat index.ts.
Konkrétní runtime vlastník je `automation/hetzner-supabase/merge/runtime-writer-policy.json`
a `runtime/build-production-function-bundle.sh`.

**Ověření:** renderer/resource testy a storage/lease failure injection, bytes
identické před/po prodeji i změně produktu/layoutu, nejvýše20 stran a byte cap,
práva/revokace, podvržený object key, stale lease, retry po uploadu.
**Exit:** celá dávka má ready tisk, samostatný i hromadný download funguje bez emailu,
chyba exportu nezdvojuje ticket a lze ji obnovit. Teprve nyní je způsobilý sell.

### Vlna 4 - administrace, Blueprint a report UI

**Změny:** `views/orders_tab.dart`, nový routed subtab/detail a typed BatchCommands
s durable ClientCommandTransport; úprava TicketsTab/model/read mapping;
Blueprint vytvoření dávky ze selectedSpotIds/secrets; report core/formatter/UI;
lokalizační strings ve všech podporovaných jazycích. RightsService pouze skrývá
akce, server rozhoduje. Vrácení do retained tabu obnoví data se zachováním výběru.

**Ověření:** cílené command/model/widget testy, headless lokální full-app průchod
s disposable backendem, desktop i úzká obrazovka, deep link/reload/back,
revokace finance práva a ztracená odpověď prodeje. **Exit:** pořadatel skutečně
vytvoří dávku, stáhne PDF, prodá podmnožinu a vidí stejný ticket v běžných vstupenkách.

### Vlna 5 - uzavření kontraktu, autorizované zpřístupnění

**Změny:** regenerovat technical operation inventory po reálné implementaci,
aktualizovat eshop/ticket-layout příručky podle skutečného kontraktu, source manifest,
provozní export recovery a audit zachovaných writerů. Odebrat provizorní fallbacky,
klientské odhady stock actions a pokusné checkout bypasses.

**Ověření:** targeted regression batch checkout/waitlist/payments/scanner/report,
registry/source-parity, migrační bootstrap/forward equivalence v disposable DB.
**Exit:** splněny akceptační scénáře, žádný známý writer obchází batch invariants,
existuje konkrétní lokální evidence a oddělené dosud neprovedené produkční kroky.

## 9. Akceptační matice a konkrétní test seams

Nové názvy níže jsou plánované testy, nikoli existující důkaz. Používat současné
fixtures/helpers, nepřidávat implementaci zrcadlící unit testy pouze pro getters.

| Scénář | Hranice a očekávaný důkaz |
| --- | --- |
| 10 vytvořeno, 3 prodáno, 2 void | SQL `database/tests/eshop/ticket_batches/lifecycle_test.sql`: available5, soldActive3, voidedUnsold2; obsazeno8; platba jen za3. |
| Identita a plná kapacita | SQL stejné ticket.id/symbol, opt.id, spots.id/resource před/po sale; remainingPublic0 neblokuje převod. |
| Cena/ceník/tisk | Snapshot test: pozdější wave/title/layout nemění cenu prodeje ani bytes dřívějších PDF. |
| Paralelní create/checkout | Dvousession test stejného posledního místa a stejného spot/hold: maximálně jeden commit. Navázat na `orders/cancellation_concurrency.test.mjs`. |
| Paralelní sale/sale, sale/void, sale/scan | Dvousession `ticket_batches/concurrency.test.mjs`; po konfliktu žádný poloviční přesun, duplicita CASH ani účtenka nového command ID. |
| Rollback a replay | Failure injection po opt/payment/history/sync; parenty i peníze buď celé původní, nebo celé prodané. Retry původní receipt. |
| Oprávnění a scope | SQL editor bez manager práva neprodá; cizí unit/occasion/batch nečte; revokace znemožní replay disclosure i download. |
| Obejít stock přes staré RPC | Rozšířit `scanning/admission_test.sql`, `snapshot_test.sql`, eshop usage/cancel tests: unpaid override, retained used RPC, paid/sent/delete stock odmítnuty. |
| Změna vytištěného místa | SQL guard na edit-products/swap/replace/context realloc/pool/resource/Blueprint; hidden note a ordinary katalogová budoucí cena fungují. |
| Email bez/jen s kontaktem/opt-in | Rozšířit email domain tests: bez volby žádný intent, opt-in přes jednotnou queue, retry jedna zpráva; ordinary checkout beze změny. |
| Fakturoid | Preview/create i sale reject; po zapnutí služby zůstane void možný; žádné prepare/complete obcházení. |
| PDF obnova a limity | `_shared/ticketBatchDocuments_test.ts` + Edge tests: lease fencing, no overwrite, digest shoda, privacy, output limits. |
| Read/UI/report | SQL stock read v get_orders a skrytí pouze z order UI; core `occasion_report_test.dart`; targeted BatchCommands/TicketsTab widget test. |
| Celý průchod | Jedna real full-app E2E session: create200, části PDF, sale2, reload receipt, void1, nový scan snapshot, report a deep link. |

SQL runner: `node web_client/scripts/run_db_tests.js <konkrétní_test.sql>`.
Cílené současné regrese: `database/tests/eshop_forms/form_capacity_test.sql`,
`database/tests/eshop_orders/waitlist_ticket_identity_test.sql`,
`waitlist_ticket_action_guards_test.sql`,
`database/tests/eshop/transactions/insert_manual_transaction_null_vs_test.sql`, `database/tests/eshop/create_ticket_order_test.sql`,
`create_ticket_order_errors_test.sql`, `order_seating_test.sql`,
`occasion_report_test.sql`, `transactions/payment_pairing_contract_test.sql`,
`transactions/bank_sync_ticket_delivery_test.sql` a dotčené waitlist/scanning sady.
Před spuštěním určit skutečný seznam ze změněného kontraktu, nespouštět celou DB
bez důvodu. Edge testy používat podle CONTRIBUTING a doplnit pevný inventory.

Dart: cílený `fvm dart analyze <soubory>` a dotčené test entrypoints.
Flutter pouze jedna úloha na stanici a `--concurrency=1`; před startem ověřit slot.
Browser přes festapp-local-e2e/agent-browser, izolovaně headless bez zásahu do
uživatelova Chrome. JavaScript výhradně pnpm11.24.0. Pro pouhé plánování tyto
aplikační testy neběží; jejich popis není passing evidence.

## 10. Retence, odstranění a rollout

| Artefakt | Finální rozhodnutí / důkaz |
| --- | --- |
| Existing eshop.tickets a opt | Zachovat jako jedinou admission/product identitu; žádný batch-ticket clone. |
| Ordinary checkout/finalizer | Zachovat veřejný kontrakt; sdílený tvorbový primitive nahradí vyjmutý blok, ne paralelní kopie. |
| apply_allocations | Zachovat pro nové alokace/storno; sale jej nikdy nevolá a nepřímé reallocate chrání dependency guard. |
| Stock order a batch source/sale audit | Retain, běžné delete zakázané; žádné konverze historických paid orders na stock. |
| Draft compat flag p_stock/p_manual / fake email / paid stock | Nesmí zůstat ve výsledku; scoped source/caller check a negativní kontraktové testy. |
| Completed PDFs/font/artwork | Privátní immutable artefakty, přesný manifest/digest; nepřegenerovat ze živých dat. |
| Stará veřejná API / retained klienti | Neměnit signatury nesouvisejících flows; serverové guardy platí bez aktualizace klienta. |
| Generated inventory / historical migration | Inventory regenerovat až s kódem; historické migrace neměnit, nový forward source manifest. |

Nasazení ani změny produkčního backendu nejsou autorizovány realizací.
Budoucí release má jediný vybraný tenant. Před zpřístupněním atomické migrace
`20261024020000_pregenerated_ticket_batches.sql` musí být připraven odpovídající Edge runtime
a privátní dokumentové úložiště. Migrace instaluje schema, společné guardy,
příkazy a nakonec grants v jedné transakci; UI následuje až po ověření backendu.
Žádný stock nesmí vzniknout dříve, než jej všechny společné write/scan cesty
bezpečně rozpoznají. Zvláštní kompatibilita starších klientů není součástí scope.

Rollback po první dávce může vypnout tvorbu/prodej, ale ponechá stock guardy,
read/export/void a historii. Nesmí dropnout schema nebo udělat neprodané QR platné.
Běžný návrat starého klienta nevrací starý serverový kontrakt. Finanční oprava
proběhne dohledatelnou vratkou, ne smazáním pohybu při rollbacku feature.

## 11. Co ještě nelze tvrdit a definice hotovo

- Není ověřena produkční DB/runtime ani aktuální konfigurace kteréhokoli tenant.
- Bucket, snapshot/fenced PDF workflow a registrace jsou implementovány a lokálně
  ověřeny. Jejich produkční instalace a provozní dostupnost nejsou ověřeny.
- Funkce v1 nepokrývá Fakturoid, Stripe/external terminal, offline prodej a povinné
  jmenné registrace. Rozšíření mají vlastní skutečný doménový kontrakt.
- Staré pozitivní offline snapshoty mají stávající grant freshness omezení;
  tento plán neslibuje okamžitou revokaci bez připojení.
- Průzkum je z rozpracovaného stromu. Pokud současné canonical operations nebo
  produktové/inventory kontrakty mezitím postoupí, upravit tento plán s evidencí.

Hotovo znamená: skutečná stažitelná zásoba viditelná ve Vstupenkách, vlastní
objednávkový panel, prodej se stejným QR/opt/spot/resource, právě jedna úhrada,
nezměněná obsazenost při prodeji, správné reporty, žádný stock admission bypass,
stabilní PDF napříč download/email a doložené retry/concurrency/permission testy.
Lokální kód, aplikovaná migrace a produkční rollout se vykazují zvlášť.
