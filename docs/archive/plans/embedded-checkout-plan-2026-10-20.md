# Embedded objednávkový formulář

Datum: 2026-10-20  
Stav: Lokální implementace dokončena a ověřena, produkce beze změny  
Verification: standard - veřejný integrační kontrakt a objednávkový tok

## Výsledek a rozsah

Pořadatel v nastavení uloženého formuláře zkopíruje HTML kód na svůj web.
Návštěvník na tomto webu vybere vstupenky, případně sedadla, vyplní formulář,
zkontroluje objednávku a uvidí potvrzení a platební údaje včetně QR.
Podporované budou dvě podoby: samotný iframe s pevnou výškou a iframe
s malým pomocným skriptem pro automatickou výšku a posouvání.

Jde o doplnění prezentace stávajícího veřejného formuláře. Zachovat stejný
FormPage, FormSession, kapacity, rezervace, odesílání objednávky a backendové
autorizace. Nezavádět druhý checkout ani novou platební implementaci.

Mimo rozsah: nákupní tlačítko otevírající překryv přes celý cizí web,
integrace karetní brány, přihlášení/OAuth uvnitř embedu, vlastní CSS pořadatele,
analytické integrace, seznam povolených domén a ukládání nových nastavení do DB.
Vzhled přebírá uložené nastavení formuláře. Identita organizátora a právní
informace zůstávají dostupné.

Tento úkol opravňuje k přípravě plánu. Implementace, commit, push a produkční
nasazení jsou samostatné následné kroky. Žádné jiné tenanty nerozšiřovat.

## Zjištěný stav

| Fakt a důkaz v repozitáři | Důsledek |
|---|---|
| `web_client/src/services/router_service.js`: `/form/`, `handleInitialLoad`, `navigateToForm`, obsluha historie | Použít existující URL, prověřit všechny vstupy a zachování query parametrů. |
| `web_client/src/services/public_link.js`: `canonicalPublicPath`, `replaceResolvedPublicLink` zachovávají query a fragment | Kanonizace slugu nesmí vypnout embed režim ani ztratit capability fragment. |
| `main.js`, `startup/initialize_core_services.js`, `components/users/user_header.js`: inicializace práv, hlavičky a auth | Pouhé skrytí hlavičky CSS nestačí; embed musí mít explicitní veřejný start. |
| `components/forms/form_page.js`: `preview=true`, načítání práv, edit tlačítko, formulář a výsledkové overlaye | V embedu nevykreslovat administraci ani editor preview; běžný formulář zůstává stejný. |
| `components/forms/db_forms.js`: `get_form_by_link`, `get_blueprint`, `select_spot` | Metadata, secret a rezervace patří současným RPC, nikoliv hostitelskému webu. |
| `components/eshop/db_orders.js`: `sendOrder` volá `send-ticket-order` s commandId/clientId | Zachovat existující příkazovou a autorizační hranici. |
| `components/eshop/ticket_order_identity.js`: fingerprint příkazu, vazba na principal, zachování identity při neurčitém výsledku | Pomocný skript nesmí objednávku odesílat, opakovat nebo získávat její payload. |
| `services/browser_storage.js` a jeho testy: náhradní paměťové úložiště při blokování storage | Základ už existuje; paměť nepřežije reload a není zárukou obnovy objednávky. |
| `form_page.js` používá transform containment; `order_preview.css` a `blueprint.css` používají fixed overlaye | Nutná úprava dialogů pro dlouhý iframe, nikoliv jen měření jeho výšky. |
| `web_client/public/_headers`, `web/_headers`: CSP bez frame-ancestors a bez X-Frame-Options | Zdrojové hlavičky embed neblokují; nepovolovat embedding globálním oslabením dalších ochran. |
| `lib/components/forms/views/form_public_link.dart`: uložený savedLink oddělený od draftu; `form_settings_content.dart` jej předává | Kopírovací UI navázat výhradně na skutečně uloženou adresu. |

Reprezentativní průchod: Main -> RouterService -> FormPage -> DbForms ->
FormSession -> OrderPreview -> FormNetwork -> DbOrders -> send-ticket-order ->
existující SQL objednávky -> OrderResult. Embed přidává pouze kontext prezentace
a komunikační adaptér kolem tohoto průchodu.

Zdrojové soubory byly prohlédnuté v pracovním stromu s mnoha existujícími
změnami. Implementátor musí zachovat cizí rozpracovanou práci. Žádný skutečný
nákup v iframe nebyl v rámci plánování otestován. Dřívější HTTP probe na
neexistující `/form/embed-probe` vrátil 404 bez frame restrikce; není důkazem
funkčnosti konkrétního nasazeného formuláře.

## Cílový kontrakt a invarianty

### URL a start

- Jediný embed vstup: existující `/form/<encoded-saved-slug>?embed=1`.
  Režim je explicitní a nespoléhá na detekci `window.top`.
- Samostatný malý `services/embed_context.js` vlastní parsování kontextu.
  Použít jej v bootstrapu, routeru a FormPage. Parametr nemění oprávnění,
  dostupnost formuláře, cenu, tenant ani backendovou aktivaci.
- V režimu embed nespouštět organizer intent, OAuth pokračování, admin navigaci
  nebo editor preview. `preview=true` ignorovat. Nezískávat ani neposílat
  přihlašovací tokeny rodičovské stránky. Potřebné veřejné backendové služby
  a kontrola backend-activation zůstávají aktivní.
- Nákup funguje bez přihlášení; izolace veřejného UI nesmí skrytě změnit
  principal rozpracovaného příkazu. Nepřepínat automaticky existující session
  ani neodhlašovat uživatele. Ověřit chování s existující session i bez ní.
- Zachovat query při interním přechodu na formulář, reloadu a kanonizaci.
  Capability fragmenty objednávky/waitlistu zůstávají pouze v iframe.
  V embed režimu žádná interní navigace nepřejde do Flutter administrace.

### Iframe a pomocný skript

- Pevná varianta funguje bez skriptu: iframe s title, šířkou 100 %, rozumnou
  výškou (výchozí 800 px) a interním posouváním. Vedle něj obyčejný odkaz
  „Otevřít objednávku v nové záložce“ na veřejný formulář bez embed parametru.
  Odkaz neobsahuje session secret ani osobní capability.
- Doporučená varianta používá tentýž iframe označený `data-festapp-embed`
  a externí deferred skript `/embed.js` ze stejného tenant hostu jako formulář.
  Ten je samostatný veřejný vanilla JS asset, bez importu aplikace a bez
  závislosti na jejím globálním stavu. Žádné inline JS nevyžadovat.
- Skript lze vložit vícekrát bez duplicitních listenerů; obslouží více iframe
  instancí nezávisle. Selhání nebo blokování skriptu ponechá pevný iframe
  a samostatný odkaz použitelné. URL odvozovat z tenantu, nikdy natvrdo
  z vstupenky.online. Vite musí asset zachovat a release bundle jej zahrnout.
- Protokol: zprávy se jmenným prostorem `festapp-embed`, `protocol: 1`, typem
  a identifikátorem instance. Child vyšle pouze neosobní `ready`; rodič po
  ověření source/origin pošle `init`. Child přijme init pouze od window.parent,
  zapamatuje skutečný origin odesílatele a identifikátor a další komunikaci
  adresuje přesně tomuto originu. Nepřebírat cílový origin z libovolné URL.
- Rodič porovnává `event.source` s konkrétním iframe.contentWindow a origin
  s originem jeho deklarované src. Obě strany kontrolují namespace, verzi,
  instance ID, typ i rozsah hodnot. Child po navázání ignoruje jiné originy.
  Handshake ošetří obě pořadí načtení a reload iframe s omezeným počtem pokusů.
  Opaque/null origin pro automatickou integraci odmítnout; pevný režim zůstává.
- Zprávy pouze `ready`, `init`, `viewport`, `resize`, `scroll-request`.
  `init` a následné rodičovské `viewport` nesou výšku hostitelského viewportu
  v CSS px v mezích 240-4000; jiné hodnoty child ignoruje a ponechá místní
  výchozí rozměr. Aktualizace viewportu dávkovat přes RAF.
  Žádné osobní údaje,
  objednávkové tokeny, session secrety, JWT, payloady ani stavy plateb rodiči.
  Rodič nemůže předvyplnit formulář, vybrat sedadlo či odeslat objednávku.
- Child měří skutečný obsah přes ResizeObserver s RAF dávkováním a cleanup.
  Rodič přijímá konečnou kladnou výšku v mezích 240-20000 px a změnu aplikuje
  jen při skutečném rozdílu. Nad limitem zůstane vnitřní scroll. Zabránit
  zpětné vazbě způsobené min-height:100vh nebo výškou odvozenou od iframe.
- `scroll-request` obsahuje pouze ověřené číselné souřadnice uvnitř iframe.
  Posouvat na validační chybu nebo nově otevřený krok po akci návštěvníka,
  nikoliv při každém resize či prvním načtení. Respektovat reduced motion.

### Obsah, dialogy a objednávka

- V automaticky vysokém embedu použít pro rekapitulaci a výsledek prezentaci
  v toku dokumentu. Plánek mít jako lokální panel s omezenou výškou vůči
  hostitelskému viewportu (ověřený viewport údaj v init a jeho aktualizaci),
  vlastními ovládacími prvky a interním pan/zoom. Nepřidávat druhou obchodní
  implementaci těchto komponent. Pevný iframe musí fungovat bez handshake;
  pro něj rozměry odvozovat od vlastního viewportu.
- Prověřit i podřízené dialogy, organizátorskou identitu, kalendáře, loadery,
  validaci a waitlist/order fragmenty. Každý fixed prvek veřejného toku musí
  být dosažitelný v obou variantách. Focus, Escape a návrat zpět zachovají
  ovládání klávesnicí; nezamykat document rodiče.
- Stávající FormSession, ceny, kapacity a seat locking zůstávají autoritativně
  na současných hranicích. Žádné SQL migrace se nepředpokládají.
- Zachovat commandId/clientId při retry po neurčité odpovědi. Po timeoutu
  automaticky neobnovovat iframe ani neopakovat nákup pomocným skriptem.
  Při blokovaném trvalém storage platí současná mez: identita přežije jen
  životnost stránky. Neslibovat exactly-once přes reload; UI nesmí doporučit
  reload a nový nákup jako automatické zotavení z neurčitého výsledku.
  Případnou širší obnovu řešit zvlášť, nikoliv novým objednávkovým endpointem.

## Rozhodnutí, předpoklady a hranice

- Rozhodnutí: veřejný formulář lze vložit na libovolný HTTPS web. Allowlist
  domén není součást první verze. Origin handshake chrání protokol, není
  autentizací pořadatele a nechrání před samotným škodlivým hostitelem.
- Rozhodnutí: základní iframe a doporučený skript jsou dva záměrné integrační
  způsoby jednoho kontraktu, nikoliv dočasné paralelní checkouty.
- Předpoklad: cílový CMS povolí iframe; pro automatickou výšku také externí
  script a odpovídající CSP frame-src/script-src. Pokud script zakáže,
  použije se pevný režim. Pokud zakáže iframe, zbývá veřejný odkaz.
- Předpoklad: současný bankovní převod/QR nevyžaduje platební navigaci.
  Karetní brány a bankovní aplikace se tímto plánem negarantují.
- Před implementací omezeně dohledat všechny veřejné overlaye, historii a
  skutečné sestavení release bundle. Jde o konkrétní domyšlení adaptérů,
  nikoliv nový průzkum celé architektury. Změní-li se faktická premisa,
  aktualizovat tento plán před rozšířením implementace.
- Žádný blokátor pro lokální implementaci. Produkční ověření čeká na výběr
  konkrétního tenantu a samostatné povolení nasazení.

## Implementační vlny

### 1. Veřejný embed kontext

Změny: přidat embed_context.js; propojit main.js, initialize_core_services.js,
RouterService, UserHeader a FormPage. Nastavit kontext před upgradem custom
elementů nebo zabránit jejich připojení v embedu. Oddělit veřejný start od
organizer intent, editor preview a administračních odkazů. Nevyřazovat
backend aktivaci, lokalizaci nebo současnou session příkazů.

Validace: cílené Node testy bootstrapu, routování a public_link; pokrýt
embed+preview, existující session, chybějící session, slug redirect,
reload a historii. Regrese běžného startu musí zůstat pokrytá.
Exit: existující formulář lze otevřít v pevném iframe bez hlavičky/admin UI,
se stejnými backendovými hranicemi. Migrace a odstranění: žádné DB změny.

### Doložená oprava premisy při implementaci

Při prvním cross-site průchodu měl iframe výšku 240 px a prázdný viditelný
obsah: `index.html` skrývá `#form-page-container` inline přes `display:none`,
ale aktuální `FormPage.init` po zavedení identity shellu nastavoval display
jen na novém vnitřním `this.host`. Vlna 2 proto explicitně odkryje `pageHost`
a přidává regresní kontrolu i pro běžnou samostatnou stránku. Nejde o novou
obchodní cestu ani backendovou změnu.

Syntetický nákup se sedadlem dále vrátil `REQUIRED_FIELD_MISSING` pro uložené
povinné pole `spot`: `FormSession.payload` posílal pouze `ticket.spot`, zatímco
`validate_waitlist_answers_internal` vyžaduje také odpověď pod ID pole.
Vlna 2 doplňuje toto ID do stávajícího payloadu; `ticket.spot`, secret,
commandId/clientId i SQL finalizer zůstávají stejné. Bez migrace nebo nového RPC.

### 2. Dokončení nákupu uvnitř iframe

Změny: kontext předat existujícím komponentám formuláře, OrderPreview,
OrderResult a blueprintu. Přidat lokálně omezené embed styly a prezentační
adaptéry. Upravit focus, měření obsahu, historii overlayů a zachování kontextu.
Sestavit jednu konkrétní mapu ostatních veřejných dialogů při implementaci
a všechny dosažitelné z formuláře přizpůsobit.

Validace: cílené komponentové testy změněných lifecycle/history cest,
testy stejné identity příkazu při opakování po timeoutu a blokovaném storage.
Exit: v pevném iframe lze od výběru produktu/sedadla dojít k výsledku a QR,
včetně chyb, nedostupného formuláře, waitlistu a návratu. Běžná stránka si
zachová současnou prezentaci. Žádné nové retry/objednávkové endpointy.

### 3. Automatická výška a scroll protokol

Změny: přidat public/embed.js a services/embed_bridge.js, měření kontejneru,
handshake, viewport aktualizace a scroll-request. Připojení/odpojení adaptérů
vázat na lifecycle stránky. Ověřit zahrnutí assetu v build_web_bundle.sh;
upravovat tooling pouze pokud kopírování public assetů dnes nestačí.

Validace: Node/jsdom testy skutečného protokolu: cizí origin/source, malformed
payload, NaN/negativní/obří rozměry, dvě instance, dvojí script, obě pořadí
načtení, reload, cleanup a zablokovaný script. Výškové oscilace a skutečný
viewport prokázat později prohlížečem, nikoliv tvrdit z jsdom.
Exit: rodič pracuje pouze s vlastními iframe a neosobními událostmi;
selhání handshake neblokuje pevný režim. Produkční cache `/embed.js` musí
umožnit aktualizace; budoucí změny zachovají protocol:1 nebo explicitně
navrhnou kompatibilitu před změnou veřejného assetu.

### 4. Kopírování kódu v administraci

Změny: FormPublicLink rozšířit o akci „Vložit na vlastní web“ s výběrem
automatické/pevné varianty, kopírovatelným kódem a krátkým vysvětlením.
Použít existující AppDialog a CopyButton, FormStrings a všech šest jazyků
podle pravidel lokalizace repozitáře. Generování URL a HTML oddělit do
malého testovatelného helperu; správně escapovat HTML atributy.

Kód generovat jen ze savedLink. Neuložený draft zobrazí výzvu k uložení,
nikoliv nefunkční embed. Zachovat UI rozlišení uložené/draft adresy.
Nepřidávat nastavení do DB. Snippet obsahuje title a veřejný záložní odkaz;
nepoužívat blanket sandbox bez ověření jeho dopadu na formuláře a download.

Validace: doplnit test/components/forms/public_link_settings_cases.dart
o uložený/draft/nový formulář, tenant URL, encoding a obě varianty snippetu.
Exit: pořadatel zkopíruje použitelný kód pro uložený formulář a neuvidí
neuložený slug jako publikovatelnou adresu.

### 5. Integrační důkaz a dokumentace

Změny: přidat integrační fixture s hostitelskou stránkou na jiném site než
aplikace (pouhý jiný port neověří third-party storage). Podle místního
runbooku použít syntetický tenant a disposable backend, bez skutečných
objednávek, emailů nebo plateb v produkci. Pro automatické prohlížení
izolovaný headless agent-browser; respektovat festapp-local-e2e skill,
existující server a pravidla deterministických E2E gateů.

Ověřit desktop i úzký mobil, pevnou i automatickou variantu, dlouhý formulář,
sedadla/zoom, klávesnici, chybu validace, nedostupnou kapacitu, rekapitulaci,
výsledek/QR/download, dva embedy a blokované storage. Ověřit skutečný cross-site
kontext a uvést zvlášť testovaný engine a případné neověřené Safari/iOS chování.
Zakázaný script a odmítnutý handshake nesmějí znemožnit základní formulář.
Při neurčité odpovědi ověřit retry se stejnou identitou a jediný backendový
výsledek, ne automatickou duplikaci objednávky.

Přidat stručnou uživatelskou příručku pro vložení/CMS/CSP a technický kontrakt
do docs; lib/components/forms/README.md na kontrakt pouze odkáže.
Exit: kompletní syntetický nákup má zaznamenaný důkaz a omezení; běžný
samostatný formulář a administrace mají cílený regresní důkaz.

## Odstranění a zachování

| Oblast | Akce a důkaz |
|---|---|
| Existující samostatné /form URL a obchodní služby | Zachovat; regresní testy běžného formuláře. |
| Pevný iframe | Zachovat jako dokumentovanou integraci bez scriptu. |
| Případné inline embed detekce, duplicate resize listenery nebo experimentální implementace | Nahradit jedním EmbedContext a EmbedBridge; prokázat scoped rg a lifecycle testy. |
| Globální transform/fixed containment v FormPage | Ponechat nebo upravit jen podle prokázaného layoutu; odstranit pouze skutečně nahrazené embed workaroundy bez změny běžných dialogů. |
| DB, RPC, email/platební služby, tenant konfigurace | Žádné migrační ani destruktivní změny v tomto plánu. |

## Ověření, rollout a dokončení

Při plánování nebyly spouštěny testy ani buildy. Při implementaci validovat
po ucelených vlnách, neopakovat stejné úspěšné testy bez změny pokrytého kódu.

- JS: cílené `node --test` soubory při vývoji; před předáním jednou
  `npm test --prefix web_client` a `npm run build --prefix web_client`.
- Dart: `fvm dart analyze` pouze změněné soubory a příslušný test formuláře
  přes `fvm flutter test --concurrency=1`. Před Flutter úlohou zkontrolovat
  globální slot; nikdy nespouštět dvě Flutter úlohy současně.
- Prohlížeč: jeden souvislý průchod matice výše; chybějící engine nebo
  cross-site test uvést jako neověřené, nenahrazovat tvrzením z unit testů.
- Produkce až samostatně: konkrétní tenant, canonical main/tenant ancestry,
  lokální build a automation/deploy_direct.sh podle aktuálních pravidel.
  Rutinní nasazení delegovat dle AGENTS.md. Žádný GitHub deploy dispatch.
  Ověřit hlavičky skutečné form URL, dostupnost /embed.js a syntetický
  bezpečný smoke. Neprovádět neautorizované produkční nákupy.
- Rollback: vrátit příslušný aplikační bundle. Existující běžná URL funguje
  nadále; kopírované iframe mají pevnou výšku a záložní odkaz i bez scriptu.
  Nevytvářet nový backend ani rollback migraci.

Hotovo pro lokální implementaci znamená: obě integrační varianty mají tentýž
objednávkový tok, bezpečný a otestovaný protokol, dosažitelná dialogová UI,
kopírování pouze uloženého odkazu, dokumentaci, úspěšné cílené kontroly
a konkrétní důkaz cross-site nákupu. Implementace a produkční nasazení
se vykazují odděleně. Po dokončení archivovat tento plán podle lifecycle docs.

Zbytková rizika: pravidla konkrétního CMS a CSP hostitele, rozdíly mobilních
prohlížečů, ztráta paměťové identity po reloadu při zakázaném storage,
a budoucí platební metody vyžadující opuštění iframe. Tyto limity nesmí
být v uživatelské příručce prezentovány jako vyřešené.


## Výsledek implementace

Dokončeno lokálně 2026-10-20. Obě integrační varianty používají tentýž checkout;
protokol, administrátorské kopírování, syntetický cross-site nákup a cílené
kontroly mají [zaznamenaný důkaz a přesná omezení](../evidence/embedded-checkout-2026-10-20/verification.md).
Veřejný kontrakt vlastní [aktuální průvodce](../../integrations/embedded-checkout.md).
Bez produkčního nasazení, commitu nebo push. Neověřené enginy, nabídka waitlistu,
CMS a storage recovery přes reload zůstávají výslovně omezením, ne hotovou garancí.


## Integrace na aktuální main

Při integraci na main 48d8b6db0 se změnila autoritativní cesta osobních odkazů:
main už používá `/order?order_id=...&token=...`, nikoli osobní fragmenty pod
`/form`. Embed zachovává tuto novou hranici a přenáší pouze `embed=1` do
kanonického přehledu. Staré fragmenty zůstávají odmítnuté. Veřejný vstup
snippetu zůstává `/form/<saved-slug>?embed=1`; admin preview nabídky je v embedu
odmítnuté. Novější waitlist rekapitulace, demo simulace, štítky, navigace a
opravy zavírání plánku na main jsou zachované. Původní screenshoty a browser
matice jsou datovaným důkazem původní implementace, nikoli novým měřením mainu.
