# vstupenky.online - kontrola publikovatelnosti

## Připravená oprava kanonického odkazu 1.0.2

Nový zdrojový balíček 1.0.2 používá výhradně homepage `https://vstupenky.online/`. Kontrola proti původně vydanému 1.0.1 potvrzuje změnu pouze URL, verze a changelogu, nikoli runtime. Tento kandidát zatím nebyl nově publikován ani odeslán do katalogu; dřívější balíček a důkazy 1.0.1 zůstávají historicky platné. Před publikací je nutné splnit obvyklé release brány. Staré externí odkazy obsluhuje pouze přímé přesměrování na homepage.

**Podáno 2026-10-24:** vstupenky.online 1.0.0, předběžný slug
`vstupenky-online`. Automatická kontrola WordPress.org: **Pass**.
Ruční kontrola: **Awaiting Review**. Plugin ještě není veřejně v katalogu.
Receipt: `evidence/submission-20261024.json`. Další distribuci nepodávat.


## Přímá aktualizace 1.0.1

Český ZIP 1.0.1 upřesňuje místní přepsání vzhledu z aplikace ve WordPressu;
volby a chování uložených bloků ani shortcode nemění. SHA-256:
`5d8a605eb7f2663e420768d6ec5f3588181fa8ac42fc7b8462aa896ba358ca75`.
[Ověření](evidence/appearance-precedence-20261026.json) zahrnuje oba podporované
WordPress/PHP běhy a skutečný český/anglický editor. Nové podání do katalogu
neproběhlo; původní podání 1.0.0 zůstává ve frontě. Globální balíček se nevydával.

## Historické ověření 1.0.0

Ověřeno 2026-10-23/24 v odděleném lokálním prostředí. Oba pluginy jsou hotové jako samostatné instalační ZIPy. Produkční opravy služby byly nasazeny jako 0.20.389+889; podání a schválení WordPress.org jsou samostatné kroky.

| Produkt 1.0.0 | ZIP SHA-256 |
| --- | --- |
| vstupenky.online | `66c9f35ac38210bb0ca18c35011200976c92236200801626bb3e3a86fc8901c4` |
| Festapp Tickets - tickets.festapp.net | `0a5d151683a800f1520bf1aff8d1abb448c25dfc5108f4bd02a6860e977b9482` |

ZIPy jsou v `dist/`. Každý obsahuje vlastní kořenový adresář a 12 souborů. `shared/` je jediný společný zdroj rendereru, validace, nápovědy, editoru a překladů; `products.json` určuje dvě explicitní identity. Generátor vytvoří izolované PHP namespaces, textdomains, bloky, shortcode a asset handles. Instalace fungují jednotlivě i současně, bez dalšího runtime pluginu. Anglický zdroj obsahuje přibalené české překlady. Manifesty `evidence/shared-build.json` a `evidence/*-package-inputs.json` vážou přesné vstupy na oba balíčky. Opakované sestavení zachovalo oba hashe.

## Audit publikovatelnosti 2026-10-24: připraveno k podání

Aktuální návrh obsahuje pouze vstupenky.online. SaaS integrace tohoto typu není
zakázaná; přijetí konkrétního podání posuzuje WordPress.org. Nezávislý kritik
ověřil servisní/právní odkazy a nenašel konkrétní PHP injekční ani oprávňovací chybu.

Opraveno: privacy tvrzení, popis přenosu počtů/cen, WPCS zarovnání a zastaralá
vazba schvalovacího balíčku. Prošlo 280 WordPress assertions na obou WP/PHP
sestavách, skutečné načtení překladů, aktuální Plugin Check 2.1.0 (0 errors;
na nové sestavě 1 zdůvodněný translation warning, na minimální 0 warnings),
WPCS českého pluginu (0 errors / 0 warnings) a produkční origin gate.
Finální repack změnil pouze readme; jeho finální ZIP byl znovu instalován a
prošel Plugin Check na obou sestavách. Runtime PHP/JS a překlady se nezměnily.

**Produkční brány prošly:** main `db6db44d5`, tenant `fa0de1bd2`, verze
0.20.389+889. Tři koherentní live probes a skutečný cross-origin embed
z instalovaného ZIPu prošly. Plánek se otevře, Escape ho zavře a vrátí scroll
na původních 885 px. Nebyla vytvořena objednávka ani rezervováno sedadlo.
Helper SHA odpovídá zdroji. Doloženo v `evidence/production-release-20261024.json`.
Vlastní doména nyní drží helper až čtyři hodiny v cache; klient je kompatibilní
s předchozím helperem. Samotný formulář načítá živou službu.

Přesný stav je v `evidence/publishability-review-20261024.json` a `dist/APPROVAL.json`.
Kontrola `verify-submission.py --product vstupenky-online` ověřuje shodu artefaktů;
`--submit-ready` musí potvrdit uzavření produkčních bran. Globální distribuce
není součástí tohoto podání. Následující onboarding receipt ověřoval dřívější ZIP.

## První použití po instalaci (2026-10-24, dřívější ZIP)

Aktuální ZIPy přidávají v seznamu pluginů odkaz **Začít**, tři nativní kroky
v nastavení a odkaz pro vytvoření stránky. Opraven je chybný gettext kontext
v názvu pluginu a český název formuláře v editoru. Technické a servisní údaje
zůstávají dostupné v rozbalovací části.

- **206 assertions PASS** v instalovaných ZIPech: 16 onboarding/gettext + 39
  původního kontraktu + 48 společného kontraktu na každé ze dvou WP/PHP sestav.
  Samostatně prošlo skutečné načtení českých PHP i editorových katalogů.
- Český Gutenberg: skutečné přidání bloku přes vkládání, uložení, reload a
  publikace stránky 33. Anonymní návštěvník vidí formulář; editor službu nenačítá.
- WPCS: 0 errors, 6 warnings ve stávajícím `includes/embed.php` (zarovnání
  přiřazení, tři na distribuci); měněné administrační PHP nemá findings.
- Obrázkový průchod: `preview/onboarding/index.html`. Aktuální receipt:
  `evidence/onboarding-refresh-20261024.json`.

Následující starší průchody jsou historické důkazy funkcí, nikoli opakování
všech release kontrol na nových ZIPech. Veřejné vydání neproběhlo.

## Historické výsledky

- **232 WordPress assertions PASS:** 39 původních + 37 testerských + 40 společných/produktových kontrol na obou sestavách: WP 6.6.4/PHP 7.4.33 a WP 7.1.3/PHP 8.5.12. Přesný origin a kanonická cesta, kódování, injekce, oprávnění, izolace produktů, výšky a skripty. Produkční gate odmítá lokální origin i s DEV konstantou.
- **Skutečný editor a frontend PASS:** Gutenberg publikace a opětovné načtení, žádný servisní iframe v editoru; dva různé originy na jedné stránce, nezávislé výšky, mobil 320 px, klávesový fokus, výpadek helperu a fixed režim. Pět nových browser scénářů na Twenty Twenty-One 2.9 a Twenty Twenty-Five 1.5; bloková šablona obnovena. České MO i editorové Jed katalogy skutečně načteny pro oba produkty.
- **Lifecycle PASS:** samostatná deaktivace/aktivace, skutečné smazání každého pluginu, druhý nadále funguje, čistá reinstalace ZIPů a zachování uložených bloků. Služba měla při tomto konkrétním průchodu 3 objednávky před i po. Později vznikla čtvrtá Safari objednávka. Žádná dřívější veřejná verze pro skutečný upgrade neexistuje.
- **WPCS 3.4.1 a PHP syntax PASS:** oba pluginy, celkem 6 PHP souborů. Plugin Check 2.1.0 s runtime bootstrapem: každý 0 errors, 1 vyhodnocený warning k `load_plugin_textdomain`, ponechanému pro přibalené překlady při instalaci mimo katalog. Nejde o nulový počet warnings.
- **Čtyři skutečné syntetické nákupy:** Chrome český běžný lístek (order 1), Chrome globální sedadlo A2 (order 2), nativní Mobile Safari globální běžný lístek (order 3) a sedadlo A4 (order 4), každý 120 CZK. Anonymní návštěvník, skutečný checkout/RPC, skutečná kapacita a cena, replay bez duplicit. Globální lokální origin je oddělený; backend je stále stejná explicitní syntetická organizace, nikoli živý globální tenant.
- **PDF, QR a vstup PASS:** kanonická fronta a renderery, ruční syntetické bankovní potvrzení, PDF, dekódované QR a scanner: první vstup přijat, replay bezpečný, druhý vstup `already_used`. Nativní Safari 26.5/iOS 26.5 navíc skutečný výpadek gateway a retry stejného příkazu [0,200], zakázaná obě webová úložiště, zachované údaje a právě jedna objednávka. Kanonická PDF příloha načtena v nativním PDF preview z loopback capture sinku, QR dekódován i ze screenshotu. Save to Files/share sheet se netestoval.

Historické důkazy před touto aktualizací ZIPů: `evidence/dual-block-browser-receipt.json`, `dual-classic-browser-receipt.json`, `dual-uninstall-receipt.json`, `shared-service-receipt.json`, `global-safari-receipt.json`, `global-editor-publication.json`, `final-runtime-inputs.json`. Starší příjmové průchody a původní český ZIP jsou historické, nikoli doklad totožnosti nových ZIPů. Původní balíček je v `dist/archive/` pod původním hashem.

## Registrace od nuly

`evidence/new-organizer-onboarding.json`: skutečné veřejné Create account, syntetický nový email, registrace přes kanonický endpoint bez předem vloženého uživatele či oprávnění, kód z reálné fronty/rendereru, přihlášení, automatická vlastní jednotka, první vlastní akce a vlastní uložený formulář `36t9dry5`, vložení a publikace přes Gutenberg a anonymní zobrazení. Emailový kód je počáteční přihlašovací heslo; není doložena samostatná aktivace účtu nebo jednorázovost tohoto počátečního hesla.

Odhaleny a lokálně opraveny chyby: nelokalizovaná duplicitní registrace, normalizace emailu před kontrolou duplicity, rozbitý reset formulář kvůli prázdnému ID, rozdílná minimální délka hesla a spotřebování reset tokenu slabým/null heslem. Osm cílených Node testů PASS; SQL regresní test nejprve selhal na původní funkci a po opravě prošel, stejně jako test expirace. Skutečná UI obnova hesla, nové přihlášení a odmítnutí použitého tokenu prošly. Přesné opravy a migrace jsou připravené v pracovním stromu a ve focused patchi, **nejsou nasazené do produkce**.

Nová vlastní jednotka ještě nemá platební/právní konfiguraci. První placený prodej nového obchodníka proto není doložen; nákupní průchody použily připravenou syntetickou jednotku. WordPress nápověda vysvětluje účet, akci, publikovaný formulář a dokončení obchodních/platebních podmínek. Plugin nepřenáší servisní účet do WordPressu a nespravuje objednávky.

## Externí brány a limity

Účet WordPress.org **festappnet**, potvrzený **info@festapp.net**, profil a nové přihlášení heslem + TOTP ověřeny (`evidence/accounts.json`). Vlastník povolil nastavení 2FA agentem; heslo, autentikátor a recovery kódy jsou v místní login Klíčence. Žádné tajné údaje v ZIPech ani veřejných důkazech. Před odesláním znovu ověřit stav submission; dřívější dostupný formulář není rezervace názvu ani trvalý stav.

Živé globální `/login`, `/embed.js` (protokol 1), anglické privacy/terms/support/choices a aktivace `festappticketsglobal`/canonical byly načteny izolovaným skutečným Chrome (`global-public-origins.json`). Není tím ověřen živý globální platební obchodník, Stripe/SCA ani produkční nákup. Emailové průchody používají hlídaný lokální provider sink pouze pro `@example.invalid`; neprokazují SES acceptance ani doručitelnost. Žádná skutečná platba ani externí testovací email.

Dvě podobné distribuce může WordPress.org posoudit jako duplicitní; schválení ani finální slug nelze slíbit. Připraveny jsou dvě oddělené žádosti, nikoli obcházení review. Po souhlasu vlastníka následuje podání, rozhodnutí katalogu, přidělení SVN a samostatné schválení veřejného vydání. Lokální opravy služby vyžadují samostatný autorizovaný release po sladění s aktuálním main. Checkout obsahuje i cizí rozpracované změny, žádný commit/push nebyl proveden.

## WordPress.org review correction, 2026-10-27

Česká verze 1.0.3 sjednocuje Requires at least na 6.6 v hlavičce a readme.
Čistá instalace/aktivace a 39 reálných kontraktů prošly na WP 6.6/PHP 7.4.33;
Plugin Check 2.1.0: 0 errors, 1 známý překladový warning. Runtime embed/admin/editor/style
je shodný s main 1.0.2; změněny jsou metadata a release/cache version.
ZIP byl ověřeným podáním nahrán do původní žádosti, reviewer dostal odpověď
ve stejném vlákně. Nejde o schválení ani veřejné katalogové vydání.
Důkazy: `evidence/review-response-20261027.json`.
