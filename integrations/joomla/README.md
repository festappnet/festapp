# Joomla: vstupenky.online / Festapp Tickets

Česká distribuce **vstupenky.online 1.0.1** a samostatná globální varianta 1.0.0
ze společného zdroje. Toto vydání se týká pouze vstupenky.online. Finální český balíček má název
[vstupenky.online.zip](dist/vstupenky.online.zip). Kandidáti obou značek jsou
v [artifacts/](artifacts/); SHA-256 a vstupní/souborové manifesty obsahuje
[evidence/packages.json](evidence/packages.json). Stav ověření a publikační
hranice: [READINESS.md](READINESS.md).

| Modul | Povolený origin |
| --- | --- |
| mod_vstupenky_online | https://vstupenky.online |
| mod_festapp_tickets | https://tickets.festapp.net |

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
4. Nastavte modul jako **Zveřejněný**, přístup **Veřejný**, zvolte pozici své
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
povolený rozsah 240-4000 px. Automatická výška a převzetí vzhledu jsou výchozí.
Pevná výška s vypnutým převzetím vzhledu externí helper nepotřebuje. Záložní
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
kanál; první přechod na 1.0.1 vyžaduje ruční instalaci. Globální varianta má
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
na 59821, formuláře `embedded-synthetic` a `embedded-seats`. Neseedujte znovu
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
