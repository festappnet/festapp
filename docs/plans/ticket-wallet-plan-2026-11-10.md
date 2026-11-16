# Uložení vstupenek do Google Wallet z e-mailu

Historický plán vydávání. Synchronizaci nahrazuje [plán změnové fronty](ticket-wallet-change-queue-plan-2026-11-13.md).

Datum: 2026-11-10. Stav: lokální implementace probíhá; bez produkčního nasazení.
Ověřování při implementaci: `standard` (nová veřejná capability, podpisové klíče a databázová migrace).

## Výsledek a rozsah

Každý nově připravený e-mail, který skutečně doručuje vstupenky, automaticky nabídne jejich uložení do Google Wallet, pokud pořadatel samostatnou volbu nevypne. Volba je výchozí zapnutá a nezávislá na PDF / QR způsobu doručení; skutečné nabídnutí je podmíněno provozuschopnou integrací. Příjemce nepotřebuje účet Festapp ani instalaci naší aplikace; uložení potvrzuje v Google Wallet ve svém Google účtu. Dosavadní PDF / QR doručení zůstává funkční. Součástí následného provedení plánu je také registrace a zprovoznění issuera, ne pouze předání této podmínky uživateli.

Rozsah této dodávky je pouze Google Wallet. Apple Wallet je odloženo a není podmínkou dokončení: neprovádět Apple registrace, nepřidávat Apple adaptéry, certifikáty, APNs ani obecný framework pro více peněženek. Zachovat jediný checkbox `wallet_enabled` bez rezervovaných Apple nastavení. Nezobrazovat nefunkční tlačítka. V této dodávce se neřeší NFC, změna skeneru, převod vstupenek mezi lidmi, hromadné rozesílání starých objednávek ani nasazení na všechny tenanty.

Produktová kritika: nabídka patří automaticky ke vstupenkám, nemá být ručně vkládaným odkazem pořadatele. Uložení nelze provést bez akce příjemce. Google Wallet samo o sobě nepokryje iPhony. Peněženka nezabrání kopírování QR a nezaručuje okamžité promítnutí storna do telefonu bez připojení; o vstupu dál rozhoduje současný skener a jeho pravidla synchronizace.

## Zjištěný stav a vlastníci

- `supabase/functions/_shared/emailRenderer.ts::renderQueuedEmail`, větev `order_tickets`, načítá kontext přes `get_order_details_for_email` a `get_tickets_with_details`. Volá `prepareTicketDelivery` a předává `ticketBlock` společnému rendereru.
- `_shared/ticketDelivery.ts::prepareTicketDelivery` podporuje `pdf_attachment`, `inline_qr`, `both`. `issuableTickets` vyřazuje `storno`/`waitlisted`, kontroluje identitu a příslušnost k akci. Samotný tento filtr není autorizací nového veřejného endpointu.
- `_shared/emailDelivery.ts::renderEmail` vloží `ticketBlock` jednou na `{{tickets}}`, případně ho připojí při chybějícím markeru. To už pokrývá vlastní šablony i PDF-only doručení; není potřeba nová povinná proměnná šablony.
- `database/functions/emails/email_queue.sql::email_intent_valid` chrání odesílání ticket intentu aktuálním stavem objednávky, verzí a online platební projekcí. E-maily musí stále jít přes `public.email_messages` a `process-email-queue`.
- `download-ticket/index.ts` a `customerAccess.ts` ukazují oddělení zákaznického přístupu od admin klienta. Nové Wallet oprávnění ale musí být omezeno na jedinou vstupenku, ne na celý přehled objednávky.
- `_shared/orderEmailOverview.ts` a `database/functions/eshop_waitlist/order_overview_*` jsou reference pro šifrovaný zdroj a fragmentový token. Přehled závisí na formuláři, proto není vhodné jej vynucovat u objednávek bez formuláře.
- `_shared/ticketRenderData.ts::normalizeTicketData` zná akci, místo, časové pásmo a produkty. `get_tickets_with_details.sql` vrací vazby na místa. Sdílet interpretaci těchto dat, ne převádět PDF do obrázku peněženky.
- `database/functions/scanning/projection.sql` a `admission.sql` vlastní projekci vstupu a použití. Peněženka nesmí vytvořit druhý rozhodovací systém o přijetí platby nebo platnosti vstupu.
- Při průzkumu nebyla ve vymezených zdrojích nalezena existující integrace Google Wallet. Dostupnost účtu a credentials nebyla ověřována. Pracovní strom obsahuje jiné rozpracované změny; zachovat je.

## Ověřené externí podmínky

Google podporuje vydávání event tickets odkazem v e-mailu: [web/email vydávání](https://developers.google.com/wallet/tickets/events/web). Potřebuje issuer účet, Google Cloud service account s přístupem k issueru, zapnuté API a publishing access pro veřejné vydávání; demo režim je určen testovacím účtům: [issuer onboarding](https://developers.google.com/wallet/tickets/events/getting-started/issuer-onboarding).

Jedna akce odpovídá `EventTicketClass`, jednotlivá vstupenka `EventTicketObject`. Objekt má barcode, seatInfo, stav a interval platnosti: [objekt](https://developers.google.com/wallet/reference/rest/v1/eventticketobject). Uložení používá podepsaný JWT: [JWT](https://developers.google.com/wallet/tickets/events/use-cases/jwt). Změny již vydaných objektů podporuje REST API: [aktualizace](https://developers.google.com/wallet/tickets/events/use-cases/updates). Použít oficiální lokalizované tlačítko podle [brand pravidel](https://developers.google.com/wallet/tickets/events/resources/brand-guidelines).

## Rozhodnutí a invarianty cíle

### Doplněný průzkum Google event tickets

- Pro webové/e-mailové vydání nepotřebujeme Android aplikaci, Google Play developer účet ani placené členství Google Developer Program. Onboarding vyžaduje Google účet, Wallet issuer a pro REST zapnuté API v Google Cloud projektu; pro veřejné vydávání publishing access. [Onboarding](https://developers.google.com/wallet/tickets/events/getting-started/issuer-onboarding).
- Použít nativní `EventTicketClass` / `EventTicketObject`. Class povinně vyplní `id`, `issuerName`, lokalizované `eventName` a `reviewStatus`. Pro použití poslat `UNDER_REVIEW`, potvrdit `APPROVED`, potom vytvořit objekt; draft nelze použít. Stav Class je oddělený od publishing access issueru. Stabilní `eventId` do 64 znaků umožní seskupení více vstupenek stejné akce. `dateTime` poslat jako místní čas akce s odpovídajícím offsetem včetně letního času. Pokud posíláme `venue`, potřebuje jméno i adresu; chybějící adresu nevymýšlet, blok lze vynechat a známý název zobrazit v textovém modulu. [Class kontrakt](https://developers.google.com/wallet/reference/rest/v1/eventticketclass).
- Objekt povinně obsahuje `id`, `classId` a `state`. Naše integrace navíc vyžaduje `barcode.type=QR_CODE`, `barcode.value=ticket_symbol`, čitelný ticket number a pravdivý termín. Sedadlo dát do `seatInfo.seat`; skupinu/stůl přenést jako lokalizovaný text „Stůl“ bez vymyšlené řady či brány. Bez číslovaných míst seatInfo vynechat. [Object kontrakt](https://developers.google.com/wallet/reference/rest/v1/eventticketobject).
- Rozhodnuté mapování: způsobilá nepoužitá vstupenka -> `ACTIVE`, použitá -> `COMPLETED`, storno/revokace/neplatná platba -> `INACTIVE`, po skutečné platnosti -> `EXPIRED`. Posílat kanonické uppercase enumy. Tyto stavy řídí zobrazení passu; nepotvrzují nárok u našeho skeneru. [State enum](https://developers.google.com/wallet/reference/rest/v1/State).
- Save JWT odkazuje na předem vytvořený objekt, čímž zkracuje link a omezuje historické payloady. Kontrolovat délku URL; Google v FAQ řeší problém nad 1800 znaků předvytvořením objektů. Objekty nelze přes API smazat: používat stabilní identitu a neplatnost, nikoli delete/recreate. API podle FAQ omezuje provoz na 20 requestů/s; společně omezit vydání i worker a respektovat 429. [FAQ](https://developers.google.com/wallet/tickets/events/resources/faq).
- Nezavádět omezení na prvního držitele či jediný telefon bez dalšího produktového rozhodnutí. V této dodávce není transfer systém; QR lze stejně jako PDF přeposlat a opakovaný vstup blokuje skener. Google má pro tato omezení samostatné [holder/device nastavení](https://developers.google.com/wallet/reference/rest/v1/MultipleDevicesAndHoldersAllowedStatus).

### Invarianty implementace

1. Jeden Wallet pass = jeden existující `eshop.tickets.id`. QR obsahuje přesně původní `ticket_symbol`, bez prefixu, změny skeneru nebo druhé vstupenky. Opakované uložení a opakovaný e-mail používají stejný Google object ID.
2. Class ID a object ID jsou deterministické z issueru, neměnné identity backend prostředí, tenanta, akce a vstupenky. Testovací a produkční prostředí nikdy nesmí sdílet identity. V URL není samotné sekvenční ID oprávněním.
3. U každé doručované vstupenky je oficiální tlačítko Google Wallet s rozlišujícím popisem (pořadí, typ, místo, pokud existuje). Neslibovat jedno hromadné tlačítko pro celou objednávku. Nezjišťovat zařízení z e-mailu; Google tlačítko zobrazit konzistentně. Jediný checkbox zapíná nabídku Google Wallet.
4. E-mail vede na tenantem spravovanou stránku `.../wallet#<token>`. Stránka po explicitní akci příjemce požádá backend o Google save link. Žádný Google požadavek není součástí odesílání e-mailu. E-mailový bezpečnostní skener pouhým GET nevytváří pass.
5. Token má minimálně 256 bitů náhodnosti. DB uchovává hash a serverově šifrovaný zdroj pro opakované doručení, nikdy otevřený token ve sdílených klientských datech. Capability je vázána na tenant/akci/jedinou vstupenku, vydávací kontext a aktuální generaci; nepovoluje čtení objednávky, dalších vstupenek ani úpravy.
6. Vydání capability je interní, ověřuje aktuální ticket intent a příjemce stejným pravidlem jako email queue, včetně legitimního ručního doručení. Oprava e-mailové adresy nezmění starý token automaticky. Explicitní revokace je nevratná pro danou generaci; replay ji nesmí obnovit. Pro podporu doplnit explicitní autorizovaný reissue s auditním záznamem, který zneplatní předchozí generaci.
7. Při každém použití se ze serverových vazeb ověří scope, expirace/revokace, zapnuté vstupenky, platnost objednávky a platební projekce. Pořadatelův skener může povolit jiné režimy vstupu; Wallet nesmí rozšířit oprávnění oproti doručení zaplacených/free vstupenek. `used` zobrazit jako použité; nenabízet nově aktivní průkaz. `storno`, čekající, neprodané skladové a platebně neplatné vstupenky nevydat jako aktivní.
8. Backend vytvoří/upsertuje třídu a objekt přes REST a JWT nese odkaz na již vytvořený objekt. Nepoužívat vložený historický barcode payload, který by mohl při opětovném uložení přepsat aktuální stav. Existující objekt při 409 načíst a synchronizovat, nevytvářet nový ID suffix.
9. Pass obsahuje název akce, skutečný termín v zóně akce, místo, typ vstupu, místo/stůl a stejný QR. Jméno pouze pokud existuje skutečný držitel a jeho zveřejnění je součástí vstupenky; nekopírovat automaticky kupujícího na všechny passy. Nepřenášet e-mail, interní poznámky, celou objednávku ani finanční historii. Chybějící povinná metadata neodhadovat; vynechat nabídku s interní diagnostikou.
10. Automatické nabídnutí po aktivaci issueru a při zapnuté volbě akce platí pro všechny tři režimy doručení, resend, ruční doručení, free objednávky a prodané předtištěné dávky v daném tenantovi. E-maily bez doručovaných vstupenek, čekací listina, preview a neprodané dávky capability ani pass nevytvářejí.
11. Samostatné selhání volitelné Wallet přípravy nesmí zablokovat doručení původní vstupenky. Zachytit pouze tuto chybu, ponechat PDF/inline QR a zaznamenat sanitizovanou diagnostiku. Chyby původního doručení nesmí tato větev spolknout. Nedostupný Google při kliknutí nabídne opakování; nevytváří novou objednávku ani e-mail.

## Implementační vlny

### 0. Registrace a zprovoznění issuera je součást dodávky

Tuto provozní větev zahájit včas a provádět souběžně s implementací, protože schválení Googlu nemá garantovanou délku. Agent má registraci skutečně provést přes dedikovaného browser agenta podle AGENTS.md, ne ji odložit jako obecný úkol uživateli. Uživatel výslovně autorizoval svůj hlavní Chrome přes rozšíření Panerelay pro správné přihlášené účty. Použít skill `panerelay-browser` a `agent-browser --provider panerelay`, delegovat operace na `gpt-6.1-terra`. Před změnou ověřit konkrétní Google účet/projekt; neodvozovat správný účet jen z otevřené konzole. Pracovat v nových agentových background tabech, nezaměňovat či nenavigovat uživatelovy rozpracované taby, nevytvářet izolovaný login profil namísto povoleného Chromu. Pokud rozšíření nemá autorizovaný tab, vyžádat jeho povolení, neobcházet ho jiným připojením. Samotná nynější úprava plánu účty nevytváří.

1. Nejprve zjistit existující firemní Google Cloud projekt, Google Wallet issuer a oprávnění připojených účtů. Existující vhodný issuer znovu použít; nevytvářet duplicitní identitu nebo nový osobní účet.
2. V Google Pay & Wallet Console zaregistrovat chybějící issuer pod správnou existující firemní identitou a skutečnými údaji provozovatele. Vyplnit profil, kontakty a branding, zaznamenat issuer ID, správce a projekt bez tajných hodnot. Zkontrolovat, zda smí platformový issuer vydávat vstupenky pořadatelů ve zvoleném rozsahu. [Postup registrace](https://developers.google.com/wallet/tickets/events/getting-started/issuer-onboarding).
3. Zapnout Google Wallet API ve vybraném projektu, připravit samostatný service account a udělit mu potřebný přístup k issueru. Podpisové credentials uložit do chráněného backend prostředí a uchovat podle pravidel Keychain, bez zveřejnění v repozitáři či receiptu. Žádné nové placené služby bez výslovného zadání.
4. Přidat demo testery, dokončit skutečnou Class/Object ukázku s testovací vstupenkou a ověřit uložení i aktualizaci. Připravit požadované podklady a odeslat žádost o publishing access podle [aktuálního postupu Googlu](https://developers.google.com/wallet/tickets/events/test-and-go-live/request-publishing-access). Zaznamenat stav a konkrétní další krok; demo nesmí být označeno jako veřejně schválená integrace.
5. Pokud registraci zastaví chybějící firemní údaj, nepřístupný účet, lidské ověření nebo potvrzení vyhrazené majiteli účtu, vyžádat pouze tento konkrétní vstup. Údaje nevymýšlet a nepřijímat právní závazky bez příslušné pravomoci. Pokračovat v nezávislé implementaci a registraci po doplnění dokončit.

Výstup: stručný provozní runbook a sanitizovaný registrační receipt s Google issuer ID, projektem, vlastníkem, ověřeným umístěním credentials, demo důkazem a stavem publishing access. Registraci skutečně provést; čekání na Google nebo potřebné lidské ověření doložit konkrétně.

### 1. Bezpečný datový a capability kontrakt

Přidat kanonické SQL do `database/functions/ticket_wallet/` a odpovídající forward migraci v `supabase/migrations/`. Nové tabulky `eshop.ticket_wallet_capabilities` a `eshop.ticket_wallet_objects` mají RLS bez klientských přímých grantů, unikátní identitu objektu a vazby na skutečného tenanta/akci/vstupenku. Uchovávat pouze provider metadata, hash/šifrovaný zdroj capability, expiraci/revokaci, stav synchronizace a sanitized chybu. Nezavádět paralelní ticket lifecycle.

Nové `public` RPC pro interní přípravu odkazu, capability resolve, autorizovanou revokaci/reissue a worker claims. Security-definer používá `search_path=public,extensions`, explicitní `eshop` kvalifikaci a kanonické operation predicates pro správce. Interní příprava a worker jen service role; public resolver nedostane volný ticket ID jako alternativu tokenu. Převzít šifrovací pattern existujících capability zdrojů, nikoli jejich oprávnění k celé objednávce. Životnost odkazu: do konce akce + 7 dní, po tomto termínu nevydávat aktivní pass; chybějící termín je nevyřešená metadata, ne nekonečná platnost.

Validace: SQL testy pro scoped přístup, cross-tenant, hádání ID, replay/reissue/revokaci, expiraci, ruční doručení a souběžné vytvoření jediné identity. Výstup vlny: veřejný token umí vrátit pouze svou vstupenku a žádný Google požadavek zatím neprobíhá. Jde o aditivní migraci bez backfillu historických e-mailů a bez application triggerů.

### 2. Google adaptér a vydání na vyžádání

Přidat `_shared/googleWallet.ts` s injektovatelným HTTP/časem/podpisem, `_shared/ticketWallet.ts` jako vlastníka orchestrace a nový Edge endpoint `ticket-wallet`. Po capability autorizaci načíst aktuální minimální projekci a vytvořit/srovnat Class + Object. Rozšířit serverový DTO o potřebná metadata, pokud je stávající RPC nevrací. Sdílet normalizaci času/míst/produktů; neimportovat PDF renderer jako závislost.

Přihlašovací údaje zůstávají pouze v chráněném backend secret prostředí. Vytvořit úzce vymezený service account, rotaci klíče popsat v runbooku, nesdílet klíč Google sign-in ani bankovních integrací. Při vytvoření nových credentials zachovat požadavky na Keychain a neuvádět hodnoty v receiptech. Nastavit omezené timeouty, retry/backoff pro 429/5xx a limit požadavků na capability + zdroj. OAuth access token cachovat do expirace s rezervou.

JWT, capability, barcode a podpisový klíč nesmí do logů nebo analytiky. Odpovědi `no-store`, pevný allowlist původů a pevný Google save origin, žádný uživatelský redirect target. POST vyvolaný uživatelem, žádné side effects při GET. Neplatný token vrací obecnou chybu bez potvrzení existence vstupenky.

Validace: Deno kontraktové testy JWT (podpis, issuer, object reference), deterministických ID, přesného QR, dat/minimalizace, duplicitních a souběžných požadavků, 409/429/5xx, storna a zamítnuté platby. Výstup: povolený demo tester uloží právě jednu skutečnou testovací vstupenku; opakování nevytvoří duplikát.

### 3. Nezávislé nastavení, automatický blok v e-mailu a zákaznická stránka

Přidat boolean `wallet_enabled` do stávajícího ticket feature a `ticketDraft`, nikoli další hodnotu `delivery_mode`. Chybějící hodnota znamená `true` u existujících i nových akcí; explicitní `false` musí přežít uložení, editaci, duplikaci a zpracování staršího klienta. Neplatné typy odmítnout serverově. `TicketFeature`, `FeatureConstants`, setup draft/finalizer a kanonické feature save RPC musí používat stejnou interpretaci. V `database/functions/occasion_setup/drafts.sql` doplnit zachování uložené hodnoty při payloadu staršího klienta bez klíče, obdobně jako u `delivery_mode`; dohledat a pokrýt také běžný save akce. Nevynucovat backfill všech historických feature JSON.

UI umístit ve stávajícím bloku doručování vstupenek jako samostatný checkbox pod trojicí PDF / QR / obojí, před náhledem e-mailu. Titulek: „Nabídnout uložení do peněženky“. Popis: „Do e-mailu se vstupenkami přidá možnost uložit každou vstupenku do Google Wallet.“ Stejná sdílená komponenta patří do `lib/components/occasion/setup/occasion_setup_communication.dart` i `lib/components/ticket_layout/views/ticket_settings.dart`. Řídit se jejich stávajícími komponentami, mezerami a read-only stavem; nepřidávat samostatnou stránku ani další volbu do delivery selectoru. Přístupný popisek, přepínatelný celý řádek a lokalizace ve stejných podporovaných jazycích jako okolní nastavení.

Závěr cíleného posouzení agentem Astra Medium: zachovat šířku a zarovnání selectoru (max. 440 px), respektovat `showDeliverySelector`, aby průvodce nezobrazil checkbox duplicitně i v editoru vzhledu. Doplnit „Změna se projeví v dalších e-mailech. Již přidané vstupenky zůstávají platné.“ `TicketDeliveryPreview.revision` musí zahrnout draft Wallet preference a dostupnost integrace. Preview RPC a jeho koordinátor musí přijmout neuloženou preferenci i při editaci existující akce, nikoli jen znovu načítat uloženou feature.

Rozlišit uloženou preferenci od dostupnosti: checkbox je standardně zaškrtnutý a pořadatel jej smí změnit i před zprovozněním integrace. Pokud tenant nemá hotový issuer/publishing access, zobrazit „Google Wallet zatím není k dispozici. Po zprovoznění se nabídka začne přidávat automaticky.“ Nevykreslovat falešné aktivní tlačítko v náhledu ani e-mailu. Při vypnutých vstupenkách checkbox zakázat, jeho uloženou hodnotu ponechat. Po zprovoznění automaticky respektovat předchozí hodnotu bez jejího přepisování.

Serverový výpočet nabídky je `ticket feature enabled AND wallet_enabled(default true) AND tenant integration ready AND skutečně doručované způsobilé vstupenky`. Žádný UI checkbox nenahrazuje platební nebo autorizační kontroly. Vypnutí pořadatelem je volba pro nové nabídky: nevytváří nové capability při přípravě e-mailu, ale neruší odkazy v již odeslaných zprávách ani uložené passy. Endpoint proto zpětně neodmítá existující capability pouze kvůli této preferenci; stále ověřuje její životnost, revokaci a aktuální nárok na vstup. Údržba passů běží dál. Explicitní bezpečnostní revokace zůstává oddělená.

V `emailRenderer.ts` pouze ve větvi `order_tickets` připravit ticket-scoped odkazy a přidat jejich HTML ke `delivery.html` před předáním do `ticketBlock`. Doplnit `_shared/ticketWalletEmail.ts`; jedna implementace výběru vstupenek a jeden průchod rendererem. Zachovat stávající `{{tickets}}` fallback a dědičnost wrapperů. Pro Wallet odkazy vždy `postAction.tracking_policy='disabled'`, i bez order overview.

V `web_client/src/services/router_service.js` přidat skutečnou veřejnou `/wallet` route a samostatnou malou komponentu. Token z fragmentu držet jen v paměti, nezapisovat do localStorage; odstranit ho z adresního řádku po načtení, nastavit `Referrer-Policy: no-referrer`, vypnout měření této route a neodesílat token do error reportingu. Po reloadu bez tokenu zobrazit pokyn znovu otevřít odkaz z e-mailu. Stav načítání, uložení, dočasná chyba a nedostupná/stornovaná vstupenka mají vlastní srozumitelné stavy. Nepovolovat externí skripty či analytiku před odstraněním fragmentu.

Použít oficiální lokalizované Google badge dle pravidel Googlu, hostované jako veřejné brand assets přes kanonický image Worker/R2, s textovými alternativními odkazy při blokování obrázků. Viditelný text podle jazyka e-mailu, formální oslovení v češtině. Preview vrátí pouze neaktivní ukázku; `occasion-setup-email-preview/content.ts` nesmí vydat capability ani skutečný pass. Testy zahrnují připravený i nepřipravený Google issuer při zaškrtnutém i nezaškrtnutém checkboxu.

Validace: kontraktové testy default true / explicit false / neplatný typ, round-trip a duplikace, zachování false při starším payloadu, změny delivery mode bez změny Wallet preference, obě UI plochy a read-only stav. Renderer testy pro 1/N vstupenek, všechny delivery modes s ON i OFF, nepřipravený issuer při ON, vlastní šablonu bez markeru a s opakovaným markerem, formless/batch/free/resend, nulový počet ticketů a selhání pouze Wallet větve. Náhled checkbox respektuje bez vydání skutečné capability. Web testy pro fragment, explicitní akci a chybové stavy. Výstup: při ON a připravené integraci je nabídka jednou u každé skutečně doručované vstupenky; při OFF chybí a původní doručení funguje stejně.

### 4. Aktualizace uložených passů a provozní dokončení

Přidat interní `sync-ticket-wallet` worker, který v omezených dávkách opakovaně načítá VŠECHNY registrované objekty a jejich aktuální projekci. První etapa používá periodickou reconciliaci, ne háčky do všech storno/platebních/scan writerů. Díky tomu zachytí i změnu akce, místa, produktu, platby nebo smazání vazby. Zaniklá vstupenka musí zanechat dost provider identity pro zneplatnění passu; nepoužívat kaskádu, která tuto stopu odstraní.

Registraci zapsat před prvním externím upsertem, aby timeout s neznámým výsledkem zůstal dohledatelný. Neúspěšné vydání se stejným object ID musí být obnovitelné. Synchronizaci konkrétního objektu serializovat mezi endpointem i workerem, používat claim/lease a podmíněné dokončení. Staré zpracování po ztrátě claimu nesmí zahájit další zápis. Vzdálený API požadavek nelze atomicky svázat s SQL, proto pravidelně porovnávat i skutečný vzdálený stav a napravovat případné opožděné zápisy.

Výchozí cíl při zdravých službách: každá registrace projde porovnáním do 5 minut. Dávky mají férový cursor/next-attempt, retry/backoff a metriky stáří backlogu; nelze donekonečna kontrolovat jen první stránku. Interval potvrdit proti reálné kvótě issueru a počtu objektů před aktivací. Použití/storno/revokace/propadlá platba projektuje Google neaktivní stav; expirace podle termínu akce. Změna sedadla nebo času aktualizuje tentýž objekt. Revokace capability zneplatní i již vydaný pass; reissue může znovu aktivovat stejnou ticket identity pouze po explicitní autorizaci a kontrole aktuálního nároku.

Validace: změna místa/času, storno, used, refund/platební invalidace, revokace a zánik ticketu; restart workeru, timeout po úspěšném Google upsertu, concurrent save+sync, opožděný zápis a průchod přes více stránek. Prokázat, že chybný pass nikdy nemění lokální nárok ke vstupu. Výstup: existuje recovery postup a měřitelný stav synchronizace; offline telefon může mít starší vzhled a je to přiznané omezení.

## Rollout, blokery a návrat

- Externí závislosti veřejného spuštění: skutečný issuer, publishing access, service account oprávnění, chráněné credentials, schválený branding a demo end-to-end důkaz. Jejich zajištění je výslovnou prací vlny 0, ne výlukou ze zadání. Neověřeno, zda již účty existují. Agent dokončí dostupné kroky; lidské ověření nebo rozhodnutí Googlu může zůstat přesně doloženou blokací.
- Předpoklad: platformou spravovaný issuer může obsloužit vybraného tenanta a jeho pořadatele. Před aktivací ověřit s pravidly/registrací issueru; pokud potřebuje vlastní issuer pořadatel, mění se konfigurace identity, nikoli ticket ani e-mailový kontrakt. Nevytvářet nyní onboarding UI pro každý subjekt.
- Pořadí: aditivní SQL a secrets -> endpoint + synchronizační worker -> web route -> e-mailový blok -> aktivace jednoho výslovně vybraného tenanta. Produkční tenant zatím nebyl vybrán, plán neopravňuje rollout.
- Oddělit dvě různé věci: serverovou připravenost Google integrace tenanta (issuer a publishing access) a pořadatelovu preferenci `wallet_enabled` na akci (výchozí zapnutá). Po aktivaci nabídnout automaticky, pokud ji pořadatel nevypnul. Bez checkboxů v jednotlivých šablonách a bez vazby na `delivery_mode`. Credential readiness samo nenahrazuje publishing access.
- Již doručené e-maily se nezmění; nový explicitní resend respektuje aktuální preferenci. Připravený, ale dosud neodeslaný snapshot musí odpovídat aktuálnímu ON/OFF před získáním fenced send permitu. Doplnit interní fingerprint Wallet preference do metadata snapshotu a v `begin_email_send` zneplatnit pouze neodeslaný ticket snapshot při neshodě, obdobně jako existující `offer_snapshot_changed`; worker ho bezpečně znovu připraví přes stejný renderer. Neměnit běžící provider pokus ani neposlat druhý e-mail po nejistém výsledku. Retry beze změny preference ponechá původní snapshot, odkazy a přílohy; žádné hromadné přepracování historických zpráv. Ověřit OFF mezi renderem a send permit, změnu zpět na ON a retry bez změny.
- Vypnutí nabídky nezastavuje údržbu již vydaných passů ani nezneplatní původní PDF. Při výpadku podpisu vracet dočasnou chybu. Při kompromitaci klíče provést zvláštní revokační/rotační postup, nezveřejňovat tajné hodnoty.
- Před publikací zdrojů spustit dotčené canonical lanes přes `automation/test_ci.sh` podle `automation/ci/checks.json`. Produkční migrace/deploy vyžadují samostatné zadání, přesný `baseMainSha` s úplně zeleným `release_gate.py` a současný kanonický backend/restart postup. Tento plán nic necommitne, nepushuje a nenasazuje.

## Ověření a hotovo

V implementaci doplnit cílené Deno, SQL a web testy do existujících CI vlastníků; přesné runtime parametry převzít z aktuálního `automation/ci/checks.json`, nikoli obcházet lane vlastním runnerem. Před finálním předáním jednou souhrnně spustit relevantní canonical lanes. Reálné demo Google Wallet: e-mail -> klik -> uložená karta -> současný skener přijme přesný QR; po stornu skener odmítne a online Wallet následně zobrazí neplatnost. Registrace/účty se provádějí autorizovaně přes Panerelay v hlavním Chromu podle vlny 0; automatické interní UI testy odděleně podle AGENTS.md. Snímky světlé, lokalizované, bez skutečných tokenů.

Hotová lokální implementace znamená dokončené vlny 1-4 pro Google, testy a runbook, žádné nefunkční badge či dummy JWT. Dodávka dále obsahuje provedení registrační vlny 0 a doložený stav Google žádosti. Hotová produkční funkce navíc znamená Google publishing access, schválený tenant rollout a live důkaz vydání i aktualizace. Tyto stavy v předání rozlišit. Apple není podmínkou žádného z nich.

Žádný starý doručovací režim se nemaže. Není zde legacy Wallet cesta k odstranění. Nezavádět druhou e-mailovou frontu, druhý admission lifecycle, náhradní Supabase Storage ani nové persistentní aplikační triggery. Google Wallet je jediná peněženka v rozsahu této implementace; žádné prázdné adaptéry.

## Upřesnění při implementaci 2026-11-10

Uživatel požaduje také srozumitelný vzhled karty v nastavení a ověření použitého
stavu i stejného skenovatelného QR. Google řídí nativní rozložení, font a barcode.
Přidává se orientační náhled v existujícím nastavení vzhledu, automatické převzetí
kompatibilní barvy/loga/obrázku a volitelné úpravy těchto tří položek pouze pro
Google Wallet; nevzniká druhý editor PDF šablon. Jediným přepínačem nabídky
zůstává `wallet_enabled`. Registrační a provozní důkazy patří do
`docs/operations/google-wallet-registration-2026-11-10.md` a provozní kontrakt do
`docs/operations/google-wallet.md`. Kamera/displej a scanner RPC jsou odlišné
důkazy; nesmějí se zaměňovat.
