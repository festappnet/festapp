# Webclientový embed: jednotný protokol, startup a obnova

Datum: 2026-11-08
Stav: Implementováno a ověřeno lokálně včetně oddělení veřejné instalace od Flutteru; kanonické CI lanes i static release build prošly. Viz [výsledek](web-embed-architecture-RESULT-2026-11-08.md).
Ověřování implementace: **standard** - veřejný integrační kontrakt, kontrola původu zpráv, analytické souhlasy a souběh obnovy aplikace
Autoritativní zadání: tato konverzace a PR [#769](https://github.com/festappnet/festapp/pull/769), testovaný head `987574b9dbe9a9617a4f070332fffa511b2b1004`

## 1. Výsledek a rozsah

Vložený veřejný formulář používá výhradně web client. Načítá se bez velké
startovní plochy a loga, přirozeně přizpůsobuje výšku obsahu a při běžné
aktualizaci neztratí rozepsaná data. Selhání startu nabídne srozumitelnou
obnovu. Pravidla režimu stránky, obnovy a protokolu mají každý jediného vlastníka.

Do rozsahu patří:

- Webclientové `/form/:slug` a `/order`, jejich startup a integrační helper.
- Společná pravidla aktualizace a obnovy používaná existujícím runtime skriptem.
- Rozdělení hostitelské a child implementace na transport, rozložení,
  prezentaci a měření se zachováním stávajícího vnějšího rozhraní.
- Trvalé testy přes skutečné HTML, skutečný helper a skutečné formulářové prvky.
- Odstranění překonaných interních implementací a rozšíření architektonických
  dokumentů u existujících vlastníků.

Mimo rozsah jsou změny SQL, oprávnění uživatelů, plateb, cenových výpočtů,
objednávkového modelu, analytických účelů a sbíraných údajů, redesign formuláře,
nový framework, nová infrastruktura a publikace či nasazení.
Nevzniká Flutter varianta embedu. Společný update runtime se může interně
změnit, ale chování běžné Flutter aplikace musí zůstat zachované.

## 2. Výchozí bod a ověřené skutečnosti

Při zápisu plánu byl pracovní strom čistý, na větvi
`docs/festapp-tickets-readme-20261107`, HEAD
`742d614b722bbe619b3a095f66605bd4bb536006`. Tato větev není implementačním
základem. Lokální `origin/main` tehdy ukazoval na
`06671adfbf42b30a331eb73d7efe3ec6975615f0`; PR #769 je vedené samostatně.
Při implementaci nejdříve načíst aktuální autoritativní `main`, zjistit stav
PR a pracovat v izolovaném checkoutu. Nesměšovat cizí rozpracovanou dokumentaci.

| Skutečnost | Zdroj | Důsledek |
|---|---|---|
| `/form/...` a `/order` obsluhuje web client | `automation/cloudflare_build.sh`: `handlePublicPage`, větev `/order`, větev `/form/` | Flutter shell není testovacím zástupcem produkčního embedu. |
| Stávající detekce embedu kontroluje cestu i přesné `embed=1` | `web_client/src/services/embed_context.js`: `isEmbed` | Z této definice vycházet pro všechny spotřebitele. |
| PR používá v dalších místech jen query parametr | PR: `web/festapp_update_prompt.js`, `web_client/index.html`, `web/index.html` | Odstranit odlišné definice stejného režimu. |
| Bridge zpracovává spojení, geometrii, cenu, souhlas i události měření | `web_client/src/services/embed_bridge.js`: `start`, `publishHeight`, `scrollTo`, `connectConsent`, `activate`, `track` | Rozdělit interní odpovědnosti bez rozšíření rozhraní pro formulář. |
| Host helper má podobně smíchané odpovědnosti | `web_client/scripts/embed.template.js`: `scan`, `send`, `projectPrice`, `bindChoice`, message listener | Sdílený transport a samostatné hostitelské moduly. |
| Helper vzniká textovým vložením measurement kontraktu a souhlasu | `web_client/scripts/build_embed.mjs` | Převést generování na importy a již dostupný esbuild; zachovat výstup a kontrolu jeho aktuálnosti. |
| esbuild je již připnutý v závislostech | `web_client/package.json`, `scripts/build_measurement_runtime.mjs` | Není potřebný nový bundler ani runtime závislost CMS. |
| Reload má několik vstupů a ochrany po čekání na worker | `web/festapp_update_prompt.js`: `checkVersion`, `cutOverToVersion`, `recoverFailedCutover`, `deepRefreshIfStale`, `recoverStalledStartup`, `recoverCorruptRuntime` | Nestačí hlídat jen pravidelnou kontrolu verze; prověřit každý navigační efekt. |
| Ready marker má JS i Dart spotřebitele | obě HTML, `web_client/src/main.js`, `lib/services/web_bootstrap_bridge.dart` | Zachovat funkci `markFestappAppReady`, událost `festapp-app-ready` a význam existujícího markeru. |
| Generátor již vkládá společnou pre-paint logiku do HTML | `automation/lib/startup_theme.cjs`, `configure_version.js` | Navázat na deterministické generování, nevytvářet ručně udržované kopie pravidel. |
| Recovery skripty jsou součástí verzovaných build artefaktů | `automation/emit_version_manifest.sh`, `lib/pwa_shell_manifest.mjs`, `verify_web_build.mjs` | Zachovat publikované názvy, pořadí načítání a koherenci cache/CSP. |

### Dosavadní důkazy, které nejsou validací budoucího refaktoru

PR head prošel 1076 webovými testy mimo databázi, 24 případy CMS rendererů,
webclientovým a Flutter release buildem a testy update/PWA. Tři DB testy
nejdříve selhaly kvůli chybějícímu `DATABASE_URL`, následně prošly na vlastní
aktuálně migrované lokální databázi. Ostatní přeskočené DB testy nebyly tímto
prohlášeny za spuštěné.

V Chromiu prošel přístup k formuláři, skutečná SQL objednávka místa i offline
obnova. Exploratorní scénáře potvrdily krátký a dlouhý formulář, kalendář,
validaci, scroll, cross-origin komunikaci, starý helper, pevnou výšku a
zachování rozepsaného pole při aktualizačních událostech.
Lokální evidence je v
`/Users/miakh/source/artifacts/festapp-pr769-qa-20261108/report.html`.
Je to pomocný zdroj, nikoli přenositelná závislost implementace. Pokud chybí,
zrekonstruovat scénáře z matice níže a existujících verzovaných fixtures.

Pokus se samostatným Flutter shellem a nedostupným `main.dart.js` byl mimo
produkční trasu formuláře. Není blokátorem webclientového embedu a nesmí být
vydáván za chybu této trasy.

## 3. Cílová architektura

Následující nové cesty jsou zvolené cílové umístění, nikoli tvrzení, že již
existují. Pokud během implementace vznikne kolize se současným vlastníkem,
aktualizovat tento plán a zachovat uvedené odpovědnosti.

### 3.1 Kontext stránky a startup

- `web_client/src/runtime/page_context.js` vlastní čisté rozpoznání režimu
  `public-embed` nebo `full-page`. `public-embed` odpovídá současnému
  podporovanému `/form/:slug` a `/order` s přesným `embed=1`; ostatní cesty
  embed režim nezískají. Režim nezakládá identitu uživatele ani oprávnění.
- `web_client/src/services/embed_context.js` zachová existující funkce pro
  volající a použije tohoto vlastníka. Nezůstane druhá vlastní URL podmínka.
- Startup před prvním vykreslením dostane tutéž logiku generováním inline
  kódu. Nesmí čekat na stažení nebo inicializaci hlavního modulového grafu.
  Doplnit existující generování; společný zdroj se může objevit ve více
  sestavených artefaktech, nesmí však mít více ručně psaných definic.
- Stav `starting / ready / failed` má jednoho vlastníka v runtime. HTML
  adaptéry předávají ready/failure a vykreslují odpovídající shell. Zachovat
  stávající ready marker a událost jako projekci stejného stavu, nikoli jako
  druhý nezávislý stavový automat. Ready se nepřepne zpět na starting kvůli
  opožděné chybě; opožděná startup chyba nesmí překrýt funkční formulář.
- Embed startup CSS a chybové UI patří pouze webclientovému HTML.
  Běžný Flutter startup, theme preference a Dart phase diagnostika zůstávají.

### 3.2 Politika a provádění obnovy

- `web_client/src/runtime/update_policy.js` je čisté rozhodování nad aktuálním
  kontextem, stavem a důvodem operace. Nepracuje s DOM ani nepřenačítá stránku.
- `web_client/src/runtime/update_controller.js` vlastní síť, worker handshake,
  deduplikaci operací, časovače a provedení efektů. Stávající banner je jeho
  prezentační adaptér. Moduly mohou interně obsahovat současné funkce;
  nevytvářet obecný plugin systém.
- Stávající `web/festapp_update_prompt.js` se stane deterministicky sestaveným
  standalone IIFE vstupem z uvedených zdrojů. Zůstává na současné veřejné cestě.
  Do produkce se neposílají nové neohlídané runtime importy nebo CDN závislosti.
- Všechny cesty k `reload`, `replace`, `SKIP_WAITING` a destruktivnímu čištění
  cache mají explicitní důvod a procházejí politikou. Bezprostředně před
  efektem po posledním `await` znovu přečíst aktuální stav. Zachovat ochrany
  proti zastaralému výsledku, souběžné obnově a opakovaným reloadům.
- Existující globální recovery funkce mají jedinou delegující implementaci.
  Jejich skutečné HTML/Dart spotřebitele migrovat pouze spolu s nimi;
  neodstraňovat názvy jen proto, že jsou globální. Session klíče a jejich
  význam zůstanou v tomto refaktoru kompatibilní.

| Důvod / stav | Public embed | Běžná aplikace |
|---|---|---|
| Běžná nová verze, aplikace ready | Bez banneru, aktivace vynucující přechod a automatické navigace | Dosavadní banner a uživatelské rozhodnutí |
| Oprava před ready | Povolená dosavadní samooprava, při selhání kompaktní retry UI | Dosavadní startup recovery |
| Ready dosaženo během čekání na běžnou aktualizaci | Opožděný výsledek neprovede přechod ani reload | Zachovat dosavadní ochranu interaktivní stránky |
| Prokázané poškození runtime | Zachovat současnou jednorázovou obnovu | Zachovat současnou jednorázovou obnovu |
| Ruční retry po startup chybě | Povolit skutečnou obnovu, zabránit dvojímu kliknutí a nekonečné smyčce | Zachovat současné chování |
| Legacy Flutter cache | Zachovat stávající omezenou migraci; startovní load může vyžadovat deep refresh | Stejná stávající omezená migrace |

Legacy deep refresh není běžná kontrola nové verze. Jeho odlišné chování musí
být v politice pojmenované a testované. Tento plán neslibuje zákaz každé
navigace při prokázaném poškození aplikace. Zachovat odpovídání workeru na
dotazy na verzi klienta i po ready; vypnutí update UI nesmí odstranit protokol
pro bezpečné ponechání cache otevřených klientů.

### 3.2.1 Navazující požadavek uživatele: Flutter se neinstaluje veřejnou návštěvou

Po auditu velikosti uživatel výslovně rozšířil zadání: veřejný web a formuláře
nesmějí při registraci workeru stahovat Flutter. Původní společná instalace
celého core se nahrazuje dvěma sadami v jediném manifestu a jediném workeru:

- `webCoreResources` se instaluje atomicky při registraci. Obsahuje úplný
  webový modulový graf, veřejné dokumenty a sdílené recovery závislosti.
- `flutterCoreResources` se připraví atomicky na skutečný vstup do aplikace,
  přes existující `prepareFlutterRuntime`, Flutter HTML startup a navigaci
  do Flutter shellu. Všechny deferred části zůstávají jedním celkem.
- `FESTAPP_QUERY_BUILD_VERSION` a repair předávají `runtime: web | flutter`.
  Sdílený `runtime/worker_shell.js` vlastní klientský dotaz. Starý worker
  vracející pouze version zůstává kompatibilní; staré veřejné form/order
  dotazy nový worker rozpozná podle URL. Web repair nikdy neinstaluje Flutter.
- Nemění se vlastnictví per-version cache, připnutí otevřených klientů,
  ochrana proti míchání verzí ani pruning. Nepřibývá worker či update engine.
- Offline Flutter vyžaduje předchozí skutečný online vstup do aplikace.
  Samotná návštěva veřejného formuláře jej již předem nepřipravuje.
- Gate prokáže nulové Flutter požadavky při čisté veřejné instalaci/query/
  repair/offline reload, atomický neúspěch a retry, skutečný vstup do app
  a její další offline navigaci. Browser používá skutečný generovaný worker;
  payload Flutter engine je v této síťové fixture simulovaný a výslovně označený.

### 3.3 Protokol a spojení

- `web_client/src/embed/protocol.js` vlastní namespace, verzi 1, limity,
  validaci obálek a schémat základních zpráv, vyjednání minimální výšky a
  pravidla směru zpráv. Protokol měření zůstane u současného
  `form_measurement_contract.js`; nevytvářet druhého vlastníka souhlasů.
- `web_client/src/embed/channel.js` vlastní připnutí peer originu a instance,
  ověření `source`, odesílání na přesný `targetOrigin`, předání validovaných
  zpráv a ukončení spojení. Host má jeden kanál na iframe, child jeden na
  parent. Host musí dále kontrolovat aktuální deklarované `src` a rušit starý
  záznam při změně originu nebo odstranění iframe.
- Jediný wildcard je dosavadní neosobní `ready`. Nezavádět komunikaci s `*`
  pro data, neprůhledné originy ani libovolné callbacky z hostitelského HTML.
- Nový helper nabízí `minHeight: 120`; child bez přesně této nabídky drží
  240. Viewport zůstává 240-4000, resize má horní mez 20000. HTML fallback
  bez JS zůstává 800 a explicitně pevnou výšku helper při startu nepřepíše.

### 3.4 Rozložení, prezentace a měření

- `web_client/src/embed/layout.js` vlastní child měření, RAF/timeout fallback,
  obsahy dialogů/kalendáře, resize a správné rozdělení scrollu mezi hostitele
  a iframe. `ResizeObserver` a měření nesmějí vyvolávat samovolný scroll.
- `web_client/src/embed/measurement.js` implementuje současné measurement
  rozhraní přes kanál: manifest, scoped consent, lease, grant, generation,
  revokaci, runtime fallback a povolené analytické payloady. Používá existující
  kontrakt a `FormMeasurementSession`; nepřebírá doménová rozhodnutí o měření.
- `EmbedTheme` zůstává vlastníkem aplikace prezentačních tokenů a písem.
  Host vzhled povoluje pouze uložené nastavení formuláře.
- `web_client/src/embed/host.js` je standalone vstup helperu. Interně oddělí
  správu iframe, hostitelské scroll/resize efekty, výběr vzhledu, cenovou
  projekci a hostitelský souhlas. Vytvořit moduly pro tyto skutečné
  odpovědnosti; nevytvářet třídu pro každou zprávu.
- `EmbedBridge` zůstává malým integračním modulem pro existující formulářové
  volající a skládá uvedené části. Veřejné funkce `revealEmbedStep`,
  `publishEmbedPrice` a `preserveCheckoutScroll` zůstanou použitelné z
  validátoru, náhledu, price widgetu a blueprint selectoru.
- Cena přenášená do hostitele zůstává prezentační projekcí existujícího widgetu.
  Hostitel nesmí počítat cenu, vlastnit stav objednávky nebo rozhodovat o platbě.
- `start / destroy`, opakovaný `init`, navigace na jiný formulář, výměna iframe
  a `pagehide / pageshow` musejí uvolnit nebo správně obnovit všechny zdroje.
  Starý disposer, lease či pozdní zpráva nesmí ovlivnit nového vlastníka.

## 4. Rozhodnutí, předpoklady a blokátory

- **D1:** Zachovat wire protokol 1 a externí API `window.FestappEmbed`, atributy
  `data-festapp-*`, výstupní `/embed.js` a CMS integrační markup. Žádný nový
  `embed-v2.js`, V2 bridge, feature flag nebo souběžný update engine.
- **D2:** Použít existující esbuild pro deterministické IIFE výstupy. Rozšířit
  generační vstupy a `--check`, zachovat existující vstupní příkaz
  `scripts/build_embed.mjs`. Výstup nesmí obsahovat cesty konkrétního počítače.
- **D3:** Pozorovanou funkčnost PR #769 převzít; její Flutter embed CSS a
  inline embed detekci vyjmout. Nesouvisející změny Flutteru nerevertovat.
- **D4:** Interní alternativy po migraci odstranit. Kompatibilita se starými
  externími helpery a publikovanými CMS rozhraními je úmyslná integrační mez.
- **A1:** Stav PR a `main` se může změnit. Implementátor porovná aktuální
  source s uvedeným PR headem a aktualizuje fakta plánu; nesmí přepsat novější
  sdílený kód starší kopií souboru z PR.
- **A2:** Lokální QA artefakty nemusí být dostupné. Závazné scénáře jsou
  popsány zde a v repozitáři; jejich absence není důvod přeskočit testy.
- **A3:** Staré globální recovery vstupy mohou být součástí již sestavených
  klientů. Zachovat jejich publikované názvy a session klíče, dokud je
  samostatný inventář a release kontrakt nedovolí odstranit. Uvnitř nesmí
  zůstat alternativní rozhodování.
- **B1 - uzavřeno po schválení uživatelem:** Původní limity 25/60 MiB
  blokovaly build. Audit potvrdil aktivní gzip/Brotli na produkci, malý přínos
  další minifikace a odložené načítání velkých non-core assetů. Uživatel schválil
  limity 35/80 MiB: `36700160` / `83886080` B v `automation/project.conf`.
  Obsah offline cache ani runtime se nemění. PWA budget gate i finální static
  verifier prošly nad již sestavenými artefakty; Flutter se znovu nekompiloval.
  Podrobná evidence a neprovedené provozní kroky jsou ve výsledku.
- Chybějící prostředí při implementaci znamená
  neprovedenou konkrétní validaci, nikoli úspěšný výsledek.

## 5. Etapy implementace

Každá etapa je koherentní změna. Etapy jsou logické závislosti, nikoli pokyn
šestkrát opakovat průzkum a celé testovací sady. Cílené kontroly dávkovat podle
části 5.1; finální sady znovu spouštět jen při změně pokrytého kódu.

### 5.1 Tokenově a provozně úsporné provedení

Tato pravidla platí pro všechny etapy. Nemění povinný režim `standard` ani
bezpečnost, wire kompatibilitu a finální gates. Není zadán číselný tokenový
limit; úspora má vzniknout odstraněním opakované práce a zbytečného kontextu.

1. **Jeden vstupní průzkum.** Jednou přečíst plán a povinné repo instrukce,
   zjistit rozdíl aktuálního základu proti zaznamenanému stavu a dohledat pouze
   dotčené deklarace/volající. Používat scoped `rg`, `git diff --name-only`
   a krátké výřezy. Před další etapou číst jen nově potřebný kód; neopakovat
   inventuru repozitáře, celou konverzaci, staré QA logy ani již přečtené skills.
2. **Implementovat po ucelených změnách.** Nejprve dokončit přesun vlastníka
   včetně volajících a odstranění původní implementace, potom jeden cílený
   ověřovací běh. Nespouštět test/build/browser po každém souboru. Sousední
   etapy lze ověřit společným během, pokud pokrývá všechny jejich podmínky;
   charakterizační důkazy z etapy 2 však musejí vzniknout před refaktorem.
3. **Evidence platí pro své vstupy.** Průběžně držet krátkou tabulku
   `kontrola | pokryté soubory/kontrakt | revize nebo otisk vstupů | výsledek |
   log`. Po změně zneplatnit jen související důkazy. Úspěšný nadřazený suite
   může pokrýt cílený test; samostatně jej znovu nespouštět. Skipped nebo
   chybějící prostředí není PASS. Povinné CI gates se tím nenahrazují.
4. **Plné kontroly až nad stabilním celkem.** Širší web suite, buildy a
   kanonické lanes naplánovat nad finálními vstupy. Browser případy zahrnuté
   v kanonickém lane podruhé ručně neprocházet, pokud výsledek neodhalí
   konkrétní nejistotu. Neopakovat Flutter build kvůli pouhé úpravě JS testu
   nebo dokumentace. Před těžkým ověřením stabilizovat zdroje i generátory.
5. **Jedno browserové zadání pro Terra.** Předat přesný checkout/revizi,
   požadované scénáře, příkazy a výsledkový formát. Reuse jedné vlastní
   izolované session a fixture serveru, kde to zachová správnou izolaci testů;
   nerozdělovat každý viewport nebo scénář do dalšího agenta. Neprovádět
   paralelní nezávislé review ani několik agentů čtoucích tentýž kód.
   Závěrečný browser běh používá stabilní vstupy; po jejich změně označit
   příslušné výsledky za neplatné a zopakovat pouze dotčené scénáře.
6. **Krátké výstupy, plné logy na disku.** Úspěch vypisovat jedním řádkem
   s počtem testů/skips a cestou k logu. Při selhání číst relevantní assertion
   a okolí, opravit konkrétní příčinu a zopakovat dotčený test. Celou sadu
   opakovat až při doloženém širším dopadu. Snímky pořizovat pro reprezentativní
   layout a reprodukci chyby; rutinní interakce ověřovat kompaktním snapshotem
   a měřitelnými hodnotami, bez přenosu velkých DOM dumpů nebo base64 do kontextu.
7. **Levné pokračování napříč relacemi.** Pokud bude práce pokračovat v jiné
   relaci, uložit jeden stručný průběžný záznam vedle plánu: source revizi,
   hotové/zbývající etapy, změněné cesty, tabulku platných kontrol, přesný další
   krok a vlastněné běžící procesy. Záznam aktualizovat, nepřidávat další
   přepis plánu nebo deník každého příkazu. Při pokračování číst plán, tento
   záznam a nový diff; neopakovat již hotový průzkum nebo platné kontroly.

Minimalizace počtu modulů je také součástí úspory: vytvořit pouze vlastníky
konkrétně popsaných odpovědností. Nevytvářet generický framework, plugin registr,
nový test runner ani další abstrakce bez skutečného spotřebitele. Pokud se
objeví nesouvisející problém, stručně jej oddělit a pokračovat v rozsahu plánu;
pokud blokuje povinný gate, zůstává explicitním blokátorem dokončení.

### Etapa 1: Aktuální základ a správný rozsah PR

**Cíl:** Převzít požadované chování PR na aktuální `main`, bez Flutter embedu.

**Změny:** Zjistit, zda je PR již integrováno. Pokud není, převzít jeho
webclientové a společné update změny spolu s testy a dokumentací, se zachováním
novějšího kódu. V `web/index.html` nepřidávat, případně odstranit pouze
PR-specifické `festapp-embed-startup` a související embed CSS. Upravit testy,
které by embed branding očekávaly ve Flutter HTML. Neměnit routing `/form`
a `/order` na jiný renderer. Výjimku runtime recovery zachovat.

**Validace:** Dosavadní `embed.test.js`, `festapp_update_prompt.test.js`,
`startup_theme_consistency.test.js` a update behavior test. Počet testů a
skipped případy zapsat; úspěch staršího commitu nepřebírat.

**Výstup:** Nový základ má chování PR; pouze webclientový shell podporuje
prezentaci embedu a není ztracena žádná novější změna.

### Etapa 2: Trvalé integrační důkazy před přesunem vlastníků

**Cíl:** Přesunout důležité jednorázové QA scénáře do běžného testovacího toku.

**Změny:** Rozšířit existující fixtures a server z
`scripts/test_form_access_browser.mjs`, `tests/fixtures/form_access/` a
`tests/fixtures/embedded-checkout/`. Přidat koherentní embed scénáře do
existujícího browser gate; případné samostatné scénářové funkce používají
stávající izolovaný browser launcher, nikoli druhý runner.

Scénáře musejí načítat skutečné HTML, Main/formulář, generovaný helper a
update skript. Simulovat pouze backend transport nebo konkrétní síťové
selhání. Update test musí doložit aktivní produkční větev skriptu, ne jeho
předčasný návrat kvůli local development. Pokrýt také inicializaci před ready;
vložení skriptu až do připravené stránky není jediným důkazem startupu.

Starý helper pro kompatibilitní test uložit jako pojmenovanou zmrazenou testovací
fixture s původním commitem a účelem. Neodvozovat jej při běhu z `HEAD^`, jehož
význam se po dalších commitech změní. Fixture není publikovaný runtime.

**Validace:** Existující `test:form-access-browser` s novými případy a test
interakcí. Failing regresi zapsat a vyřešit v příslušné další etapě; neupravovat
očekávání tak, aby se ztratilo zamýšlené chování.

**Výstup:** Krátký/dlouhý formulář, kalendář, validace, starý helper,
cross-origin, pevná výška, startup a draft při update jsou skutečně sbírané
a spouštěné testy v existující CI cestě.

### Etapa 3: Jeden kontext a politika obnovy

**Cíl:** Odstranit odlišné definice embedu a rozptýlené rozhodování o navigaci.

**Změny:** Zavést vlastníky z 3.1 a 3.2. Generovat inline pre-paint bootstrap
ze stejného zdroje jako runtime klasifikaci. Extrahovat update implementaci
do zdrojových modulů, zachovat současný standalone asset a všechny potřebné
globální delegáty. Zajistit deterministickou generaci před kompilací obou
shellů, kontrolu generačního driftu a návaznost na build/verzování/CSP.

Inventarizovat každé `location.reload/replace`, worker activation a cache
cleanup v dotčené cestě; přiřadit důvod a aplikovat politiku. Zachovat existující
worker handshake a ochranu otevřených klientů. Nepřidávat druhý stav ready.
Pro webclientový embed vytvořit kompaktní lokalizovanou chybovou plochu a retry
bez aktualizačního banneru; offline, dvojklik a pozdní chyba mají jasný výsledek.

**Odstranění:** Query-only detektory, rozptýlená nezávislá embed rozhodnutí,
ručně udržovaný obsah generovaného update assetu a redundantní interní větve.
Hlídání po `await` se centralizuje, jeho bezpečnost se neruší.

**Validace:** Behaviorální tabulka z 3.2, pomalé worker/fetch výsledky, ready
během každého relevantního čekání, běžná aplikace, chybný runtime, legacy
cache, opakovaná chyba a race dvou obnov. Dále generační idempotence,
update/PWA testy, reálný shell v browser gate a normální Flutter startup
kontrakt. Testy založené na regexu vnitřní funkce převést na pozorované
chování; zachovat skutečné build wiring assertions.

**Výstup:** Každý dotčený efekt má vysvětlitelný důvod, rozhoduje stejná
politika, opožděná background aktualizace nezničí ready embed a recovery
zůstává funkční. Generovaný asset nelze publikovat zastaralý vůči zdrojům.

### Etapa 4: Jediný základní protokol a sestavení helperu

**Cíl:** Obě strany používají stejné definice a validaci veřejných zpráv.

**Změny:** Zavést `embed/protocol.js` a `embed/channel.js`, přesunout existující
hostitelský vstup do `embed/host.js`. `build_embed.mjs` sestaví standalone
IIFE pomocí esbuild, v režimu `--check` sestaví do paměti a přesně porovná
s verzovaným `public/embed.js`. Zachovat namespace, protokol 1, globální
API, singleton chování opakovaného vložení a všechny publikované atributy.

Measurement kontrakt importovat od současného vlastníka. Převést host i child
na sdílený základní kontrakt a validovaný kanál v jedné etapě. Validace
neznámých doplňkových polí zůstane kompatibilní; neznámé typy zpráv nesmějí
vyvolávat efekty. Nezavést dynamické načítání modulů do cizího CMS.

**Odstranění:** `scripts/embed.template.js`, textové vkládání kontraktů a
duplicitní definice namespace/limitů/obálek. Aktualizovat všechny build/test
odkazy na šablonu. Výsledný `public/embed.js` zůstává generovaný a verzovaný.

**Validace:** Nový helper + nový child, zmrazený starý helper + nový child,
nový helper + starý child bez nového pole. Dále origin/source/instance,
null origin, malformed payload, dva iframe, změna src, load před/po helperu,
opakované init, fixed/no-JS a limity 119/120/239/240/4000/20000.
Ověřit deterministickou generaci, CMS adaptéry a existující Wix kontrakt.

**Výstup:** Ve zdrojích existuje jeden vlastník základního protokolu; runtime
helper nepotřebuje další soubory ani změnu hostitelského HTML. Staré integrační
verze jsou podporovány pouze u jasně pojmenované externí meze.

### Etapa 5: Rozdělení bridge a hostitele podle odpovědností

**Cíl:** Změna layoutu nevyžaduje editaci souhlasů a změna souhlasu neovlivní
vlastnictví scrollu ani rozměrů.

**Změny:** Vyčlenit `layout.js` a `measurement.js` podle 3.4. Na hostiteli
oddělit stejné odpovědnosti za kanálem; zachovat cenovou projekci a současný
výběr prezentačních tokenů. `EmbedBridge` deleguje na jediné implementace.
Přizpůsobit propojení ve `form_page.js` s `FormMeasurementSession` a zachovat
veřejné pomocné funkce používané náhledem, validátorem a blueprint selectorem.

Přesouvat vždy i vlastnictví disposerů a časovačů. Přístup k consent/lease
nesmí být schovaný v layout modulu; layout nesmí rozhodovat o grantech.
Přenos souhlasu kontroluje scope a revizi stejně jako před refaktorem.

**Odstranění:** Původní implementace měření a layoutu z bridge/host monolitu
po migraci volajících; žádný dočasný dvojí listener nebo mirror stavu.

**Validace:** Stávající embed, vzhled a measurement testy a browser scénáře.
Zvlášť revokace, vypršení lease, starý disposer po novém init, více formulářů,
odstranění/výměna iframe, pagehide/pageshow, zachování host price bez vlastního
cenového výpočtu a nulové efekty starých kanálů po destroy.

**Výstup:** Jeden listener/kanál vlastní každé spojení, bridge je složení
ucelených modulů a zachované volající neznají pořadí interních inicializací.

### Etapa 6: Kontrakce, dokumentace a závěrečné ověření

**Cíl:** Nová architektura je jedinou interní cestou a je ověřena na finálních vstupech.

**Změny:** Dokončit ledger níže. Aktualizovat
`docs/integrations/embedded-checkout.md`, relevantní část
`docs/architecture/ai_context.md` a existující forms README, pokud vysvětluje
nové propojení. Popsat vlastníky, podporované cesty, retry výjimky a externí
kompatibilitu; nevytvářet další kopii protokolové tabulky v novém README.
Pro `public/embed.js` a update asset ponechat označení generovaného původu.

**Validace:** Cílené absence checks, normální web suite, browser gate a
dotčené kanonické CI mirror lanes podle části 7. Žádné produkční odeslání,
platba, e-mail nebo deploy. Výsledky zapsat s přesným finálním commitem/diffem,
počty tests/skips a konkrétními environment blokátory.

**Výstup:** Každá položka ledgeru je prokazatelně odstraněná nebo úmyslně
ponechaná na vymezeném rozhraní. Není potřeba dopracovat skrytou druhou větev.

## 6. Ledger odstranění a úmyslně zachovaných rozhraní

| Položka | Akce | Důkaz dokončení |
|---|---|---|
| Flutter `festapp-embed-startup` a embed CSS z #769 | Odstranit/nepřevzít | Flutter HTML nemá embed prezentační větev; normální startup test stále prochází. |
| Ručně psané query-only klasifikátory | Nahradit jedním `page_context` | Scoped `rg` a test `/`, `/login`, `/form/:slug`, `/order` s různými query; generované kopie se nepočítají jako noví vlastníci. |
| `embed.template.js` a textové vložení exportů | Odstranit | Žádní aktivní build/test spotřebitelé, helper generován modulovým buildem. |
| Duplikáty základního embed kontraktu | Odstranit | Host i child importují `embed/protocol.js`; measurement má svého stávajícího vlastníka. |
| Layout/measurement těla ve starém bridge a host monolitu | Přesunout a odstranit | Jeden vlastník každého observeru, časovače a stavu; test destroy a opožděných zpráv. |
| Ruční update implementace v distribuovaném assetu | Převést na generovaný výstup | `--check` a build preflight odhalí drift, zveřejněná cesta zachována. |
| Regex testy závislé na vnitřním názvu/těle funkce | Nahradit behaviorálními | Stejné riziko kryje veřejné rozhraní a pozorované efekty; build wiring testy zůstanou. |
| Externí protokol 1, 240 fallback, CMS API a atributy | Zachovat | Kompatibilitní matice a CMS/Wix testy procházejí. |
| Zmrazený starý helper pro testy | Zachovat pouze ve fixtures | Není ve veřejném bundlu, má původní SHA a jednoznačný účel. |
| Ready marker, událost, globální recovery vstupy, session klíče | Zachovat jako adaptér stejného vlastníka | JS/Dart/HTML spotřebitelé fungují; žádná alternativní politika. |
| Omezená migrace skutečně starých Flutter cache | Zachovat současné omezení | Jen legacy cache/worker, žádné mazání aktuálních app-shell cache otevřených klientů. |

## 7. Ověřovací matice a příkazy

### Automatizované scénáře

1. **Režim:** `/form/:slug` a `/order` s `embed=1`; bez parametru, `embed=true`,
   `/`, `/login` a běžná Flutter cesta; frontendová normalizace URL zůstane
   kompatibilní. Režim se nepoužívá jako oprávnění.
2. **Startup:** pomalé moduly, žádný flash loga/SEO, průhlednost pouze během
   startupu embedu; po ready vlastní vzhled formulář; chybový text a retry,
   offline, opakované kliknutí, pozdní chyba a retry po obnovení sítě.
3. **Výška a scroll:** šířky 320/390/1440, krátký a dlouhý formulář, validace,
   kalendář, skutečné modální dialogy/náhled a plánek, reduced motion,
   zvětšení textu/reflow. CSS zoom označit jako simulaci, ne fyzický browser zoom.
   Resize sám neposouvá hostitele. Fixed a capped iframe zachovají vnitřní scroll.
4. **Protokol:** obě pořadí načtení, dva iframe, starý/new helper a child,
   no-JS, odmítnuté originy/zdroje/instance, změna src, odstranění a znovuvložení.
5. **Update:** všechny vstupy focus/load/visibility/timer/worker event,
   odložená fetch/worker/repair odpověď, ready během čekání, rozepsané pole,
   žádný background reload nebo banner v ready embedu, funkční běžný update,
   startup a corrupt-runtime recovery, legacy deep refresh a deduplikace.
6. **Měření:** bez souhlasu nic neposílat, správný scope/revision, expiry,
   page lifecycle, revokace, host/runtime volba, žádný replay starého grantu,
   stejný whitelist a izolace dvojice iframe.
7. **Objednávka:** existující kanonický browser+SQL výběr místa, rezervace,
   náhled, objednávka a offline recovery nad označenou izolovanou DB.

### Příkazy a jejich použití

- Instalace v každém dotčeném JS balíčku: `pnpm install --frozen-lockfile`,
  pnpm přesně 11.24.0. Žádný nový package manager/lockfile.
- `pnpm --dir web_client exec node scripts/build_embed.mjs --check` a
  analogická kontrola nového runtime generátoru: determinismus zdroj/výstup.
- `pnpm --dir web_client exec node --test tests/core/embed.test.js
  tests/core/festapp_update_prompt.test.js
  tests/core/startup_theme_consistency.test.js tests/forms/embed_appearance.test.js`:
  existující plus nové cílené kontrakty. K novým vlastníkům přidat testy chování,
  nikoli kopie implementačních podmínek.
- `node automation/tests/update_prompt_behavior.test.mjs` a
  `node --test automation/tests/pwa_offline.test.mjs automation/tests/pwa_manifest.test.mjs`:
  zachování recovery a PWA kontraktu; adaptovat interně závislé assertions.
- `pnpm --dir web_client run test:form-access-browser` a
  `pnpm --dir web_client run test:form-interaction-browser`: skutečný shell,
  nové embed scénáře a interakce. Neobcházet je přímým Playwright spuštěním.
- `bash automation/test_embed_adapters.sh`: CMS renderery; Wix ověřit jeho
  kanonickým lane níže. Zachovat současnou podobu HTML integrací.
- Finální source publication gate: `./automation/test_ci.sh web-startup
  wix-checkout-compatibility seat-checkout`. Tento příkaz patří k dokončené
  implementaci před publikací zdrojů, nikoli k zápisu tohoto plánu.
  Používá připnuté runtime a vlastněné disposable prostředí podle aktuálního
  kontraktu v `automation/ci/checks.json`. Nezastavit ani neresetovat cizí DB;
  při obsazeném mirroru počkat nebo použít kanonicky konfigurovatelnou vlastní
  instanci. Neslibovat úspěch při chybějící závislosti.
- `pnpm --dir web_client test` a `pnpm --dir web_client run build`: finální
  širší web ověření. DB část musí mít vlastní označený lokální backend, nebo
  musí být výsledek explicitně neúplný. Nepovažovat chybějící env za pass.
- Změna sestavování sdíleného runtime vyžaduje build wiring/PWA/CSP kontroly
  a ověření release Flutter shellu podle existujících build pravidel, přestože
  se jeho embed prezentace odstraní. Žádná změna Dart domény není plánovaná.
  Flutter tasky spouštět po jednom a testy vždy s `--concurrency=1`.

Browser práci provádí delegovaný `gpt-6.1-terra` podle osobních pravidel:
izolovaný headless profil s explicitním lokálním providerem, ztlumený zvuk,
světlé snímky, přirozená česká data, zavření vlastních sessions a serverů.
Neužívat otevřené uživatelské taby. Logy a snímky nesmějí obsahovat tajemství.
Žádná běžná prohlídka webu ani delegace nezakládá oprávnění nasazovat.

## 8. Publikace, nasazení a rollback

Plán ani jeho implementace samy neautorizují commit, push, merge PR nebo deploy.
Nejdříve vznikne lokálně ověřený celek. Jeho pozdější zdrojová publikace musí
respektovat aktuální `main`, repozitářové CI gates a vlastnictví větví.
Výchozí rozsah zůstává `main` a nejvýše jeden výslovně vybraný tenant.

Nejsou potřeba datové migrace ani změny hostitelského markupu. Staré a nové
externí helpery/child stránky mohou po dobu cache coexistovat; to kryje
kompatibilitní matice. Nové moduly musí být zahrnuté v deterministických
standalone výstupech, které procházejí současným verzováním a manifesty.

Pokud bude později autorizovaný web deploy: místní kanonický build a
`automation/deploy_direct.sh` pro vybraný tenant, exact-baseMainSha CI release
gate a coherent live-version probes podle repository pravidel. Rutinní výkon
delegovat levnějšímu agentovi podle osobních pravidel. Nepoužít GitHub Deploy
bez výslovného požadavku.

Rollback provozu používá předchozí koherentní artefakt celé verze. Nemíchá
starý updater s novým shellem, nemaže cache jiných klientů a neobnovuje
interní V1/V2 implementace v nové větvi. Případná oprava source proběhne u
nového kanonického vlastníka se stejnými regresními scénáři.

## 9. Hotovo znamená

- [x] Produkční embed zůstává webclientový, bez Flutter prezentační odbočky.
- [x] Funkčnost #769 je zachovaná na aktuálním `main`.
- [x] Jeden zdroj klasifikuje kontext a jeden vlastník řídí runtime stav.
- [x] Všechny update/recovery efekty respektují aktuální politiku a důvod.
- [x] Chyba webclientového startupu nabídne použitelný retry bez update banneru.
- [x] Host a child sdílejí základní protokol a každý peer má jeden validovaný kanál.
- [x] Layout, prezentace a měření mají jasné vlastníky a korektní lifecycle.
- [x] Publikované CMS API, wire protokol, ready/recovery rozhraní a measurement
      pravidla zůstávají kompatibilní.
- [x] Ledger je uzavřený; žádné paralelní interní implementace ani dočasné flagy.
- [x] Generované artefakty, HTML bootstrap a build manifesty jsou koherentní.
      CSP, PWA size gate i finální verifier prošly; B1 je uzavřený.
- [x] Testy skutečně sbírají scénáře z matice a dotčené finální gates prošly.
- [x] Evidence rozlišuje fixture transport, reálné SQL, browser simulaci,
      neprovedené testy a dosud neautorizované provozní kroky.
- [x] Platné kontroly jsou navázané na vstupy; nebyly zbytečně opakované
      průzkumy, plné sady ani duplicitní browserové průchody.
- [x] Vlastní testovací sessions, servery a disposable prostředí jsou uklizené.

## 10. Zbytková rizika

Externí CMS může přepisovat iframe CSS nebo blokovat skripty; zůstává proto
HTML fallback a odkaz na samostatný formulář. Nelze odstranit již uložené
staré helpery z cizích webů, jejich podporu kryje wire kompatibilita.
Chromium a simulovaný reflow nejsou důkaz všech fyzických mobilů, Safari,
Firefoxu nebo úplného WCAG auditu. Největší technické riziko refaktoru je
pořadí startupu a asynchronní změna ready/consent stavu, proto jim odpovídají
samostatné invariants a testy; velikost souborů sama není důvod k další vrstvě.
