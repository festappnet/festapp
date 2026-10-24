# Organizační notifikační centrum

Datum: 2026-10-23
Stav: Lokální implementace dokončena a cíleně ověřena. Organizační zvoneček není nasazený ani aktivovaný v produkci. Globální architecture gate má níže výslovně uvedený nesouvisející blocker.
Ověřování implementace: standard (oprávnění, souběh, databázové migrace).
Autorita: tento plán a rozhodnutí uživatele zachycená níže.

## Cíl a závazný rozsah

Správce organizace i organizátor akce mají osobní zvoneček napříč dostupnými akcemi jedné organizace. Obsah i detail respektují současná serverová oprávnění. Organization je tenant, Unit organizační jednotka, Occasion konkrétní akce; nikdy neslučovat různé tenanty do jedné odpovědi.

- Aktuální akce nahoře, ostatní pod ní. Společný problém s dopadem na aktuální akci nad oběma skupinami; bez zvolené akce společné problémy a následně skupiny akcí.
- Automaticky sledovat dostupné akce, umožnit osobní ztlumení jednotlivé akce.
- Pouze tečka u zvonečku. Žádný počet, toast, zvuk, push ani upozorňovací e-mail.
- Otevření panelu označí všechny do té chvíle doručené dostupné položky za přečtené, včetně nenačtených stránek a nerozbalených skupin. Stav je osobní a společný všem zařízením uživatele.
- Nová událost po otevření znovu rozsvítí tečku, i když přibude do již přečtené skupiny. Zaplacení a zotavení problému pouze aktualizují stav bez nového nepřečtení.
- Historie zůstává v panelu, starší obsah se stránkuje. Skupina se minimalisticky rozbalí přímo v panelu; jednotlivý řádek vede na existující detail.
- Vlastní administrátorské úkony autorovi nehlásit, ostatním ano. Pozdější automatické selhání související s jeho úkonem autor vidí.
- Pouze nové události od aktivace organizace. Žádné doplnění starých objednávek ani existujících problémů.
- Bez společného přebírání, přiřazování a ručního uzavírání problémů, změn oprávnění a účastnického zvonečku.
- Nezahrnovat přihlášení do aplikace, vytvoření účtu ani registraci na programový workshop. První verze míří na objednávky, náhradníky, prodejní kapacity, banku a všechny druhy odchozích e-mailů.
- Samostatné nové upozornění na běžnou platbu ani nová pravidla platebního párování nejsou součástí.

## Katalog událostí a chování

| Zdroj | Chování | Seskupení / pozornost |
|---|---|---|
| Úspěšně vytvořená běžná objednávka | Ihned, včetně nezaplacené; bezplatná se svým skutečným stavem | Akce + místní kalendářní den + běžné objednávky |
| Objednávka do pořadníku | Ihned, označení V pořadníku | Samostatná skupina akce + den |
| Zaplacení, odeslání vstupenek | Aktualizovat projekci existující objednávky | Bez nové pozornosti; nevytvářet položku, pokud původní neexistuje |
| Storno celé objednávky / části vstupenek | Skutečný potvrzený přechod, skutečný rozsah | Akce + den + storna; stav kapacity připojit k příčině |
| Náhradník přijal / odmítl / nabídka vypršela | Jednotlivé položky, počty míst a identita nabídky | Jedna položka na nabídku, výsledek a zdrojový příkaz; částečná přijetí zachovat |
| Kapacita dosáhla 90 % | Serverový přechod přes hranici | Samostatně pro skutečný celkový limit a omezený typ vstupenky |
| Vyprodáno / místa opět dostupná | Rozlišit veřejně volná místa a místa držená pro pořadník či nabídky | Jedna změna nemá vytvořit storno a totožné druhé upozornění |
| Bankovní připojení | Potvrzený problém tokenu hned; přetrvávající chyby nebo zastaralá kontrola po toleranci | Jedna aktualizovaná epizoda na připojení; zotavení bez nové tečky |
| Všechny odchozí e-maily | Trvalý bounce, complaint, reject, rendering failure, dead, neočekávaná suppression a déletrvající nejistota/zdržení | Jedna problémová položka na zprávu; při hromadném dopadu kompaktní skupina podle příčiny a rozsahu |

Seskupení po kalendářním dni v časovém pásmu organizace (pokud není uloženo, použít současnou tenant konfiguraci času a výsledek zdokumentovat) je návrhový výchozí parametr, ne dodatečný uživatelský požadavek. Jednotlivé řádky zůstávají dohledatelné; skupiny nevytvářejí duplicitní události. Nejnovější změna pozornosti řadí skupinu pouze v její sekci. Souběžné překročení 90 % a vyprodání zobrazit jako vyprodání, ne dvě položky.

## Ověřené opory ve zdrojích

| Fakt | Zdroj / symbol | Důsledek |
|---|---|---|
| Objednávky mají explicitní SQL boundary a replay receipts | `database/functions/eshop_orders/create_ticket_order_client_sync_v1.sql`, `database/functions/eshop/create_ticket_order.sql`: `create_ticket_order_internal_v1` | Vznik události patří k úspěšné změně, ne k Flutter/JS kliknutí |
| Pořadník má příkazy register/send/accept/decline/cancel/withdraw | `database/functions/eshop_waitlist/commands.sql`: `execute_waitlist_command_client_sync_v1` | Rozlišit registraci do pořadníku a přijetí již existující objednávky |
| Expirace se provádí i mimo explicitní příkaz návštěvníka | `database/functions/eshop_waitlist/offers.sql`: `expire_waitlist_form_internal`; `fakturoid_recovery.sql` | Publikace expirace musí být v tomto vlastníku, včetně pravidelné údržby |
| Celková kapacita je nyní formulářová, ne univerzální číslo na Occasion | `database/functions/eshop_waitlist/form_capacity.sql`: `get_form_capacity_snapshot_internal` | Nepřepočítávat osoby nebo libovolně nesčítat formuláře |
| Nabídky a čekatelé ovlivňují skutečně dostupná místa | Stejná funkce: `remainingPublic`, `offerablePlaces`, `offeredPlaces`, `waitingPeople` | Prosté limit minus prodané je chybný výpočet |
| Storno má sdíleného doménového vlastníka | `database/functions/eshop_orders/update_order_and_tickets_to_storno.sql`: `cancel_order_domain_internal_v1`; `internal_storno_tickets_221.sql` | Prověřit celá i částečná storna a platební automatizaci, nevkládat jen do UI wrapperu |
| E-mailová fronta již uchovává události i konečné stavy | `database/functions/emails/email_queue.sql`: `finish_email_attempt`, `reconcile_email_events`, `record_email_events`, `recover_email_delivery`; `email_schema.sql` | Číst potvrzený výsledek společného reduktoru, žádná druhá fronta odesílání |
| Reporting má oddělené oprávnění pro organizaci/akci | `database/functions/emails/email_reporting.sql`: `email_report_allowed`, `get_email_delivery_detail` | Všechny druhy zpráv neznamená zpřístupnit bezpečnostní e-maily všem organizátorům |
| Stav banky zahrnuje poslední pull a chybu | `database/functions/eshop_bank_sync/bank_sync_manage.sql`: `get_bank_sync_connection`, `record_bank_sync_pull` | Stav musí vznikat i bez otevření nastavení účtu |
| Současný status se obnovuje při požadavku z klienta | `supabase/functions/bank-sync-manage/index.ts`: operation status; `bank-sync-reconcile` řeší operation intents | Nelze předpokládat, že existuje pravidelný monitoring všech připojení |
| Existující notifikace slouží také publikaci novinek a push | `database/functions/notifications/publication.sql`, `dispatch_log_notification.sql`, `public.log_notifications` | Zachovat účel, nepoužít jako osobní organizační inbox |
| Navigace a dialogy mají sdílené vlastníky | `lib/components/occasion/admin_page.dart`, `docs/architecture/tab_deep_links.md`, `lib/widgets/app_dialog.dart` | Nepřidávat druhý navigační shell či paralelní systém dialogů |

Jde o lokální evidenci zdrojů, nikoli ověření nasazené produkce. Pracovní strom obsahuje rozsáhlé jiné rozpracované změny; neuklízet je ani nepřepisovat.

## Architektura a kontrakt

### Vlastnictví

Nová aditivní doména `database/functions/notification_center/`, Flutter `lib/components/notification_center/`. Doménové události vlastní server. Flutter renderuje bezpečné DTO a volá autorizované RPC. Veřejný JS checkout zůstane pouze producentem přes současné příkazy; nedostává administrátorský panel.

Doménová změna zapíše malou trvalou událost v téže transakci. Nový interní projektor z ní po commitu idempotentně vytvoří osobní doručení. Žádné síťové volání v transakci objednávky, žádné persistentní aplikační triggery. Automatický běh projektoru a monitoringu přes ověřený servisní scheduler, s doháněním nevyřízených položek po výpadku; nevyžadovat otevření panelu. Projektor nic neposílá e-mailem ani push.

Názvy níže jsou cílové návrhy nových objektů, nikoli tvrzení o existujících API:

- `notification_center_activation`: tenant, `enabled`, neměnný počátek první aktivace, generace. Pauza nezakládá nový začátek ani znovu neimportuje historii.
- `notification_center_events`: UUID, tenant, akce/jednotka nebo explicitní množina ovlivněných akcí, druh, reference na entitu/příkaz, ověřený actor, `occurred_at`, dedupe key, bezpečná minimální data, revize pozornosti versus revize prostého stavu. Unikátní klíč tenant + zdrojový fakt + druh přechodu.
- `notification_center_recipients`: zamýšlení příjemci zachycení při vzniku nové události podle doménových oprávnění, ne pozdější libovolní členové. Projektor při doručení práva znovu kontroluje.
- `notification_center_deliveries`: osobní projekce, unikátní příjemce + událost + revize pozornosti, sekvence doručení, rozsah a group key; žádné kopie tajemství či celých objednávek.
- `notification_center_user_state`: uživatel + tenant, `last_delivery_sequence`, `read_through_sequence`. Přidělení sekvence i označení přečtení serializovat zámkem stejného řádku. Nepoužívat globální sequence ID nebo čas jako důkaz pořadí commitů.
- `notification_center_preferences`: uživatel + tenant + akce, osobní mute. Ztlumení zastaví nová běžná doručení a tečku pro danou akci, historie zůstane; odtlumení nevytvoří zpětná doručení. Společný bankovní problém se týká i dalších neztišených akcí, proto nesmí zmizet všude kvůli jediné ztlumené akci.
- `notification_center_source_state`: baseline a epizoda monitorovaného zdroje, poslední pozorování, číslo přechodu, poslední úspěch; inicializace existujícího problému potichu.

Před finální DDL zvolit nejmenší normalizaci, která zachová tyto kontrakty. Nevytvářet framework univerzálního event busu. Recipient snapshot, idempotence a commit-safe přečtení jsou povinné bez ohledu na fyzické rozdělení tabulek.

### RPC a souběh

- `get_notification_center_badge(organization)` vrací pouze dostupnou nepřečtenou pozornost. Žádná čísla ani názvy nepovolených entit.
- `open_notification_center(organization, current_occasion, limit)` pod zámkem osobního stavu vezme horní sekvenci, uloží monotónní přečtení a vrátí první stránku + snapshot a cursor. Celý read/ack se děje na serveru. Znovuotevření je bezpečné.
- `get_notification_center_page(...)` a `get_notification_center_group(...)` používají stabilní cursor v rámci sekce/skupiny; priorita aktuální akce není globální časový sort. Parametr aktuální akce jen mění řazení, nerozšiřuje práva. Neoprávněný kontext odmítnout.
- `set_notification_center_muted(...)` smí změnit pouze vlastní preference v dostupné organizaci.
- Privilegovaný publish/project/observe/cleanup API bez grantů pro anon/authenticated. Před interním voláním ověřit servisní identitu; `SECURITY DEFINER` vždy `search_path = public, extensions`, explicitní oprávnění a uzavřené granty.

Pokud po otevření dorazí událost, má vyšší osobní doručovací sekvenci a zůstává nepřečtená, i když je panel stále otevřený. Automatický refresh sám neposouvá přečtení. Starší ack z jiného zařízení nesmí přepsat novější kurzor. Pozdě doručený projektor je nová doručená věc a rozsvítí tečku. Odpověď na ztracené spojení může být znovu bezpečně načtena; klient nesmí ukazovat potvrzené označení, pokud zápis není potvrzen.

Po změně účtu/tenantu vyčistit stav i rozpracované požadavky. Veškeré seznamy, skupinové počty, badge a detaily znovu ověřují současná práva; odebraná práva okamžitě přestanou zpřístupňovat stará doručení. Nepřidávat osobní data do veřejného Client Sync katalogu ani sdílených cache.

### Oprávnění a citlivé zdroje

Objednávky/pořadník/kapacita: skutečná serverová práva číst příslušné objednávky nebo agregovanou kapacitu. Obecné členství v akci nestačí. Konkrétní predikát odvodit ze stávajícího RPC detailu, nevymýšlet klientské role.

Banka: účet může být sdílen mezi jednotkami. Administrátor připojení smí otevřít bankovní detail; oprávněný organizátor ovlivněné akce může dostat pouze bezpečný dopad na zpracování plateb a odkaz na vlastní objednávky. Nikdy mu nedávat token, chybový payload, celý účet ani bankovní nastavení. Explicitně testovat obě úrovně a vazbu účtu na danou akci.

E-maily: pokrýt všechny `message_kind`, ale vždy přes skutečná reporting oprávnění. Autentizační/resetovací/bezpečnostní zprávy bez oprávněného detailu dát pouze správci organizace, bezpečně a bez obsahu, odkazu s tokenem či příjemce navíc. Neorganizátor nedostává účastnický inbox. Complaint znamená potvrzené označení příjemcem jako spam; automatické umístění do spamové složky nelze z nynějšího kontraktu tvrdit. Open/click nejsou důkaz doručení do Inboxu.

### Baseline, kapacita a problémy

Při aktivaci pouze zaznamenat výchozí zdrojové stavy, bez doručení. Existující problém pokračující po aktivaci není nový. Po skutečném zotavení může další nové selhání založit novou epizodu. U zpožděného provider webhooku použít čas původního faktu a zdrojovou identitu, ne datum zpracování; staré selhání zůstane mimo. Nové selhání e-mailu vytvořeného před aktivací je naopak nová událost, pokud nastalo až po aktivaci.

Přechody kapacity sledovat ve stávajících autoritativních transakcích pod jejich doménovými zámky. Používat snapshot před/po a serverová pravidla reálné prodejnosti, ne znovu implementované čítače. 90 % jednou při překročení, znovu aktivovat až po poklesu pod 85 %. Sold-out/reopened podle přechodu skutečné dostupnosti, při opakovaném kmitání aktualizovat jednu epizodu namísto proudu duplicit. Vyprodání veřejného prodeje kvůli čekatelům označit přesně; přijatá nabídka není další nová objednávka. Běžné dočasné držení vybraného sedadla nesmí spamovat kapacitu; použít současná pravidla závazných rezervací/objednávek.

Nynější celková kapacita je per formulář. Má-li akce více formulářů, upozornění vždy pojmenuje formulář; nevymýšlet celkovou akční kapacitu jejich součtem. Typy vstupenek a blueprint/inventory mají své vlastní autoritativní limity. Ve vlně 1 přesně navázat jejich dostupnost; bez existujícího limitu nic nehlásit. Změna limitu může vyvolat legitimní přechod, vlastní nastavení autorovi nehlásit.

Banka: nový serverový health refresh sdílí autentizovaného BankSync klienta a mapování účtů se současným status flow. Nečíst banku přímo ani neoživovat starý import. Výchozí kontrola po 5 minutách, omezené dávky, timeout/backoff a lease; toleranci odvodit od skutečného provider intervalu. Pro přechodné chyby minimálně dvě po sobě jdoucí neúspěšná pozorování a 15 minut trvání; neočekávané stáří poslední úspěšné kontroly je samostatný problém i bez nového error. Potvrzený neplatný/neaktivní token hlásit hned; timeout za něj nevydávat. Ruční suspend není porucha. Zotavení potvrzuje úspěšný pull, ne uložení tokenu. Výpadek BankSync transportu odlišit od chyby konkrétního bankovního účtu.

E-maily: vyhodnocovat společný `email_reporting_state` a skutečný výsledek fronty, neměnit frontu. Běžné krátké retry bez upozornění; pro nejistotu/zdržení výchozí práh 30 minut od splatnosti, ne od vytvoření plánované zprávy. Deadline nabídky může vynutit dřívější pozornost. Zrušená/expirující zastaralá zpráva není sama o sobě doručovací incident. Potvrzený nový bounce/complaint se neztratí kvůli dřívějšímu delivery webhooku. Opakované webhooky a pozdější stejné selhání nezvyšují pozornost; skutečně nová třída dopadu může jednou zvýšit revizi stejné položky.

Výchozí retence panelu 90 dní, po dávkách čistit doručení a bezpečné projekce; aktivní nové problémy zachovat do zotavení. Nečistit obchodní historii ani email audit. Jde o návrhový výchozí parametr, ne schválení ničení existujících dat. Bez nového obecného nastavení prahů/retence v první verzi.

## UI/UX kontrakt

Návrh zpracoval samostatný agent s medium reasoning podle skillu impeccable a existujících komponent; nic nevykresloval ani neměnil. Jeho doporučení jsou začleněna níže.

### Společná lišta a panel

- Jeden bell před uživatelskými ovládacími prvky v desktopové i mobilní administrátorské liště. Vlastník `lib/components/_shared/app_panel_helper.dart` (desktop actions kolem řádku 635, mobile kolem 816); integraci spotřebovává `lib/components/navigation/routed_tab_scaffold.dart` i `lib/components/unit/views/unit_admin_page.dart`. Nepřidávat další zvoneček do jednotlivých tabů.
- Existující breakpoint 720 px: desktop pravostranný `AppDialog`, přibližně 440 px široký s bezpečnými okraji a omezenou výškou. Pod breakpointem `AppDialog.fullscreen`. Hlavička Upozornění, nastavení, pravé zavírání; používat sdílený dialog z `lib/widgets/app_dialog.dart`.
- Tečka přibližně 8 px, kontrastní, bez čísla; celý cíl minimálně 48 px. Přístupný popis Upozornění / Upozornění - nové události. Escape, Back a close vracejí fokus na bell.
- Barvy, ikony a typografie z existujícího `ThemeConfig`, žádný nový designový systém. První verze je pracovní rozhraní, bez dekorativních animací a zvuků.

### Sekce, skupiny a nové příchozí

- Jedno scrollovatelné tělo se společnými problémy aktuální akce, aktuální akcí a ostatními akcemi. Prázdné sekce skrýt. Sdílený problém pouze jednou s bezpečným rozsahem dopadu.
- Aktivní akci určit z aktuální route. Na unit úrovni může být `RightsService.currentOccasion()` zastaralé, proto jej nepoužít jako jediný zdroj kontextu.
- Skupiny objednávek a storen začínají sbalené, hlavička obsahuje skutečný počet a druh. Po rozbalení nejvýše pět řádků, následně Zobrazit další. Řádek: symbol objednávky, oprávněně dostupné jméno, skutečný stav a čas, ovládání Detail. Nabídky náhradníkům jednotlivě.
- Změna platby nepřesune skupinu na začátek. Zobrazený počet je počet objednávek ve skupině, ne počet nepřečtených na bellu. Případný údaj nových položek se počítá proti snapshotu před open ack, ne proti již posunutému watermarku.
- Nové příchozí při otevřeném panelu rozsvítí tečku, zachovají scroll/fokus a nerozhází řádky pod kurzorem. Tiché inline Nová upozornění načte nový snapshot stejným open RPC a potvrdí jeho přečtení; běžný background refresh nic neackuje.
- Stránkovat v rámci prioritních sekcí, aby historie ostatních akcí nevytlačila aktuální akci. Historie zůstává viditelná bez zvýraznění přečtených jako nových.
- Nastavení v hlavičce otevře jednoduchý seznam dostupných akcí se ztlumením; tentýž ovladač v menu sekce akce. Vysvětlit zachování historie a absenci replay po odtlumení.

### Přímé odkazy mají konkrétní cíl

UI agent ověřil, že `/:occasionLink/reservations/orders/current` a `.../orders/email-history` jsou seznamy, nikoli obecný kontrakt detailu konkrétního objektu. Proto vlna 4 musí doplnit kanonický AutoRoute/deep-link parametr pro konkrétní order/message ID, který po autorizovaném načtení vybere a otevře objekt. Obecný seznam bez výběru nesplňuje tlačítko Detail. Implementovat podle `docs/architecture/tab_deep_links.md`, bez ručních změn generovaného routeru a bez alternativního detailového UI.

- Objednávka a pořadník: existující `lib/components/eshop/views/waitlist_order_detail.dart` a vlastník otevření v `lib/components/eshop/eshop_columns.dart` kolem řádku 617; sdílet skutečný stávající detail.
- E-maily: `lib/components/eshop/views/orders_email_history_page.dart` má `ordersOnly: true`, proto nestačí pro všechny zprávy. Použít scope-aware `lib/components/email_delivery/email_delivery_history.dart` s autorizovaným message cílem. Neoslabovat reporting práva jen kvůli pohodlnému odkazu.
- Banka: existující `/unit/:id/edit/bank-accounts/:accountId/connection` v `lib/app_router.dart` pouze pro oprávněného administrátora účtu. Pro organizátora jen bezpečný dopad a jeho relevantní objednávky.
- Před navigací zavřít panel, zachovat potvrzení neuloženého draftu; odmítnuté oprávnění nebo smazaná entita zobrazí nedostupný detail bez přepnutí na jinou náhodnou akci.

### Stavy a přístupnost

- Prázdno: Zatím žádná upozornění. Zde uvidíte nové události od zapnutí upozornění.
- První loading: stabilní hlavička a malý progress. Chyba: Upozornění se nepodařilo načíst + Zkusit znovu. Chyba refresh zachová obsah s Nelze aktualizovat; chyba další stránky je lokální.
- Dokud není read ack potvrzen, nevydávat tečku za úspěšně vymazanou. Offline nelze předstírat úspěšné přečtení na ostatních zařízeních.
- Ověřit 320 px, obě strany 720px breakpointu, desktop a 200% text; dlouhé názvy, theme kontrast, expand/collapse semantics, klávesnici, čtečku, focus restoration a reduced motion. Barva není jediný nositel problému.
- Vykreslený stav je nutné ověřit až při implementaci na reálném lokálním toku; tento návrh není vizuální QA evidence.

## Implementační vlny

### 1. Základ, bezpečnost a průchozí objednávka

Cíl: jedna skutečná objednávka vytvoří přesně jednu oprávněnou osobní položku.

- Přidat kanonické SQL `notification_center/`, aditivní migraci, privátní tabulky/RLS/indexy, interní publish a omezené RPC. Aktivace defaultně vypnutá.
- Zmapovat všechny aktuální callery `create_ticket_order_internal_v1` a zapsat událost v jediném společném úspěšném doménovém bodě; replay a chyby nevytvářejí další události. Totéž pro waitlist register. Dedupe zdrojové identity, ne jen UI request UUID.
- Přidat projektor s lease/retry a bezpečným snapshotem příjemců, bez síťových vedlejších efektů checkoutu. Ztráta události při rollbacku je požadovaná; ztráta doručení po commitu se dohání.
- Explicitně vyřešit chybějící ověřený actor u servisních wrapperů; nenahrazovat jej libovolným klientským parametrem. Vlastní změnu potlačit pouze pro ověřeného administrátorského autora. Pozdější automatická chyba se nepotlačuje.
- Ověření: izolované SQL testy pro ACL, dvě organizace, dvě akce, vlastní úkon, replay/rollback a fanout retry; dvouspojový test delivery versus open ack a dva souběžné ack.
- Výstup: fungující DB kontrakt v lokální izolované DB, nula produkčních změn.

### 2. Všechny obchodní přechody a kapacity

Cíl: všechny schválené obchodní události dosáhnou stejného vlastníka.

- Napojit běžné a částečné storno v jejich doménových vlastnících, ne duplicitně ve wrappers; ověřit automatické expirace a storna z platebních cest.
- Napojit accept/decline a expiraci nabídky včetně `expire_waitlist_form_internal` a scheduler cesty. Atomicky zachytit počet změněných slotů, nevyrábět událost při nulovém přechodu.
- Platební a ticket-send přechody aktualizují pouze existující projekce bez nové revize pozornosti. Odebraná či smazaná entita má bezpečný nefunkční-detail stav; historie nesmí bránit legitimnímu smazání přes FK.
- Připojit před/po snapshoty formulářové, typové a seat/inventory kapacity při vytvoření, stornu, nabídce, přijetí, expiraci a změně nastavení. Dodržet současné pořadí doménových zámků, recipient/state zámky držet jen v projektoru.
- Ověření: relevantní stávající order/waitlist/capacity SQL testy + cílené testy přechodů 90/full/reopen, sdílených limitů, partial offer, souběhu nabídky a objednávky, žádných duplicit.
- Výstup: schválený katalog objednávek/pořadníku/kapacit je pokrytý včetně nepřímých cest, staré záznamy nevytvářejí inbox.

### 3. Banka a všechny e-maily

Cíl: problémy přicházejí bez návštěvy nastavení a nevytvářejí falešná tvrzení.

- Přidat servisní monitor bankovních stavů sdílející současný BankSync transport; oddělit od operation-intent recovery. Přidat registraci scheduleru v kanonickém SQL/runtime konfiguraci a ověřit auth, lease, timeout i bounded dávky.
- Z reduktorů e-mailů zachytit skutečné nové problémové přechody; pro časové prahy doplnit bounded servisní evaluator. Neprovádět doménový read monitoring přes veřejné klienty, nevytvářet druhý mail sender.
- Baseline a activation generation zavést pro oba monitory. Při každé nové epizodě uložit skutečný čas, bezpečnou třídu důvodu a dopad, bez provider credentials.
- Ověření: SQL + relevantní Deno testy sdíleného klienta/nového workeru s lokálními pevnými transportními odpověďmi; token versus timeout, suspend, stale health, recovery, starý problém, opožděný webhook, complaint a suppression, plánované zprávy a všechna `message_kind`.
- Výstup: přetrvávající nová porucha vytvoří jednu položku a zotavení ji aktualizuje; žádný únik přes sdílený účet či security mail.

### 4. Flutter zvoneček a navigace

Cíl: kompletní minimalistický tok ve stávající administraci na webu i mobilu.

- Přidat modely/service/controller a panel do `lib/components/notification_center/`; mount v existujícím společném chrome ověřeném UI agentem, ne v každém tabu.
- Badge načítat po přihlášení/změně organizace, při návratu aplikace a v popředí nejvýše jednou za 60 sekund; otevřený panel obnovovat po 15 sekundách. Bez nového Realtime/public sync subsystému, background poll po logout/dispose zastavit. Poll odpověď nesmí přepsat novější potvrzený stav.
- Otevření přes serverový snapshot+ack, expanze seskupených řádků, stránkování, mute přes menu akce, bezpečné deep links na existující objednávky/pořadník/e-mail historii/banku podle oprávnění. Pouhé otevření skupiny už znovu neackuje nové události.
- Lokalizace přes `*_strings.dart` a všechny podporované překlady; žádné hardcoded UI kódy chyb. Needitovat generovaný router ručně.
- Samostatný medium UI/UX agent již dodal návrh výše; během implementace mu přidělit i kontrolu vykresleného výsledku. Implementátor nesmí dodávat odlišný layout bez aktualizace plánu.
- Ověření: cílený analyzer změněných souborů, existující Flutter test root s novými controller/widget scénáři, jeden izolovaný headless lokální end-to-end tok podle `festapp-local-e2e` (backend s fixture tenanty). Desktop i mobil, klávesnice, dlouhé názvy, prázdno a chyba. Nezakládat druhý vývojový server ani rušit uživatelův prohlížeč.
- Výstup: skutečná událost rozsvítí tečku, otevření ji zhasne na dvou zařízeních, nová souběžná událost nezmizí a skupina se rozbalí uvnitř panelu.

### 5. Integrační dokončení a připravenost k aktivaci

Cíl: připravená lokální funkce s ověřenou aktivací od čisté hranice.

- Udržovat přehled skutečně připojených producentů a jednoho canonical vlastníka; odstranit případné dočasné mock adaptéry, fixture přepínače a duplicitní emit místa. Activation zůstává legitimní tenant release hranicí, není dočasným fallbackem.
- Doplnit doménové README pouze o kontrakty, pořadí zámků, ACL a recovery. Archivovat tento plán až po reálném dokončení, ponechat případné nenaplněné provozní kroky explicitní.
- Jednou spustit finální dotčené DB/Deno/Flutter kontroly a lokální integrační tok. Nepřidávat plný release build jen kvůli plánu nebo před autorizovaným vydáním.
- Výstup: žádný schválený typ události nechybí, plán obsahuje skutečné výsledky kontrol a produkční stav je výslovně dosud neaktivovaný.

## Ověřování a příkazy

Implementace používá standard. Související změny se ověřují společně; výsledky níže rozlišují provedené lokální kontroly a nenaplněné provozní kroky.

- Izolovaná DB dle `CONTRIBUTING.md`: existující lokální instance, případně `./automation/bootstrap_local_db.sh` pouze pro vyhrazený lokální testovací volume. Nikdy produkční DATABASE_URL.
- Přidat `database/tests/notification_center/` s permissions, activation, replay, grouping, read cursor, retention a source transition scénáři. Spouštět `node web_client/scripts/run_db_tests.js database/tests/notification_center/` s lokální `DATABASE_URL`; ověřit nenulový počet skutečně vybraných testů. Dvouspojové concurrency testy vést skutečným Postgres runnerem po vzoru `database/tests/eshop/orders/cancellation_concurrency.test.mjs`.
- Přibrat dotčené existující testy `database/tests/eshop_orders/`, `database/tests/eshop/orders/`, `database/tests/emails/`, `database/tests/eshop/transactions/bank_sync_*`. Vybrat konkrétní soubory podle změněných doménových funkcí, ne celou nesouvisející sadu.
- Servisní TypeScript: cílené stávající Deno příkazy dle `docs/backend/edge_functions.md`, včetně auth a transport simulace skutečným sdíleným klientem. Nepotřebuje živou banku ani placené odesílání.
- Flutter: před úlohou zkontrolovat běžící Flutter procesy, maximálně jedna úloha na workstation, testy s `--concurrency=1`. Testy přidat do existujícího discoverable root podle `CONTRIBUTING.md`; spustit konkrétní root, ne pomocný import. Cíleně `fvm dart analyze` změněné soubory.
- Pro UI ověření headless izolovaná browser session, snapshoty před screenshoty, žádný produkční testovací zákazník. Scénáře dvou rolí, dvou zařízení, cizího tenantu a odebrání oprávnění mají skutečný backend, ne jen widget mock.

## Rollout, kompatibilita a rollback

Plán neautorizuje implementaci, commit/push, migraci ani deployment. Po samostatném zadání implementace lze provést lokální vlny; produkční aktivace zůstává zvlášť autorizovaným krokem pro jediný určený tenant.

Po autorizaci vydání: kompatibilní DB expanze s vypnutou aktivací, servisní monitory/projektor, Flutter klient, ověřit migrace a scheduler i bez návštěvy administrace, pak atomicky inicializovat baseline a aktivovat přesnou organizaci. Při inicializaci serializovat zdroje/aktivaci tak, aby událost na hranici nebyla ztracena ani zpětně doplněna. Nejprve nainstalované producenty musí tento activation gate respektovat.

Starší klient nadále objednává přes stejný server a inbox nemusí znát. Nepodporovaný nový klient před DB vrstvou funkci bezpečně skryje jedním detekovaným capability stavem, nikoli náhradním úložištěm. Rollback skryje bell a pozastaví projektor/monitory při zachování dat a původního activation watermarku; definovaná pauza sběru netvoří historii po resume. Běžné objednávky, bankovní import a e-mail fronta pokračují. Žádné odstraňování obchodních dat nebo návrat starého bankovního importu.

Rutinní vydání/monitorování po autorizaci delegovat levnějšímu agentovi dle AGENTS.md s přesným SHA, tenantem a gates. Nasazení webu lokálně `automation/deploy_direct.sh`, bez GitHub Deploy workflow, není-li výslovně požadován. Pro UI/UX během implementace použít samostatného medium agenta dle uživatelova zadání.

## Ledger zachování a odstranění

| Objekt/cesta | Rozhodnutí a důkaz |
|---|---|
| `public.log_notifications`, existující notify/push/novinky | Zachovat, odlišný existující účel; žádný přesměrovaný consumer ani druhé doručování téže push zprávy |
| `public.email_messages`, delivery events a sender | Zachovat jako autoritu; nové centrum je pouze spotřebitel bezpečných přechodů |
| BankSync a payment matching | Zachovat autority, žádný druhý payment engine nebo znovuzapnutý polling banky |
| Mock inboxy / duplicitní emit z wrapperů a UI | Při finální implementaci odstranit; hledání callsites a integrační replay test prokazují jedno emit místo |
| Feature activation a source baseline | Zachovat jako vědomou provozní hranici; bez historického backfill jobu |

## Předpoklady, reziduální rizika a hotovo

- Potvrzené: samostatný osobní přehled bez společného issue workflow, nové události, všechny druhy e-mailů v mezích oprávnění, medium UI/UX agent.
- Návrhové výchozí hodnoty: denní skupiny, 90denní retence, 85% reset hranice, intervaly a timeouty výše. Implementátor je smí podle doloženého provozního kontraktu upřesnit v tomto plánu bez rozšíření rozsahu.
- Ověřit ve vlně 1 konkrétní owner pro omezené typy/blueprint a skutečná čtecí oprávnění. Nesmí se nahradit aproximací prodejnosti ani pozastavit celý plán kvůli novému obecnému capacity modelu.
- Zjistit skutečný BankSync interval, dostupné status API rate limity a podporovanou scheduler registraci před nasazením monitoru. Při nedostupnosti externího kontraktu dokončit lokální integraci s pevnými odpověďmi, přesně uvést neověřený bod; netvrdit živé monitorování.
- Fanout může být velký, proto bounded dávky, indexy tenant/příjemce/sekvence a lease; žádné skenování všech objednávek při každém pollu.
- Nejrizikovější jsou ACL sdílených účtů/security e-mailů, commit-order read watermark a nepřímé expirace. Mají konkrétní testy ve vlnách, ne až neplánovaný audit na konci.
- Hotovo lokálně: všechny události mají vlastníka a bezpečné doručení, replay/souběh nepřidává duplicitní ani ztracenou pozornost, read se synchronizuje mezi zařízeními, UI odpovídá dohodě, nenulová cílená sada testů projde.
- Hotovo provozně: až zvlášť autorizované nasazení a ověřená aktivace jednoho tenantu. Lokální implementace sama tento stav neprokazuje.


## Implementační evidence 2026-10-23

### Doložená upřesnění kontraktu

- Skutečná čtecí práva objednávek/kapacit jsou `occasion_users.is_editor_order_view`, včetně aktuálního tenant scope; obecné členství ani administrátor organizace automaticky nezpřístupní objednávky bez tohoto práva. E-maily mají vlastní reporting pravidlo s tenant administrátorem. Bankovní administrátor má pouze vlastní oprávněný účet a propojenou jednotku.
- Časová zóna organizačního seskupení je při aktivaci zaznamenaná IANA zóna, výchozí `Europe/Prague` podle `TimeHelper.setTimeZoneLocation`. Nepoužívá se časová zóna zařízení.
- Skutečně vynucovaný produktový limit je `products.maximum` v `materialize_ticket_products_internal_v1`. `product_types.maximum` se v materializátoru nevynucuje, proto z něj nevzniká vymyšlená druhá kapacita. Blueprint používá vlastní aktuální sedadla; inventory svůj fyzický/komerční limit po kontextu, stejně jako allocator.
- První aktivaci serializuje organizační advisory gate i v okamžiku, kdy aktivační řádek ještě neexistuje. Doručení a open mají společný osobní row lock. První activation timestamp zůstává neměnný; samostatná hranice aktuálního collection okna vyloučí opožděné provider fakty z pauzy. Recipient snapshot má vlastní eligibility revizi pozornosti: nový skutečný dopad znovu zachytí současné příjemce a současného ověřeného autora; původní potlačení vlastní změny neschová pozdější automatickou poruchu. Projektor má transakční lease a limit zpracovaných příjemců, nikoli pouze limit událostí; mute/revokace dostanou zpracovanou revizi bez pozdějšího replay.
- UI doplnilo `get_notification_center_updates(organization,snapshot,ids[])`, maximálně 200 ID na request, pro aktualizaci už načtených řádků bez ack a bez změny pořadí. Vynechaná ID po revokaci zmizí, oprávnění se znovu ověřují.
- E-mailová původní splatnost se zachytí před přepisováním retry target time; zdržení se proto neodsouvá každým retry. Hromadné incidenty se seskupují podle stejné příčiny, povoleného scope a místního dne, stále s jednotlivým autorizovaným detailem zprávy.
- Bankovní dopad organizátorům vychází z explicitního účtu formuláře nebo skutečného platebního účtu objednávek, včetně aliasů. Pouhé propojení účtu na jednotku se nevydává za skutečný dopad na všechny její akce.
- Lokální BankSync zdroj (`src/cloudflare.ts:apiMinIntervalS`, `wrangler.example.toml`) má výchozí minimum 30 sekund a minutový scheduler. Zvolený třicetiminutový stale práh je konzervativní; skutečná produkční konfigurace intervalu a API rate limit ještě nejsou provozně ověřené. Health refresh má čtyři účty na dávku, 20s transport timeout, dvouminutovou lease a 5/10min interval/backoff.

### Artefakty a vlastnictví

Kanonické SQL je v `database/functions/notification_center/`, souhrnný kontrakt a ledger producentů v jeho README. Nová migrace je `supabase/migrations/20261023210000_organization_notification_center.sql`, její explicitní zdrojový manifest a parity kontrola v `automation/assemble-notification-center-migration.py`. Předchází jí souběžná ticket-batches migrace `20261023200000`; její vlastník odkládá notification hooky do této následující migrace. Žádná dřívější migrace se nedoplňuje závislostí na dosud neexistujících helperech.

Flutter vlastní společný bell/panel, šest překladů, query selection `orderId`/`messageId` ve stávajících detailech a osobní controller. Samostatný medium UI agent implementoval a ověřuje vykreslení. Osobní obsah se nepřidal do veřejného sync katalogu ani sdílené cache.

### Dosavadní skutečné kontroly

- Úspěšné atomické načtení celé forward migrace v dedikované lokální DB `127.0.0.1:55432`, bez produkčních dotazů a bez přestavění cizích testovacích tenantů. Další finalizované helpery se načítají cíleně a kontroluje se deterministická parity migrace.
- Discoverable nové SQL soubory `contract_test`, `producers_test`, `email_sources_test`, `bank_sources_test`, `projection_lifecycle_test`: nenulové discovery. Pokrývají ACL, dva tenanty/akce, replay/rollback, skutečné objednávky a částečná přijetí, scheduler expiraci, všech 17 podporovaných druhů e-mailů, suppression/complaint/due time, bankovní lease/token/transport/stale/suspend/recovery, stránkování, recipient snapshot, bounded fanout a retenci.
- Čtyři skutečné Node/Postgres testy v samostatných transakcích, tři s dvěma spojeními: delivery versus open v obou pořadích, souběžné open, první aktivace před vznikem řádku a změna ověřeného autora při nové revizi kapacitního problému. Skutečné blokování se potvrzuje přes `pg_blocking_pids`, nejde o simulaci timestampů.
- Dotčené stávající SQL: form capacity, waitlist lifecycle, Fakturoid recovery, canonical email queue a cancellation outcomes prošly. Konečná cílená dávka po frozen pořadí 200000 -> 210000 má 11 skutečně vybraných SQL souborů včetně aktualizovaného canonical mutation source parity kontraktu, všechny prošly.
- Deno: 52 skutečně provedených testů, včetně HTTP vstupů, nového workeru, skutečného sdíleného BankSync transportu s pevnými fetch odpověďmi a izolace credentials. Vnější banka ani placené e-maily se nevolaly.
- Cílený Flutter analyzer: bez chyb a varování, pouze existující/style infos. Finální discoverable Flutter dávka: 25 testů prošlo v normálním i obráceném pořadí (`FESTAPP_FIXTURE_ORDER=reverse`), vždy `--concurrency=1 --no-pub`: 12 nových notification scénářů a 13 souvisejících occasion navigation bar scénářů. Zahrnuje lokalizované důvody, bulk e-mailové skupiny, počty míst a absenci nefunkčního Detail u kapacit. Cílený analyzer skončil exit 0, bez chyb a varování (40 style/deprecation infos). Skutečný UI tok je zaznamenaný níže.
- Runtime test discovery/coverage manifest prošel (2 testy), router proof-route/idempotence/drift sada prošla (3 testy); canonical operation source kontrakt a assembler parity prošly.

### Dosud neprovedené provozní kroky

Produkční migrace, nasazení Function/runtime proof route a omezených credentials, ověření skutečné registrace obou schedulerů bez návštěvy administrace, Flutter/web vydání, atomický baseline a aktivace přesně určené organizace. Stejně tak nebyl proveden commit ani push. Žádný z těchto kroků tento implementační prompt neautorizuje. Před aktivací ověřit skutečnou BankSync konfiguraci a rate limit, načíst aktuální potvrzený status všech připojení do místního baseline přes stávající autentizovaný transport (live freshness a interpretace původní bankovní failure epizody nejsou tímto lokálním testem prokázané), ověřit origin machine health jobu a shodu main/tenant release podle samostatného zadání. Migrace 210000 nyní navazuje na současný draft ticket-batches 200000; samostatné produkční vydání musí tuto závislost výslovně vyřešit, nikoli nepozorovaně aktivovat cizí rozpracovanou funkci.


### Skutečný lokální UI tok

Samostatný medium UI agent použil vlastní full-stack tenanty na 57421/57422 a jediný Flutter server 57481, se třemi izolovanými headless browser sessions. Produkční služby byly blokované, cron vypnutý, testovací objednávky nevytvořily žádnou odchozí e-mailovou zprávu. Auth/REST, skutečný checkout, SQL emit a osobní projekce nebyly nahrazeny mock inboxem.

- Stejný administrátor ve dvou oddělených desktop/mobile sessions: snapshot 7; skutečná další objednávka rozsvítila inline nové upozornění v obou panelech po 15s, bez přesunu či změny původních rozbalených řádků. Explicitní obnovení na desktopu vzalo snapshot 8 a potvrdilo přečtení i pro další poll mobilu; mobil zachoval původní rozbalený obsah do vlastního obnovení.
- Admin a organizátor četli jen své dostupné položky, skutečný cizí tenant vracel 403. Čerstvý oprávněný read-only uživatel měl skutečně prázdnou historii, bez historického recipient replay.
- Skutečné ztlumení v mobilním nastavení: další reálný checkout se emitoval/projektoval, osobní stav zůstal 8/8. Odtlumení nevytvořilo replay.
- Detail konkrétní objednávky otevřel stávající order-history dialog se správným symbolem a ticketem přes `?orderId=13`; zavření spotřebovalo jen cílový query parametr. Fokus po zavření panelu se v DOM vrátil na skutečné tlačítko Upozornění.
- Vykreslený desktop/mobile, 320/719 px fullscreen a 720 px pravý 440px panel byly zkontrolovány. Reálná kontrola odhalila a opravila kontrast ikon hlavičky, lokální formát data a přetečení dlouhého názvu ve společném breadcrumbu. Pro 200% text běží cílené widget scénáře.
- Simulovaná síťová chyba konkrétního open RPC (explicitně jediná mockovaná transportní hranice) zobrazila bezpečnou chybu a Retry; úspěšný retry šel na skutečný backend a obnovil obsah.
- Omezení důkazu: browser input driver nedoručoval nativní Escape ani do instrumentovaného document keydown listeneru, takže browser Escape není tvrzený jako ověřený. Escape je pokrytý skutečným Flutter widget testem; close/focus a přímý detail jsou ověřené i ve skutečném browseru.

Vlastní Flutter server i všechny tři browser sessions byly po scénářích ukončeny. Poslední krátký analyzer/widget běh po nalezených UI opravách je dokončený, výsledky výše. Žádný release build není součástí tohoto úkolu.

Lokální obrazové doklady: [720 px panel](/tmp/festapp-notification-720-final.png), [320 px mobil](/tmp/festapp-notification-mobile-320.png), [nová událost](/tmp/festapp-notification-new-arrival.png), [konkrétní detail](/tmp/festapp-notification-order-detail.png). Jde o syntetické lokální účty a data.


### Zbývající omezení ověření

Normální architecture guard (`cd packages/festapp_core && fvm dart run tool/check_architecture.dart /Users/miakh/source/festapp`) byl skutečně spuštěn. Blokují jej nesouvisející rozpracované registrace: nezařazené Flutter roots `occasion_setup_settings_test.dart`, `occasion_setup_appearance_panel_test.dart`, `occasion_setup_story_shell_test.dart`, `occasion_setup_ticket_gallery_test.dart`, `client_command_identity_test.dart` a chybějící klasifikovaný `ticket_background_image_cases.dart`. Vlastní notification cases jsou zapsané v existujícím shared_default_3 registry; cizí soubory ani jejich klasifikace tento úkol nepřepisuje. Tento globální gate tedy není vykazovaný jako zelený.

Současné výsledky tvoří lokální implementační dokončení, nikoli povolení k publikaci. Tento záznam a prompt zůstávají u neuzavřených produkčních gates; archivovat až s jejich výslovným provozním vypořádáním. Commit, push, produkční migrace, deployment a aktivace nebyly v tomto úkolu provedeny.


### Rozhodnutí uživatele: dočasný UI preview

Po lokálním dokončení uživatel požádal o dočasný feature flag pouze pro UI:
zvoneček zatím vidí účet `bujnmi` (`bujnmi@gmail.com`), po vyzkoušení všichni
jinak oprávnění uživatelé. Řídí jej
`NotificationCenterRollout.visibleToEveryone = false`; přepnutí na `true`
se projeví v následujícím sestavení. Skryté účty nezačínají klientský polling.
Na výslovné upřesnění uživatele se nemění RPC, oprávnění, recipient snapshoty
ani serverové doručování. Není to bezpečnostní allowlist ani nový aktivační gate.
