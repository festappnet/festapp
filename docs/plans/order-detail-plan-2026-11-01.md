# Detail objednávky bez přeplněné tabulky

Datum: 2026-11-01  
Stav: varianta A implementována; připraveno k lokální kontrole, bez produkčního nasazení. Výsledek a důkazy: [lokální kontrola](evidence/order-detail-local-review.md)  
Ověřování: low-risk pro návrh a prototyp; standard pro následné změny oprávnění, kontaktního příkazu, databázových kontraktů nebo sdíleného chování gridů

## Výsledek a rozhodnutí k posouzení

Po otevření objednávky pořadatel vidí zákazníka, platbu, vstupenky, zprávy a historii na jednom místě. Kontakt lze upravit i po úspěšném doručení. Tabulka slouží k hledání, porovnávání a hromadným akcím; běžné akce jedné objednávky jsou v detailu.

Uživatel vybral variantu A: kontextový boční panel při dostatečné šířce a celoplošný detail na menší obrazovce. Detail lze rozšířit pro práci s plánkem; nejde o další paralelní implementaci. Autoritativní UX specifikace Astry s medium reasoning je v `order-detail-UX-2026-11-01.md`. Tento dokument vlastní technické hranice, reuse, pořadí realizace a ověření.

`docs/prototypes/order-detail-prototype-2026-11-01.html` je původní průzkumná simulace A/B/C, nikoli finální realizace nově rozpracovaného návrhu. Její dosavadní browser kontroly nedokládají hotový propojený plánek ani níže navržené admin čtečky.

## Zjištěný současný stav

| Fakt | Důkaz | Dopad |
| --- | --- | --- |
| Kontaktní e-mail v Objednávkách je textový sloupec pouze pro čtení. | `lib/components/eshop/eshop_columns.dart`, `ORDER_EMAIL` | Přímá běžná úprava zde chybí. |
| Červená obálka vedle stavu objednávky otevírá opravu pouze při aktuálních problémech. | `views/order_state_cell.dart`, `OrderStateCell` | Úspěšné doručení na jinou platnou adresu nezpřístupní tento vstup. |
| Kanonický příkaz změnu bez problému podporuje: zdrojová zpráva může být null, `p_resend=false`. | `database/functions/eshop_orders/repair_order_email_client_sync_v1.sql` | Pro zpřístupnění editace běžného kontaktu není důvod zavádět dalšího zapisovatele. |
| Příkaz ověřuje očekávanou adresu, stav, platební verzi i fingerprint; zapisuje projekci kontaktu, formulářové pole a historii. | Tentýž SQL příkaz; `OrderCommands.repairEmail` | Nový editor musí zachovat idempotentní příkaz a konfliktní odpovědi. |
| Změna kontaktu ruší staré neodeslané zprávy pro jiného příjemce. Již probíhající nebo nejisté odesílání neodvolá. | Příkaz, aktualizace `email_messages` | Uložit kontakt a poslat novou zprávu jsou odlišné volby. UI nesmí slibovat automatické doručení po uložení. |
| E-mail lze měnit také jako odpověď formuláře. UI a SQL zde používají odlišné stráže oprávnění. | `FormResponsesContent`: `canUpdateUsers`; `FormResponseModel.updateMethod`; `update_order_responses`: `can_write_orders` | Jde o existující alternativu, nikoli spolehlivý obecný vstup pro každého editora objednávek. Nový detail ji nepoužije jako náhradní zapisovatel. |
| Běžné uložení `OrderModel` mění pouze interní poznámku. | `OrderModel.updateMethod` | E-mail nelze zpřístupnit pouhým odemčením buňky tabulky. |
| Tabulka má samostatné sloupce s historií, transakcemi a zákaznickým přehledem; hromadné odeslání a zrušení jsou v liště. | `eshop_columns.dart`; `views/orders_content.dart` | Rozlišit přesun akcí jedné objednávky od zachování hromadných akcí. |
| Existuje autorizovaná historie a vstup do zákaznického přehledu. | `DbOrders.getOrderHistory`, `database/functions/eshop/get_order_history.sql`; `get_order_overview_admin_context`; `ORDER_OVERVIEW` | Znovu použít data a schválený přístup, nevkládat zákaznickou capability URL do admin API ani iframe. |
| Notifikace už používají `orderId` a `orderMessageId`. | `OrdersContent._openNotificationOrder` | Detail má navázat na tento vstup, zachovat scope a správu historie prohlížeče. |
| Překlady obsahují 27 stavů, událostí a diagnostických údajů e-mailu. | `assets/translations/cs.json`, `EmailDelivery.state`; `email_reporting.sql`; `EmailDeliveryHistory` | Legenda obsahuje všech 27 položek. Událost pokusu a sledování nejsou dalším stavem objednávky. |

Platnost syntaxe adresy ani úspěšné doručení neověřují vlastnictví schránky. Historické zprávy musí nadále ukazovat skutečného původního příjemce. Změna kontaktu není změnou přihlášeného uživatele ani převodem vlastnictví objednávky.

## Cílové chování

### Otevření a pohyb

- Kliknutí na neinteraktivní obsah řádku nebo na symbol otevře detail. Checkbox vybírá pro hromadné akce, kopírování pouze kopíruje. Výběr textu ani dvojklik v editovatelné poznámce nesmí nechtěně otevřít panel.
- Na širokém desktopu panel nesmí zakrývat vybraný řádek ani vyžadovat vodorovné posouvání celé stránky. Rozhoduje dostupná šířka kontejneru, ne typ zařízení. Pokud by zbývala nečitelná tabulka, detail přejde na plnou šířku.
- Na telefonu je detail celoplošný se zřetelným návratem. Při návratu se obnoví filtr, řazení, scroll, hromadný výběr i fokus konkrétního řádku.
- Předchozí/další prochází aktuálně filtrované řádky, nikoli skryté objednávky. Přímý odkaz na objednávku mimo filtr otevře detail podle ID s upozorněním a explicitní volbou zobrazení řádku; nemění filtr potichu.
- Neuložený kontakt nebo poznámka vyžaduje volbu pokračovat v úpravě nebo zahodit před zavřením, přepnutím řádku či opuštěním. Přepnutí záložky nebo rozšíření stejného detailu zachová tentýž controller-owned draft bez dotazu; Přehled a E-maily nesmějí mít odlišně rozepsané adresy. Příslušné záložky ukážou Neuloženo. Při probíhajícím zápisu je změna kontextu řízená a pozdní odpověď nesmí zasáhnout jinou objednávku.

### Obsah a akce

- Záhlaví: symbol, zákazník, stav objednávky; pod ním samostatně platba a doručení. Jedno barevné označení nesmí zastupovat všechny tři výsledky.
- Přehled: kontakt s nenápadným tlačítkem `Upravit`, cena, přijato, vráceno a zbývá, místa a produkty. Nepřebírat všechnu veřejnou prodejní výzvu ze zákaznického přehledu.
- Podrobnosti vstupenek, plateb, e-mailů a historie otevírat až na vyžádání. Zachovat historii původní i nové adresy. Detail konkrétní zprávy rozlišuje pokusy, události, sledování a aktuálnost kontaktu.
- Zrušení objednávky je oddělená akce s potvrzením; samotné zrušení nevrací platbu. Správa bankovních transakcí nadále vyžaduje její vlastní oprávnění, nikoli pouze čtení detailu objednávky.
- V prototypu změny pouze v paměti. Neautorizuje žádný reálný e-mail, platbu, změnu objednávky, migraci ani vydání.

### Úprava e-mailu bez problému

1. `Upravit` je dostupné také pro zdravé doručení, pokud lze objednávku upravovat.
2. Při validní nové adrese je výchozí akce `Uložit kontakt`; neposílá zprávu. Samostatně je možné explicitní uložení a odeslání aktuálního potvrzení nebo vstupenek podle stavu objednávky.
3. Uživateli se ukáže, že změna neodvolá již odeslanou zprávu. Při změně příjemce, kdy existují zrušené čekající zprávy, nesmí zpětná vazba předstírat, že nové automaticky odejdou.
4. `sending` a `unknown` dovolují bezpečně uložit kontakt podle kanonického kontraktu, nikoli obejít zákaz dalšího odeslání. Suppression posuzuje skutečného nového příjemce; změna velikosti písmen blokování neodstraní.
5. Při konfliktu 409 obnovit data a vyžádat posouzení změněných okolností; neprovést tiché opakování s novým příkazem.
6. Zrušené, uzavřené a jinak neměnitelné objednávky nepovolí editaci. Rozhoduje kanonická autorita, ne odhad podle barvy štítku.
7. U již čekající zprávy nesmí UI předpokládat, že kombinovaná akce obejde aktivní intent. Podle nynějšího kontraktu nejprve výslovně uložit nový kontakt (čímž se zruší příslušné čekající staré zprávy), obnovit stav a teprve poté nabídnout samostatné odeslání. Neřetězit oba kroky automaticky za jediné skryté potvrzení.

## Konkrétní uspořádání detailu

Pět záložek má stabilní ID; přepínání neposílá data. Přehled nesmí být kopií všech ostatních záložek. Podrobné pořadí prvků a microcopy vlastní UX specifikace.

| Záložka | Otázka pořadatele | Obsah a přímé přechody |
| --- | --- | --- |
| Přehled | Čí objednávka to je a co nyní potřebuje? | Kontakt a Upravit, obchodní stav, serverový finanční souhrn, kompaktní souhrn vstupenek/míst, skutečné aktuální problémy. Kliknutí na problém přejde na konkrétní zprávu, nedoplatek do Plateb, místo do Vstupenek a míst. Odpovědi objednávky, veřejná poznámka a interní poznámka jsou odlišné oddíly; dlouhé odpovědi se rozbalují. |
| Vstupenky a místa | Co je objednáno, komu a kde? | Jednotlivé vstupenky s produkty a objednanými cenami, místo/stůl nebo stání, stav platnosti/použití. Rozbalení jedné vstupenky ukáže její vlastní odpovědi a poznámky. Náhled plánku má seznamovou alternativu. Pro akci bez vstupenek použít odpovídající označení účastníků/položek a nepředstírat QR. |
| Platby | Co bylo přijato a co zbývá? | Cena, přijato, vráceno, nedoplatek/přeplatek, záloha a oba termíny podle projekce. Způsob platby, VS/RF, relevantní účet a transakce. Přidání hotovosti nebo přiřazení existujícího pohybu přes nynější potvrzované operace; Stripe nemá převodové instrukce ani ruční simulaci karetní platby. |
| E-maily | Která zpráva šla komu a s jakým výsledkem? | Aktuální kontakt, konkrétní zprávy s původními příjemci a časy, vybraná zpráva s pokusy/událostmi, omezení sledování, oprava a výslovné odeslání aktuálního obsahu. V běžném UI pouze skutečné stavy; všech 27 položek je dostupných v nápovědě, ne jako produkční přepínač. |
| Historie | Co, kdy a kdo změnil? | Existující snapshoty a skutečně doložené změny kontaktu, produktů, ceny, míst a stavu. Zobrazení rozdílu dvou záznamů, aktér a čas. Časy odeslání a pohyby účtu mají vlastní záložky; nevytvářet falešně sjednocenou historii z neporovnatelných hodin. |

### Reálné informační varianty

- Objednávkové odpovědi patří objednávce, odpovědi jménem jednotlivého návštěvníka jeho vstupence. Stejně pojmenované pole různých formulářů není stejná identita. Zachovat typed form field ID, pořadí, formátování a rozdíl mezi skrytým, chybějícím a vymazaným údajem.
- Objednaný název/cena produktu jsou snapshot objednávky; aktuální katalogová cena je nesmí přepsat. Duplicity produktů nezmizí chybným sloučením podle `productId`.
- Vstupenky, místa a doplňky nejsou stejný počet. Objednávka může mít více produktů na jedné vstupence, volné stání bez židle, vstupenku bez přiřazeného místa a část zrušenou či použitou.
- `waitlisted`, nabídka náhradníka, `preparing_payment`, předgenerovaná dávka a běžná zaplacená objednávka používají vlastní existující lifecycle/allowedActions. Žádné ruční převádění na běžný stav jen kvůli univerzálním tlačítkům. Nabídky zachovávají `WaitlistOrderDetail` a své příkazy.
- Prázdné datum/pole/částka je neznámý údaj, nikoli nula. Finanční projekce `unknown` se nesmí přepsat na nezaplaceno. Měny se nesčítají ani automaticky nepřevádějí; Stripe respektuje svou přesnost a stav plateb.

## Reuse a hranice nových komponent

| Současný vlastník | Co se použije | Co se nepřebírá / nutná úprava |
| --- | --- | --- |
| `views/order_email_repair_dialog.dart`, `OrderCommands.repairEmail` | Stavová pravidla, identita příkazu, očekávaná verze/fingerprint, save-only a resend. | Vyjmout obsah do jediného `OrderEmailContactEditor`; nevytvářet druhý editor pro zdravý kontakt. Dialog ani panel nejsou autoritou stavu. |
| `EmailDeliveryHistory`, `EmailDeliveryModel`, `OrderEmailIssue` | Stránkování historie, detail událostí, příjemce, význam stavů a aktuálních problémů. | Sdílet obsah a loader s kompaktní záložkou. Nevkládat celou širokou tabulku v modalu do úzkého panelu a nepsat druhý agregátor problémů. |
| `TransactionsDialog`, `DbEshop.getTransactionsForOrder` | Autorizované čtení transakcí, řazení, omezení a existující akce. | Vyjmout obsah/řízení do `OrderPaymentsContent` a ponechat dialog jako případného tenkého hostitele pro ostatní volající. Jeden zdroj refresh a mutací. |
| `AddCashPaymentDialog`, `SearchTransactionsDialog` | Ověřené malé formuláře a potvrzení konkrétní operace. | Zachovat vlastní práva, validaci a platební příkazy. Nevkládat správu všech bankovních pohybů do detailu. |
| `OrderHistoryDialog`, `OrderHistoryModel`, `DbOrders.getOrderHistory` | Parsování historických záznamů a aktérů, existující prezentace změn. | Sdílený obsah `OrderHistoryContent`; případný dosavadní dialog má stejného vlastníka. Není univerzálním zdrojem aktuálních plateb, geometrie nebo všech vztahů. |
| `TicketModel`, `OrderDataTicketModel`, `OrderDataProductModel`, `FormResponseModel` | Rozlišení živých identit a objednaných snapshotů, typované odpovědi. | `TicketModel.relatedSpot` je singulární prezentace. Nesmí být jediným zdrojem všech míst nebo záminkou pro odvozování vztahů podle názvu. |
| `DbTickets.downloadTicketPdf`, `ProductsDialog`, existující změny/zrušení vstupenek | Přípustné stažení a explicitní editace produktů přes současné vlastníky. | Neimplementovat nové generování PDF, přepočet ceny, potvrzení vstupu nebo přesazení přímo v panelu. Dříve dokončená operace není vracena zavřením detailu. |
| `VenueLayoutViewer`, `BlueprintLayoutSnapshot`, `BlueprintLayoutAssetResolver` | Kanonický schema-2 dokument, renderer, ověřené resource manifesty, pan/zoom. | Viewer zatím nemá veřejné focus-to-seat/hit callback API. Rozšířit jej úzce v generickém balíčku, neimportovat jeho `src` ani celý editor. |
| `SeatReservationWidget`, `VenueLayoutPicker` | Pouze jejich zavedený renderer/presentation vzor. | Tyto hostitele nepoužít: selection callback může volat `select_spot` a měnit hold. Čtecí zobrazení nesmí přebírat secret, TTL, rezervaci ani checkout. |
| `CustomerOrderOverviewView`, webclient `order_overview*.js`, `festapp_core` | Informační hierarchie, doménové modely, sjednocené formátování a serverové projekce. | Nekopírovat JS renderovací strom do Flutteru, nevkládat veřejnou zákaznickou stránku/iframe ani použít capability token jako admin oprávnění. |
| `customer_order_payment_internal`, `stripe_order_payment_projection_internal`, `order_tickets_with_seating_internal`, `get_order_allowed_actions_internal_v1` | Pravidla plateb, textového obohacení míst a přípustných akcí. | Seating helper používá pro order/ticket/product první shodu (`LIMIT 1`); není úplným mapováním jednotlivých instancí. Mapa potřebuje skutečné order-product-ticket/spot vazby. Helper platby vrací i transakce; core je nemusí vystavit, ale neslibovat nulový SQL náklad helperu. |

Nové komponenty mají odpovídat úlohám: `OrderDetailController`, responzivní hostitel, přehled, seznam vstupenek/míst a čtecí propojení s plánkem. Nebudovat obecný konfigurovatelný engine detailů, druhý bankovní modul nebo novou knihovnu ikon.

## Čtení dat a přímé odkazy

### Potřebný kontrakt

**Zjištění:** `get_orders` načítá celou akci/formulář, nemá filtr konkrétní objednávky a jeho současná projekce míst neobsahuje všechny vazby pro mapu. `get_order_history` vrací objednávku a historii, nikoli kompletní aktuální detail. `DbForms.getBlueprint(mySecret, formKey, blueprintId)` je veřejný checkout reader; nelze jej považovat za nový admin kontrakt nebo mu dodávat smyšlený secret.

**Rozhodnutí:** zavést dvě úzké autentizované čtecí hranice, bez nových zapisovatelů:

1. `public.get_order_admin_detail(p_order bigint, p_occasion bigint)` v novém kanonickém `database/functions/eshop_orders/get_order_admin_detail.sql`. Vyhledá uloženou objednávku, ověří její skutečnou akci a `can_read_orders` fail-closed (`IS NOT TRUE` znamená odmítnutí), porovná očekávaný kontext, vrátí pouze její detail. Existující/dostupná versus cizí/neexistující objednávka nesmí obejít obecný unavailable stav v klientu. `SECURITY DEFINER`, explicitní `search_path = public, extensions`, grant pouze odpovídající autentizované roli, žádné přímé klientské čtení tabulek jako fallback.
2. `public.get_order_blueprint_view(p_order bigint, p_occasion bigint, p_blueprint bigint, p_expected_placement_fingerprint text)` v novém kanonickém `database/functions/eshop_orders/get_order_blueprint_view.sql`. Stejná kontrola objednávky a skutečné vazby na požadovaný plánek i očekávaného read otisku přiřazení; vrací ověřenou současnou geometrii a veřejné resource manifesty bez jmen jiných zákazníků, jejich objednávek, hold secrets nebo privátních originálů. Tato čtečka nic neukládá ani nepřipravuje authoring textové vektory.

Jde o **navržené nové podpisy**, nikoli tvrzení o existujících RPC. Nejprve implementovat a otestovat kanonické SQL a příslušnou migraci; frontend vydat až s touto čtecí verzí. Neprovádět migraci v rámci této plánovací práce.

Core odpověď má pevné sekce:

| Sekce | Minimální obsah |
| --- | --- |
| `order` | ID/occasion/form, symbol/pořadí, created/updated, obchodní stav, currency, objednané snapshoty, kontaktní projekce, noteHidden a očekávané email payment version/fingerprint. |
| `capabilities` | Odvození z nynějších typed predicates a `get_order_allowed_actions_internal_v1`, nikoli nové klientské skládání rolí. Přípustné editace jednotlivých ticketů/dávky z příslušných současných autorit. |
| `payment` | Serverový normalizovaný souhrn přes nynější helper a Stripe větev; core nevrací široký seznam transakcí. |
| `tickets` | Stabilní ticket ID/symbol, skutečný stav/usage, objednané produkty a ceny, příslušné odpovědi/poznámky. Bez duplicitního ticketu za každý jeho produkt. |
| `places` a `placementFingerprint` | `spotId`, `ticketId`, přesný `admissionItemId`/order-product-ticket, `blueprintId`, `nodeId`, text místa/stolu a současná či historicky nedostupná vazba. `plans` obsahuje ID/název/layoutRevision bez geometrie. Otisk identifikuje tuto konkrétní současnou projekci. Stání samostatně, nikoli fiktivní seatId. |
| `form` a `answers` | Potřebné definice/order-vs-ticket scope, stabilní field ID, typ a pořadí. Nepřebírat veřejné hidden-field filtrování jako admin oprávnění. |
| `emailSummary` | Stávající autorizovaný summary a `current_issues`, nikoli další klientská prioritizace podle poslední zprávy. |

Stávající `get_order_history`, `get_email_delivery_page/detail` a `get_transactions_for_order` zůstávají vlastníky detailních záložek. Žádný požadavek pro každý řádek gridu a žádné načtení celého eshopu kvůli jednomu detailu. Přístup k tabulce se neuděluje novým public table grantem; čtečky zachovají nynější role a typed predicates.

### Identita a životnost

- Jediný controller je vázán na `(occasionId, orderId)`. Každá sekce má idle/loading/ready/error/stale a vlastní generaci requestu. Při změně kontextu se okamžitě zahodí data i práva předchozí objednávky; pozdní výsledek ji nikdy nevrátí.
- Při otevření načíst core a výchozí Přehled. Historii, seznam transakcí a zpráv až při vstupu na záložku; geometrii/resource obrázky až při otevření náhledu. Přepnutí již načtené záložky bez změny dat neopakuje požadavek. Žádné nové periodické polling smyčky.
- Po potvrzené změně kontaktu obnovit core, zprávy a historii. Po platbě či změně produktů také vstupenky/místa/platební souhrn. Aktualizovat dotčený řádek a jeho finanční/stavové filtry; nevymazat checkboxy ostatních řádků. Nepřekrýt neuložené pole příchozím refreshem.
- Úspěšný příkaz a neúspěšný následný refresh jsou dvě informace: uložená operace se neopakuje. Zobrazit poslední známý stav jako neaktuální a nabídnout obnovu; není to nové selhání platby/odeslání.
- Během nejisté nebo běžící mutace nelze vytvořit novou identitu příkazu pro tichý retry. Refresh nepovolí obejít suppression ani send fencing.

### Routing a návrat

Použít současnou routu seznamu a `orderId`, doplnit `orderTab=overview|tickets|payments|emails|history` a volitelné `orderTicketId`. `orderMessageId` zachová dosavadní význam cíleného doručení/notifikace; nepřidávat souběžné `messageId` pro tutéž věc. Vazbu ticketu/zprávy na objednávku vždy reautorizovat. Výchozí Přehled parametr záložky nepotřebuje.

Otevření detailu vytvoří očekávaný Back krok. Přepnutí záložky nebo předchozí/další objednávky nahrazuje detailový stav, aby Back neprocházel desítky kontrol. Zavření odebere jen detailové parametry. Přímý vstup bez předchozího seznamu bezpečně vrátí seznam, nikoli externí neznámou historii. Query mění pouze AutoRoute vlastník; fyzický reload, Back/Forward i notifikace musí mít stejný výsledek.

Změna tabulkového filtru může odstranit právě otevřenou objednávku z viditelné množiny. Detail zůstane viditelný s informací o filtru, předchozí/další nepřejde na cizí skrytý záznam a zobrazení řádku je samostatná vědomá volba. Hromadný výběr je od otevřeného detailu nezávislý.

## Místa: identity, lifecycle a propojený plánek

### Ověřená autorita a známé pasti

| Zjištění ze současných zdrojů | Závazné chování detailu |
| --- | --- |
| Vazba `spots.order_product_ticket` určuje skutečné přiřazení. `SeatingMapping` pracuje s ticketId, admissionItemId, expectedSpotId a targetSpotId. | Primární join je uložené ID konkrétní položky, ne jméno zákazníka, titulek židle, productId, index snapshotu nebo zděděné x/y. |
| `order_tickets_with_seating_internal` vybírá jednu shodu pro order/ticket/product. `TicketModel.relatedSpot` je singulární. | Použít je pro dosavadní textovou prezentaci, nikoli jako úplnou mapovou projekci a nikoli pro instanční rozlišení duplicitních produktů. |
| `BlueprintLayoutSnapshot.seatBindings` mapuje spotId na nodeId; titulek stolu vychází z binding.group_node a skutečného labelu uzlu. | Mapa neodhaduje příslušnost ke stolu geometrickou vzdáleností, vizuální barvou nebo textovým hledáním. Rozlišit groupNodeId, selectionUnitId a prostého rodiče kresby. |
| Atomic seating unit může zahrnovat více míst, zatímco fyzická skupina může být pouze grafická. | Kliknutí při prohlížení neexpanduje objednávku o cizí členy skupiny; skutečné skupinové mutace a ochrany zůstanou vlastníkem serverového příkazu. |
| `seating_admissions_internal` už rozlišuje assigned/unassigned/standing/waiting/offered/blocked a důvody used/printed/ambiguous. | Nezavádět další osobní lifecycle v panelu. Jsou-li přítomné transition vztahy, použít tuto doménovou interpretaci pouze pro příslušný scope a z odpovědi vybrat danou objednávku. Neexponovat neveřejný helper jako nové RPC. |
| `can_read_seating_status` dovoluje také configure-only authora; čtení držitelů a přiřazení mají jiné podmínky. | Čtecí endpoint detailu vždy vyžaduje `can_read_orders` a skutečnou vazbu objednávky. Právo upravit kresbu samo nezpřístupní zákazníky. Běžný order reader nepotřebuje configure/assign oprávnění pro čtení svých dat. |
| Swap/cancellation preview mohou uvnitř spustit skutečného vlastníka operace a změny vrátit rollbackem. | Ani endpoint s názvem preview se nesmí volat při pouhém otevření mapy, změně tabu, hoveru či fokusování místa. Čtečka je skutečně bez obchodní operace a bez jejích zámků. |

Zdrojové hranice: `database/functions/eshop/order_seating.sql`, `database/functions/blueprint/seating_transition_context.sql`, `preview_blueprint_swap.sql`, `ticket_cancellation.sql`, `database/functions/user_permissions/seating_transition_operations.sql`, `lib/components/blueprint/seating_transition_models.dart` a `README.md`. V této pracovní kopii jsou souběžné nepublikované úpravy seating transition; jejich přítomnost není důkazem nasazení. Při implementaci ověřit konkrétní dotčené podpisy/revize, neslučovat do této práce cizí rozpracované změny.

### Přesná projekce míst

- Core oddělí **admission/ticket**, jeho produktové položky a přiřazení místa. Vrací úplné vazby právě této objednávky a explicitní úplnost (`placesComplete`) i souhrnné počty; žádná tichá truncation na první stránku. Je-li nutné stránkování dlouhého seznamu, mapa a souhrn nesmí vydávat pouze viditelné řádky za všechna místa. Kontrakt musí zachovat úplnou sadu ID vlastních míst odděleně od stránkované textové prezentace. Více doplňků nevytváří více návštěvníků, stejný produkt se nesloučí pouze podle productId. Každý vazební řádek má skutečné order-product-ticket ID.
- Aktivní místo je pouze spot, jehož aktuální uložená vazba vede k této objednávce a správnému ticketu. Částečně zrušené či historické místo není aktuálně obsazené touto objednávkou. Použitá, ale nezrušená vstupenka místo stále může vlastnit; její nepřesaditelnost neznamená, že zmizí z mapy.
- Chybějící, víceznačná nebo protichůdná vazba je zobrazitelný problém dat. Jeho řádek zůstane čitelný, ale nemá aktivní Zobrazit v plánku ani automatickou opravu. Současná admission projekce vyžaduje jednu primární admission položku; dvě takové položky jednoho ticketu jsou `ADMISSION_DATA_AMBIGUOUS`, nikoli podporovaný vícežidlový ticket. Platná dvoumístná pohovka má odpovídající odlišné admissions/tickety. Nikdy svévolně vybrat první z více admission položek/placementů.
- `nodeId`, `blueprintId`, `spotId`, `admissionItemId` a `ticketId` jsou odlišné identity. Hodnoty se nepřetypovávají přes popisky, pořadí ani lexikografické zkracování. Dva sály mohou mít stejné jméno Stůl 1 a Místo 2.
- Neadresná inventory alokace není automaticky židle. Stání používá skutečný product/context/area binding v konkrétním plánku, případně příslušnou organizer-managed transition, nikoli podmínku „spot.blueprint je null, tedy stání“. Více resource spotů pro jednu inventory alokaci nesmí navýšit počet osob ani množství prodaného stání.
- Vstupenka bez přiřazení, waiting/offered osoba, nekompatibilní produkt, zaplacený a dosud neusazený návštěvník i nespojená vstupenka jsou různé existující případy; panel z absence spotu neodvozuje selhání nákupu. Použít doložený důvod/lifecycle serveru.
- Předgenerované/tištěné vstupenky zachovají batch identitu a platný symbol. Stock není běžná zákaznická objednávka. Prodána/tištěna/použita se neplete s příznakem obsazenosti mapy; existující immutability omezení zůstává účinné i z nového detailu.

### Současná geometrie versus objednávka v minulosti

Náhled zobrazuje **současný uložený plánek**, nikoli rekonstrukci historické kresby ani neuložený draft otevřeného Blueprint editoru. Controller detailu nepřebírá jeho undo/redo, operationSelection ani rozpracované kapacity; otevření náhledu nevyvolá automatické Save, shaping nebo discard cizího draftu. Textové snapshoty, současné přiřazení a renderovací dokument jsou oddělené vrstvy. Přejmenovaný či posunutý stejný node/spot se zobrazí jako aktuální umístění, při relevantním rozdílu s historickým popiskem. Smazaný nebo nově vytvořený stejně pojmenovaný uzel se za původní místo nevydává.

Při zrušení či přesazení se uvolněná židle může prodat jinému zákazníkovi. V historii původní objednávky smí zůstat starý popis, ale mapa původní objednávky ji již nesmí zvýrazňovat jako její aktivní místo a nesmí odhalit jméno nového držitele. Zrušené historické položky mají samostatně přístupnou textovou část; jejich existence nevyžaduje obnovu celého starého plánku.

Více plánků ukázat jen při skutečných vazbách objednávky nebo jejího seating scope. Historický původ sám nezakládá oprávnění číst libovolný starý/smazaný/cizí plánek. Neplatná či nedostupná vazba má srozumitelné nedostupné zobrazení; žádné hledání v jiné akci, duplikátu nebo legacy rendereru.

### Konzistence core a později načtené mapy

1. Jedna core odpověď vznikne nad konzistentním DB snapshotem dotčených řádků. Tvarování pokud možno jedním SELECT/CTE; při použití nynějších helperů ověřit jejich snapshot/volatility semantiku. Nesmí slepit starý ticket se současným přiřazením z dalšího nezávislého načtení.
2. `placementFingerprint` je read-only odvozený otisk se stabilním řazením relevantních `(ticketId, ticketState, admissionItemId, productId, spotId, blueprintId, nodeId)` a existujících transition/area vazeb. Nepřidává se nová uložená verze, tabulka ani trigger. Tento read otisk není oprávnění, payment fingerprint ani náhrada command fence při zápisu. Rozsah zahrnuje i zmizení/zrušení přiřazení, nikoli jen existující spoty.
3. Lazy map reader přijme očekávaný otisk core, odvodí vlastní skutečné vazby a vrátí dokument, layoutRevision, svou placement projekci, čas načtení a otisk ze stejného snapshotu. Čas označuje pozorovaný stav, není příslibem živé dostupnosti všech míst. Při rozporu vrátí konfliktní výsledek `ORDER_PLACEMENT_CHANGED`, nikoli mapu s náhodně zkombinovanými daty. Jde o navržený read kontrakt, ne nynější produkční reason.
4. Geometrická `layoutRevision` není verze přiřazení: swap nebo změna držitele nemusí změnit geometrii. Samotné order.updatedAt ani geometrická revize nestačí. Při stejné vazbě, ale nové geometrii lze načíst novou uloženou revizi; UI uvede aktualizaci a zachová vlastní identitu, nikoli staré pixelové souřadnice.
5. Konflikt obnoví core i dotčenou mapu, zachová neuložený kontakt a zkontroluje, zda dříve zvolený ticket/spot ještě patří objednávce. Nejvýše jeden řízený navazující refresh; při dalším konfliktu nabídnout Obnovit. Žádná nekonečná smyčka nebo automatická obchodní operace.
6. Příchozí existující client-sync invalidace a návrat z mutačního workspace označí core/mapu jako neaktuální. Nevytvářet nový polling. Při návratu aplikace do popředí či explicitním obnovení používat běžný refresh boundary. Nezachovávat ochranně starou „kompatibilitu“ po změně plánku, produktů, formuláře nebo transition.

### Prohlížení a kamera

- Primární je seznam se stavem ticketu, držitelem, produkty a skutečným místem. `Zobrazit v plánku` zaměří daný node a ponechá rozlišitelné všechny aktivní místa téže objednávky. Kliknutí na vlastní zvýrazněné místo označí jeho řádek; nenavštěvuje jiné objednávky a nemění hromadný výběr gridu.
- Vizuální overlay má nejméně tři významy: kontext plánku, aktivní místa této objednávky a právě zaměřené místo. Použití/zrušení/omezení ticketu se zobrazí samostatným textem či symbolem. Barva původně autorem nakreslené židle neznamená dostupnost. Cizí místa jsou neutrální orientační pozadí, bez vymyšleného dostupné/obsazené a bez osobních tooltipů.
- Kapacitní oblast může reprezentovat více admission této objednávky. Její aktivace ukáže například „Stání: 3 vstupy této objednávky“ a odpovídající filtrovaný seznam, nikoli svévolně první osobu. Stejně tak sdílený group node nesmí být vydáván za unikátní vazbu na ticket. Více současných držitelů jedné adresné židle je naopak problém dat, ne legitimní volič.
- Kliknutí na stůl, pódium, text nebo prázdnou plochu nevybere nejbližšího zákazníka. U malého dotykového cíle musí být deterministická hit priorita; cizí nebo nedostupný uzel nepropadne na sousední vlastní místo. Nepřebírat rezervační activation/atomic expansion callbacky.
- Veřejný generický `VenueLayoutViewer` dostane minimální focus/highlight/hit/viewport seam. Výběr order/ticket drží hostitel; renderer zná jen node IDs a saved geometry. Nepoužívat editor controller, package src, parent přes interní widget state nebo `VenueLayoutPicker`.
- Kamera se uchovává lokálně pro `(occasionId, blueprintId)` při přepnutí tabu a rozšíření/zúžení téhož detailu. První otevření nabízí fit vlastních míst s minimálním okolím; Zobrazit celý plánek ukáže celek. Jeden seat nesmí být neomezeně zvětšený přes celý displej. Rozsah více vzdálených míst má přiměřený zoom a čitelný seznam.
- Resize zachová rozumné centrum/zoom v novém viewportu a fokus identitou, ne starým pixelem. Render nebo přepnutí vedlejšího tabu sám znovu nespouští fit/pan. Při změně geometrie označit aktualizaci, vyřazený fokus odvolat; opětovné zaměření je vědomá akce.
- Seznam a mapové ovladače fungují klávesnicí; informace nesmí být dostupná jen hoverem, barvou, dotykovým gestem nebo rozpoznáním QR. Zpět z celoplošné mapy vrátí stejnou vstupenku, tab a scroll. Escape zavírá nejprve nejvyšší mapovou vrstvu, ne celou objednávku s rozepsaným kontaktem.

### Návrat z existujících změnových operací

Detail sám nepřesazuje, neruší seating skupinu ani nezveřejňuje plánek. Pokud je podle existujících capabilities nabídnut vstup do nynějšího workflow, předá přesná order/ticket/item/spot/blueprint IDs, žádný předpotvrzený hash. Cílový vlastník znovu ověří oprávnění, rozsah a živý stav; získá aktuální preview a potvrzení. Atomic unit může zahrnout další místa/objednávky, které musí potvrzení jmenovitě zahrnout. Z detailového výběru se nesmí odvodit souhlas se změnou cizího ticketu.

Swap používá nynější finanční preview, confirmationHash/revision a receipted command; zrušení rozlišuje jednotlivé aktivní tickety, poslední ticket může zrušit celou objednávku. Upozornění/e-mail po zrušení je nynější oddělená explicitní volba. Zrušení ani uvolnění holdu neznamená refundaci; hold release odmítá objednaná místa a není řešením problémů tohoto detailu.

Po potvrzeném příkazu obnovit všechny dotčené části detailu a označit relevantní další řádky/cache za neaktuální podle receiptu, ne jen číselně aktuální orderId. Výsledek zůstává provedený i při zavření workspace nebo chybě návratového refreshe. Při neznámém výsledku použít existující recover/readback, nikdy nový command UUID nebo automatické opakování operace.

### Zdroje, výkon a poruchy

Geometrii a resources načítat jen pro otevřený plánek, nikoli pro všechny řádky/sály. Ověřit canonical schema-2 dokument a schválené resource manifesty; `BlueprintLayoutAssetResolver` musí zpracovat chybu/pozdní completion/dispose bez návratu do staré objednávky. Sdílet kvalifikované bytes, ne mutovatelný order state. Žádné nové kopie bitmap, legacy Supabase Storage fallback, externí originály nebo authoring text-vector generování při čtení.

Při chybě obrázku či font/vector resource se nesmí kreslit přesvědčivě chybné popisky na vymyšlené geometrii. Zůstane čitelný textový seznam a konkrétní chyba mapy s obnovou; případné bezpečné částečné vykreslení musí výslovně označit neúplnost. Theme/high-contrast overlay nebarví uložené authored fills a neukládá layout. Výběr tisku nemění QR/ticket symbol ani schéma plánku.

Velký sál se nevykresluje jako tisíce samostatných DOM/Flutter detailových karet. Použít stávající renderer, virtualizovat dlouhý seznam podle skutečné potřeby a zachovat dostupnou textovou alternativu. Limit počtu, velikosti resources a fit chování ověřit na hustém i rozlehlém plánku; neobcházet existující resource budget. Seznam nesmí čekat na dekódování všech obrázků.

### Konkrétní seating scénáře a důkazní hranice

Tato sada je součástí exit podmínek čtecího kontraktu a propojené mapy. Neznamená psát jeden test pro každou větu; sloučit související případy do smysluplných SQL/viewer/host scénářů. Neexistující nové testy musí být skutečně zaregistrovány a jejich počet/názvy viditelné v běhu.

| Případ | Správný výsledek | Co musí kontrola odhalit |
| --- | --- | --- |
| Stejný název židle ve dvou sálech a různých stolech | Přesné ID správného plánu i ticketu | Chybné hledání názvu, indexu nebo blízké geometrie. |
| Jeden ticket, několik opakovaných doplňků stejného produktu | Položky se neztratí a počet návštěvníků se nenavýší | Deduplikaci podle productId nebo mylné opakování prvního místa z LIMIT-1 helperu. |
| Dvě primární admission položky jednoho ticketu / více než jedno současné přiřazení | Zřetelná nekonzistence a bezpečný textový výpis | Neoprávněnou volbu první shody či automatickou opravnou mutaci. |
| Atomická dvoumístná pohovka se dvěma tickety | Dvě skutečné vazby, lokální fokus jedné osoby; skupinový obrys není vlastnictví | Automatickou selekci/rezervaci celého unit nebo přičtení cizího ticketu. |
| Jeden člen unit patří jiné objednávce/formuláři | Žádná cizí osoba v detailu; případné změny přes přesné potvrzení vlastníka | Rozšíření práv nebo tichou skupinovou mutaci. |
| Částečné zrušení a opětovný prodej stejné židle jiné objednávce | Jen zbývající živá místa v aktivním overlayi; původní popis v historii | Historický highlight nyní cizího místa a únik nového držitele. |
| Poslední ticket zrušen / order cancelled | Aktualizovaný obchodní stav, žádný resend/edit mimo kanonická práva | Ponechanou aktivní mapu, automatický refund nebo nevyžádaný e-mail. |
| Used a sold/printed batch ticket | Viditelné skutečné místo a důvod omezení; žádné obejití ochrany | Nabídku přesazení pouze na základě ceny/zeleného stavu. Print mismatch je historický/importovaný problém, ne podporované přesazení immutable ticketu. |
| Stání s více resource alokacemi na jednu admission | Správné osoby/množství a skutečná area vazba | Počítání inventory spot řádků jako židlí/osob; fiktivní seatId. |
| Kliknutí do kapacitní oblasti společné třem vlastním admissions | Označení oblasti a seznam tří příslušných vstupů | Svévolný výběr první osoby nebo mapování group/area uzlu jako jediného ticketu. |
| Bez místa versus čekající nabídka versus zaplacený neusazený ticket | Odlišná stávající lifecycle informace, přípustná další cesta | Sjednocení všech do Nezaplaceno nebo chyba rezervace. |
| Organizer-managed transition s více formuláři | Pouze správná admission této objednávky a její kompatibilita | Použití celého cohortu jako seznamu zákazníků této objednávky. |
| Přejmenování/přesun stejného uzlu, rozdělení skupiny | Stabilní spot/node identita; nový příslušný label/current geometry | Přepojení přes titul, staré row/column nebo nejbližší stůl. |
| Smazaný uzel / nová stejně pojmenovaná židle / historický blueprint | Text zůstává, mapování není vymyšlené | Legacy renderer fallback a náhodné dohledání jiného místa. |
| Swap během prodlevy mezi core a lazy mapou, layoutRevision stejná | Otisk odhalí nesoulad, nejvýše jeden refresh, zachovaný draft | Použití samotné geometrické revize nebo smíchání dvou snapshotů. |
| Editor současně drží neuloženou geometrii, cenu nebo kapacitu | Náhled čte uložený canonical dokument a cizí draft zachová | Tichý Save/discard, přebrání editor operationSelection nebo společnou mutovatelnou kameru/undo historii. |
| Nová geometrická revize při stejné placement vazbě | Nová uložená mapa, informace o změně a řízený fokus | Staré pixelové souřadnice nebo nevyžádané opakované auto-fit. |
| Změna práv/akce při doběhu starého bitmap fetch | Stará data se nevrátí, zdroje se uvolní | Pozdní překreslení cizí mapy nebo stale closure do jiného detailu. |
| Configure-only autor a běžný readonly order viewer | První bez zákaznických dat, druhý čte svůj scoped detail | Použití can_read_seating_status jako zákaznického oprávnění nebo vyžadování editora pro prosté čtení. |
| Chybějící/poškozený bitmap/vector manifest, čeština a RTL label | Bezpečná chyba/označená neúplnost a čitelný seznam | Nové stažení privátního originálu, reshaping zápis při read nebo falešný fallback. |
| Hustý tmavý sál, vzdálená místa, 320 px a zoom 200 % | Kontrastní focus, přiměřený fit, dostupné ovladače a seznam | Splývání authored barev s obsazeností, nekonečné přiblížení a chytání gest okolí. |
| Návrat z platně potvrzeného swapu/produktové změny dvou objednávek | Obnova aktuálního detailu a invalidace všech dotčených řádků | Refresh pouze jedné strany, tichou druhou mutaci nebo úspěch odvozený ze zavření dialogu. |
| Celá navigace seznam↔mapa, změna tabu, resize a zavření | Nulové obchodní writes a nezměněné hold/stock/layout údaje | Volání select_spot, save, swap/cancellation/publication preview nebo command při prohlížení. |

Opřít validaci o existující vlastníky: SQL sady `database/tests/blueprint/seating_assignment_test.sql`, `seating_transition_test.sql`, `seating_publication_test.sql`, `capacity_resources_test.sql`, `resource_admission_test.sql` a concurrency scénáře podle změněného kontraktu. Hostitelské operace už mají `test/components/blueprint/seating_transition_test.dart`, `ticket_cancellation_commands_test.dart`, `seat_order_commands_test.dart`. Nezaměnit importovaný `*_cases.dart` za samostatný spustitelný test root.

Generické viewport/renderování má existující testy `layout_surface_viewport_test.dart`, `layout_scene_cache_test.dart`, `layout_vector_text_test.dart` a `layout_dark_preview_test.dart` v balíčku. Přidat cílené testy nového veřejného read-only API a skutečný host journey, nikoli pouze znovu otestovat interní konstanty. Celý regresní balíček spouštět podle skutečné změny, ne preventivně pro tento plán. Při závěrečné lokální UI kontrole porovnat stav DB před/po read-only cestě a potvrdit nepřítomnost mutačních požadavků; absence viditelné změny v canvasu není důkaz.

## Zklidnění tabulky a odstranění duplicit

| Místo dnes | Cílové místo | Co zůstává a důkaz odstranění |
| --- | --- | --- |
| `ORDER_HISTORY` | Historie detailu | Odebrat z výchozího `OrdersContent.columnIdentifiers`; jiní oprávnění hostitelé používají stejné obsahové widgety. |
| `ORDER_TRANSACTIONS`, přidání platby v buňce | Platby detailu | Částky lze ponechat jako volitelné datové sloupce, nikoli druhá sada mutačních tlačítek. |
| `ORDER_OVERVIEW` | Další možnosti detailu: Zákaznický přehled | Nadále použít autorizované vytvoření odkazu `adminOverviewUrl`, ne nový veřejný token writer. |
| `ORDER_CONTRACT_DOWNLOAD` a další feature přílohy | Vhodná část detailu / Další možnosti | Zachovat podmíněnou dostupnost a nynější generátory/stažení. |
| Červená obálka v `OrderStateCell`, e-mailová značka | Tentýž detail, přímo E-maily a konkrétní problém | Jediný editor doručení. Nenechat vedle panelu druhou nezávislou opravnou obrazovku. |
| `OrderEmailRepairDialog`, `TransactionsDialog`, `OrderHistoryDialog` | Sdílené obsahy | Nepoužívané hostitele odstranit až po scoped kontrole callers. Potřebný dialog jinde je tenký hostitel stejného obsahu, ne compatibility implementace. |
| `ORDER_NOTE_HIDDEN`, generické uložení/smazání řádku | Poznámka v Přehledu; zachované obecné funkce, dokud mají volající | Neodstranit horní Uložit/Zahodit, pokud stále existuje editace nebo staged deletion. V první vlně je ponechat; zbytek gridového editačního kontraktu neřešit potichu jako „kosmetiku“. |

Výchozí grid ponechá identitu objednávky, zákazníka/kontakt, obchodní stav, finanční orientaci a stručný problém; datum, formulář, VS a další data lze zapnout bez ztráty exportu. Checkboxy, filtry, řazení, export, hromadné odeslání a hromadné zrušení se zachovají. Neprovádět globální redesign všech gridů.

## Realizační vlny

### 1. Čtecí kontrakt a vztahy

**Změny:** kanonické dva admin RPC a jejich SQL migrace; typované `OrderAdminDetail`/map projection modely v modulu eshop. Sdílet uvedené SQL helpery a současné autorizace, vrátit exact-order data i mimo aktuálně načtený filtr. Mapa používá úplné přímé vazby item/spot, nikoli LIMIT-1 textový seating helper. Doplnit konzistentní snapshot, read fingerprint a konfliktní mapový výsledek popsaný výše.

**Invariant:** žádný cizí order/ticket/blueprint, secret nebo cizí zákazník v odpovědi; otevření detailu je bez zápisu. Migrační změna je pouze rozšíření čtecího kontraktu, žádné změny datového lifecycle nebo produkční backfill.

**Ověření standard:** cílené SQL nad disposable DB pro čtenáře/editora/cizí tenant, nesprávnou akci, neexistující ID, ticket z jiné objednávky, cizí blueprint, dávku/waitlist; shoda finanční projekce a skutečných vazeb míst. Ověřit read-only chování a žádnou změnu zásob/holdů. Nové migrační gates podle `CONTRIBUTING.md`.

**Výstup:** přímé bezpečné načtení jedné objednávky a odpovídajícího čtecího plánku bez dotazu na celý eshop.

### 2. Responzivní hostitel a jedno načítání

**Změny:** `OrderDetailController`, nový responzivní hostitel v eshop/views, opt-in aktivace v `SingleDataGridController`/`SingleTableDataGrid`, AutoRoute query v nynější Orders routě. Pět záložek s lazy sekcemi, cíleným přechodem a zachováním table state.

**Invariant:** samostatný hromadný výběr; žádný hit overlay nad buňkami; jeden aktivní detail bez stacku kopií. Ztráta práv/změna kontextu skryje předchozí data, pozdní response se zahodí.

**Ověření standard při změně shared grid:** cílené widget testy row/copy/checkbox, editovatelné buňky a text selection, loading/error/stale, scoped requests a neplatné child ID, návrat fokusu. Jeden lokální skutečný browser průchod direct link, reload, Back/Forward, A→B→A, notifikace a detail mimo filtr. Nezakládat tests duplikující pouze layout konstanty.

**Výstup:** detail lze otevírat a procházet bez úpravy obchodního chování a bez ztráty práce v seznamu.

### 3. Reuse obsahu a bezpečné změny

**Změny:** vyjmout společný editor kontaktu, platební obsah a historii z nynějších dialogů. Připojit existující příkazy, PDF, produkty a feature přílohy. Přehled propojí konkrétní problém se záložkou a vybranou zprávou/vstupenkou. Nynější dialogy mají stejné řízení, pokud je potřebují jiní callers.

**Invariant:** save-only nic neposílá, aktuální příjemce nemění historické události, změna emailu není změnou vlastníka/účtu. Práva bankovních akcí, ticket akcí a objednávek se neslévají. Příkaz a jeho následný refresh mají samostatné výsledky.

**Ověření:** normální targeted widget/SQL stávajících operací podle změny; zdravý kontakt, validní cizí adresa, suppression se stejnou/case-only/jinou adresou, pending/sending/unknown, 409, uloženo+refresh selhal, readonly/cancelled. Hotovost a přiřazení pohybu přes reálné disposable operace; žádné skutečné externí e-maily nebo karetní platby. Respektovat 1 Flutter úkol a `--concurrency=1`.

**Výstup:** všechny sekce obsahují skutečná aktuální data a přípustné akce přes stejné vlastníky, bez samostatné nové obchodní implementace.

### 4. Propojená mapa

**Změny:** minimální rozšíření veřejného `VenueLayoutViewer`/viewport API a `OrderPlacesView`. Přečíst příslušné vendored `AGENTS.md`; postup aktualizace balíčku zachová jeho archivní/consumer gates. Katalogové/seat editory se do detailu neimportují.

**Invariant:** list↔map používá skutečné identifikátory, zatímco geometrie a rezervace jsou beze změny. Rozšíření mapy zachovává stejnou objednávku i stav zbytku detailu.

**Ověření:** generický viewer test zvýraznění/focus/fit/hit bez obchodních callbacků a targeted host tests vazeb. Použít konkrétní seating akceptační sadu níže, zejména změnu vlastníka bez změny layoutRevision, opakované produkty, atomic unit a historicky uvolněné místo. Lokální integrační scénář: více míst u jednoho i různých stolů, místo mimo viewport, žádná místa, stání, historicky nedostupné místo, jiný blueprint, chyba resources; nulové hold a order write požadavky při prohlížení. Pro případné změny package kontraktu standard včetně jeho normálních spotřebitelských kontrol.

**Výstup:** pořadatel dohledá skutečné místo a vrátí se ke vstupence i na telefonu bez otevření editoru nebo rezervace.

### 5. Přesun akcí, sjednocení a dokumentace

**Změny:** provést výše uvedený deletion ledger až po nahrazení akcí v detailu; zachovat ostatní callers a shared grid kontrakt. Rozšířit HTML jen pokud je potřeba ukázat finální vybrané rozložení před implementací, bez jeho přímého přebírání do produkce. Aktualizovat skutečné screenshoty a článek s kompletními 27 stavy po zprovoznění finálního UI.

**Ověření:** scoped callers, targeted Dart analyze změněných souborů, současné objednávkové/mailové/platební widget testy podle dopadu, jedna závěrečná browser sada klíčových cest a rozměrů. Passing checks neopakovat bez změny pokrytých vstupů. Flutter nespouštět souběžně.

**Výstup:** výchozí tabulka nemá nahrazená tlačítka a všechny jejich přípustné operace jsou dohledatelné v detailu; dokumentace ukazuje skutečnou konečnou implementaci. Prototyp archivovat jako návrhový podklad nebo odstranit, žádné A/B/C přepínače v app.

## Akceptační cesty a konkrétní data

| Situace | Co musí jít dokončit |
| --- | --- |
| Jana Novotná, 4 místa po 650 Kč, uhrazeno 2600 Kč | Otevřít řádek; v Přehledu změnit zdravý kontakt a pouze uložit; ověřit původního příjemce v E-mailech a změnu v Historii. Žádné nové odeslání. |
| Petr Dvořák, dvě místa u stolu 8 a dětský doplněk | Zobrazit správné místo v plánku a zpět jeho vstupenku. Počet produktů se nesmí vydávat za počet návštěvníků. |
| Alžběta Černá-Svobodová, 6 míst, část zaplacena jako záloha | Správně ukázat zálohu, termín doplatku a autoritativní nedoplatek; při dlouhém kontaktu nesmí zmizet ovládání. |
| Rodina s různými odpověďmi za jednotlivé návštěvníky | Otevření jedné vstupenky nezobrazí kontakt objednávky jako jméno každého držitele a nepromíchá odpovědi. |
| Volné stání a vstupenka bez místa | Přečíst produkty/počet a kapacitní oblast, nezobrazit nefunkční Zobrazit v plánku pro neexistující židli. |
| Nedoručeno versus doručeno na platný cizí kontakt | V obou případech najít stejný editor kontaktu. Nové odeslání je vědomá akce a respektuje cílovou suppression. |
| Used/zrušený ticket, zrušená objednávka, dávka či waitlist | Zachovat správné stavy a povolené akce; nemačkat univerzální Editovat/Odeslat podle domněnky klienta. |
| Neznámý payment nebo Stripe pending/refund | Neukázat falešné Nezaplaceno ani hotové Vráceno. Zrušení objednávky nevrací peníze. |
| Readonly, ztráta oprávnění, změna akce při načítání | Nepovolit příkaz a nezobrazit data předchozího kontextu. Chyba jedné lazy sekce neblokuje ostatní platné sekce. |
| 320/390 px, tablet, široké okno a zvětšený text | Záložky dosažitelné klávesnicí, žádný globální overflow, čitelný seznam míst, ovladatelná mapa bez povinného gesta a návrat na stejný řádek. |
| Uloženo, ale readback selhal / souběžná změna | Nezopakovat mutaci. Rozlišit potvrzený výsledek, konflikt a neaktuální načtení; neuložený text uživatele se neztratí. |

## Povinná lokální kontrola před nasazením

Poslední pokyn uživatele stanovuje závazné pořadí: implementace → skutečné lokální napojení → ověření → lokální předání a zpětná vazba → teprve samostatně autorizované nasazení. Exekuční postup vlastní `order-detail-EXECUTION-PROMPT-2026-11-01.md`.

Lokální výstup je skutečná Flutter aplikace na loopback URL se skutečným izolovaným Supabase Auth/DB/REST a potřebnými Functions. Realistické fiktivní objednávky mají konzistentní částky, stavy a vazby; změna kontaktu i oprávněné místní operace musejí přežít skutečný reload. HTML simulace, podvržené RPC nebo pouze screenshot nestačí. Externí doručení/banka/karty nejsou autorizovány a jejich neověřenou hranici nezaměňovat za reálné provider potvrzení.

Předání obsahuje stabilní lokální URL, přístup k ukázkovému účtu, stručné kroky a vyplněný `docs/plans/evidence/order-detail-local-review.md` s konkrétními revizemi, endpointy, datovým fixture a výsledky. Aplikační server a vlastněný lokální backend se po automatické QA ponechají běžet pro uživatele; jeho instance se neuklidí dříve, než ji může vyzkoušet. Jiným projektům a běžícím Flutter úlohám se nepřerušuje práce.

Po lokálním předání práce zastaví na stavu „připraveno k lokální kontrole“. Produkční migrace, tenant release, Functions/Worker deployment, balíčková publikace a zveřejnění článku čekají na další výslovný pokyn. Souhlas s variantou A nebo vytvořením promptu sám o sobě není souhlas s nasazením.

## Zbývající hranice a dokončení

Výběr A je uzavřený. Přesná šířka panelu se odvodí z UX specifikace a ověří na skutečných datech; samotný breakpoint z průzkumného prototypu není produkční kontrakt. Uživatel může při další kontrole upravit výchozí množinu datových sloupců, nikoli tím automaticky změnit obchodní oprávnění.

Tato práce je plánovací: nepovoluje implementaci, produkční změny, migrace, nové zprávy, commit/push ani vydání. Budoucí implementace používá normální standard kontrol u veřejného read kontraktu, sdíleného gridu a balíčkového API. Nové read-only RPC se nasazují před jejich frontendem bez legacy fallbacku; samotný frontend návrat ke starému vydání může čtečky nechat nevyužité, nikdy neobnovuje starý writer.

Hotovo znamená současně: užitečný detail všech pěti záložek, bezpečná běžná editace kontaktu, správné list↔map místo, sdílené vlastníky plateb/historie/mailů, zachovaný hromadný výběr/routing a odstraněná nahrazená řádková tlačítka. Pouhé otevření panelu nebo obrázek mapy za hotovou realizaci neplatí.

## Ověření návrhových podkladů

Astra s medium reasoning vytvořila UX návrh i HTML. Nezávislý věcný kritik zkontroloval technické předpoklady a úplný slovník stavů; opravy `done` a názvu vstupní metody jsou zapracovány výše.

Terra ověřila statické HTML v izolovaném headless prohlížeči při 1440, 1024, 390 a 320 px: varianty A/B/C, záložky, rozlišení checkboxu od otevření řádku, uložení bez odeslání, ochranu změn při zavření i přepnutí a všech 27 stavů. Globální vodorovné přetékání ani chyby JavaScriptu nezjistila. Po opravě znovu ověřila návrat voliče scénáře při odmítnutí přechodu a rozdíl mezi původní blokovanou a novou neblokovanou adresou. Neznámý výsledek nadále blokuje odeslání. Doplněné šipky přepínače prošly kontrolou syntaxe; plný browser průchod kvůli nim nebyl opakován.

To dokládá interaktivitu simulace, nikoli skutečné doručení nebo kompatibilitu s backendem. Prohlížeč byl uzavřen a nebyl spuštěn žádný server. Kontrolní snímky jsou v `.private/order-detail-prototype/`. Tyto výsledky patří původnímu průzkumnému prototypu. Rozpracovaný cílový plán navíc zachovává draft při přepnutí záložky stejné objednávky a specifikuje propojený read-only plánek; tyto nové chování nebyly v původním HTML implementovány ani browserem ověřeny.

Poslední zpřesnění blueprint části je zdrojové plánovací ověření nad současnou pracovní kopií: konkrétní helpery, lifecycle, kardinality, oprávnění a existující testové hranice byly dohledány; integrační kontroly popsané v nových scénářích se teprve provedou při implementaci. Aplikace, balíček, SQL, HTML a produkce se tímto zpřesněním neměnily.
