# Joomla: vstupenky.online / Festapp Tickets

Česká distribuce **vstupenky.online 1.0.5** a samostatná globální varianta 1.0.2
ze společného zdroje. Toto vydání se týká pouze vstupenky.online. Finální český balíček má název
[vstupenky.online.zip](dist/vstupenky.online.zip). Kandidáti obou značek jsou
v [artifacts/](artifacts/); SHA-256 a vstupní/souborové manifesty obsahuje
[evidence/packages.json](evidence/packages.json). Stav ověření a publikační
hranice: [READINESS.md](READINESS.md).

| Modul | Povolený origin |
| --- | --- |
| mod_vstupenky_online | https://vstupenky.online |
| mod_festapp_tickets | https://tickets.festapp.net |

## Joomla Extensions Directory

[Veřejný záznam vstupenky.online](https://extensions.joomla.org/extension/vstupenky-online/)
obsahuje krátký popis služby a screenshoty českého rozhraní s ukázkovými daty.
Český popis vyberte v **Full description > Language > Czech**; hlavní text
vyžaduje katalog anglicky. ZIP je zdarma pod GPLv2 or later. Označení
**Paid download** vychází z pravidla JED C2.4 pro integraci s placenou SaaS
službou; cena služby se sjednává samostatně.

## Instalace a první zveřejnění

1. V příslušné službě vytvořte účet pořadatele, akci a uložený veřejný formulář.
   Účet služby je oddělený od účtu Joomly. Pro placený prodej dokončete obchodní
   a platební nastavení služby.
2. Joomla: **Systém > Instalace > Rozšíření > Nahrát soubor balíčku**. Vyberte
   ZIP správné značky. Obě značky lze nainstalovat současně.
3. **Obsah > Moduly stránek > Nový**: vyberte vstupenky.online nebo Festapp
   Tickets. Vyplňte název modulu a uložený veřejný odkaz
   `https://vstupenky.online/form/slug`, respektive
   `https://tickets.festapp.net/form/slug`. Parametry, fragmenty, administrace
   ani URL druhé značky nejsou přípustné. Diakritiku ponechte kanonicky
   zakódovanou ze zkopírovaného odkazu, například `%C5%BE`.
4. Zvolte **Cíl měření**. Nový modul doporučuje **Web**, existující modul bez této volby zachovává **Jednotka Festapp**. Režim webu předává události a konverzní kontakty skriptům stránky, proto vyžaduje odpovídající souhlas a schválenou doménu. Vzhled se řídí uloženým nastavením formuláře ve službě. Nastavte modul jako **Zveřejněný**, přístup **Veřejný**, zvolte pozici své
   šablony a v **Přiřazení nabídky** vyberte požadované stránky. Uložte a
   otevřete veřejnou stránku. V nastavení modulu se externí formulář nenačítá.
5. Pro vložení do článku zapněte standardní Joomla plugin **Obsah - Načítání
   modulů** a do článku napište `{loadmoduleid 123}`. Číslo nahraďte skutečným
   ID modulu ze seznamu. Vyberte vlastní neexistující pozici, například
   `ticket-article`, pokud se stejný modul nemá zároveň zobrazit v šabloně.
   Zkontrolujte publikaci, přístup a přiřazení nabídky modulu i článku.

Čeština a angličtina jsou součástí obou ZIPů; Joomla zvolí jazyk podle svého
aktivního jazyka. Pro celou českou administraci nainstalujte český jazyk Joomly.
Přístupný název iframe popisuje formulář pro čtečky. Výchozí výška je 800 px,
povolený rozsah 240-4000 px. Výchozí je automatická výška; vzhled vlastní uložený formulář.
Pevná výška používá stejný externí helper pro vzhled jako automatická. Záložní
odkaz otevírá běžný formulář v nové záložce i při blokování helperu.

## External service / English setup

Install the matching ZIP through **System > Install > Extensions**. Under
**Content > Site Modules > New**, select the brand, paste its saved public
`/form/slug` URL, choose a descriptive iframe title, set **Published**, select
a template position and assign menu items. Save and view the public page.
For articles, enable Joomla's **Content - Load Modules** plugin and insert
`{loadmoduleid 123}` with the actual module ID. Use a custom position when the
module should appear only in the article. The English/Czech onboarding in the
native module settings explains the separate organizer account and service links.

Orders, prices, seat reservations, payments, email, PDFs and admission remain
in the external service. Joomla stores only the public URL and presentation
settings. No API keys, organizer login or buyer orders are copied to Joomla.
The module makes no server-side request to the supplied URL. Website appearance
sharing may load website fonts inside the iframe, subject to font CORS.

## CSP, cache, updates and removal

Povolte odpovídající origin v CSP `frame-src`; pro automatickou výšku nebo
převzetí vzhledu také v `script-src`. Helper je externí `/embed.js`, registrovaný
přes Web Asset Manager jednou pro značku na stránku. Modul nepřidává inline
JavaScript ani vlastní kopii helperu. Nepřidávejte neověřený iframe sandbox.
Hostitelská šablona musí povolit vykreslení stylu rozměrů iframe. Každá stránka
obsahuje i veřejný odkaz; použijte jej, pokud web iframe zakazuje.

Cache výstupu modulu je vypnutá (skrytý parametr `cache=0`), aby registrace
helperu nebyla vynechána. Ověřena konzervativní globální cache Joomly a opakované
načtení. Plná cache stránky, CDN a cizí optimalizační pluginy vyžadují vlastní
ověření a vyčištění po změně. Neslibujeme univerzální chování všech platebních
bran, Safari ani bankovních aplikací; platí limity stávajícího embed kontraktu.

Český modul registruje stabilní [Joomla update XML](https://raw.githubusercontent.com/festappnet/festapp/main/integrations/joomla/updates/vstupenky-online.xml).
Nové verze se zobrazí v **Systém > Aktualizace > Rozšíření**; instalace probíhá
standardním Joomla updaterem. ZIP je veřejný GitHub release asset, feed obsahuje
SHA-256 a podporované řady Joomla 5.4/6.1 s PHP 8.3 nebo novějším. Lze také ručně
nahrát novější český ZIP přes instalátor. Původní lokální 1.0.0 neměla update
kanál; první přechod na aktuální vydání vyžaduje ruční instalaci. Globální varianta má
zatím pouze ruční aktualizace a není součástí tohoto veřejného vydání.

Ověřena přeinstalace při zachování nastavení i skutečný updater přes lokální
HTTP kopii feedu a identické bajty vydávaného ZIPu. Test starší instalace používá
výslovně syntetickou verzi v metadatech, neslibuje dřívější veřejné vydání.
Odinstalace přes **Systém > Správa > Rozšíření** odstraní modul a jeho nastavení,
nikoli objednávky ve službě. Druhá značka zůstává samostatná. Po změně nebo
odinstalaci modulu vloženého do článku vyčistěte také cache Joomly
(**Systém > Údržba > Vymazat mezipaměť**), zejména `com_content`.
Joomla může do té doby uchovávat předchozí vykreslení článku.

Služby: [vstupenky.online](https://vstupenky.online/),
[Festapp Tickets](https://tickets.festapp.net/). Každý modul má v administraci
odkazy své značky na `/login`, `/terms/`, `/privacy/` a `/support/`. Přístupové
podmínky a ceny služby jsou oddělené od GPL licence modulu.

## Reproducible build and verification

Vyžaduje Python 3, Docker a `agent-browser`; PHP poskytují připnuté kontejnery.
Není potřeba Flutter ani JavaScript závislosti pro sestavení samotných ZIPů.

```sh
cd integrations/joomla
python3 scripts/package.py
python3 scripts/environment.py start
```

Testovací kontejnery používají vlastní síť/databázi a pouze loopback porty
59915/59916. Přesné image digesty jsou v `docker-images.json`. Hesla jsou náhodná
v ignorovaném `.private/` (0600). Moduly se instalují z ZIPů, nejsou mountované
ze zdrojů. K opakování celé sady začněte novým prostředím nebo proveďte stop/start.

Browser používá existující [disposable fixture](../wordpress/README.md#disposable-služba)
na 59821, nebo samostatný označený Joomla backend na 59931. Backend musí
odpovídat aktuálnímu RPC kontraktu; starou neprázdnou fixture nepřepisujte.
Pro aktuální schéma použijte oddělenou databázi s kanonickou baseline a upgrady.
Browser scénáře používají české odkazy `ples-u-lipy` a `ples-u-lipy-mistenky`
navázané v této nové fixture na její syntetické formuláře. Neseedujte znovu
neprázdnou cizí databázi. Je-li již spuštěná, použijte ji bez restartu či změn.
Pro službu použijte její existující snapshot a příkaz `pnpm run web:start`
z adresáře `integrations/wordpress`; pnpm 11.24.0. Vlastní testovací TLS
certifikát a HTTPS frontend jsou popsány v `scripts/fixture.sh`.

```sh
# V samostatném terminálu: HTTPS frontend existující fixture.
./scripts/fixture.sh
# S běžící fixture a oběma CMS:
python3 scripts/verify.py
python3 scripts/release-gate.py
python3 scripts/environment.py stop
```

Browser test mapuje pouze ve svém izolovaném headless profilu produkční jméno
vstupenky.online na lokální HTTPS frontend 59803. ZIP neobsahuje vývojový origin
ani konfigurační bypass. Globální vzdálené požadavky jsou v testu blokované.
Jde o skutečný formulář a plánek proti disposable backendu, bez odeslání nákupu.
Zastavte jen proces fixture spuštěný touto relací a zavřete jen session
`festapp-joomla-20261026`. Nikdy nepoužívejte globální Docker prune/stop.

## Český release gate

[SUBMISSION.md](SUBMISSION.md) odděluje ověření balíčku, schválení kritikem,
veřejné vydání ZIPu a případné katalogové podání. `scripts/verify.py` spustí
celou cílenou sadu a sváže každý zdrojový/testovací vstup, nainstalované soubory,
živé sondy a receipty s přesným hashem kandidáta. Změna vstupu nebo důkazu
zneplatní `scripts/release-gate.py`. ZIPy se zachovávají pod neměnným SHA-256;
`dist/vstupenky.online.zip` je pohodlná kopie, jejíž shodu gate také kontroluje.

Běžná návštěva i release sonda mají ověřenou dostupnost servisních/právních
URL. Cloudflare odmítá obecný `Python-urllib` User-Agent chybou 1010; sonda se
proto poctivě identifikuje jako `Festapp-Joomla-Release-Check/1.0` a ověřuje také
obsah stránek. Nejde o vypnutí ochrany. Živý browser test používá skutečný
produkční helper a veřejný formulář z nainstalovaného Joomla modulu, bez
odeslání objednávky nebo výběru sedadla.

## Centrální vzhled formuláře

Jediný vlastník je uložené `forms.data.design.embed_inherit_style`. Oprávněný editor ho nastaví ve Vzhledu formuláře a formulář uloží. Všechna vložení použijí tuto volbu při příštím načtení bez výměny HTML. Nativní doplněk ukládá odkaz a své nastavení výšky či názvu, nikoli vlastní volbu vzhledu. Staré uložené atributy jsou neúčinné a nové verze je negenerují. Helper zůstává v obou režimech výšky; plánek sálu se nepřebarvuje.

Níže uvedené dřívější publikační důkazy dokládají své historické verze, ne nový centrální kontrakt.


## Measurement destination

Existing blocks, shortcodes and modules retain the Unit runtime. Select Website
dataLayer explicitly to use the website's tags and consent manager. The setting
is `measurement="host"` or `measurement="unit"`; missing or invalid values select
`unit`. Website mode shares bounded conversion contacts and transaction IDs with
page scripts. It does not install tags, grant consent or enable measurement.
Both modes require enabled Festapp measurement and an approved website origin.
Unit mode requires a consent adapter. See the canonical
[measurement contract](../../docs/integrations/form-datalayer.md).

New modules select Website mode, recommended for websites with their own GTM and consent banner. Saved modules without a measurement parameter keep Unit mode, including when reopened in the editor. Unit mode reads the website Consent Mode unless an explicit adapter is connected.

## Převzetí souhlasu s cookies do nové záložky

Volitelná karta **Souhlas s cookies** v nastavení modulu předá uloženou volbu lišty
webu formuláři otevřenému v nové záložce. Podporované lišty v Joomle jsou
**Cookiebot** a **CookieConsent v3 (orestbida)**; Complianz existuje jen pro WordPress.
Výchozí stav je vypnuto a výstup zůstává bajtově stejný jako dosud.

1. Ve službě zapněte **Převzít souhlas z lišty schválených webů** a web přidejte
   do **Moje weby**; převzetí funguje až po schválení webu platformou.
2. V modulu zapněte převzetí, vyberte lištu a vyplňte ID organizace a jednotky
   a `analytics.consent_revision` z metadat formuláře. Cookiebot: CBID, přesný
   HTTPS origin, `consentValidFrom` (UTC ISO s milisekundami a `Z`) a
   `maxAgeSeconds` nejvýše 31536000. CookieConsent: kladná `revision`, volitelně
   názvy obou kategorií. Prázdná pole jen navrhnou origin webu a aktuální okamžik
   jako zástupný text; uloží se pouze to, co správce zadá. Hodnoty jsou prohlášením
   pořadatele o pokrytí lišty, nikdy se negenerují z požadavku ani neaktualizují.
3. **System - HTTP Headers**: nastavte *Cross-Origin-Opener-Policy* na
   `same-origin-allow-popups`. Výchozí `same-origin` novou záložku v Chromiu
   a Firefoxu odpojí a formulář se zeptá sám (ověřeno v E2E testu níže).

Neplatné nastavení nelze uložit; uložené neplatné hodnoty modul ignoruje, odkaz
zůstane s `rel="noopener noreferrer"` a skript bez `data-festapp-consent`. Platné
nastavení vydá konfiguraci na jediném `embed.js` (Cookiebot také
`data-cookieconsent="ignore"`) a odkaz modulu označí `data-festapp-consent-link`
bez `noopener noreferrer`. Stejné nastavení ve více modulech sdílí jeden skript;
odlišné nastavení na stejné stránce převzetí na celé stránce vypne. Konflikt,
neplatné hodnoty a výchozí COOP se zapisují jako varování do logu Joomly
(*Log Almost Everything* nebo ladění). Nastavení platí i pro vložené formuláře
v režimu měření jednotky na stejné stránce. Jedna stránka obslouží jednu značku:
pokud jsou na ní moduly obou značek, běží jen první načtený helper.

**Zobrazení → Pouze tlačítko** vykreslí jen odkaz (výchozí třídy `btn btn-primary`)
bez iframe, například do menu nebo na úvodní stránku. Bez převzetí souhlasu tento
režim nenačítá žádný externí skript. Ruční odkazy v článcích se nedoporučují:
editor TinyMCE k `target="_blank"` doplňuje `rel="noopener"`, který převzetí vypne.

## Cookie consent transfer to a new tab (English)

The optional **Cookie consent** tab passes the website banner's saved choice to a
form opened in a new tab. Supported Joomla banners: Cookiebot and CookieConsent v3
(orestbida). Enable “Take over consent from the banner of approved websites” and
add the website under “My websites” in the service. Enter the organization/Unit
IDs, `analytics.consent_revision`, and the CMP-specific values from the
[measurement contract](../../docs/integrations/form-datalayer.md#live-consent-transfer-to-a-new-tab).
Empty fields only show suggestions as placeholders; the module stores only what
the administrator saves and never derives values from requests. Set Joomla's
**System - HTTP Headers** Cross-Origin-Opener-Policy to `same-origin-allow-popups`.
Invalid, missing or conflicting settings keep the legacy link and an unconfigured
helper. **Display → Button only** renders a marked link without an iframe.

Tests: `tests/consent-contract.php` (stubbed APIs, also in `automation/test_embed_adapters.sh`
and both CMS containers), `tests/consent-page.py` (native saves and public markup),
`node tests/consent-parity.mjs` (generated settings accepted by the real adapters;
needs `web_client` dependencies and PHP) and `node tests/consent-browser.mjs
[--browsers=chromium,firefox,webkit] [--cookiebot]` (browser E2E with real
CookieConsent 3.3.0 in the Joomla template and, with `--cookiebot`, the live
Cookiebot SDK of a dedicated test domain answered locally; no production form,
order, lead or measurement request).
