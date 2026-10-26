> Historický plán. Veřejnou prezentaci služby dnes vlastní homepage `/`; pro aktuální směrování platí `automation/release/organizers/README.md`. Tento dokument není zadání k obnově původní samostatné stránky.

# Stránka pro pořadatele a dokončení katalogu

Datum: 2026-10-15. Stav: implementováno lokálně, bez publikace.
Ověření: low-risk pro vzhled; standard pro zapojení společného bootstrapu, přihlášení a případné produkční nasazení.

## Výsledek a rozsah

1. Nadpis katalogu bude přesně „Proběhlé události“, bez celkového počtu v závorce a bez modré oddělovací čáry. Zachovat viditelné karty a dělení podle roku od 9 akcí ve více letech. Požadavek na odstranění počtu se týká hlavního nadpisu archivu; roční členění zachovat.
2. `/pro-poradatele` bude plnohodnotná, vizuálně propracovaná součást vstupenky.online se stejnou funkční hlavičkou jako katalog. Přihlášený uživatel má existující „Moje akce“ a profil, host existující přihlášení. Logo, barvy, písmo i téma vycházejí z konfigurace tenantu; screenshot není zadání přepsat značku natvrdo na festapp.
3. Výsledkem jedné session je dokončená implementace a ověření. Pokud zadání session zahrnuje nasazení, dokončit je pouze pro `prod/festapptickets`; žádné další tenanty.

Teď se vytváří pouze plán. Žádné změny aplikace ani nové nasazení tento dokument neprovedl. Nezasahovat do objednávek, cen, databáze, oprávnění, Flutter navigace ani jiné administrace. Nevymýšlet reference, metriky, ceny a screenshoty produktu.

## Ověřený výchozí stav

- Sdílený main: `acb70361f2a724e6a811ee6d0dfeb75a6d206a19`; nasazený tenant: `b3af34f6598da0fc913208b237d7e9c465781d19`, verze `0.20.215+699`. Před prací fetch a přizpůsobit případnému posunu upstreamu.
- `web_client/src/components/unit/unit_page.js`, `renderSection`: hlavnímu nadpisu přidává `(${list.length})`. Stejný počet vytváří SSR `handleHome` v `automation/cloudflare_build.sh`.
- `web_client/src/components/unit/unit_page.css`: `.catalog-archive` má `border-top:1px solid var(--primary-color)`. To je modrá čára ze screenshotu.
- `automation/release/organizers/page.html` má vlastní zjednodušenou hlavičku. `render_organizer_page.mjs` vytváří statický dokument, přebírá jen Vite CSS; společný JS/bootstrap stránky se nespouští.
- Skutečná hlavička je `web_client/src/components/users/user_header.js` + CSS. Odebírá stav `RightsService`; aktivaci backendu a první načtení práv vlastní `initializeCoreServices` volané z `web_client/src/main.js`. Nelze bezpečně jen vložit tag hlavičky a spustit druhou vlastní inicializaci auth.
- `Main.init` po společném bootstrapu řeší router a katalog. Stránka pro pořadatele musí mít explicitní větev před tímto směrováním, jinak ji aplikace může nahradit katalogem/formulářem/Flutterem.
- PWA už má opravené mapování veřejného dokumentu `/pro-poradatele` v `automation/lib/pwa_shell_manifest.mjs` a `generate_pwa_service_worker.mjs`. Zachovat je.
- Původní pracovní strom má mnoho nesouvisejících změn. Pracovat v čistém worktree z aktuálního mainu, nepřebírat jeho celkový diff. Předchozí čistý release worktree je `/tmp/festapp-seo-followup-20261015`.

## Cílové řešení a vizuální směr

- Použít existující `<user-header>` a tentýž Vite vstup/bootstrap. Generovaný dokument označit jednoznačným typem stránky. `Main.init` po společné inicializaci rozpozná stránku pro pořadatele a ukončí startup bez spuštění katalogu či routerového fallbacku. Nedělat kopii přihlášení, práv, menu ani další backend klient.
- Generátor převezme z výsledného Vite HTML skutečný fingerprintovaný module entry a potřebné CSS. Žádné natvrdo zadané hashe, další build písma či paralelní implementace headeru. Statický obsah a odkazy zůstanou čitelné i před JS nebo při selhání backendu; hlavička se nesmí ztratit při pomalé inicializaci. Případný statický fallback hlavičky nahradit upgradem komponentu, nezobrazovat dvě hlavičky.
- Zachovat navigaci a její chování při přechodu z katalogu. Změna nesmí plošně měnit výšku, styl či akce společné hlavičky. Pokud komponent nyní přidává skrytý H1 značky, na obsahové stránce použít neheadingový prvek: jediný hlavní H1 patří obsahu stránky.
- Pod hlavičkou vytvořit kompaktní úvod s jasným příslibem „Prodej vstupenek a registrace na akce“, krátkým vysvětlením a dominantním CTA „Založit akci“. Sekundární cesta vede na existující kontakt. Ukázat praktický průběh založení, správy objednávek a odbavení v přehledné kompozici; nepoužít prostý dlouhý seznam textových bloků ani nekonečnou mřížku stejných karet.
- Využít dostatek prostoru, zarovnanou obsahovou mřížku, promyšlené rozdíly ve velikosti nadpisů, krátké texty a kvalitní stavy odkazů/tlačítek. Nejvýraznější je akce, podpůrné informace ustupují. Bez dekorativních modrých oddělovačů. Obsah strukturovat: úvod, průběh/praktické možnosti, cena a kontakt, stručné FAQ a právní patička. Dlouhý právní text nepřesouvat do úvodu.
- CSS nového obsahu omezit pod vlastní třídu, aby nepřepisovalo společnou hlavičku, modály, tlačítka a obecné nadpisy aplikace. `ThemeService` zůstává vlastníkem motivu; odstranit současné konkurenční přepisování barev stránky podle systémového motivu, které ignoruje uloženou volbu.
- Mobil: žádný vodorovný scroll, jedna čitelná obsahová osa, pohodlné cíle, funkční menu. Světlé i tmavé téma musí mít použitelný kontrast. Zachovat tenantové fonty/logo, existující cenu na dotaz a pravdivé údaje poskytovatele.

## Postup v jedné session

### 1. Katalog

Upravit klientský nadpis i SSR a odstranit pouze border archivu. Zachovat roční skupiny, řazení, všechny karty i odkazy. Aktualizovat existující katalogové a SSR testy. Hotovo: klient i server mají shodný nadpis bez `(47)` a archiv bez modré čáry.

### 2. Společná hlavička a dokončený redesign

Upravit `page.html`, `page.css`, generátor a malou explicitní větev v `Main.init`. Nejprve zajistit skutečnou hlavičku a bezpečný startup, potom provést celý výše popsaný vizuální návrh. Odstranit starý `.organizer-header`, nepoužívané styly a konfliktní vlastní theme overrides. Zachovat statické SEO HTML, canonical, sitemap, URL a CTA `/?create=1`; již existující intent rozhoduje o registraci/správě. Zpřehlednit vysvětlení u CTA, neukazovat uživateli implementační text o „ověřování dostupnosti po otevření aplikace“.

Hotovo: přímé načtení, proklik z katalogu i zpět fungují; společná hlavička respektuje přihlášení a téma; obsah nenahrazuje router a nevytváří duplicitní H1.

### 3. Jeden souvislý ověřovací blok a vizuální doladění

- Existující `node --test web_client/tests/components/catalog.test.js automation/tests/public_seo.test.mjs automation/tests/organizer_page.test.mjs` a `node automation/tests/pwa_offline.test.mjs`. Doplnit významný regresní scénář startupu stránky: žádné načtení katalogu/routerového fallbacku, sdílená inicializace pouze jednou; zachovat existující startup testy podle příslušného npm scriptu.
- Jeden Vite build po dokončení změn. Ověřit skutečný generovaný HTML výstup a jeho module/CSS assety, nejen fragment šablony. Další plný běh sady jen pokud jej vyžaduje CONTRIBUTING nebo nové změny zneplatní předchozí důkazy.
- Izolovaný headless `agent-browser`: desktop 1440 px a mobil 390 px, obě témata. Screenshot je zde nutný pro posouzení vzhledu. Bez manipulace s uživatelovým prohlížečem. Zkontrolovat mezery, typografii, první obrazovku, header a případné překryvy při scrollu.
- Projít hosta i přihlášeného uživatele s autorizovanou testovací identitou; použít existující lokální E2E prostředí, pokud je pro přihlášení potřeba. Bez nové produkční registrace, objednávky nebo změny práv. Nemá-li session testovací identitu, ověřit stav právy řízeného headeru cíleným testem a omezení v závěru výslovně uvést.
- Ověřit kliknutí „Pro pořadatele“ pod aktivní PWA, přímé načtení, zpět do katalogu, CTA, „Moje akce“/profil a přihlášení; žádný odkaz nesmí skončit prázdnou stránkou. Ponechat čitelný obsah i při nedostupnosti backendu.

### 4. Publikace, pokud ji zadání session zahrnuje

Aktuální main a jediný tenant `prod/festapptickets`, kanonická ancestry a main-owned drift check. Respektovat GitHub ochrany: použít PR, je-li vyžadován; předchozí jednorázová výjimka review pro PR #424 není trvalá výjimka. Lokální Flutter/Vite build přes existující skripty a přímé `automation/deploy_direct.sh`, žádný GitHub-hosted produkční build. Verzi odvodit z tehdy aktuální produkce. Zachovat chráněný lokální manifest, neuvádět jeho hodnoty do logů. Po nasazení coherent live probes a jeden skutečný browser smoke finálního katalogu a stránky pořadatele; ukončit testovací browser.

## Akceptace a předání

- Archiv bez celkového počtu a modré čáry, se zachovaným ročním členěním a všemi událostmi.
- Stránka pro pořadatele působí jako součást produktu: skutečná společná hlavička, stavy účtu, téma, přesvědčivá hierarchie a dotažený mobilní vzhled.
- Není ponechaná stará samostatná hlavička, druhý auth/bootstrap, konkurenční téma ani náhradní veřejná URL.
- Handoff stručně uvede změny, provedené kontroly, odkazy na finální desktop/mobil screenshoty a při nasazení verzi, main/tenant SHA a live výsledek. Žádné deklarování hotového redesignu jen podle procházejících unit testů.


## Dokončení implementace 2026-10-15

- Pracovní větev `feat/organizers-ui-20261015`, izolovaný worktree `/tmp/festapp-organizers-ui-20261015`, základ po fetch `acb70361f2a724e6a811ee6d0dfeb75a6d206a19`. Původní pracovní strom zůstal nedotčený. Změny nejsou commitnuté ani publikované.
- Archiv má shodný klientský a SSR nadpis „Proběhlé události“, bez celkového počtu a borderu; roční skupiny a všechny karty zachovány.
- Stránka má skutečný `user-header`, statický obsah, jediný H1, společné fingerprintované CSS/JS a existující startup/PWA handshake. Statický obsah ani logo se při čekání na backend nemažou. Téma se inicializuje před síťovým čekáním.
- Upřesnění předpokladu: u `isAppSupported=true` společný bootstrap běžně přenechává načtení práv routeru. Obsahová stránka proto požaduje načtení práv už v tomto bootstrapu; žádný další auth klient ani druhá inicializace nevznikají. Generátor musí převzít i sdílený version handshake, na který Vite entry při registraci PWA odkazuje.
- Ověření: 30 cílených Node testů prošlo; po finální úpravě startupu znovu prošly jeho 4 testy a po doplnění kontroly profilu test hlavičky. PWA offline test prošel, Vite build prošel, skutečné HTML má existující fingerprintované JS/CSS a jeden H1. Kontrola generátoru byla opakována po zpřísnění odmítnutí neúplného vstupu. `git diff --check` čistý.
- Headless agent-browser: 1440 x 1000 a 390 x 844, světlé i tmavé téma, bez horizontálního přetékání; kontrola screenshotů. Ověřeny přihlášení, mobilní nastavení, změna motivu, zavření přes Escape, návrat logem do katalogu, proklik „Pro pořadatele“ pod aktivním PWA a CTA vedoucí k existující registraci. Browser i lokální testovací server ukončeny.
- Důkazy: `/tmp/organizers-ui-evidence/desktop-light.png`, `desktop-dark.png`, `mobile-light.png`, `mobile-dark.png`. Testovací HTTP server pouze obsluhoval reálný Vite build a lokální simulaci veřejných RPC; veřejnou backend URL v obsluhovaném JS přesměroval na tuto simulaci. Pro lokální generování PWA byly převzaty Flutter vstup a loader z předchozího build artefaktu; nešlo o nový Flutter build ani ověření celé administrace.
- Omezení: bez autorizované testovací identity není ověřeno skutečné přihlášení. Přihlášený stav, profil a „Moje akce“ ověřeny cíleným komponentovým testem. Žádné produkční zápisy, registrace ani objednávky. Plná předcommitová/release sada nebyla spuštěna; žádný commit ani release tento úkol neprovádí.

## Upřesnění od uživatele

Počty se nezobrazují ani u jednotlivých roků, včetně Flutter administrace. Odstraněn počet z ročního nadpisu administrace i SSR katalogu; klientský katalog již roky bez počtů vykresluje. Roční skupiny, jejich řazení a obsah zůstávají zachovány.
