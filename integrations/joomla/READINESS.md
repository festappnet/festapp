# Joomla vstupenky.online - readiness 2026-10-26

**Česká distribuce 1.0.1 je veřejně vydaná. Kritik ji schválil a všech pět CI kontrol prošlo. Podání do JED bylo přijato jako ID 17931 a čeká na redakční kontrolu.**
Finální uživatelský soubor: [vstupenky.online.zip](dist/vstupenky.online.zip).
Globální varianta 1.0.0 zůstává ověřovanou samostatnou distribucí, její veřejné
vydání není v tomto kroku autorizováno.

Český SHA-256: `8396ed9892ab07791e037a44e0bc1459274c68a6933f6a531f1e90653494ba6f`.
[Neměnný balíček](dist/sha256/8396ed9892ab07791e037a44e0bc1459274c68a6933f6a531f1e90653494ba6f/vstupenky.online.zip),
[vstupy a soubory](evidence/packages.json), [release metadata](dist/CANDIDATE.json).
Původní lokální český 1.0.0 ZIP zůstává zachován. Globální ZIP se nezměnil.

## Opravy po první kritické revizi

Kritik označil původní runtime validaci/escapování za odpovídající, ale našel
mezery v průkaznosti publikace, cache, browser kontrol a vazbě důkazů na ZIP.
Následující opravy byly provedeny před vydáním:

- Skutečné **Nový modul > výběr značky > uložení > Published > pozice/přiřazení
  nabídky > veřejná stránka** přes nativní Joomla formuláře. Nové ID modulu se
  vkládá také přes nativní editor článku. Nejde o SQL seed vydávaný za onboarding.
- Článek se testuje samostatně bez pozicového modulu na studené i zahřáté cache,
  se všemi čtyřmi kombinacemi auto/fixed a převzetí vzhledu. Fixed bez vzhledu
  skutečně nevydá helper přes dispatcher.
- Browser kontroluje zmizení ovládání plánku po Escape a skutečnou URL nově
  otevřené záložky po klávesnicové aktivaci fallbacku.
- Start testovacího prostředí čeká na hotovou instalaci, správnou CLI verzi a
  HTTP odpověď obou CMS. Dřívější závod start/verify je odstraněn.
- ZIPy mají neměnné cesty podle digestu. Jediný úspěšný `scripts/verify.py`
  svazuje zdroje, tooling, testy, nainstalované soubory a receipty s přesným
  českým ZIPem. `scripts/release-gate.py` vyžaduje ještě souhlas kritika s tímto
  konkrétním výsledkem, kontroluje identitu/verzi/URL napříč produktem,
  instalačním manifestem a feedem a odmítne pozdější změnu kteréhokoli vstupu.

## Ověření

| CMS | PHP | Rozsah |
| --- | --- | --- |
| Joomla 5.4.10 | 8.3.36 | instalované ZIPy, 210 kontraktových assertions, CMS lifecycle, updater |
| Joomla 6.1.4 | 8.4.27 | stejný rozsah, navíc mobilní browser a živá služba |

[Image digesty](docker-images.json), macOS arm64, Docker 29.5.2. Neprohlašujeme
ověření jiných CMS řad. Minimum českého distribučního kanálu je PHP 8.3.

- [Kontrakt 5.4](evidence/contract-5.json), [kontrakt 6.1](evidence/contract-6.json):
  přesný HTTPS origin, kanonický Unicode slug, odmítnutí nebezpečných URL,
  escapování title/XSS, výška 240-4000 px, čeština/angličtina skutečně načtené
  Joomla Language loaderem, lokální chyba bez iframe pro neplatný vstup.
- [Instalované soubory](evidence/installed-files.json) odpovídají všem souborům
  přesných ZIPů. [Nativní CMS](evidence/cms.json) ověřuje uložení/reload,
  odmítnutí cizí URL, CSRF bez změny dat, anonymní/registrovaný přístup bez práv,
  žádné vzdálené iframe/helper v administraci, souběh značek, jeden helper
  na origin a zachování nastavení při přeinstalaci.
- [První publikace a matice článku](evidence/native-publication.json) doplňují
  původní seed test o skutečné nové objekty přes nativní CMS.
- [Browser](evidence/browser.json): 320 px bez horizontálního přetečení,
  skutečná disposable služba, automatická výška, klávesnice, otevření/zavření
  plánku a funkční fallback s blokovaným helperem. Tento test izolovaně mapuje
  český origin na existující HTTPS fixture 59803/backend 59821; jiné relace
  ani backend data se neresetují.
- [Updater 5.4](evidence/updater-5.json), [updater 6.1](evidence/updater-6.json):
  registrace správné veřejné update URL, skutečný Joomla discovery, HTTP stažení,
  SHA-256 a nativní instalace při zachování nastavení. Transport používá lokální
  kopii stejného feedu/ZIPu a výslovně synteticky sníženou verzi metadat. Není
  to tvrzení o historickém veřejném vydání. Veřejné URL se potvrzují zvlášť.
- [Odinstalace 5.4](evidence/lifecycle-5.json), [6.1](evidence/lifecycle-6.json)
  a [HTTP readback](evidence/uninstall-http.json): odstranění české značky
  zachová globální. Cache článku je nutné po změně/odinstalaci modulu běžně
  vyčistit; postup je v README.

Autoritativní otisk finální sady je [verification.json](evidence/verification.json).
Finální [kritik schválil přesný ZIP a otisk ověření](evidence/critic.json) bez
nevyřešených technických blokérů; [release seal](dist/RELEASE.json) má stav
`READY_TO_PUBLISH`.
Při jeho neexistenci nebo neshodě vstupů release gate záměrně neprojde.
Neproběhly Flutter buildy, migrace ani plošné repository testy.

## Živé URL a původní 403 jsou vyřešené

[Živá sonda](evidence/live-links.json) vrací 200 pro sedm českých servisních,
právních a embed zdrojů a kontroluje skutečný obsah, nikoli pouze stav HTTP.
Izolovaný browser ověřil právní a podpůrné stránky i skutečný produkční formulář
z instalovaného Joomla modulu: [live-browser.json](evidence/live-browser.json).
Jde o mobilní zobrazení, skutečný helper/automatickou výšku a otevření/zavření
plánku. Nebyla odeslána objednávka ani vybráno sedadlo. Nákupní kontrakt služby
se neměnil a není potřeba opakovat syntetický nákup.

Původní Python sonda dostala Cloudflare 403/error1010 kvůli výchozímu
`Python-urllib` User-Agentu. Stejný klient se samostatně identifikovaným
`Festapp-Joomla-Release-Check/1.0` dostává 200; také `Joomla/6.1.4`, curl a skutečný
browser prošly. Tento závěr je doložen porovnáním stejné URL/klienta při změně
jediné hlavičky. WAF ani ochrany produkce nebyly vypnuty. Historický výsledek
zůstává v `evidence/public-links.json`, aktuální stav v novém receiptu.

## Distribuce a zbývající veřejné kroky

Český ZIP je [veřejně vydaný](https://github.com/festappnet/festapp/releases/tag/joomla-vstupenky-online-v1.0.1)
a stabilní update feed je dostupný. [PR #603](https://github.com/festappnet/festapp/pull/603)
byl po výslovném souhlasu vlastníka administrátorsky sloučen do `main` jako
`4b06687ce418bb790d6cc34e295dddbb14fc2159`. Všech pět CI kontrol prošlo;
přechodná chyba CDP při startu browser jobu prošla jediným cíleným opakováním.

[Byte readback veřejného ZIPu a feedu](evidence/public-release.json) souhlasí
se zapečetěnými hashi. [Skutečná instalace a update HTTP transport na obou CMS](evidence/public-cms-update.json)
potvrdily verzi 1.0.1, veřejný update kanál a download stejného ZIPu přes
nativní Joomla API, bez simulace starší verze. Nebyl proveden aplikační deploy,
produkční databázová změna ani vydání jiné značky.

## Joomla Extensions Directory - podání přijato

Účet autora je aktivní. Dne 2026-10-26 bylo skutečně odesláno podání
**vstupenky.online 1.0.1**, ID **17931**. JED zobrazil „Listing Submission Received“
a potvrdil přijetí: [receipt](evidence/jed-submission.json). Přiložený ZIP je
stejný jako veřejný schválený release, s hashem uvedeným výše.

[Oficiální JED Checker 2.4.4](evidence/jed-checker.json) dokončil všech 12 pravidel
na Joomla 5.4.10/PHP 8.3.36 bez chyb. Upozornění na iframe odpovídá záměrnému
embed rendereru; notice se týká nepovinných authorEmail/authorUrl. Pravidlo update
serveru i GPL prošlo. Checker samotný na Joomla 6.1 používá odstraněnou legacy
Folder třídu, proto je úplný checker receipt z podporovaného Joomla 5 prostředí;
instalace a runtime modulu na Joomla 6.1 jsou samostatně ověřené výše.

[Odeslaná metadata](submission/listing.json), [anglický popis](submission/description.en.txt),
logo, skutečný download, dokumentace, licence a support byly vyplněny v nativním
formuláři JED. Vybrána kategorie Calendars & Events > Events, modul, GPLv2 or
later a placená SaaS integrace s bezplatným ZIP downloadem, bez nepravdivého
slibu trvale bezplatné služby. Produkční zákaznická akce nebyla použita jako demo.

**Katalogové zveřejnění zatím není schválené.** Podání musí projít kontrolou
specialistou JED; případné připomínky nebo oznámení o publikaci jsou další
externí událostí. Nezaměňovat přijetí podání s veřejným záznamem v katalogu.
