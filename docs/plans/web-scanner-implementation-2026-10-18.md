# Web scanner - lokální implementace a důkazy

Datum: 2026-10-18. Rozsah: revize 3 plánu a prováděcího kontraktu, lokální změny.
Produkční migrace, nasazení, commit/push ani další tenant rollout nebyly provedeny.
Existující rozsáhlé změny pracovního stromu zůstaly zachovány.

## Výsledek

Scanner má vanilla JS lifecycle, společný controller pro ruční vstup, kameru a
HID, serverovou konfiguraci produktů/polí, nastavení s náhledem, historii a přehled
akce, explicitní unpaid potvrzení, read-only program a samostatný recepční login.
Recepční credential nikdy není ticket a nepřepíná přihlášeného pracovníka.
Reset hesla používá současnou chráněnou online politiku.

Online i offline potvrzení prochází skutečným IDB outboxem a jediným
`sync_scanner_operations`. Session, parent locks, aktuální eligibility, opaque
fingerprint a immutable receipt vlastní SQL. Retry po admin unused nepíše ticket
znovu. Receipt overlay se odvozuje jen pro matching fingerprint starého snapshotu;
novější unused snapshot se tím nepřepisuje. Snapshot pages a manifest vznikají z jednoho statement snapshotu; přesné
UTF-8 digests se ověřují před atomickým přepnutím. Lease fencing chrání dvě záložky.
Neznámé schema, nefunkční storage a známé neplatné oprávnění blokují zápis bezpečně.

Serverové RPC zůstávají v `public`; nevznikla Edge Function ani vlastní produkční
REST služba. SQL migrace je generována z kanonických souborů. Testovací loopback
adaptér v `web_client/scripts/scanner_integration_server.mjs` není součást produktu.
Provozní instrukce: [runbook](../runbooks/web-scanner.md).

## Ověření

| Seam / scénáře | Provedený důkaz |
|---|---|
| C01, C02, C17 - vstupy | Controller/input testy, skutečný pixelový QR decode lokální knihovnou, browser HID Enter skončí v result bez operation. Fyzický hardware je samostatná gate. |
| C03, C07, C08 - retry a generace | SQL accepted/replay/payload mismatch, skutečný admin unused a native/admin used wrappers; browser ztráta odpovědi po SQL commitu a reload obnoví stejný operation ID jako accepted. |
| C04, C05 - souběh | Dvě nezávislá PG spojení: jeden accepted, druhý already_used; další dvě konkurenční změny order eligibility pod kanonickým parent lockem čekají a odmítnou stale fingerprint. Nejde o test bankovního providera. |
| C06 - dvě zařízení | Browser A uloží pending offline, samostatná server session B přijme ticket, A se po sync změní na conflict/already_used. Historie zůstane zachována. |
| C09 - snapshot | SQL digests přes přesné UTF-8; browser skutečná IDB: nekompletní manifest i digest mismatch odmítnuty, původní active pointer zachován. |
| C10 - storage/crash | Browser zavření skutečné IDB connection před confirm: storage_write_failed, bez nové operation; restart a response-loss recovery. Node testy navíc explicitně odmítají unavailable storage. |
| C11, C12 - autorita | SQL scope/foreign bearer/snapshot, role a soukromé helpers; rotace skutečným update_scan_code, revoke, historické receipts; sync blokuje auth a zachová payload. Clock rollback/expiry ověřeny deterministicky. |
| C13 - nastavení | SQL all/none/selected, NULL/stale CAS, foreign IDs, canonical ticket-owned odpovědi bez leaků jiného držitele; skutečná duplicate_occasion remapuje produkty/form/field a nekopíruje secret/session. |
| C14 - routing/PWA | Sdílený resolver, router testy, generated-worker offline navigace všech scanner routes. Browser cold navigation na /scan z reálného generated PWA shellu načte 10,000-ticket snapshot bez Flutter requestu. Network failure přešel na source=offline. |
| C15 - dvě záložky | Skutečná browser IDB ve dvou záložkách: A lease generation 1 vyprší, B získá generation 2; pozdní update A vrátí false, pending se nezhorší. Node tests ověřují i terminal-state guard. |
| C16 - aktualizace | Nedestruktivní close/reopen, sending recovery a future operation schema zůstává uložené jako blocked_schema bez dispatch. Existující worker pinning/reconcile gates zůstávají zachované. |
| C18 - UI | Vizuálně prohlédnut mobil 390 a 320 px, desktop 1280 px, světlý/tmavý motiv, dlouhý text při 200% CSS zoomu a klávesnicový fokus. Při 320 px je CTA na 564 px a scrollWidth=viewportWidth=320. |

Provedené cílené kontroly:

- 72 JS testů scanner/router/startup/Supabase konfigurace a katalogového startupu, 0 failed/0 skipped,
  včetně lokálního decoderu a transient Auth recovery. SQL concurrency test v
  tomto počtu skutečně běžel.
- 6 SQL suites: čtyři `database/tests/scanning/*_test.sql`, současná autorizace
  programu a `reset_password_via_scan_authorization_test.sql`; 6 passed, 0 failed.
- Existující recepční Deno suites: 4 passed, 0 failed.
- PWA manifest/reconcile: 3 testy passed; `pwa_offline.test.mjs` prošel včetně
  scanner routes; `deploy_workflow.test.sh` prošel.
- Vite produkční web build prošel; žádný Flutter/release build nebyl spuštěn.
- Cílená Dart analýza čtyř změněných callers: bez errors/warnings, 18 lint infos.
- `git diff --check` pro dotčené scanner seams prošel.

Katalogový startup test je dokončený: ověřuje skutečný aktuální bootstrap,
zachování serverových odkazů, dostupnost retry po chybě, recovery callback a
idempotentní ready událost. Již nehledá odstraněný inline reveal skript.
Oba katalogové testy jsou zahrnuté v uvedených 72 passing testech.

[Galerie skutečného rozhraní](web-scanner-gallery-2026-10-18.html) obsahuje mobil,
desktop, oba motivy, offline pending, konflikt, storage failure a dlouhý text.
Je samostatná, funguje přímo ze souboru a obsahuje vložené skutečné screenshoty.

Databáze byla explicitně izolovaná: `festapp_scanner_20261018` na loopback portu
59132, PostgreSQL 15.8. Zdroj byl lokální integrační dataset, nikoli produkce.
Po schema restore byly doplněny původní ACL z lokálního zdroje; auth suites potom
prošly i s původními permissions. Nebyly měněny ani zastavovány jiné lokální DB.

Vizuální důkazy: [mobil](web-scanner-evidence-2026-10-18/mobile-result.png),
[320 px](web-scanner-evidence-2026-10-18/mobile-320-result.png),
[desktop](web-scanner-evidence-2026-10-18/desktop-result.png),
[offline pending + pravdivý počet](web-scanner-evidence-2026-10-18/mobile-offline-pending.png),
[konflikt](web-scanner-evidence-2026-10-18/offline-conflict.png),
[storage failure](web-scanner-evidence-2026-10-18/storage-failure.png),
[světlý motiv](web-scanner-evidence-2026-10-18/mobile-light.png),
[200% a dlouhý text](web-scanner-evidence-2026-10-18/zoom-200-long.png).

## Měření

Referenční host: Apple M5, macOS, agent-browser headless Chromium 151,
PostgreSQL na stejném hostu. Jde o lokální fixture, ne o výsledky cílového telefonu.

| Metrika | Naměřeno |
|---|---|
| Fixture | 10,000 ticketů / 1,000 pending operací |
| Snapshot payload | 4,350,801 UTF-8 bytes, přibližně 4.35 MB |
| Příprava snapshotu včetně přenosu, digestů a IDB aktivace | 539 ms |
| Lokální lookup, samostatný vzorek 20 čtení | průměr 77.8 ms, maximum 92.2 ms, včetně kontroly receipts overlay |
| Feedback po potvrzeném IDB commitu | 0.4 ms do dokončení renderu |
| Uložení 1,000 outbox položek | 1,970 ms |
| Sync 1,000 položek se skutečným per-operation abuse účtováním | 8,565 ms, 1,000 accepted / 0 conflicts |
| Běžný online lookup | 44.7 ms |
| RPC delta běžného vstupu | lookup_scanner_ticket=1, sync_scanner_operations=1; žádný snapshot/settings/summary refresh |
| Scanner JS chunks, všechny režimy + settings | 52.19 kB raw, 17.32 kB gzip |
| Scanner CSS | 12.57 kB raw / 3.14 kB gzip |
| Lazy lokální QR decoder | 130.73 kB raw / 47.28 kB gzip |

SQL symbol lookup na lokálních přibližně 20,000 tickets měl EXPLAIN ANALYZE
1.05 ms. Nepřidával se preventivní JSON index. Bundle scanneru a decoder se do
katalogového route nenačítají; při PWA instalaci je existující worker zahrne do
atomického shellu, aby byl možný cold start. Souhrn má throttling 15 s a automatický
snapshot rebuild odstup nejméně 60 s; potvrzení neprovádí globální COUNT.

Scanner shell se mountuje lokálně před síťovou inicializací Auth i při nepravdivém
online signálu. První skutečný RPC nadále používá normální ověření backendu.
Transientní chyba inicializace se může opakovat; nepřipne klienta k odmítnutému
promise navždy. Tato hranice má vlastní startup test.

## Cutover a hranice

- `/scan` odstraněn z JS Flutter handoff seznamu. Settings/history/offline/program,
  `/login-qr`, legacy code a programové deep links vlastní tentýž resolver.
- SW i deployment worker přebírají stejný resolver. Root slouží nejprve JS shell,
  protože server ani SW nedostanou hash; následný běžný forced-home handoff zůstává
  v routeru. Tím funguje i `/#/scan/...` bez tichého Flutter startu.
- Pevné Dart `specificFieldMappings` odstraněny, nativní reader čte uloženou
  konfiguraci. Konkrétní historické IDs/cenová výjimka jsou pouze v jednorázovém
  SQL backfillu, nikoli v runtime rozhodování podle linku.
- Recepční CDN decoder odstraněn. Scanner používá lokální lazy jsQR. Scanner route
  nespouští externí font stylesheets.
- Původní full-order scan/export nemají nové webové callers. Native signatury jsou
  zachované, admission sdílí parent-before-ticket primitive. Dart scan/check/login
  pages předají webovou úlohu ven a na webu nerenderují kameru.
- Produktové čerpání, odchody, obecný workflow/auth framework a V1/V2 přepínač
  nevznikly. Jediný registry scanner receipts je scanner_operations.

## Přesně zbývající gates

1. Před release spustit požadovaný celkový repo gate.
2. Fyzická kamera na Safari/iOS a Chrome/Android, reálná USB/Bluetooth HID čtečka,
   torch/camera-switch capability, kill/reopen a storage chování cílových zařízení.
   Headless decoder/input důkaz tyto kontroly nenahrazuje.
3. Samostatně autorizovaný jeden tenant: backup/DB identity, produkční migrace,
   lokální build, deployment přes automation/deploy_direct.sh a live-version smoke.
   Neprovádět další prod/* rollout ani commit/push implicitně.

Implementace se kvůli chybějícím fyzickým a produkčním gates neoznačuje release-ready.

## UI polish a živé demo - následné zadání

- UI/UX průchod podle `ui-ux-pro-max` a `ux-designer`: kompaktní značka a
  stavový řádek, navigace s aktivní linkou, přepínač vstupu, klidný prázdný stav,
  jasně odlišený stav vstupenky, držitel, produkt a potvrzení. Lokální SVG ikony,
  Futura a původní Festapp barevné tokeny v obou motivech; 48px ovládací prvky.
- Kamera má živý obraz, hledáček, nápovědu, explicitní zapnutí/vypnutí, přepnutí
  a capability-gated torch. Obnova souhrnu zachová stejný video element a stream;
  další vstupenka obnoví kameru. Zachování streamu má regresní test.
- Lokální fixture má oddělenou demo lištu s předvyplněným nepoužitým symbolem,
  tlačítkem „Vyzkoušet vstupenku“ a skutečným QR. Po potvrzení další pokus vybere
  další nepoužitý ticket. Neresetuje historii ani used tickets. Lišta ani pomocný
  SQL HTTP adapter nejsou součástí produkčního klienta.
- Browser prošel skutečný lookup -> IDB outbox -> SQL receipt accepted pro
  SCANNER-1236-10000; další výběr byl SCANNER-1236-9999. Šířky 390 a 320 px bez
  horizontálního overflow, na 320 px confirm končí na 760 px včetně demo lišty.
- Axe ve stabilním světlém i tmavém výsledku: 0 violations / 0 incomplete;
  kamerový pohled 0 violations / 2 incomplete (video/frame nelze automaticky
  plně posoudit). Živý stream byl automatizovaně ověřen syntetickým Chromium
  zdrojem, nikoli fyzickou kamerou: track live, video playing, šířka 640,
  stejný video element po recover(). Fyzická zařízení zůstávají samostatný gate.
- Cílený běh: 72 passed / 0 failed / 0 skipped, produkční Vite build prošel.

Aktuální důkazy:
[mobil](web-scanner-evidence-2026-10-18/polished-mobile-light.png),
[320 px](web-scanner-evidence-2026-10-18/polished-mobile-320.png),
[desktop](web-scanner-evidence-2026-10-18/polished-desktop-light.png),
[kamera se syntetickým testovacím obrazem](web-scanner-evidence-2026-10-18/polished-camera-synthetic.png).
Původní statická galerie zachycuje stav před tímto následným UI polish zadáním.
Živé demo: `http://127.0.0.1:5174/scan?camera=1`.

### Zjednodušení hlavní obrazovky

Kamera je výchozí vstup a dominuje první obrazovce. Nad ní zůstává pouze název,
nabídka a kompaktní průběh vstupů. Historie, offline, režimy zadávání, motiv
 a podrobné statistiky jsou v nabídce; kamera má samostatně sbalené ovládání.
Demo lišta je až pod aplikací. Ve 390 × 844 px začíná živý obraz na y=113 px,
bez horizontálního overflow. Výsledek stále na mobilu nahrazuje vstupní panel.
Ověřen regresní camera lifecycle test a vizuálně syntetický Chromium stream:
[snímek](web-scanner-evidence-2026-10-18/simple-camera-synthetic.png).

### Kontextová nabídka podle následné zpětné vazby

Samostatný HID/čtečka režim a jeho přepínač byly na výslovné následné zadání
odstraněny z rozhraní; běžné zadávání kódu zůstává standardní formulář.
Nabídka ve zdravém online stavu obsahuje pouze historii a motiv. Offline příprava
je pod sbalenými Dalšími možnostmi, nastavení jen podle oprávnění. Odesílání vstupů
se v hlavní nabídce ukáže až při pending, konfliktu nebo ztrátě připojení.
Manuální zadávání má kontextový návrat ke kameře a kamera odkaz na ruční zadání.
Ověřen mobile menu render a camera lifecycle test.

## Více QR, souvislá navigace a živé scénáře - následné zadání

Scanner zůstává soustředěné pracovní místo: návrat na hlavní stránku je stejný
odkaz jako v ostatním webovém klientu, název akce drží kontext. Nabídka označuje
nástroje kontroly vstupu; historie má vlastní nadpis a návrat ke kameře, pokročilé
nastavení vlastní stránku. Volba kamera/ručně je kontextová u vstupu a stav
synchronizace se ukazuje jen při problému. Globální účet ani přepínání účtů se do
pracovního scanneru nepřidávaly. Demo scénáře jsou oddělené ve spodní testovací
liště, nikoli v produktové navigaci.

Kamera nyní vyhledává až 12 různých QR payloadů z jednoho snímku. Lokální jsQR
se používá s maskováním rozpoznaných čtyřúhelníků, překryvnými oblastmi a druhým
průchodem pro sousední/otočené kódy. Originální snímek se nemění. Opakovaný kód
zůstává potlačen, dokud neopustí obraz nebo pracovník výslovně nepovolí opakování.
Pro větší skupinu je potřeba další záběr; rychlost a ostrost na cílových telefonech
nadále vyžadují fyzické ověření.

Každá položka skupiny má samostatný původní ScannerController, lookup, durable
outbox operation a receipt. Skupinový přehled je pouze UI, nevznikl další writer
ani serverový registry. Výběr položky zobrazí její detail. Potvrdit platné přeskočí
použité, chybné a nezaplacené položky; nezaplacený vstup nadále vyžaduje vlastní
checkbox a jednotlivé potvrzení. Jeden neplatný QR nezablokuje ostatní.

Lokální demo používá samostatnou fictional akci s 100 vstupenkami a různými jmény.
Scénáře: živá kamera, právě načtený lístek, potvrzený vstup, 3 platné, 3 potvrzené,
smíšená skupina a pending při simulované ztrátě sítě. QR panel nabízí skutečné
nepoužité symboly pro zobrazení na jiném displeji nebo tisk. Potvrzené scénáře
provádějí normální lokální SQL admission; pending má skutečný IDB záznam bez
receipt a po změně scénáře se normálně synchronizuje. Produkce se nepoužívá.

Ověření:
- 76 JS testů, 0 failed / 0 skipped, včetně 4 nových skutečných QR pixelových
  testů: více symbolů, rotace, duplicitní payload, široký záběr a opakované snímky.
- Browser syntetický canvas -> skutečný MediaStream/video -> scanner decoder ->
  3 správně přiřazené ticket lookup výsledky. Nejde o fyzický hardware test.
- Browser skupina 3 platných -> 3 nezávislé accepted receipts. Smíšená skupina
  potvrdila pouze platnou položku, použitá zůstala použitá a neznámá má error.
- Pending scénář: skutečná outbox položka pending, žádný receipt, navigator offline;
  přechod zpět na online scénář odeslal zachovaný záznam.
- Produkční Vite build a samostatný nový PWA fixture build prošly. Původní PWA
  artifact zůstává oddělený. Nová fixture toleruje nedostupné pomocné demo scénáře
  při offline startu; její metadata a překlady se při buildu vkládají lokálně.
- Axe na mobilní potvrzené skupině: 26 passed, 0 violations / 0 incomplete.

[Potvrzená skupina](web-scanner-evidence-2026-10-18/demo-group-accepted.png),
[pending](web-scanner-evidence-2026-10-18/demo-pending.png).
Živé demo: `http://127.0.0.1:5174/scan?scene=mixed`.

### Trvale živá kamera při výsledku - výslovná UX korekce

Na následný výslovný požadavek už live camera preview po lookup, při skupině,
chybě ani po potvrzení nemizí a nezastavuje se. Pozastaví se pouze QR decoding.
Stejný video element i MediaStream track přežijí všechny render/receipt přechody.
Další vstup pokračuje na stejném streamu. Stop, ruční režim, opuštění scanneru
 a dispose nadále kameru uvolní. Program/reception zachovávají výchozí stop-on-pause.

Kontrola podle ux-designer proběhla skutečně přes samostatného agenta
`gpt-6-astra` s `medium` reasoning. Obecná rada skillu o zmrazení feedu ustoupila
výslovnému zadání uživatele. Astra nenašla koncepční blocker v mobilním návrhu;
upozornila na krátký landscape a příliš malý detail při otevření controls.
Tato připomínka byla reprodukována a opravena: portrét má stabilní live náhled
 a samostatně posuvné výsledky, krátký landscape používá dva sloupce. Rozbalené
camera controls v landscape nepřekrývají live feed. Skupinové akce zůstávají pod
seznamem a u větších skupin vyžadují posunutí výsledkového panelu.

Důkazy: 77 JS passed / 0 failed / 0 skipped, Vite build passed; regresní testy
pokrývají zachování preview v looking_up/error/pending/accepted a group review,
ukončení při odchodu a oddělení paused decoderu od živého streamu. Browser
syntetický stream: skutečné group confirmation accepted, stejný video+track,
track live a rostoucí currentTime. Při 390 px je preview y=113-273, 320 px bez
horizontal overflow. V 844x390 s rozbalenými controls zůstává video y=113-191
 a výsledkový panel y=113-273. Axe: 0 violations, 2 incomplete (video obsah).
Fyzickou kameru toto automatizované ověření nenahrazuje.

[Aktuální náhled se syntetickým obrazem](web-scanner-evidence-2026-10-18/live-review-final-synthetic.png).

### Oprava zamčeného ručního zadávání

Přepnutí kamera/ručně nyní prochází stejným přechodem na další vstupenku jako
Next: ukončí pouze aktuální zobrazení výsledku/skupiny, přepne controller do ready
 a nastaví fokus do aktivního pole. Durable fronta se nemění. Během lookup/persist/
awaiting-server nelze režim přepnout uprostřed rozpracované operace. Regresní test
prošel pro samostatný výsledek i skupinu, včetně zadání a lookup dalšího symbolu.
Izolovaný mobilní browser: pole disabled=false, focused=true, ruční tlačítko Načíst vyhledalo
skutečnou platnou SCANNER-1281-85 přes lokální SQL adapter.

Obnova souhrnu navíc zachová rozepsaný symbol/jméno a fokus, aby klávesnicové zadávání nepřerušil background render.

### Zvuky, krátké potvrzení a podmíněná obnova hesla

Reset UI nyní vyžaduje AppConfig.isAppSupported, online lookup a explicitní
can_reset_password z RPC. Server odvozuje možnost ze stávajícího
organizations.data.IS_APP_SUPPORTED a přiřazeného neprivilegovaného účtu.
Stejnou kontrolu znovu provádí reset_scanner_password, takže skrytí UI není jedinou
zábranou. Privilegovaný target, vypnutá podpora a chybějící účet vracejí false.
Capability je jen v online lookup, nikoli v offline snapshotu. Žádný nový feature
přepínač ani nový reset writer nevznikl; nativní kontrakt je zachovaný.

Technický čas serverového commitu byl odebrán z běžného výsledku; zůstává
v historii/receiptu. Ostatní časy scanneru používají aktivní jazyk aplikace.
Po serverově accepted potvrzení se zobrazí výsledek 1200 ms a pokračuje se dál na
stejném živém streamu. Automatický přechod nenastává při pending, chybném výsledku
ani nevyřešené smíšené skupině. Periodické receipt refresh nepípají znovu.

ScannerFeedback lokálně syntetizuje skutečné Web Audio tóny: 880 Hz pro platný
lookup, 880/1175 Hz pro potvrzení a 220/165 Hz pro chybu. Žádný externí zvukový
soubor ani speech služba. AudioContext se odemyká uživatelským gestem; nabídka má
Zapnout zvuk/Zvuk zapnutý/Zvuk vypnutý. Demo ovladače odemykají audio také, aby
šly zvuky zkoušet scénáři. Zvuk nenahrazuje vizuální stav.

Ověření: 81 JS passed, 0 failed/skipped; 7 SQL suites prošlo (6 zachovaných a nový
password capability test po opravě syntaxe testu). Vite build prošel. Lokální
browser: AudioContext running, skutečná accepted receipt -> po 1200 ms ready,
žádný technický čas ani reset v neapp demo akci, stream live a decoder opět ready.
Samostatný test ověřuje odlišné frekvence a zákaz auto-advance u pending/chyb.
SQL byl aplikován výhradně do explicitní izolované lokální scanner databáze;
produkční migrace ani deploy se neprováděly.

### Ruční zadání jako jednorázová výjimka

Po potvrzeném ručním vstupu se scanner vrací do primárního kamerového režimu.
Pokud kamera už byla používaná, obnoví stream; pokud nikdy spuštěná nebyla,
automatický návrat pouze nabídne kameru bez vynuceného permission promptu.
Při zamítnuté/nedostupné kameře zůstává ruční fallback. Neplatný kód uživatele
nepřepíná a dovolí opravu. Prázdný výsledkový panel v ručním ready stavu je pryč;
zůstává kompaktní formulář, nenápadný návrat ke kameře a krátké vysvětlení návratu.
Pět targeted lifecycle/feedback testů prošlo, včetně všech tří camera fallback
variant. Browser ověřil skutečný manual lookup -> accepted -> camera ready/live.
