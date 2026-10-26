# Joomla: prodej vstupenek přes existující službu

Datum: 2026-10-26
Stav: Dokončeno lokálně 2026-10-26. Dvě distribuce 1.0.0 a reálné Joomla ověření předány; JED/produkční publikace neprovedena.
Ověření: úsporné plánování; při realizaci cílené `standard` pro validaci veřejných URL, escapování a oprávnění CMS.

## Výsledek realizace

Aktuální návod a ověřené SHA: [Joomla README](../../../integrations/joomla/README.md)
a [readiness](../../../integrations/joomla/READINESS.md). Ověřeno Joomla 5.4.10 /
PHP 8.3.36 a Joomla 6.1.4 / PHP 8.4.27, oba produkty, nativní ukládání, ACL/CSRF,
cache, přeinstalace a odinstalace; browser na skutečné disposable fixture.
Checkout ani embed protokol služby se neměnil. Nový syntetický nákup nebyl potřeba.
Zjištěné chování cache článku po odinstalaci je popsané v návodu.
Externí publikační brány zůstávají v readiness: skutečný update server pro JED,
veřejné download/demo stránky a potvrzení obsahu servisních/právních URL
(HTTP sonda byla blokovaná 403). Nejde o blokery dokončeného lokálního adaptéru.
Následující text zachovává původní návrh jako historický podklad.

## Výsledek a navržený goal

Vytvořit a lokálně ověřit Joomla doplněk, který pořadateli umožní nainstalovat
ZIP, vložit uložený veřejný odkaz na formulář a zveřejnit prodej na vlastním
webu. Použít existující checkout a embed kontrakt Festapp. Výsledkem budou
reprodukovatelné instalační ZIPy, český a anglický onboarding, stručný návod
a důkaz instalace, publikace a funkce v reálné izolované Joomle.

Goal končí ověřenými lokálními balíčky a předáním. Veřejná publikace v Joomla
Extensions Directory (JED), produkční instalace a nasazení služby jsou další
samostatné kroky. Schválení katalogem nelze zahrnout do garantovaného výsledku.

## Rozsah navržený k odsouhlasení

- Jeden Joomla site modul jako uživatelský doplněk. Umístění do pozice šablony
  a do článku přes standardní Joomla vložení modulu podle ID. Samostatný
  obsahový plugin ani vlastní správce akcí nejsou potřeba.
- Stejně jako WordPress dvě samostatné distribuce ze společného zdroje:
  `mod_vstupenky_online` pro `https://vstupenky.online` a
  `mod_festapp_tickets` pro `https://tickets.festapp.net`. Oba balíčky musí
  fungovat samostatně i současně. Toto je návrh rozsahu, nikoli již schválená publikace.
- Uložený odkaz, přístupný název iframe, automatická nebo pevná výška
  240-4000 px (výchozí 800), převzetí vzhledu zapnuté ve výchozím stavu
  a záložní odkaz do nové záložky.
- Nativní nastavení Joomly, české a anglické překlady a krátký postup:
  účet služby -> uložený formulář -> vložení odkazu -> zveřejnění modulu.
- Cílové řady Joomla 5.4 a 6.1. Při zahájení realizace jednou ověřit jejich
  podporu a připnout dostupné přesné patch verze a PHP. Starší řady neslibovat.

Mimo rozsah: nový checkout, nové objednávkové API, přihlášení do služby přes
Joomlu, synchronizace zákazníků, vlastní platby, Joomla e-shop integrace,
změny databáze, Flutter buildy a automatická publikace do katalogu.

## Podklady a poučení z WordPressu

| Ověřený podklad | Co z něj převzít |
| --- | --- |
| `docs/integrations/embedded-checkout.md` | Jediný technický kontrakt: uložená cesta `/form/<slug>?embed=1`, host wrapper, iframe, tenant `/embed.js`, protokol 1. |
| `integrations/wordpress/shared/embed.php.in`: `validate_url`, `render` | Přesný origin, kanonické kódování slugu, bezpečný HTML výstup, výšky, varianty helperu a fallback. |
| `integrations/wordpress/shared/admin.php.in` | Srozumitelný onboarding; účet CMS a účet služby jsou oddělené; admin nenačítá vzdálený checkout. |
| `integrations/wordpress/products.json`, `scripts/build-plugins.py`, `scripts/package.py` | Dvě explicitní značky, společná šablona, oddělené identifikátory a deterministické ZIPy. |
| `integrations/wordpress/tests/contract.php`, `tests/dual-products.php` | Negativní URL případy, izolace produktů, více instancí a bezpečné renderování. Převzít scénáře, nikoli mock WordPress API. |
| `integrations/wordpress/READINESS.md` | Instalovaný ZIP, skutečný editor, životní cyklus a nákup mají odlišnou důkazní hodnotu; připravenost není publikace. |
| `docs/plans/integration-distribution-and-help-2026-10-24.md` | Joomla už je navržený další kanál; podpora služby nesmí vytvořit druhý platební model. |

Průchod: správce uloží URL v modulu -> Joomla ověří oprávnění k uložení ->
serverový renderer znovu ověří uloženou hodnotu -> návštěvník dostane iframe
a fallback -> stávající služba vykonává nákup. Parent/child komunikaci
nadále vlastní `web_client/public/embed.js` a `web_client/src/services/embed_bridge.js`.

Dokumentace Joomly ověřená 2026-10-26:

- [Site modul, manifest, provider a namespace](https://manual.joomla.org/docs/building-extensions/modules/module-development-tutorial/step1-basic-module/).
- [Web Asset Manager](https://manual.joomla.org/docs/general-concepts/web-asset-manager/).

Ve workspace je rozsáhlá cizí rozpracovaná práce a aktivní větev
`feat/occasion-setup-wizard-20261007`. Před implementací vymezit vlastní nové
soubory; před případným commitem použít větev založenou na `main` a přenést jen
vlastní změny. Neprovádět hromadný stash, reset ani přepínání špinavého checkoutu.

## Architektura a invarianty

1. Nové zdroje žijí v `integrations/joomla/`: `products.json`, `shared/`,
   `scripts/`, `tests/`, `README.md`, `READINESS.md`. Build a ZIPy jsou odvozené
   výstupy. Nevytvářet závislost instalovaného modulu na WordPress pluginu.
2. Joomla provider a dispatcher používají podporované CMS API a template layout.
   Helper obsahuje pouze URL validaci a HTML prezentaci. Značky mají vlastní
   namespace, element, překladové klíče a asset handle.
3. Povolit pouze vlastní přesný produkční HTTPS origin a kanonickou veřejnou
   cestu. Odmítnout query, fragment, credentials, porty, poddomény, alternativní
   schémata, nejednoznačné kódování a cesty do administrace. Žádné stahování
   uživatelských URL serverem. Neplatný vstup zobrazí bezpečné lokální hlášení.
4. Každá veřejná instance má `data-festapp-embed-host`. Auto výška nebo
   převzetí vzhledu vyžadují helper; pevná výška s vypnutým převzetím jej
   nenačítá. Pevná výška s převzetím používá `data-festapp-height="fixed"`.
5. Externí helper registruje Web Asset Manager jednou na origin a stránku.
   Ověřit chování při vložení modulu do článku i při Joomla cache; žádné
   inline skripty ani kopie `/embed.js` v balíčku. Modulová cache nesmí
   způsobit chybějící registraci helperu - v první verzi ji vypnout a doložit.
6. Admin nastavení a preview nenačítají službu ani iframe. Ukládání chrání
   Joomla ACL a CSRF. Nepřidávat vlastní nechráněný endpoint. URL a title jsou
   znovu validované/escapované při renderu, bez ohledu na validaci formuláře.
7. Do Joomly se neukládají service tokeny, objednávky ani osobní údaje kupujících.
   Nákup se nikdy automaticky neopakuje. Služba zůstává vlastníkem cen,
   rezervací, objednávek, plateb, e-mailů a odbavení.
8. Fallback funguje při výpadku helperu. Návod vysvětlí externí službu a
   potřebné CSP `frame-src`/`script-src`. Nepřidávat neověřený iframe sandbox
   ani sliby univerzální podpory karetních bran, Safari a bankovních aplikací.

## Postup realizace

### 1. Společný zdroj a první instalovatelný balíček

V `integrations/joomla/shared/` vytvořit šablony manifestu, provideru,
dispatcheru, rendereru, layoutu a překladů. V `products.json` oddělit dvě
identity. `scripts/build.py` a `scripts/package.py` mají generovat samostatné
balíčky s licencí, deterministickým pořadím/časem ZIP entries, SHA-256
a manifestem vstupů. Neprovádět společný refaktor WordPressu jen kvůli reuse.

Bez migrací a bez úprav checkoutu. Selhání nebo odinstalace modulu nemá
měnit službu. Výstupem etapy jsou dva skutečné instalační ZIPy; žádné placeholdery.
Kontroly kódu a balíčků se provedou společně po dokončení této souvislé změny.

### 2. Nastavení a první zveřejnění

Přidat parametry, bezpečný render a nativní onboarding. Návod musí popsat
instalaci, vytvoření modulu, uložení odkazu, stav Published, přiřazení ke
stránkám a vložení do článku podle ID. V administraci nesmí být nutné psát HTML.
Vazby na účet, podmínky, soukromí a podporu musí odpovídat skutečné značce.

Výstup: správce může z instalovaného ZIPu zveřejnit prodej oběma cestami;
publikovaný obsah přežije uložení a reload. Při chybné URL se služba nenačte.

### 3. Jedna cílená ověřovací sada

V `tests/` a `scripts/` vytvořit opakovatelný vstup `scripts/verify.sh`.
Použít skutečně instalované ZIPy v izolované lokální Joomle a vlastní testovací
DB bez produkčních přístupů. Připnout image verze/digesty a zapsat skutečně
ověřené kombinace Joomla/PHP. Existující WordPress scénáře slouží jako zadání,
nejsou důkazem průchodu v Joomle.

Sada ověří:

- Syntax PHP, manifesty a skutečnou instalaci obou ZIPů na obou cílových řadách.
- Přesný origin, kanonický Unicode slug, negativní URL případy, XSS/title,
  hranice výšky a všechny kombinace auto/fixed a převzetí vzhledu.
- ACL a CSRF uložení přes Joomla; žádné vzdálené načítání v administraci.
- Publikaci do pozice a článku, reload, více instancí, souběh obou značek,
  helper právě jednou na origin, chování s cache i bezpečný fallback.
- Reinstalaci/upgrade stejného balíčku, zachování nastavení a odinstalaci jedné
  značky bez poškození druhé. Neprohlašovat tím ověření neexistující starší verze.
- Jeden browser průchod v hlavní kombinaci: mobilní šířka 320 px, klávesnice,
  načtení formuláře, automatická výška, otevření/zavření plánku a blokovaný helper.
  Použít skill `agent-browser`, headless pojmenovanou session a vlastní profil.

Pro formulář a plánek použít existující disposable fixture popsanou v
`integrations/wordpress/README.md` a embed dokumentaci; nezakládat druhý testovací
backend. Začít omezeným čtením příslušných setup příkazů při realizaci.
Nový skutečný syntetický nákup provést pouze tehdy, když adaptér změní
objednávkový průchod nebo objevená chyba zneplatní existující důkazy služby.
Pouhé načtení formuláře se nesmí vykázat jako úspěšný nákup.

Pro jeden Flutter task, pokud ho disposable fixture vyžaduje, nejdříve ověřit
volný workstation slot. Browser ani Docker prostředí ostatních relací nerušit.
Výstup: uložený kompaktní receipt skutečných kontrol a poctivé omezení důkazů.

### 4. Předání a příprava případné distribuce

Dokončit `README.md` a `READINESS.md`, znovu sestavit finální balíčky a svázat
ověření s jejich hashi. Změní-li repack runtime soubory, opakovat jen zasažené
kontroly. Zkontrolovat aktuální oficiální pravidla JED pro tento typ SaaS
integrace, licenci, veřejné servisní/právní odkazy a způsob aktualizací.
Zapsat konkrétní podmínky publikace; schválení nevydávat za jisté.

Vyčistit vlastní kontejnery, DB, sessions a procesy. Finální předání má obsahovat
odkazy na oba ZIPy, hashe, ověřené Joomla/PHP verze a přesný zbývající krok.
Po dokončení přesunout tento plán a prompt do archivu podle pravidel repozitáře.

## Úsporný režim realizace

- Začít tímto plánem a uvedenými soubory, ne novým průzkumem celého repozitáře.
- Jeden společný generátor a jeden renderer pro obě značky; nepřenášet
  WordPress infrastrukturu a neopakovat její historické audity.
- Souvislou změnu dokončit před validací. Cílené kontroly spustit jako jednu
  sadu, úspěšné výstupy držet na jedné řádce. Neopakovat průchod pro nezměněné vstupy.
- Ověřit kontrakt na obou CMS řadách, plný browser průchod jednou. Další
  kombinace přidat jen při konkrétním rozdílu nebo selhání.
- Žádný Flutter build ani plné repository testy pro samostatný Joomla adaptér.
- Rutinní generování, doklady a průběžné komentáře držet krátké. Nezakládat
  další agenty nebo nezávislý audit bez výslovného zadání.
- Při změně sdílené služby zastavit rozšiřování rozsahu: zapsat nález,
  dopad a potřebnou cílenou opravu, neskrývat backend práci do CMS doplňku.

## Rozhodnutí, předpoklady a zbývající hranice

- **Návrh rozhodnutí:** site modul, dvě značky, lokálně ověřené balíčky jako
  konec goalu. Uživatel může před spuštěním rozsah zúžit na českou distribuci.
- **Předpoklad:** původní embed kontrakt postačí. Řešení při neplatnosti:
  doložit konkrétní Joomla reprodukci a upravit plán před změnou společného protokolu.
- **Předpoklad:** vhodná CMS/PHP image a disposable fixture jsou dostupné.
  Přesné verze ověřit jednou při startu; při nedostupnosti uvést konkrétní
  neověřenou řadu, neslibovat širší kompatibilitu.
- **Externí hranice:** účet JED, pravidla katalogu a jeho review nejsou lokální
  implementační důkaz. Kontaktování lidí ani přijetí smlouvy není tímto plánem autorizováno.
- **Rollback:** lokálně odinstalovat modul; existující objednávky i služba
  zůstávají u původního vlastníka. Žádná migrace ani odstraňování legacy cest
  se neplánuje, jde o přidání dalšího CMS adaptéru.

## Podmínky dokončení goalu

- Dva reprodukovatelné ZIPy ze společných zdrojů, oddělené identity a hashe.
- Nativní české/anglické nastavení a onboarding; publikace do pozice i článku.
- Validace URL a bezpečný HTML výstup, žádný druhý checkout ani tajné údaje v CMS.
- Úspěšná cílená sada nad instalovanými ZIPy, reálný browser průchod
  a výslovně uvedené případné externí blokery. Neúspěšná povinná kontrola znamená
  nedokončený goal, nikoli jen poznámku v předání.
- Návod, readiness a čisté ukončení vlastního prostředí. Publikace a produkční
  nasazení jsou výslovně oddělené a neproběhly.

## Stav při sepsání

Prvotně omylem vytvořené implementační soubory byly odstraněny po upřesnění
uživatele. Zůstávají pouze tento plán a realizační prompt. Během průzkumu byl
stažen Docker image `joomla:6-php8.4-apache`; nebyl spuštěn žádný Joomla
kontejner ani test. Tento tag není náhradou připnuté verze při realizaci.
