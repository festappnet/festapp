# Úplnost funkcí plánku V1 při napojení V2

Inventura zdrojového kódu k 2026-10-19. Tento seznam doplňuje
[implementační plán V2](blueprint-v2-plan-2026-10-18.md), zejména vlny 7-9 a 10B.
Nové zadání vyžaduje zachovat všechny níže uvedené funkce V1, nejen ceny,
výměnu a vytvoření objednávky. Neznamená oprávnění k nasazení nebo ke změnám
skutečných objednávek. Inventura neověřuje stav nasazené databáze.

Spustitelnou integraci řídí [nový plán B](blueprint-v2-integration-plan-2026-10-19.md)
a jeho [execution prompt](blueprint-v2-integration-EXECUTION-PROMPT-2026-10-19.md).
Tento dokument zůstává akceptačním seznamem všech funkcí.

## Stav a pravidlo dokončení

Festapp používá pouze kanonický V2 layout a bindings. V1 renderer ani zapisovací
fallback není podporován. Historické objekty slouží jen jako explicitní vstup
kontrolovaného převodu. Všech49 existujících plánků bylo převedeno offline a
skutečný SQL převod/replay4516 míst prošel na lokálních syntetických identitách
v transakci ukončené rollbackem. Produkční aktivace dosud neproběhla.

Každý řádek má konkrétní důkaz níže. Kombinované ověření spojuje skutečný UI tok
s testem serverového pravidla; netvrdí opakování každé ochrany prohlížečem.
Pouze čtecí funkce nevyžadují umělou mutaci. Otevřené finální brány se neuzavírají
na základě starších testů. Úplný Basic vizuální přehled všech49 prošel samostatně.

## Zdroje

- [Editor a jeho režimy](../../lib/components/blueprint/views/blueprint_editor_tab.dart): `handleSeatTap`, `saveChanges`, `loadData`, skupiny, výměna a objednávka.
- [Produkty a skupinové/individuální přiřazení](../../lib/components/blueprint/views/blueprint_product_dialogs.dart): `SelectProductDialog`, `EditProductDialog`, `GroupProductManagerDialog`.
- [Objednávka z míst](../../lib/components/blueprint/views/blueprint_create_order_dialog.dart): analýza konfliktů, storna, nové položky, součet, kontakt a odeslání.
- [Skupiny](../../lib/components/blueprint/views/blueprint_groups_panel.dart), [legenda](../../lib/components/blueprint/views/blueprint_legend.dart), [rozměry a podklady](../../lib/components/blueprint/views/blueprint_controls_bar.dart), [mobilní ovládání](../../lib/components/blueprint/views/blueprint_mobile_scroll_view.dart).
- [Model místa a administrátorské tooltipy](../../lib/components/blueprint/blueprint_object_model.dart), [skupiny a pojmenování](../../lib/components/blueprint/blueprint_group.dart), [stavy](../../lib/components/blueprint/blueprint_seat_state.dart), [načtení a propojení dat](../../lib/components/blueprint/get_orders_helper.dart).
- [Flutter zákaznický výběr](../../lib/components/blueprint/seat_reservation/widgets/seat_reservation_widget.dart), [webový zákaznický výběr](../../web_client/src/components/blueprint/blueprint_selector.js), [webová příprava dat](../../web_client/src/components/blueprint/blueprint_data_preparer.js), [veřejné tooltipy](../../web_client/src/components/blueprint/tooltip_provider.js).
- [Form RPC adapter](../../lib/components/forms/db_forms.dart), [form commands](../../lib/components/forms/supabase_form_commands.dart), [ticket commands](../../lib/components/eshop/ticket_commands.dart), [objednávkové operace](../../lib/components/eshop/db_eshop.dart), [objednávkový transport](../../lib/components/eshop/db_orders.dart).
- SQL doména: [uložení V1](../../database/functions/eshop/update_blueprint.sql), [analýza míst objednávky](../../database/functions/eshop/analyze_new_order_spots.sql), [výměna a finanční přepočet](../../database/functions/eshop/swap_spot_tickets.sql). Tyto doménové implementace nejsou pokynem obejít jejich aktuální command/receipt fasády.

## A. Produkty a ceny

| ID | Povinně zachovat / doložit | Stav V2 |
|---|---|---|
| P01 | Nabídka místových produktů dané akce, názvy, formátovaná cena a označení aktuálního produktu. Přirozené řazení nabídky. | ověřeno - Verified - actual catalog names, selected product and formatted CZK prices; existing dialog retains natural sorting.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| P02 | Vytvoření místového produktu včetně převzetí odpovídajícího typu/kontejneru akce z existujícího produktu; ošetřit chybějící výchozí produkt. | ověřeno - Verified - actual create from existing product template, reload retained QA Seat; missing-template widget coverage.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| P03 | Úprava názvu a ceny existujícího katalogového produktu. Rozlišit okamžité uložení katalogu od rozpracovaného přiřazení v plánku. | ověřeno - Verified - actual rename and price135 retained after full reload; catalog save separated from layout draft.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| P04 | Validace neprázdného názvu a nezáporné číselné ceny; zachovat měnu a formátování hosta. Server je autoritou částek. | ověřeno - Verified - actual blank title and empty/negative-filtered price validation; server authoritative amounts retained.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| P05 | Jedním krokem přiřadit produkt celé skupině a skutečně jej promítnout do všech jejích míst. | ověřeno kombinovaně - Verified combined - actual mixed-group free-only assignment/save/reload retained protected member; host atomic full-group assignment tests cover all eligible members.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| P06 | Přepsat produkt jednotlivého místa bez změny ostatních míst skupiny. | ověřeno - Verified - actual individual Free premium override135/save/reload preserved other assignments.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| P07 | Rozpoznat jednotný i smíšený produkt skupiny; zobrazit odpovídající cenu, stav a seznam individuálních přiřazení. | ověřeno - Verified - actual mixed/default/member-price inspector before and after persisted assignment.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| P08 | Obsluha skupiny bez míst, skupiny bez produktu a místa bez přiřazení; nevytvářet tichou cenu 0 ani demo cenu 250. | ověřeno kombinovaně - Verified combined - actual empty/unknown groups and unassigned seat show empty, no invented price; host null-product tests.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| P09 | Nové místo zdědí produkt vybrané skupiny / dosavadní fallback V1. Případnou změnu tohoto pravidla výslovně rozhodnout, nikoli ji skrýt migrací. | ověřeno kombinovaně - Verified combined - host explicit group inheritance tests and wizard reconciliation; mixed/unknown groups require explicit default rather than silent first-product fallback.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| P10 | Ochrana objednaných, použitých a rezervovaných míst při hromadných i individuálních změnách; ověřit skutečná pravidla serverového ownera. | ověřeno kombinovaně - Verified combined - actual protected group and used-seat controls disabled; free-only persisted; SQL covers ordered/used/foreign and own holds atomically.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| P11 | Změna katalogové ceny není lokální přepsání historické ceny prodané vstupenky. Finanční účinky změny místa řeší existující order/swap owner. | ověřeno kombinovaně - Verified combined - catalog mutation persisted separately; actual target-price swaps and SQL payment/history proof establish financial owner.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |

## B. Skupiny, místa a stavy

| ID | Povinně zachovat / doložit | Stav V2 |
|---|---|---|
| S01 | Vytvořit skupinu s názvem, stabilní identitou a přirozeným řazením. | ověřeno - Verified - actual QA Group10 and QA Group2 created/saved, DB revision16 confirms stable new UUID. Final release chooser displays2 before10; selecting group leaves Save disabled. Natural-sort widget assertion passes; layer order unchanged.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| S02 | Výběr skupiny zvýrazní odpovídající místa; zobrazit počet míst a produkt/cenu či smíšený stav. | ověřeno - Verified - actual group highlights/count/default/mixed inspector; selection does not dirty layout.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| S03 | Smazání skupiny odstraní její volná místa, ale nesmí odstranit chráněná/obsazená místa. | ověřeno kombinovaně - Verified combined - shared editor deletion plus host protection and SQL protected-delete rollback; no separate browser destructive replay.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| S04 | Přidat prodejné místo do vybrané skupiny; převzít produkt a vytvořit výchozí označení podle skupiny a posloupnosti písmen. | ověřeno kombinovaně - Verified combined - exact existing A..Z/AA formatter reused by host; explicit group default/inheritance retained. All49 conversion preserves4516 identities/source labels; final host regression passes.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| S05 | Zablokovat místo/plochu, vytvořit volné místo a odstranit místo/plochu. V2 musí nabídnout obchodní ekvivalent i bez mřížky V1. | ověřeno kombinovaně - Verified combined - actual block/unblock save/reload; generic authoring create/remove and SQL protected geometry tests cover remaining mutations.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| S06 | Chránit `ordered`, `used`, cizí `selected` i vlastní `selectedByMe` při strukturálních změnách. Server rozhoduje o aktuálním hold stavu. | ověřeno kombinovaně - Verified combined - actual used/protected controls and SQL all protected-state structural guards/races.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| S07 | Rozlišit všech sedm stavů V1: empty, available, selected, selectedByMe, ordered, used, blocked. Legendy, počty, klikatelnost a zvýraznění mají odpovídat datům. | ověřeno - Verified - actual seven-state text/count legend and own/unavailable behavior. Basic review decision: physical unassigned chairs remain green but unavailable/nonselectable with no-product tooltip; absence of a node is transparent. All230 unassigned chairs remain visible.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| S08 | Přepnutí/vypnutí režimu i obnovení dat vyčistí dočasný výběr pro swap/objednávku a vrátí skutečný stav míst. | ověřeno kombinovaně - Verified combined - widget mode/Escape preserves geometry draft; actual successful swap/order clears temporary selection and refreshes states.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| S09 | Administrátorský detail místa: produkt, označení, cena; u prodaného místa také symbol vstupenky, zákazník, objednávka, další produkty a veřejné/interní poznámky podle oprávnění. | ověřeno - Verified - actual final release screenshot shows ticket symbol, public/private ticket notes, additional product, customer, customer note and private order note. Admin-only projection fix is SQL-tested; anonymous projection still excludes private data.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| S10 | Obchodní skupina V1 se nesmí automaticky zaměnit za libovolný geometrický parent V2. Tabulka vazeb určí členství a jeho změny. | ověřeno kombinovaně - Verified combined - explicit binding membership and host reparent/history tests; copied wizard binding remap verified in DB.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |

## C. Výměna / přesun vstupenek

| ID | Povinně zachovat / doložit | Stav V2 |
|---|---|---|
| W01 | Dvoufázový výběr míst, vizuální označení obou, zrušení opakovaným klikem a potvrzení se souhrnem zákazníků/vstupenek. | ověřeno - Verified - actual two-seat toggle2->1->2, ticket/customer summary and confirmed operations.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| W02 | Odmítnout prázdnou/blokovanou plochu, stejné místo, neexistující ID a místa z různých akcí. | ověřeno kombinovaně - Verified combined - UI only activates valid bound seats; SQL rejects same/missing/cross-event/blocked targets.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| W03 | Dvě obsazená místa: prohodit přiřazení vstupenek, zachovat identity vstupenek a příslušných objednávek. | ověřeno - Verified - actual same/different-order swaps; DB retained ticket/order identities; final receipt RPC200 refreshes selection0.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| W04 | Obsazené ↔ volné: přesunout vstupenku na volné místo. Dvě volná místa jsou serverový no-op. | ověřeno kombinovaně - Verified combined - actual ticket6 moved to free target; SQL two-free no-op coverage.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| W05 | Produkt patřící fyzickému místu zůstává na místě; vstupenka přijme cílový produkt přes serverovou operaci. Neprohazovat ceny pouhou výměnou UI barev. | ověřeno - Verified - target retained QA product135, source retained100; existing owner changed moved ticket/order amount.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| W06 | Rozdílné ceny/produkty: zachovat přepočet položek, celku objednávky, platební částky/stavu a historie podle stávající SQL domény. Ověřit obě vstupenky ze stejné i různých objednávek. | ověřeno - Verified - actual same-order250 unchanged and different-order100->150/150->100; DB payment/history checks.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| W07 | Stejné produkty, různé stavy vstupenek, již použitá vstupenka a aktuální rezervace: doložit pravidla, identitu a metadata podle autoritativního ownera. | ověřeno kombinovaně - Verified combined - actual occupied and free cases; SQL used/held rejection and metadata identity coverage.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| W08 | Úspěch obnoví data. Zamítnutí, síťová chyba a opakovaný submit nesmějí zanechat zdánlivě provedenou výměnu ani dvojitý finanční účinek. Použít stávající command receipts/sync. | ověřeno - Verified - actual aborted submit preserved selection/no optimistic success; retry succeeded; final canonical receipt200 refreshed selection and cleared error. Receipt replay SQL coverage.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |

## D. Vlastní objednávka z výběru

| ID | Povinně zachovat / doložit | Stav V2 |
|---|---|---|
| O01 | Vícenásobný výběr skutečných míst, odebrání opakovaným klikem, počet vybraných a potvrzení dostupné až pro neprázdný výběr. | ověřeno - Verified - actual three-seat selection/toggle/count and successful order; empty action disabled.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| O02 | Výběr může obsahovat již objednaná místa; nejde jen o nákup dosud volných míst. Blokovaná plocha ani geometrická dekorace není objednatelná. | ověřeno - Verified - actual selected occupied SameA/OtherB plus free OtherA; blocked/decorative selection guarded by host/SQL.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| O03 | Před odesláním spustit `analyze_new_order_spots`, zobrazit nové položky/produkty/místa a celkovou cenu. Všechna místa musí patřit téže akci. | ověřeno - Verified - actual analyze_new_order_spots showed authoritative three items/350CZK before confirmation.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| O04 | Zobrazit konflikty po původních objednávkách: dotčené vstupenky, zákazník, produkty, částky a úplné versus částečné storno. | ověřeno - Verified - actual preview partial order3 and full order4 cancellation with customer/ticket/product/amount detail; DB confirms both effects.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| O05 | Zachovat upozornění, že se neposílá storno e-mail, i existující vysvětlení finančních důsledků v dialogu. | ověřeno - Verified - actual conflict dialog retained no-storno-email notice and financial explanation.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| O06 | Kontaktní e-mail, validace, zrušení dialogu a ochrana proti zavření/opakovanému odeslání během submitu. Chyba umožní opravu/opakování. | ověřeno kombinovaně - Verified combined - actual email validation, mobile dialog, failed-command retry and accepted fresh command; widget pending close/duplicate suppression.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| O07 | Potvrzení použije `DbEshop.createOrderFromSpots` → `DbOrders.replaceTicketOrder`, tedy existující Edge/command hranici; nevytvářet nezávislý klientský order engine. | ověřeno - Verified - actual existing Edge/command owner created order20, three tickets350; DB exact completed receipt.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| O08 | Po úspěchu vyčistit výběr a obnovit objednávky/stavy. Při konfliktu mezi analýzou a potvrzením rozhoduje server, nikoli zastaralý součet náhledu. | ověřeno kombinovaně - Verified combined - actual accepted replacement clears selection and refreshes counts; SQL concurrency/revalidation rejects stale state atomically.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |

## E. Zákaznický výběr ve Flutteru i na webu

| ID | Povinně zachovat / doložit | Stav V2 |
|---|---|---|
| C01 | Stejné ID místa, produkt, cena a dostupnost v obou klientech. Zachovat napojení výběru na formulář, položky a součet objednávky. | ověřeno - Verified - JS order8 four tickets360 and Flutter order19 two tickets180, both addressed plus standing; DB products/prices/payment match.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| C02 | Výběr i odvýběr přes `select_spot`/stávající session boundary se secretem, expirací a kontrolou vlastnictví hold. Geometrický výběr sám nic nerezervuje. | ověřeno kombinovaně - Verified combined - both actual clients hold/release atomic pair through one select_spot; SQL ownership/expiry/race coverage.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| C03 | Optimistický vzhled s návratem po konfliktu/chybě; zabránit souběžným opakovaným klikům na jedno místo. | ověřeno kombinovaně - Verified combined - actual JS aborted selection rolls back and retry succeeds; package lifecycle and Flutter host tests prevent duplicate/past-generation results.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| C04 | Obnovit vlastní výběr při znovuotevření, převzít serverem vrácený secret a zachovat soulad s payloadem formuláře. | ověřeno kombinovaně - Verified combined - both clients reopen retained own unit and release it; host secret adoption and actual checkout payload tests.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| C05 | Zachovat limit vstupenek a dostupnost produktů/prodejních vln podle pravidel hosta. Zobrazené místo není automaticky prodejné. | ověřeno kombinovaně - Verified combined - actual both checkout flows and standing quantities; authoritative offered/wave/max guards plus nine real races, including maximum race.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| C06 | Pokračování/zavření vrací aktuální výběr; zpracovat i neúspěšné načtení a nedostupný plánek bez falešného potvrzení. | ověřeno - Verified - actual failed reader shows Retry/Close, Continue disabled; retry recovers; close/continue preserves current selection.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| C07 | Veřejné tooltipy zobrazují jen veřejná data. Administrátorské interní poznámky, zákazníci a cizí objednávky nesmějí přejít do veřejné projekce. | ověřeno kombinovaně - Verified combined - actual public labels/status/price only; SQL anonymous projection privacy assertions exclude private customer/order data.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| C08 | Desktop/mobil, pan/zoom/fit, ovládání dotykem a myší, neztratit výběr při překreslení a korektně uvolnit handlery při zavření. Geometrie V2 již existuje, host tok je nutné doložit. | ověřeno kombinovaně - Verified combined - actual mobile both clients, JS pan/zoom/keyboard/Escape/reopen; shared renderer lifecycle and disposal tests.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |

## F. Uložení, načtení a provozní pravidla

| ID | Povinně zachovat / doložit | Stav V2 |
|---|---|---|
| U01 | Načíst plánek pro danou akci, objekty, produkty, skupiny a oprávněná order/ticket metadata. Výběr míst veřejně a administrátorsky používá správnou projekci. | ověřeno kombinovaně - Verified combined - actual admin/public routes, product and authorized ticket/customer previews; SQL projection/role tests.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| U02 | Uložit a zahodit změny; dirty stav zahrnuje rozměry, podklad, členství a produktová přiřazení. Odlišit neuložený draft od okamžitých objednávkových operací. | ověřeno kombinovaně - Verified combined - actual rename, product assignment, block, background dirty/save/reload and undo/redo; host geometry/history/late-save regression.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| U03 | Zachovat existující `spot.id` při pohybu, rotaci, změně tvaru a přečíslování. Nové místo dostane novou identitu, kopie nikdy nepřevezme objednávku/hold původního místa. | ověřeno kombinovaně - Verified combined - canonical save stable IDs and new/copy identities tested; actual wizard copied15 bindings with zero foreign products/holds/orders.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| U04 | Uložit vazby a geometrii konzistentně; konfliktní revize, neplatný/cizí produkt a chráněné odstranění se musí vrátit bez částečných změn. | ověřeno kombinovaně - Verified combined - actual successful canonical save; SQL revision/product/protected-delete atomic rollback and replay tests.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| U05 | Použít stávající `update_blueprint_client_sync_v1` / `FormCommands.saveBlueprint`, receipt a sync publication; neobejít je přímým zápisem nové geometrie. | ověřeno - Verified - actual host Save/full reload through existing command wrapper; SQL receipts and publication coverage.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| U06 | Zachovat možnost změny rozměrů a vložení/odstranění SVG či obrazového podkladu. V2 má bohatší nástroje, ale musí fungovat jejich uložení v hostu. | ověřeno kombinovaně - Verified combined - actual PNG/SVG processed upload/render/save/full reload and remove; JS same background mobile; generic canvas dimensions and canonical geometry persistence tests.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| U07 | Read-only a editační oprávnění, odděleně objednávkové operace; serverová kontrola scope/akce je povinná i při skrytých UI tlačítkách. | ověřeno kombinovaně - Verified combined - actual read-only/editor context, distinct operation controls; SQL geometry vs order role/scope rejection tests.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| U08 | Přeložitelné popisky/hlášky, formát ceny/měny, úspěch/chyba/načítání a mobilní dostupnost všech obchodních akcí. | ověřeno kombinovaně - Verified combined - cs/en localization seams, actual Czech mobile products/orders/standing/error/loading, widget320px and final release chooser/detail.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |
| U09 | Prototyp/demo nevolá živé swap/order/product operace a je viditelně označené. Funkční ukázka není dokladem persistence ani oprávnění. | ověřeno - Verified - reachable wizard offline demo banner, local edit/save and zero requests after ResourceTiming reset; no live business controls.; [důkazy](evidence/blueprint-b-20261019/ui/parity-evidence.md) |

## Navíc zachovat už zadané chování V2

Tyto body nemají úplný ekvivalent V1, proto je nelze prohlásit za splněné paritou:

- Gauč / atomická jednotka: společné select/release, objednávka, storno, swap a náhrada bez napůl prodejné jednotky; jednotlivé vstupenky zůstávají identifikovatelné a skenovatelné.
- Stání po kusech: produktové inventory a množství používají stávající ledger; změna stepperu nesmí předstírat rezervaci konkrétního sedadla.
- Kulatý, obdélníkový i vlastní stůl, řady, dopravní sestavy a volná židle používají stejnou stabilní seat → spot vazbu.
- Historie změn geometrie/produktového draftu nesmí odvolat či znovu odeslat již potvrzenou serverovou objednávku. Geometrické a obchodní operace mají jasné hranice.
- Backendové změny, veřejné projekce a oba klienti se ověřují společně; samotný úspěch Flutter dema neuzavírá host integraci.

## Známé pasti, které inventura odhalila

1. `_performSwap` ve V1 upravuje místní stavy ještě před dokončením RPC. Po chybě je ve V2 nutné obnovit autoritativní data nebo vrátit změnu; tento nedostatek není požadovaná parita.
2. Skupinový `product` je ve V1 přechodové pole; produkt se materializuje do míst. V2 nesmí při načtení odvodit nesprávnou cenu pouze z geometrického rodiče.
3. Produktový katalog se může uložit už v dialogu, zatímco přiřazení míst čeká na uložení plánku. Zrušení geometrického draftu není automatické storno katalogové úpravy.
4. Zdrojové SQL soubory obsahují doménu i historické wrappery. Před implementací se ověří aktuální fasáda/transport a testy; nevybírá se RPC jen podle podobného názvu.
5. Order tooltips obsahují osobní a interní data. Veřejný renderer nesmí dostat administrátorský payload a teprve ho lokálně skrývat.

## Existující důkazy a následná validace

Výchozí regrese:
[editorové akce](../../test/components/blueprint/blueprint_editor_actions_cases.dart),
[draft produktů](../../test/components/blueprint/blueprint_draft_product_cases.dart),
[metadata objednávek](../../test/components/blueprint/blueprint_order_metadata_cases.dart),
[seat adapter](../../test/components/blueprint/blueprint_seat_adapter_cases.dart),
[kapacita formuláře](../../test/components/forms/form_blueprint_capacity_cases.dart),
[webové načtení](../../web_client/tests/components/blueprint_loading.test.js) a
[webový viewport](../../web_client/tests/components/blueprint_viewport.test.js).
Jsou to zdroje existujících scénářů, nikoli důkaz jejich průchodu na V2.

Pořadí implementace: stabilní bindingy a konzistentní save/read → produkty a
skupiny → režimy/ochrany stavů → objednávka a swap → oba zákaznické pickery →
integrační regression. Finanční/rezervační scénáře navíc potřebují skutečné
serverové testy atomity, oprávnění, dvojitého odeslání a souběhu; nejsou nahraditelné
mockem UI. U každého dokončeného řádku zaznamenat vlastníka, test a výsledek.


## Přísnost uzavření při předání B

Každý z 54 řádků má konkrétní dostupnou evidenci a stav. `Otevřeno`
nezpochybňuje dílčí passing test; znamená, že příslušný účinek ještě není
doložen přes skutečný host/server a UI. U čistě čtecích a bezpečnostních
požadavků se ověřuje správná projekce, dostupnost a zamítnutí u autority;
nevyžaduje se umělá mutace jen kvůli tvaru akceptačního zápisu. SQL-only
ani widget-only důkaz nepotvrzuje neprovedený obchodní UI tok.
