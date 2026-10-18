# Skenování ve web klientovi jako výchozí cesta

Datum: 2026-10-18
Stav: Revize 3 lokálně implementována; důkazy a zbývající gates viz [implementační záznam](web-scanner-implementation-2026-10-18.md); produkční kroky nejsou provedené
Verification: standard pro implementaci (oprávnění, souběh a migrace); při tvorbě plánu bez testů

Součástí tohoto plánu je závazný [prováděcí kontrakt](web-scanner-contract-2026-10-18.md): přesné routy, moduly, datové modely, API, zámky, stavové přechody, životní cyklus a 18 akceptačních scénářů. Pro návrh obrazovek slouží [interaktivní HTML](web-scanner-preview-2026-10-18.html); jde o smyšlenou demonstraci, nikoli implementaci scanneru.

## Výsledek a rozsah

Celá obsluha skenování vstupenek bude dostupná v existujícím vanilla JS/HTML/CSS web klientovi. Web bude výchozí cíl odkazů a tlačítek, bez načítání Flutter runtime. Obsluha na mobilu i počítači uvidí jednoznačný výsledek, potřebné produkty a zvolená pole. Před akcí připraví zařízení pro výpadek připojení; během výpadku se potvrzení trvale uloží a po návratu sítě bezpečně vypořádají.

Součástí jsou kamera, ruční zadání, hledání vstupenek a účastníků podle současných oprávnění, USB/Bluetooth čtečka v režimu klávesnice, detail, potvrzení vstupu, souhrnné počty, historie, synchronizace a konfigurace. Přenést také existující kontrolu účasti na programu (`CheckPage`) a QR vstup recepce jako oddělené režimy stejného webového skenovacího vstupu. Kontrola účasti dnes ověřuje přihlášení na program, nezapisuje fyzický příchod.

Reset hesla a recepční přihlášení zůstanou pouze online pod vlastní existující autorizační politikou. Přenáší se jejich dostupnost ze skenovacího toku, nikoli celá administrace, recepce či přihlašovací systém. Žádné automatické proplácení, změna plateb, dílčí čerpání produktů, počítání odchodů ani obsazenosti sálu se tímto plánem nezavádí. Nativní mobilní aplikace zůstává podporovaným klientem stávajícího backendového kontraktu.

Původní zadání se týkalo plánu. Následný execution prompt autorizoval lokální implementaci a ověření, nikoli produkční migraci, commit, push nebo nasazení. Rozsáhlé existující změny pracovního stromu nejsou součástí úklidu tohoto úkolu. Výchozí bod průzkumu: větev `feat/occasion-setup-wizard-20261007`; nejde o tvrzení o produkčním stavu.

## Ověřený současný stav

| Zjištění z repozitáře | Důkaz | Důsledek |
|---|---|---|
| `/scan` předává JS router do Flutteru | `web_client/src/services/router_service.js`, `flutterRoutes`, `handleInitialLoad` | Nestačí přidat komponentu; změnit klasifikaci rout, start i návrat přes historii. |
| Offline navigace jiné než `/` a `/form/` standardně míří do Flutteru | `automation/generate_pwa_service_worker.mjs`, `cachedNavigationTarget` | Doplnit existující generátor a manifest; nevytvářet další service worker. |
| Start JS klienta může čekat na RightsService a síť | `web_client/src/main.js`, `startup/initialize_core_services.js` | Offline scanner musí mít vlastní lokální start před nepovinnými síťovými závislostmi. |
| Lookup a potvrzení jsou oddělené | `lib/components/scan/scan_page.dart`, `setupNewId`, `_confirmTicket`; `DbTickets.scanTicket/updateTicketToUsed` | Samotné přečtení QR neznamená přijetí člověka. |
| Potvrzuje se celá vstupenka, nikoli jednotlivé produkty | `database/functions/eshop_orders/update_ticket_to_used.sql`; `scan_result_display.dart` | Nastavení produktů bude projekce zobrazení, nikoli nový skladový nebo výdejový model. |
| Potvrzovací SQL zamyká ticket, odmítá used/storno, nemá idempotency key | `update_ticket_to_used.sql`, `FOR UPDATE` | Zachovat serializaci, přidat účtenku operace pro retry po ztracené odpovědi. |
| Lookup vrací celý order a má výjimku pro skrytí cen konkrétní akce | `database/functions/eshop_orders/scan_ticket.sql` | Nová projekce musí filtrovat citlivá data na serveru; nepřenášet celý order do offline balíčku. |
| Některá dynamická pole jsou pevně podle ID | `lib/components/scan/scan_field_mappings.dart`, `specificFieldMappings` | Nahradit uloženými odkazy na skutečná pole formulářů, oddělit údaje objednávky a vstupenky. |
| Export pro hledání není offline protokol | `get_all_tickets_for_scan.sql` vrací seznam s order.data a omezuje počet/velikost | Nevydávat tento seznam za konzistentní offline snapshot. |
| Existuje oprávnění sdíleným scan kódem a ochrana proti zneužití | `get_occasion_by_scan_code.sql`, `database/functions/abuse/scan.sql` | Nové endpointy zachovají admission, limity a tenant/occasion scope. |
| Existují další skenovací vstupy | `check_page.dart`; `reception/login_qr_scanner_page.dart`; odkazy v schedule a `TicketCodeHelper` | Každý musí mít určenou webovou cestu a příslušná oprávnění. |
| `browser_storage.js` umí tiše spadnout do paměti | `web_client/src/services/browser_storage.js` | Pro outbox nepoužít; bez trvalého zápisu se nesmí ukázat offline úspěch. |
| Storno zamyká rodičovský scope a objednávku před ticketem, staré použití nejprve ticket | `storno_tickets_client_sync_v1.sql`, `check_order_is_mutable.sql`, `update_ticket_to_used{,_ws}.sql` | Změna musí sjednotit pořadí; zachování starého ticket-first wrapperu by ponechalo možnost deadlocku. |
| Vrácení na nepoužito aktualizuje timestamp a nastaví sent | `update_ticket_to_unused_ws.sql` | Historický receipt je minulá událost, ne důkaz současného used. Starý offline snapshot nesmí potvrdit nově otevřený cyklus. |
| Recepční QR skutečně přihlašuje držitele, nejde o ověření vstupu obsluhou | `users/views/login_page.dart`, `_loginWithReceptionCredential`; `festapp_core/src/forms/login_qr_payload.dart` | Samostatná přihlašovací hranice; nesmí nechtěně přepnout účet pracovníka u vstupu. |

Průzkum je zdrojový. Produkční data, aktivní schéma a konkrétní fyzické telefony nebyly kontrolovány. UX konzultaci dokončil subagent `gpt-6-astra`, reasoning `medium`, s dovednostmi `ui-ux-pro-max` a `ux-designer`; jeho návrh je zapracovaný níže. Lokální design-system vyhledávání nabídlo marketingový hero layout, který byl jako nevhodný odmítnut. Použitá konkrétní doporučení vycházejí z existujícího theme a scanner/offline referencí; užší UX hledání potvrdilo viditelný a nezakrytý fokus.

## Rozhodnutí a předpoklady

- **D1 - jedna webová implementace:** `web_client/src/components/scan/` vlastní UI; SQL vlastní oprávnění a přechod ticketu. Nevzniká React aplikace ani druhý synchronizační systém pro celou Festapp.
- **D2 - produkty:** správce nastaví povolené produkty/typy a jejich pořadí pro zobrazení. Obsluha může z povolené množiny zobrazení zúžit. Výslovné režimy `all`, `selected`, `none`; prázdný výběr není nejasné „vše“. Nové produkty se automaticky objeví jen v režimu `all`. Skrytí produktu nemění platnost ani rozsah potvrzení vstupenky.
- **D3 - pole:** správce nastaví povolená a výchozí viditelná pole; obsluha může měnit pořadí a viditelnost pouze v povoleném rozsahu. Bezpečnostní stav, původ ověření a primární akci nelze skrýt. UI nastavení nikdy samo neuděluje přístup k datům.
- **D4 - výchozí potvrzení:** zůstává vědomé tlačítko „Potvrdit vstup“. Automatické použití po přečtení QR se nezavádí. Nezaplacená/objednaná vstupenka vyžaduje výrazné zvláštní potvrzení podle serverové politiky; nesmí působit jako zaplacená.
- **D5 - výpadek:** offline přijetí je lokální rozhodnutí podle posledního připraveného stavu. Finální autoritu má server. Dvě odpojená zařízení mohou přijmout stejný QR; software to bez spojení nemůže globálně vyloučit.
- **D6 - celý skenovací tok:** kontrola programu a recepční QR mají vlastní doménové adaptéry; nikdy nevolají ticket confirm omylem. Reset hesla a přihlášení nelze zařadit do outboxu.
- **A1 - „kolik“:** nedokončenou větu interpretujeme jako přehled přijatých/celkem, zbývajících vstupenek a čekajících záznamů. Nejde o počet lidí aktuálně v sále. Při jiném záměru změnit pouze metriky, ne admission model.
- **A2 - offline rozsah:** úplné offline přijetí se týká vstupenek. Kontrola programu může offline ověřovat jen připravený seznam s časem snapshotu; žádné nové přihlášení do programu. Recepční přihlášení zůstává online.
- **A3 - rozumná velikost:** skutečný maximální počet ticketů zjistit při implementaci z autorizovaného testovacího datasetu. Výchozí výkonový scénář je 10 000 vstupenek a 1 000 čekajících operací; větší potřebný rozsah přizpůsobí stránkování a limity, nikoli tiché zkrácení.

Pro plán není blokátor. Nasazení vyžaduje samostatné zadání a konkrétní tenant. Před migrací znovu porovnat současné bezpečnostní plány ze dne 2026-10-18, zejména autoritu resetu hesla; nevytvářet jejich alternativu.

## UX návrh

### Hlavní pracovní plocha

Mobil: kompaktní hlavička akce/stanoviště, jeden stavový řádek s připojením a základním počtem; pending a konflikty jen při nenulové hodnotě. Podrobné počty patří pod rozbalovací „Přehled“. Navigace „Skenovat / Historie / Offline“; hledání podle jména patří do režimu „Ručně“. Nastavení má označené tlačítko v hlavičce. Načtený výsledek nahradí kameru a jediná dominantní akce je před potvrzením „Potvrdit vstup“, po dokončení „Další vstupenka“. Desktop má vstup vlevo, detail vpravo a stejné pořadí informací.

Astra Medium v revizi 3 zpřesnila prioritu scan -> výsledek -> akce. Pro běžné údaje na 390 × 844 px musí být bez scrollu vidět stav, jméno, první produkt a CTA. Na 320 px a při 200% zoom musí být všechno dosažitelné svislým posuvem, bez překrytí nebo ztráty fokusu. Implementace použije existující Futura, ThemeService a tokeny v obou motivech; HTML demo je pouze ilustrace a jeho CSS se nepřebírá jako nový design systém.

Výsledek vede stavem a akcí, potom jménem/identifikátorem, relevantními produkty, místem/sektorem a konfigurovanými poli. Ceny, interní poznámky a osobní údaje jen při povoleném rozsahu. Delší detail se rozbalí; tlačítko potvrzení a stav sítě nesmí odscrollovat bez náhrady. Text a ikona vždy doprovázejí barvu, zvuk a vibrace jsou volitelné. Použít existující `theme_config.css`, ThemeService, typografii a lokalizaci, nikoli nový globální design systém.

| Situace | Hlavní sdělení | Další akce |
|---|---|---|
| Platná, dosud nepoužitá | „Vstupenka je platná“ | Potvrdit vstup |
| Potvrzeno serverem touto operací | „Vstup potvrzen“ | Další vstupenka |
| Zaplacení není potvrzené | „Vstupenka není zaplacená“ + příslušný doplatek | Zvláštní potvrzení, pouze pokud povoluje server |
| Použita dříve | „Vstupenka už byla použita“ + autoritativní čas, je-li dostupný | Detail; bez dalšího použití |
| Storno/neplatná/čekací listina | „Vstup nelze potvrdit“ + důvod | Další vstupenka |
| Není v připravených datech | „V offline datech nenalezena“ | Zkusit online/ověřit u vedoucího; neoznačit za definitivně neplatnou |
| Trvale zapsáno offline | „Vstup uložen v zařízení - čeká na odeslání“ | Další vstupenka; počet čekajících |
| Timeout po odeslání | „Ověřujeme výsledek potvrzení“ | Ověřit tutéž operaci; nezakládat nové potvrzení |
| Kolize při sync | „Vstup potvrdilo také jiné zařízení“ | Zařadit k vyřešení; nemaže lokální historii |
| Úložiště nefunguje | „Záznam nelze bezpečně uložit“ | Povolit čtení, blokovat potvrzení i online; nabídnout jiné připravené zařízení |
| Kamera nepovolena/nedostupná | Konkrétní důvod | Ruční vstup, hledání nebo externí čtečka |

„Další vstupenka“ zruší deduplikaci až vědomým ukončením výsledku; stejný QR ve více snímcích nevytváří další akce. Asynchronní odpověď staršího scanu nesmí přepsat aktuální výsledek. Režim ručního hledání respektuje dosavadní serverová oprávnění; vypnutí hledání nesmí jít obejít voláním API.

Kamera startuje uživatelskou akcí, preferuje zadní kameru a nabízí svítilnu/přepnutí jen podle schopností zařízení. Po přechodu na další ticket potlačit poslední symbol do pozorované absence v obnoveném streamu; nabídnout vědomé „Načíst stejný kód znovu“, pokud absence nejde zjistit. Odblokování nikdy samo nepotvrzuje. USB čtečka má vlastní viditelně fokusované pole se stavem „Čtečka připravena“; Enter pouze načte kód, nikdy nepotvrdí vstup. Nespoléhat na odhad rychlosti psaní ani neodchytávat klávesy při editaci nastavení. Během neuzavřeného výsledku je příjem viditelně pozastaven.

Pokud ticket neobsahuje žádný z vybraných produktů, ukázat „Pro toto zobrazení nemá vstupenka žádné produkty“; není to důkaz neplatnosti. Ostatní produkty lze shrnout počtem jen v rozsahu povoleném serverovou projekcí. Dotykové akce cílit na alespoň 48 CSS px. Pořadí produktů/polí v prvním vydání měnit tlačítky nahoru/dolů; drag-and-drop framework není potřeba. Konflikty a další důležité chyby samy nezmizí.

### Nastavení a náhled

Webová stránka nastavení má části „Produkty“, „Údaje ve výsledku“, „Chování skeneru“, „Offline provoz“. U produktů hledání, skupiny podle typu, explicitní zobrazení nových produktů, řazení a náhled reálného ticketu v rámci oprávnění. U polí dostupné položky ze všech příslušných formulářů s jejich původem, vlastní popisek, řazení, skrýt prázdné a náhled. Rozlišit objednávkové odpovědi a odpovědi konkrétní vstupenky, neslévat stejně nazvaná pole z různých formulářů.

Povinné bezpečnostní údaje stojí mimo konfigurovatelný seznam. Pole odstraněné z formuláře zobrazit správci jako chybějící odkaz; obsluze nepodsouvat jinou hodnotu. Výchozí konfiguraci migrovat z aktuálního zobrazení, včetně `can_scan_manually`, `show_hidden_note`, relevantních ID a omezení cen, jen do odpovídajících akcí. Nedělat z citlivé výjimky globální oprávnění.

### Počty

Zobrazit „Použité 248 / 500“, „Zbývá 252“ a odděleně „V zařízení čeká 12“. Použité = unikátní ticket v autoritativním stavu used, včetně historického/admin used; „potvrzení skenerem“ je samostatná auditní metrika. Celkem = serverem definovaná množina oprávněných vstupenek v daném scope. Nezahrnovat storno a waitlisted; podmíněně přijatelné nezaplacené uvést zvlášť. Přesnou definici denominatoru vrací server s metrikou. Součet produktů ani počet scanů není počet osob. Při filtraci zobrazovaných produktů se celkové admission počty nemění.

Offline ukázat „Poslední stav serveru v 18:42“ a lokální pending zvlášť; lokální odhad nesmí předstírat globální stav. Retry nesmí zvýšit počty. U programové kontroly ukazovat počet přihlášených, nikoli fyzicky příchozích. Bez evidence odchodů nikdy neuvádět „uvnitř“.

### Příprava zařízení a synchronizace

Jedna akce „Připravit na výpadek“ ověří oprávnění, trvalé úložiště, úplnost dat, lokální QR dekodér a přítomnost potřebných shell assets. Skutečný cold start po zavření bez sítě je samostatný ověřovací průchod, nikoli slib odvozený z kontroly cache. Výsledek uvádí akci, počet ticketů, čas přípravy a platnost oprávnění. Částečně stažený snapshot nezpřístupní jako hotový. Při změně konfigurace se nejdřív dokončí nový balíček, pak atomicky přepne aktivní verze.

Detail synchronizace obsahuje čekající, odesílané, potvrzené a k vyřešení, včetně počtu konfliktů. Průběh například „Odesílám 8 z 12 potvrzení“, po dokončení samostatné počty přijatých a konfliktních. Trvalý banner ukazuje výpadek/obnovování; stav nesmí být jen krátký toast. Offline výslovně uvést „Bez internetu se změny ostatních zařízení neprojeví.“ Po návratu sítě běží automatické obnovení a existuje tlačítko „Odeslat znovu“. Při řízené navigaci ukázat pending a možnost pokračovat později. `beforeunload` je jen best effort; kill mobilního prohlížeče nemusí jít zachytit. Nelze slíbit běh po zavření prohlížeče. Mazání zařízení/odhlášení se neprovede tiše přes pending frontu.

## Cílová architektura a kontrakty

**Serverové rozhraní = Supabase RPC SQL funkce v `public`, volané přes `supabase.rpc(...)`.** Nevzniká nový REST server ani nová Edge Function pro skenování. Výraz API zde a v prováděcím kontraktu označuje výhradně toto RPC rozhraní. Recepční přihlášení jen zachovává svůj existující `exchange-login-qr` tok.

### Konfigurace a projekce

Přidat kanonickou occasion-scoped konfiguraci v `database/functions/scanning/` s verzí/revizí, povolenými produkty, poli, manual search, citlivými scopes a offline politikou. Preferovat samostatnou tabulku `public.scanner_settings` s autorizovanými RPC `get_scanner_settings` a `update_scanner_settings`; zabránit přímému zápisu a použít compare-and-swap revizi pro souběžné editace. Lokální preference jsou podmnožina serverového oprávnění, nikoli druhá occasion konfigurace.

SQL projekce vrací jen údaje potřebné pro ticket, nikoli celý order, kontakty ostatních držitelů či platební interní data. Allowlist použít při lookupu, snapshotu i hledání; klientské skrývání není bezpečnostní filtr. Hodnoty renderovat jako text, HTML popisy jen přes stávající DOMPurify a CSP. Nekopírovat natvrdo link akce pro skrytí ceny do JS.

### Přístup a životní cyklus

Stávající scan kód zůstává podporovaným způsobem otevření, s existujícími abuse limity. Pro web jej online vyměnit za silný omezený device session token (kryptografická náhoda, na serveru jen hash), vázaný na organizaci/akci, scopes, revizi oprávnění a expiraci. Token není náhradou přihlášeného oprávnění správce. Nastavení a řešení konfliktů vyžadují příslušnou roli, nikoli pouze znalost scan kódu.

URL s historickým kódem po výměně nahradit čistou cestou; secrets nelogovat, neukládat do analytiky ani sdílené CacheStorage. Pro stránky scanneru potlačit referrer s kódem a třetí strany. Rotace kódu/revokace zvýší autorizační epochu a zablokuje staré sessions na serveru. Offline nelze revokaci zjistit okamžitě: výchozí offline grant nejvýše 12 hodin od vydání, lze zpřísnit/vypnout. Po expiraci nové lokální přijetí nepovolit; stará fronta zůstane zachována.

Při odmítnutí/expiraci/revokaci se fronta automaticky nepřepíše pod jinou identitu. Obnova vyžaduje aktuálně autorizované opětovné otevření téhož scope; zneplatněné operace musí vedoucí vypořádat online, ne přijmout jen podle klientského času. Odeslaný klientský čas je auditní údaj, ne důkaz platného oprávnění. Session token v lokálním zařízení chránit jako bearer credential, s minimálním scope a omezenou životností; neoznačovat obyčejné IndexedDB za šifrovaný trezor.

### Snapshot a trvalý outbox

- Jeden existující service worker spravuje spustitelný shell a lokálně zabalený dekodér. IndexedDB spravuje odděleně `sessions`, `snapshots`, `tickets`, `outbox`, `receipts` a lokální preference, klíčované backend generation + tenant + occasion + session. Online auth/RPC odpovědi se univerzálně necachují.
- Snapshot vytvořit serverovým RPC jako konzistentní minimalizovanou projekci a uložit do krátkodobých, autorizovaných snapshot pages. Manifest obsahuje snapshot ID, scope, policy revision, server time, počty, velikost, stránkování a digest. Stránky nesmí být veřejným seznamem hostů. Limity existujícího exportu zachovat; jejich obcházení neomezeným stránkováním není řešení.
- Klient ověří úplnost/verzi, v jedné transakci zveřejní aktivní snapshot a ponechá předchozí do úspěchu. Stejným způsobem obnovuje snapshot při návratu sítě; vlastní pending overlay se přitom neztratí. Delta protokol není podmínka první verze.
- Každé potvrzení vytvoří trvalé `operation_id` (UUID), ticket, device/session, snapshot/policy revision a stav. Ticket pending overlay a outbox se zapíší v jedné IndexedDB transakci PŘED zobrazením lokálního úspěchu i před prvním odesláním. Online i offline používají tutéž cestu; není druhá paměťová fronta.
- Stav operace: `pending -> sending -> accepted | conflict | rejected`; síťová chyba/timeout zůstává retryable se stejným operation_id. Po restartu se sending znovu ověří. Jedna aktivní odesílací smyčka na scope s transakčním lease; více záložek koordinovat, korektnost zároveň zajišťuje DB.
- Foreground sync při startu, obnovení okna, návratu sítě, omezeném retry s backoff/jitter a ručně. `navigator.onLine` je jen signál, rozhoduje skutečný výsledek requestu. Background Sync může být doplněk, nesmí být podmínka.
- Request timeout neznamená neúspěšný serverový commit. Klient dotáže receipt nebo pošle stejnou operaci. Server má unikátní klíč operace a hash payloadu; identický retry vrací stejný výsledek, stejný klíč s jiným payloadem odmítne.

### Serverové potvrzení a konflikty

Jediný webový zapisovací RPC je `sync_scanner_operations`, pro online potvrzení s jednou položkou, při obnově s dávkou. Nevytvářet navíc jednoúčelový confirm endpoint se stejným účinkem. Atomicita zahrnuje ověření session/scopes/epochy, abuse admission, zamknutí rodičů a ticketu, aktuální doménovou platnost, změnu state a receipt. Unikátní operation identity musí fungovat i při dvou současných requestech; konflikt nesmí zanechat změněný ticket bez odpovídající účtenky. Dávka vrací výsledek po operacích; velikost je omezená, každá operace má atomickou doménovou jednotku. Žádné persistentní aplikační triggery.

Server rozhoduje podle aktuálního stavu, platební/occasion mutability a povolení, ne podle klientského used/valid. Při neznámé změně admission podmínek oproti snapshotu vrátí konflikt k ověření. Zamykání a kontrolu vstupenky a souvisejících eligibility dat sjednotit s existujícími storno/payment writery; nepovažovat ticket lock sám za důkaz ochrany proti souběžné změně objednávky. Zamykat ve stejném pořadí jako kanonické order commands.

Dvě různé operace pro stejný ticket: první platný serverový commit vyhraje, druhý vrátí `already_used` s referencí dostupné historie. Jde o konflikt, pokud obsluha lokálně už přijala, nikoli falešný nový úspěch. Lokální čas nerozhoduje pořadí. Vedoucí může zaznamenat vysvětlení/vypořádání konfliktu; automaticky nevrací used na nepoužito a nepřepisuje historii.

Existující `update_ticket_to_used` pro nativní klienty přesměrovat uvnitř serveru na stejnou admission primitive se zachovanou signaturou a odpovědí. `_ws` administrativní použití i storno/unused zůstávají samostatnými autorizovanými akcemi se stejnými invarianty, nejsou anonymní bypass. Nezaměňovat administrativní označení použito s potvrzením příchodu skenerem v auditních počtech.

### Úložiště, aktualizace a soukromí

Chyba zápisu, quota, private mode nebo vymazaný balíček explicitně vypnou offline připravenost. `navigator.storage.persist()` jen best effort; příprava kontroluje i skutečný zápis a dostatek místa. Bez snapshotu je online režim dostupný, offline admission nikoli. Po restartu a bez sítě musí fungovat přímá `/scan` navigace, lokální překlady, theme, dekodér a fronta bez requestu nutného pro start.

Aktualizace aplikace nesmí řízeným reloadem přerušit zápis nebo zničit outbox. IDB migrace jsou verzované a nedestruktivní, při nekompatibilitě nabídnout bezpečné dokončení kompatibilním klientem; chybějící starý bundle není důvod databázi smazat. Potvrzené citlivé snapshoty expirovat nejpozději 24 h po skončení grantu; nevypořádaná fronta se nikdy automaticky nemaže. Při expiraci uzamknout její citlivý detail do nové autorizace a nabídnout řízené dokončení nebo výslovné odstranění. Logout je vždy dostupný, ruší aktivní session a maže běžný snapshot; pending frontu zachová uzamčenou do opětovné autorizace. Její smazání je oddělená výslovná akce. Soukromí nesmí stát na nesplnitelném slibu vzdáleného smazání odpojeného telefonu.

## Efektivita implementace a provozu

Priorita je kompletní funkční pracovní cesta s malým počtem vlastníků. Použít stávající vanilla JS lifecycle, theme/localizaci, Supabase klient, SQL guards a jediný PWA worker. Nové části jsou pouze scanner UI/controller, input adaptér, RPC transport, trvalé úložiště a sync. Názvy souborů v příloze vymezují odpovědnosti, nepředepisují množství tříd; malé související presentation funkce mohou zůstat spolu. Nevytvářet obecný workflow engine, vlastní auth framework, druhý frontend ani univerzální offline platformu.

Nejdříve dokončit tenký průchod: otevřít session -> načíst ticket ručním kódem -> trvale uložit operaci -> RPC potvrdit -> zobrazit receipt -> po restartu bezpečně zopakovat. Tím se ověří nejrizikovější propojení už ve vlně 2. Kamera, další režimy a vizuální úpravy pak používají stejný controller. Základní IDB outbox vzniká s prvním zapisujícím klientem; vlna 4 ho rozšíří o snapshots a úplné offline UI, nenahradí dočasnou paměťovou implementaci.

Provozní rozpočet:

- Běžné online načtení má jeden lookup RPC; potvrzení jednu položku v jednom `sync_scanner_operations` RPC. Obnovu session/settings ani celý seznam hostů nestahovat při každém scanu. Otevření session vrací capabilities, settings/revizi a potřebný kontext společně.
- SQL projekce používá množinové dotazy, ne jeden dotaz na každý produkt/pole. Indexy přidat podle skutečného lookupu a EXPLAIN na reprezentativních datech; nepřidávat je preventivně ke každému JSON klíči.
- Summary obnovovat odděleně, výchozí interval nejvýše jednou za 15 s ve viditelné stránce, s časem posledního stavu. Neprovádět globální COUNT v každém potvrzení. Interval je počáteční nastavení pro měření, ne slib přesné živosti.
- Snapshot připravit na vyžádání a obnovit po návratu sítě, pokud je starý či se změnila relevantní revize; ne po každé dávce/potvrzení. Sloučit souběžné refresh požadavky, výchozí minimální odstup automatického rebuild 60 s. Zachovat starý úplný snapshot do atomického přepnutí. První vydání používá plné omezené snapshoty, delta protokol až podle měření.
- Decoder načítat jen pro scanner/kameru a předem uložit při offline přípravě. Na katalogu ani formuláři nemá vzniknout scanner download. Vyhledávání stránkovat, lokální index odvozovat jen z povoleného snapshotu; výsledky renderovat po omezených stránkách.
- Měřit velikost scanner bundle a snapshotu, počet RPC za scan, dobu lokálního lookupu a obnovení 1 000 operací. Výkonové cíle jsou ověřované na fixture 10 000 ticketů; bezpečnostní limity nezvyšovat jen proto, aby benchmark prošel.

Každou ucelenou změnu ověřit jedním odpovídajícím targeted batchem. C01-C18 mapovat na existující test seams, nikoli na 18 samostatných browser sessions. Stejný nezměněný passing check neopakovat; plný Flutter build a release gates patří až do schválené release fáze. Nepřidávat další auditní kolečka bez konkrétní otevřené otázky. Obecná správa více stanovišť/profilů, automatické potvrzování, realtime dashboard, delta sync a čerpání produktů nejsou součástí první implementace.

## Implementační vlny

### 1. Ustálit kontrakt, doménové projekce a migrovat nastavení

Změny: nové kanonické SQL v `database/functions/scanning/`, dopředná migrace, settings tabulka/RPC a projekční primitive. Zmapovat konkrétní field IDs, cenu a callers v ticket/settings editoru; založit data pro příslušné akce bez globálního backfillu cizích polí. Zachovat současnou vstupní sadu produktů, poté umožnit explicitní úpravy. Zamezit ztrátě konfigurace při serializaci `TicketFeature` a při occasion duplicate.

Selhání: revize chrání souběžnou editaci, odstraněné pole nezmění význam jiného pole. Během rozšíření funguje starý klient. Ověření: cílený SQL test nastavení/projekce, cross-tenant/role/NULL případy a roundtrip konfiguračního writeru. Exit: dva klienti vidí stejné uložené nastavení, nepovolené hodnoty nejsou v payloadu.

### 2. Admission, sessions a idempotentní účtenky

Změny: session/receipt/snapshot tabulky a RPC, reuse existujícího abuse gate, kanonický transakční primitive a nativní wrapper. Zkontrolovat všechny admission/storno/payment writers a veřejné grants. Migraci sestavit z kanonických SQL, žádný ad hoc produkční zásah.

Ještě v této vlně propojit minimální JS ruční vstup se skutečným IDB outboxem a lokálními RPC podle výše uvedené pracovní cesty. Nečekat s ověřením klient/server kontraktu až na dokončení veškerého UI. Snapshot export dopracovat ve vlně 4; zde připravit jen potřebné schéma/kontrakt.

Selhání: row locking, opakovaný request, unikátní klíče, výpadek po commitu, neplatný payload, vypršení a rotace scan kódu. Ověření: SQL scénáře + skutečný souběh dvou DB spojení nad lokální DB; výpadek odpovědi a opakování se stejným ID. Exit: jeden přechod ticketu a jeden stabilní výsledek operace, staré nativní signatury fungují bez druhého writeru.

### 3. Kompletní online webový skener a nastavení

Změny: nové komponenty `scan_page.js`, `scan_result.js`, `scanner_settings_page.js`, `scanner_input.js` a služby pro API/projekce, pod `web_client/src/components/scan/` a `src/services/`. Použít lifecycle `init/render/clear`, cleanup kamery/listenerů, lokalizaci a existující tokeny. Přidat kamery, hledání, čtečku, detail, counts, historii a nastavení s náhledem. Decode adaptér používá detekci schopností; QR knihovna i worker musí být lokálně bundlované. Případný native BarcodeDetector je optimalizace, ne jediná implementace.

Přidat explicitní režim pro kontrolu programu a recepční QR. Před portem dohledat jejich volající a návratový kontrakt; uchovat rozdíl mezi ticket symbolem, UUID uživatele a recepčním credentialem. URL payload se nesmí libovolně navigovat/otevírat. Reset hesla volá současný zabezpečený online command, žádná offline emulace nebo rozšíření role.

Selhání: odmítnutá/obsazená kamera, prázdné snímky, více QR, stale odpověď, dvojí klik a 401/409/429 musí mít různé stavy. Ověření: cílené JS testy chování a route dispatch; izolovaný headless průchod hlavního toku, ruční hardware smoke pro kameru/čtečku jako samostatná gate. Exit: všechny funkce jsou dosažitelné bez Flutter runtime, včetně nastavení, kontrol a online pomocných akcí.

### 4. Připravený offline provoz a obnova

Změny: `scanner_store.js` (IndexedDB), `scanner_sync.js`, snapshot download/validation a trvalý outbox. Reuse existujícího SW generátoru, shell manifestu a cache pinningu; rozšířit scanner routes/assets. Scanner mount před nepovinným online RightsService startupem. Doručování není závislé na Background Sync ani CDN.

Selhání: app kill po IDB commitu i po server commitu, kvóta, reload bez sítě, nekompletní balíček, vymazaná data, dvě záložky, dva telefony, expirovaná/revokovaná session. Ověření: deterministické store/sync testy s reálnou IDB integrací v browser harnessu, PWA offline navigace existujícím repo harness, výpadek v kritických bodech. Exit: v podporovaných crash/retry scénářích se žádná commitnutá lokální operace neztratí ani nezapočte dvakrát; „připraveno“ znamená úplný balíček a persistentní zápis. Ztráta zařízení a externí vymazání storage jsou výslovná zbytková omezení.

### 5. Přepnout všechny webové vstupy a odstranit nahrazené cesty

Změny: `router_service.js` včetně popstate, `main.js`, web bootstrap/rewrite a SW navigace přidělí `/scan` JS. Zachovat funkční `/scan/<code>` i hash deep links jako podporovaný vstup, po ověření normalizovat na čistou routu. Přesné cesty settings/program/history/offline a samostatné `/login-qr` určuje prováděcí kontrakt; patří do stejného route ownera a odpovídajícího SW resolveru. `TicketCodeHelper`, odkazy z orders/tickets a schedule míří na web. Flutter web vstupy převedou odpovídající úlohu ven do stejného webového toku; nativní app entry je explicitně ponechaná hranice.

Odstranění: `/scan` z Flutter handoff seznamu JS, webové CDN dekódování, hardcoded web field mappings a tenant-price branch po datové migraci. Dart implementaci nesmazat, dokud má nativní callers; pro nativní zobrazení odstranit hardcoded mapping až po napojení na serverovou konfiguraci. Neupravovat generovaný `app_router.gr.dart` ručně. Zastaralé testy a docs aktualizovat podle skutečného scope, ne prostě smazat coverage.

Ověření: route/startup/PWA testy a cílená Dart analýza změněných callers; cold direct, hash, historie, offline reload, app-supported i ticket-only konfigurace. Exit: žádný webový skenovací vstup nenačte Flutter pro skenovací UI; jediná ponechaná Flutter implementace je dokumentovaný nativní boundary.

### 6. Provozní připravenost a případný autorizovaný rollout

Lokálně dokončit recovery UX, minimální telemetrii bez secretů a osobních údajů (délka fronty, nejstarší pending, sync latency, konflikty), provozní instrukce a níže uvedená kritéria. Domluvit/ověřit reálné cílové zařízení i velikost akce před prohlášením release-ready.

Produkci mění až samostatně zadané nasazení. Pořadí: záloha/ověřená DB identita, aditivní DB kontrakt a backfill, ověřený JS/SW bundle, přepnutí vstupů jednoho tenanta, kontrola živé verze a smoke. Rutinní execution/monitoring předat levnějšímu subagentovi podle AGENTS.md. Flutter a web build lokálně, deploy přes `automation/deploy_direct.sh`; žádný GitHub-hosted build bez zadání. Žádný rollout dalších `prod/*` větví.

Rollback pozastaví nové sessions/offline preparation a zachová outbox i receipts; nevrací použité tickety na nepoužité. Předchozí kompatibilní webový bundle lze vrátit pouze pokud čte stávající IDB a umí bezpečně dokončit frontu. Dočasný rollout fallback na Flutter musí mít výslovný časový limit a nesmí zůstat finální výchozí cesta. Destruktivní kontrakce až po ověření všech klientů a vypořádání živých front.

## Deletion ledger a ponechané hranice

| Artefakt | Finální akce | Důkaz |
|---|---|---|
| JS `/scan` Flutter route classification | Odstranit | Route tests + žádné Flutter asset requesty v scanner toku |
| SW default pro scan -> Flutter | Nahradit explicitním JS resolverem | Cold offline navigation všech režimů |
| Pevná `specificFieldMappings` | Migrovat do occasion settings; odstranit po přepnutí nativních readerů | Scoped callers + testy různých akcí |
| Link-specific hide_price branch | Převést do serverové politiky konkrétní akce | Server payload test, žádný link comparison v projekci |
| CDN QR script pro web scan/reception | Nahradit lokálním decoder bundle | Offline camera decode, bez externího requestu |
| Starý plný order scan export pro nové web UI | Žádný nový web caller; minimalizovaná projekce | Payload a scoped call-map test |
| `scan_ticket`, `get_all_tickets_for_scan`, `update_ticket_to_used` | Zachovat jen potřebné nativní veřejné kontrakty, backend deleguje do kanonické autority | Nativní compatibility test; ne druhý writer |
| `ScanPage`, `CheckPage`, `LoginQrScannerPage` | Ponechat potřebné nativní entry; web je nebude renderovat | Native callers a web route tests |
| Pracovní rollout flags/duplicitní UI | Odstranit po rollout; nezavádět trvalý V1/V2 přepínač | Konkrétní source + live config kontrola |

## Ověření a definice hotovo

Při implementaci testovat doménové chování a skutečnou obnovu, ne jen seznam prvků UI. Přesné nové test soubory vzniknou ve vlnách; používat existující Node runner, izolovanou lokální DB a deterministický repo browser/PWA harness. Pro exploraci `agent-browser` v izolovaném headless session, nevstupovat do uživatelova prohlížeče. Kamera vyžaduje i skutečný hardware check; headless úspěch ho nenahrazuje.

- Settings: role/cross-tenant read/write, selected/all/none, field order/ticket scope, odstraněné pole, změna revize, serverové skrytí cen a osobních údajů, occasion duplicate.
- Admission: dvě současná potvrzení, retry po ztracené odpovědi, stejný operation_id s jiným payloadem, rotace/expirace, storno/platba během offline, neznámé QR a waitlisted. Admin unused/storno nesmí obejít audit ani oprávnění.
- Offline: přímý cold start a refresh bez sítě, výpadek během snapshot downloadu a IDB commitu, restart s pending/sending, odmítnutá quota, dvě záložky, změna app verze se živou frontou, dlouhý výpadek přes expiraci grantu, návrat sítě a částečně chybující dávka.
- UX: mobile 320 px, tablet/desktop, 200% zoom, dlouhá jména a překlady, klávesnice/USB čtečka, viditelný fokus, textové stavy a live oznámení bez zahlcení, velké dotykové cíle. Kamera Safari/iOS a Chrome/Android i desktop podle skutečně podporované matice.
- Výkon: 10 000 ticketů/1 000 pending jako počáteční fixture; odděleně měřit přípravu, hledání a sync. Cíl lokálního feedbacku do 100 ms od potvrzeného trvalého zápisu, výsledek lokálního lookupu do 300 ms na referenčním zařízení; uvést zařízení a měření, nedeklarovat bez důkazu.

Orientační cílené příkazy: `cd web_client && node --test tests/scan/*.test.js` po založení scanner suites; `node web_client/scripts/run_db_tests.js <skutečný-soubor-testu>` podle CONTRIBUTING nad izolovanou DB; existující `automation/tests/pwa_offline.test.mjs` a související shell testy přes jejich aktuální runner; `fvm dart analyze <změněný-soubor>` pro Dart callers. Před použitím zjistit skutečné runner arguments z aktuálního repozitáře, nenahrazovat repo E2E kontrakt přímým Playwright invocation. Full release gates jen při schváleném release scope.

Hotovo znamená: všechny webové skenovací vstupy fungují v JS včetně nastavení a pomocných režimů; produkty a pole jsou uložené a autorizované; offline fronta je trvalá a prokazatelně obnovitelná; počty rozlišují server a pending; konflikty mají jasné vypořádání; žádný tichý návrat do Flutteru ani druhá doménová logika; nativní hranice je funkční a zdokumentovaná. Produkční část se hlásí samostatně jako provedená nebo dosud neautorizovaná, nikdy jako implicitně hotová.

## Zbytková omezení a technické zdroje

Globální ochranu proti dvojímu použití nelze garantovat mezi odpojenými zařízeními. Ztráta zařízení nebo ruční vymazání dat může zničit neodeslanou frontu. Prohlížeč negarantuje nekonečné uchování dat ani synchronizaci po zavření; obsluha proto vidí stav připravenosti, expiraci a počty pending.

Podpora `BarcodeDetector` je omezená, proto je vyžadovaný lokální dekodér ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/BarcodeDetector)). Background Sync není univerzálně dostupný ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/Background_Synchronization_API)). IndexedDB a CacheStorage podléhají quota/eviction ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria)); kamera vyžaduje secure context a povolení ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)). Zdroje kontrolovány při tvorbě plánu; konkrétní kompatibilitu znovu ověřit před volbou dekodéru a releasem.


## Ověření této revize plánu

Revize 2 byla porovnána s konkrétními order/ticket lock guards, existujícími mutation receipts, recepčním auth tokem a PWA manifestem. Zkontrolované jsou lokální odkazy a formát všech tří dokumentů. HTML návrh byl otevřen přímo z disku v izolovaném headless prohlížeči, bez serveru; ověřený je modelový průchod offline uložením, střetem zařízení, vypořádáním počtů, chybou úložiště a filtrováním zobrazení. Kontrola mobilního náhledu proběhla na 390 px. Toto ověření demonstruje návrh rozhraní, nikoli skutečnou offline persistenci, SQL souběh, funkční kameru nebo produkční readiness. Aplikační testy, build, produkční dotazy a nasazení se pro tvorbu plánu nespouštěly.

## Implementační delta k doloženému stavu

Aktuální `extract_ticket_answers_internal` ukládá ticketová pole do `eshop.tickets.data.fields`; scanner používá tuto kanonickou autoritu, nikoli odpovědi jiného držitele v order JSON. Objednávková pole zůstávají v order data. Legacy hash není dostupný HTTP serveru ani SW resolveru, proto root nejprve vrací JS shell a až router případně provede existující forced-home handoff. Pomocné RPC pro preview, minimální user search, audit a existující reset politiku jsou popsány v implementačním záznamu. Žádná nová Edge Function nevznikla.

Přesné lokální výsledky, limity důkazů, screenshoty, měření a release/hardware gates: [web-scanner-implementation-2026-10-18.md](web-scanner-implementation-2026-10-18.md).
