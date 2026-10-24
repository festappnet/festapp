# Bezpečné vykreslování, CSP a GitHub ochrany Festapp

Datum: 2026-10-18  
Stav: Připraveno k exekuci; tato session vytváří pouze plán  
Ověřování: standard pro bezpečnost; při publikaci a nasazení také všechny povinné repository gates

## Výsledek a rozsah

Odstranit potvrzené XSS v detailu akce a SVG plánku, zapnout účinnou CSP přes ověřený přechod Report-Only a aktivovat GitHub secret scanning/push protection. Zachovat vzhled legitimního obsahu, rezervace, přihlášení, administraci a Flutter/PWA chování.

V rozsahu jsou body 1, 2, 3 a 5 z konverzace, tedy audit F01, F02 a F04 a CSP jako doplňková ochrana. **Kontejnery, RAM/CPU/PID, host, databázové migrace a backendové provozní limity jsou mimo rozsah** a vlastní je jiná session. Nevracet již opravená RPC/RLS témata do tohoto balíku.

Sdílený kód vlastní `main`. Jediný výchozí produkční tenant je `festapp` / `prod/festapp` / `https://live.festapp.net`, který byl cílem auditu. Žádné další tenantové větve se nebudou měnit, stavět nebo nasazovat. Pokud předání identifikuje jiného skutečně vybraného tenanta, před produkčními kroky vyřešit tento konkrétní rozpor; nevytvářet implicitní rollout všech variant.

Uživatel schválil zamýšlené opravy a GitHub ochrany; poslední požadavek je dodat exekuční plán. Nyní se nic neimplementuje, nepublikuje ani nezapíná. Navazující session po pokynu k exekuci provede celý níže popsaný rozsah včetně ověřeného single-tenant rollout, bez opakovaných obecných žádostí o stejné oprávnění. Placené služby, nákupy, jiné tenanty, produkční objednávky a odesílání zpráv tím nejsou schválené.

## Ověřený výchozí bod

GitHub main při přípravě: `8b1420ea1da7349db68b4a293bb37da049fb9047`. Výchozí audit: [security-audit-2026-10-17.md](../operations/security-audit-2026-10-17.md), včetně lokálního browser proofu. Exekutor před prací obnoví main a nepovažuje tento SHA za navždy aktuální.

| Fakt a důkaz | Důsledek |
| --- | --- |
| `occasion_detail_dialog.js`, `OccasionDetailDialog.show`: title/description a další hodnoty v raw template do `innerHTML` | Opravit celý konkrétní template, včetně tlačítkového textu a dynamické barvy, nikoli jen dva payloady |
| `web_client/src/utils/html.js`: existuje DOMPurify, `html`, `sanitizeHtml`, `SafeHtml`; `html_sanitize.test.js` ověřuje legitimní rich HTML | Znovu použít existující vlastníka sanitizace; netvořit druhý HTML sanitizer |
| `SvgUtils.prepareBackgroundSvg` serializuje aktivní SVG; `BlueprintRenderer.renderBackground` vkládá výsledek přes `innerHTML` | Sanitizovat před vložením; odstranit vracení původního nevalidního SVG |
| `lib/components/blueprint/views/blueprint_controls_bar.dart`, `_uploadSvgBackground`: přijímá obsah SVG souboru; editor ukládá backgroundSvg | Zachovat kontrakt uloženého SVG a URL; není nutná hromadná změna databáze |
| `automation/build_web_bundle.sh` sestaví Flutter, pak web_client a překopíruje jeho dist do stejného `build/web` | Hlavičky/hashes počítat z finálních skutečně nasazovaných dokumentů, ne z nezkompilovaných šablon |
| `automation/cloudflare_build.sh` generuje `_worker.js`; `htmlResponse`, `handleForm`, homepage a další větve mění/vracejí HTML | CSP explicitně aplikovat ve Worker odpovědích, nikoli jen do `_headers` |
| `web/_headers` a `web_client/public/_headers` mají pouze `base-uri 'self'; object-src 'none'` | Současná CSP neomezuje spouštění skriptů |
| `web/index.html`, `web_client/index.html`, `web_client/public/auth_bridge.html` obsahují inline bootstrap; Flutter používá OneSignal a CanvasKit | Tvrdé `script-src 'self'` bez přípravy by rozbilo aplikaci |
| `automation/tests/public_seo.test.mjs`, `google_auth_hosting.test.mjs` testují generovaný Worker | Rozšířit existující skutečnou hranici, ne pouze test textu v `_headers` |
| GitHub API ukazuje admin oprávnění, vypnutý secret scanning, push protection, non-provider patterns, validity checks i Dependabot security updates | Operace jsou proveditelné dostupným účtem; aktuální dostupnost jednotlivých funkcí ještě ověřit při exekuci |
| Rozpracovaný kořen má přes 1 500 změn a starší locky; aktuální main měl v pěti npm sadách 0 advisories | Implementovat v samostatném checkoutu z main; neimportovat kořenový diff ani staré dependencies |

## Cílové kontrakty a invarianty

1. Plain-text hodnoty v detailu akce jsou text, nikoli markup. Rich description používá právě existující `sanitizeHtml`; podporované odkazy, obrázky a formátování fungují.
2. SVG renderovací cesta propouští legitimní statickou grafiku, nikoli skripty, event handlery, aktivní namespace/URL či `foreignObject`. Malformed vstup se nikdy nevrací jako důvěryhodné SVG.
3. Bezpečnost XSS oprav platí i bez CSP. CSP je další vrstva, nikoli náhrada sanitizace nebo důvod vynechat opravu.
4. CSP má jednoho kanonického vlastníka policy a generuje konzistentní hlavičky pro skutečné HTML entrypointy. Nevznikají dvě ručně udržované odlišné politiky.
5. Cílové `script-src` pro veřejný web neobsahuje `unsafe-inline`, `unsafe-eval`, wildcard nebo obecné `https:`. Inline event handlery jsou zakázané (`script-src-attr 'none'`). Konkrétní potřebné externí script originy se přidávají jen s důkazem.
6. Flutter dostane vlastní doložený profil, pokud jej skutečný runtime vyžaduje. `wasm-unsafe-eval` lze povolit jen pro profil, který prokazatelně kompiluje WASM. Globální `unsafe-eval` není výchozí úniková cesta. Nepotvrzená nekompatibilita znamená nedokončenou CSP fázi, nikoli předstírané splnění.
7. CSS inline styly zatím mohou zůstat povolené, protože je produkt používá. Bez analýzy neměnit `frame-ancestors`, embeddování formulářů, síťové či obrázkové originy. V první iteraci nezužovat nesouvisející direktivy `default-src`, `img-src`, `connect-src` a `style-src`; rozsah CSP je bezpečné spouštění skriptů plus stávající base/object ochrana.
8. Ani nová hlavička nesmí rozbít již otevřený klient, service-worker update, návrat z OAuth nebo admin deep link. Změna policy není rotace session ani reset cache/dat uživatelů.
9. GitHub ochrany se týkají pouze `festappnet/festapp`. Žádné tajné hodnoty, skutečné credentials nebo payloady se nepushují pro test ochrany.

## Rozhodnutí a vyřešení neznámých

- **Rozhodnutí:** statické inline bootstrap skripty povolit SHA-256 hashes spočítanými z finálních HTML dokumentů po verzování/konfiguraci/optimalizaci. Inline event atributy přesunout na `addEventListener`; nedávat jim `unsafe-hashes`. Není třeba přepisovat celý bootstrap jen kvůli CSP.
- **Rozhodnutí:** nový build helper `automation/generate_csp_policy.mjs` bude jediným vlastníkem profilů a hashů. Vygeneruje malý policy manifest pro finální build a podklady pro existující Worker generátor i oba `_headers`. Nepřesouvat kvůli tomu celý hosting/router. Součást buildu a `verify_web_build.mjs` musí odhalit změnu HTML po výpočtu hashů.
- **Rozhodnutí:** profily odvozovat od skutečně servírovaného dokumentu `webclient`, `flutter`, `auth_bridge`, případně `organizers-page`, nikoli jen od URL prefixu. Při SPA přechodu nadále platí CSP původního dokumentu; testovat i handoff webclient -> Flutter.
- **Rozhodnutí:** runtime vložený JSON-LD/SEO se nesmí stát obecným mechanismem povolování script tagů. Jestli vyvolá CSP violation, vyřešit jeho konkrétní inertní script variantu nebo úzce vymezenou důvěryhodnou cestu. Nepřidávat nonce automaticky všem scriptům nalezeným v user-derived HTML.
- **Neznámá:** skutečné SVG exporty mohou používat defs, gradienty, clipPath, lokální `<use>` a CSS třídy. Před finálním allowlistem připravit reprezentativní statické fixture z existujících neprivátních vzorů nebo explicitně povolené kopie; nevymazat je plošným zákazem všech stylů/reference.
- **Neznámá:** přesný seznam externích script originů a požadavky Flutter/OneSignal/worker/WASM získat z produkčního release buildu v izolovaném preview. Použít minimum skutečně potřebných originů; service worker `worker-src` řešit jen podle důkazu.
- **Neznámá:** metadata/permissions GitHubu se mohou změnit. Ověřit GET a capabilities před zápisem, po každém zápisu znovu GET; 403 hlásit s konkrétní operací. Neobcházet organizací vynucenou politiku ani nezapínat placený produkt.

## Implementační vlny

### 0. Izolace a aktuální základ

Přečíst `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md`, `CONTRIBUTING.md` a relevantní release pravidla. Vytvořit samostatný checkout/worktree z aktuálního autoritativního main; při tom zachovat původní checkout beze změny. Zkontrolovat, zda některá ze dvou oprav již mezitím nevznikla. Při rozporu aktualizovat tento plán s konkrétním důkazem.

Výstup: source SHA, scope `main + prod/festapp`, seznam pouze vlastních změn. Zatím žádné testy jen kvůli založení práce, žádné produkční zápisy.

### 1. Oprava detailu akce

V `OccasionDetailDialog.show` použít existující escapující `html` pro plain text a `sanitizeHtml(description)` pro rich text. Zachovat `SafeHtml` kontrakt. Barvu z feature nastavit až DOM style property po validaci podporovaného barevného formátu; nevkládat ji jako nedůvěryhodný kus atributu. Zachovat `ThemeService` kontrast i tlačítkové akce.

Přidat `web_client/tests/components/occasion_detail_security.test.js`. Testovat payload v title/description/reserveButtonTitle/barvě, nebezpečné URL, zachování nadpisů, odkazů a obrázků, zavření přes tlačítko/Escape a správný reserve callback. DOM test musí volat skutečnou komponentu; JS DOM nenahrazuje skutečný browser pro execution assertions.

Výstup: žádný nový executable DOM z uvedených vstupů, legitimní rich text i ovládání zachované. Žádná SQL/data migrace nebo plošné přepsání uložených popisů.

### 2. Bezpečný SVG plánek

Rozšířit `web_client/src/utils/html.js` o jasně oddělený SVG sanitizer profil používající stejný DOMPurify instance mechanismus; zachovat stávající rich HTML profil beze změny. `SvgUtils.prepareBackgroundSvg` používá sanitizovaný výsledek a ověřený SVG root, upraví jen rozměry; při chybě vrátí prázdný/nepoužitelný background v existujícím návratovém tvaru, nikoli raw zdroj. `BlueprintRenderer.renderBackground` přeskočí odmítnuté pozadí, ale stále vykreslí sedadla. URL varianta zachová podporované bezpečné HTTP(S) obrazové zdroje; žádná navigace nebo interpretace URL jako inline SVG.

SVG profil zachová viewBox, transforms, paths, text, defs, gradienty, clipping a lokální reference `#id`/`url(#id)` pro podporované fixture. Zakáže event atributy, script/foreignObject, SMIL měnící URL/aktivní chování a nebezpečné href/xlink:href. Raster image reference povolit jen pro doložené obrazové protokoly/originy; data SVG a data HTML nepovolit. CSS zpracovat přes parser/ověřený sanitizační mechanismus, nikoli vlastním regexem; zachovat bezpečné grafické styly a lokální definice, odstranit externí importy a aktivní/nepovolené URL. Netvořit univerzální vlastní SVG parser.

Přidat `web_client/tests/components/blueprint_svg_security.test.js` s raw i malformed payloady a fixture kompatibility. Ověřit render samotné komponenty, změnu scale, kliknutí na sedadlo a nezměněný výběrový callback. Prokázat nepřítomnost původního raw fallbacku. Neprovádět hromadné přepisování uložených SVG, jejich souřadnic nebo rezervací.

### 3. CSP s funkčním reportováním

Vytvořit policy helper/manifest uvedený výše. Rozšířit existující `automation/cloudflare_build.sh`, `htmlResponse` a všechny HTML response větve včetně auth bridge a fallbacků. Zachovat status, redirect, cache, cookies i obsah. Duplicitní zdrojové `_headers` generovat ze stejného vlastníka; statický hosting dostane ekvivalentní podklady. Nikdy nespoléhat, že `_headers` automaticky ochrání Worker odpověď.

Zachovat současnou enforcing base/object policy a přidat kandidáta v `Content-Security-Policy-Report-Only`. Přidat `Reporting-Endpoints` a CSP `report-to`; pro browser kompatibilitu také `report-uri`. Použít stejný origin a novou malou route `/_security/csp-report` ve stávajícím Workeru, nikoli novou backend službu, databázi nebo placený produkt.

Report route přijímá jen POST podporovaných CSP JSON formátů, bounded stream max 32 KiB a max 10 reportů na batch. Příliš velká/neplatná data vrací odpovídající 4xx, validní příjem 204; `Cache-Control: no-store`. Nikdy nečte auth/session ani neposílá email. Z reportu loguje pouze pevné allowlist fields: porušená direktiva, disposition, profil a zkrácený origin zdroje; zahazuje query, fragmenty, document path s tokenem, referrer, cookies, sample a raw body. Nepoužít `report-sample`. Reporty jsou nedůvěryhodná diagnostika, nikoli bezpečnostní autorita. Proti objemovému zneužití využít dostupnou stávající edge ochranu/omezené sampling, bez zásahu do host/container limitů a bez placeného provisioningu.

Přidat `automation/tests/csp_policy.test.mjs` a `csp_hosting.test.mjs`: ověřit skutečné vygenerované odpovědi pro homepage, form, Flutter deep link, bridge, organizer a fallback; přesné hashes a chybějící/změněný script; report route s nesprávným MIME/method, přerostlým streamem i redakcí údajů. V `verify_web_build.mjs` gate ověřit policy manifest proti finálním dokumentům.

Výstup: reporting skutečně přijímá testovací syntetický violation a dokládá bezpečné logování, všechny entrypointy mají kandidátní policy. Samotná existence Report-Only hlavičky není dokončené zapnutí ochrany.

### 4. Funkčnost, rollout a enforcing CSP

Nejprve dokončit lokální/preview regresní kontrolu release buildu. XSS opravy nesmí čekat na dlouhou CSP analýzu: pokud je CSP blokovaná, vydat opravy a Report-Only jako první bezpečný release a zaznamenat zbývající gate. Následně dokončit CSP bez jejího trvalého oslabení.

Povinná matice: detail s legitimním rich HTML; SVG s gradienty/textem/lokálními odkazy; zoom/pan/výběr sedadla a návrat do formuláře; reálná lokální rezervace/objednávka v disposable tenantovi; přihlášení, logout a OAuth/bridge; Flutter admin deep link a načtení CanvasKit; push inicializace bez skutečného rozesílání; PWA první a opakovaný load, offline/online a update existující session; podporované embedded WebView scénáře. Browser checks jen headless, taskový prázdný config, bez uživatelova profilu. Použít `festapp-local-e2e` pro scénáře s DB a existující repository E2E commandy. Nenahradit deterministické CI scénáře ad hoc Playwrightem.

Pozorovat Report-Only v preview a následně v opraveném live webu. Přechod na enforcing povolit po úspěchu celé matice, potvrzeném příjmu syntetického reportu a vyřešení všech app-owned script violations z této matice. Odlišit browser-extension šum od legitimního provozu. Nečekat libovolný pevný počet hodin bez činnosti, ale ani nevydávat několik tichých minut za důkaz pokrytí reálných cest. Chybí-li reprezentativní cesta, stav je explicitně pending s konkrétním testem.

Po splnění gate přesunout schválenou script policy do `Content-Security-Policy`, zachovat reportování a zrušit identickou dočasnou Report-Only policy. Ověřit v preview a v produkci skutečné hlavičky všech reprezentativních dokumentů a že syntetický inline handler nyní prohlížeč blokuje, zatímco legitimní bootstrap/startup funguje. Nikdy nevkládat testovací payload do produkční akce nebo objednávky.

Produkční release: aktuální canonical main, tenant ancestry/drift, lokální build a `automation/deploy_direct.sh` podle repository release pravidel. Žádný GitHub Deploy workflow bez výslovného pokynu. Routine build/deploy a live-version ověření delegovat levnějšímu subagentovi `gpt-6-luna`, low, `fork_turns=none`, s přesným validovaným source SHA, jediným tenantem a gates; engineering neočekávanosti vracet primárnímu agentovi. Před publication respektovat branch protection, předepsané kontroly a aktuální upstream; preferovat přímý push/merge, pokud repository dovoluje.

### 5. GitHub ochrany

Tato vlna je nezávislá na web deployi a může se dokončit před ním; nemění runtime aplikace. Načíst a uložit pouze bezpečný before/after stav `repos/festappnet/festapp` a capabilities.

Zapnout secret scanning a pak push protection přes repository `security_and_analysis` (nebo odpovídající oficiální settings API). Podle dostupnosti bez nákupu zapnout non-provider patterns a validity checks. Zapnout vulnerability alerts a Dependabot security updates jejich vlastními API; nepředpokládat, že všechny funkce lze zapnout jediným PATCHe. Dostupnost/missing permissions vyhodnotit konkrétně a nehlásit zapnutí z pouhého HTTP success bez následného GET.

Zkontrolovat `.github/dependabot.yml` na aktuálním main. Chybí-li, přidat konfiguraci pro pět auditovaných npm rootů a GitHub Actions se seskupením kompatibilních změn a nízkým počtem otevřených PR. Ověřit odlišnost security updates a běžných version updates; výchozí úkol nejsou plošné major upgrades všech ekosystémů. Žádný auto-merge nebo oslabení CI.

Existující alerty prohlížet bez vypsání jejich secret values; případný skutečný únik je separátní incident s revokací, ne důvod automaticky přepsat historii nebo rotovat všechny session. Proveření celé Git historie použije lokální standardní secret scanner, pokud se zavádí CI gate; pinovat nástroj a GitHub Actions, nepřenášet obsah repozitáře do externího placeného scanneru. Novou gate nejprve ověřit vůči historii, aby legitimní práce uživatelů nekončila nekonečnými falešnými blokacemi; nalezené skutečné secrets neskrývat širokým allowlistem.

Výstup: přehled zapnutých funkcí s UTC readbackem; nepodporované/policy-locked možnosti mají konkrétní důvod. Netestovat push protection zasláním skutečného tajného údaje do public repozitáře.

## Odstranění starých cest a rollback

| Stará cesta | Konečný stav a důkaz |
| --- | --- |
| Raw interpolace detailu akce | Nahrazená bezpečnými text/rich HTML hranicemi; test skutečného renderu |
| Raw/malformed SVG fallback | Odstraněný; odmítnutí nebrání vykreslení sedadel |
| Druhá ručně psaná CSP ve `_headers` | Generovaná ze stejné policy jako Worker; test parity |
| Report-Only jako jediná script ochrana | Jen přechodový stav s gate; při dokončení enforcing aktivní |
| Široké CSP výjimky k umlčení chyb | Nezavedené; každá odůvodněná úzká výjimka má konkrétní runtime důkaz |

Před rolloutem uložit předchozí bezpečnou policy/release identitu. Při CSP regresi lze vrátit script část na předchozí Report-Only při zachování obou XSS oprav a base/object ochrany. **Nerollbackovat celý web na zranitelný renderer.** Nouzový opravný build nebo release zachovávající opravy musí být dostupný. GitHub ochrany nevypínat kvůli běžnému nálezu; řešit konkrétní false positive schváleným GitHub mechanismem.

## Ověřování a definice hotovo

Při plánování se testy nepouštějí. Exekutor po souvislé implementaci spustí cílenou dávku, například z `web_client`:

```sh
node --test tests/utils/html_sanitize.test.js tests/forms/field_html_security.test.js tests/components/occasion_detail_security.test.js tests/components/blueprint_svg_security.test.js tests/components/blueprint_viewport.test.js tests/components/occasion_card_action.test.js
```

Z kořene:

```sh
node --test automation/tests/csp_policy.test.mjs automation/tests/csp_hosting.test.mjs automation/tests/public_seo.test.mjs automation/tests/google_auth_hosting.test.mjs
bash automation/test_web_startup.sh
```

Nové testové názvy jsou plánované soubory, ne již existující testy. Respektovat aktuální pravidla pro CSS importy/DOM fixture, nedělat ad hoc loader místo repository contractu. Před commitem/publikací vyžaduje současné `CONTRIBUTING.md` kompletní `./automation/test_all.sh`; tuto gate nelze nahradit jen výše uvedenými cílenými příkazy. Build/publikaci ověřovat na skutečném final artefaktu a vlastní bezpečné browser matici. Passing kontrolu neopakovat bez nové změny nebo důvodu.

Hotovo znamená:

- Dvě původní exploitační cesty nefungují ani bez CSP; legitimní renderovací a rezervační chování prošlo.
- CSP enforcing je aktivní na skutečných dokumentech zvoleného live tenanta, reportování funguje a matice pokrývá i Flutter/PWA/OAuth. Jinak výslovně uvést částečné dokončení a konkrétní zbývající gate.
- GitHub secret scanning a push protection jsou potvrzené readbackem; ostatní schválené dostupné ochrany také. Případný externí blocker je přesný, bez tvrzení „zapnuto“.
- Canonical main a jediný tenant odpovídají validovaným SHA a live-version; žádný nepatřící diff ani starý lock nepřenesen.
- Záznam výsledku `docs/operations/web-security-hardening-result-2026-10-18.md` obsahuje testy, source/deploy identity, policy profiles/hash, GitHub before/after a zbývající rizika. Neobsahuje secrets ani syrové CSP reporty.
- Container limity a práce druhé session zůstaly beze změny.

Zbývá obecné riziko dalších neauditovaných XSS sinků a třetích stran. Tento balík nepředstírá úplný penetrační audit ani kompatibilitu všech historických SVG a prohlížečů bez důkazu.

## Primární dokumentace

- [MDN CSP Report-Only](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy-Report-Only): HTTP reporting a rozdíl od enforcement; reportování nelze zavést meta tagem.
- [Cloudflare Pages headers](https://developers.cloudflare.com/pages/configuration/headers/): vlastní hlavičky Worker/Function odpovědí nelze nahradit samotným `_headers`.
- [GitHub repository REST API](https://docs.github.com/en/rest/repos/repos#update-a-repository) a [push protection](https://docs.github.com/en/code-security/how-tos/secure-your-secrets/prevent-future-leaks/enable-push-protection): dostupné repository bezpečnostní operace ověřovat podle konkrétního účtu a readbacku.
