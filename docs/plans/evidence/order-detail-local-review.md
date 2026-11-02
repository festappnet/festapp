# Detail objednávky - skutečná lokální kontrola

**Stav: připraveno k lokální kontrole.** Datum: 1. 11. 2026. Aktualizováno po připomínkách k místní ukázce.
Produkční migrace, nasazení, publikace ani push nebyly provedeny.

## Zdroj a běžící prostředí

- Checkout `/Users/miakh/source/festapp`, větev `main`, výchozí HEAD
  `a31277e3c3d761ed37d6425a1f2a731584b92e8d`. Implementace zůstává v pracovních
  změnách. Předchozí změny jiných úloh byly zachovány, včetně seating transition,
  překladů, Functions a image workeru; nejsou součástí samostatného commitu této úlohy.
- Skutečná Flutter aplikace:
  [objednávky místního plesu](http://127.0.0.1:58631/order-detail-ples/reservations/orders/current).
  Přímý [detail Jany, E-maily](http://127.0.0.1:58631/order-detail-ples/reservations/orders/current?orderId=4&orderTab=emails).
- Backend `http://127.0.0.1:58621`, PostgreSQL `127.0.0.1:58622`.
  Vlastněný Supabase projekt `festapp-order-detail-20261101`, workdir
  `/Users/miakh/.local/share/festapp-order-detail-20261101`. Auth, REST, PostgreSQL,
  Storage a Edge runtime skutečně běží. Ostatní místní projekty nebyly zastaveny ani resetovány.
- Použita aktuální baseline `20260906140000_schema.sql`, její bootstrap a reference
  seed, následující migrace a vlastní fixture. Nová migrace
  `20261101210000_order_admin_detail.sql` je aplikována pouze zde.
- Entry `test/browser/full_app_e2e.dart` a soukromé Dart defines směřují na stejný
  backend, kontrolovaný portem 58621. UI není simulace, RPC nejsou podvržena.
  Pouze externí push callbacks izoluje stávající E2E entry; Auth zůstává skutečný.
- Frontend je release build Flutteru 3.47.7 přes FVM. Obsluhuje jej ponechaný
  HTTP server na `127.0.0.1:58631`, PID 54513, bez běžícího Flutter kompilátoru.
  SHA-256 skutečně obsluhovaného `main.dart.js`:
  `6d45c5442881ca013a2ebb2b47281841c072a3300ba80328a1e753367951bb6e`.
- Heslo ani tokeny nejsou v tomto záznamu. Přístup je v soukromém souboru
  `/Users/miakh/.local/share/festapp-order-detail-20261101/pristup.txt` s právy 0600.

## Data a skutečně uložené operace

Fixture vlastní organizace 1, jednotka 7, akce 7 (`order-detail-ples`), formulář 8,
plánek 5, uložená revize 2. Zdroj je v `test/fixtures/order_detail/`; pomocné
blueprint fixture dodaly kanonické číselné resources. Navigační fixture byla použita
v místní kopii s kontrolou konkrétní syntetické organizace, protože současná
baseline obsahuje také referenční organizaci. Žádná cizí testovací DB nebyla změněna.

Jana má 4 místa za 2600 Kč, Petr původně 2 místa a dětské menu za 1450 Kč, po skutečné úpravě další menu
a aktuální cenu 1600 Kč, Alžběta 6 míst
za 3900 Kč se zálohou 1000 Kč, Eva dvě vstupenky atomické pohovky a Martin tři
vstupy na stání. Klára má nedoručení, Tomáš použitou vstupenku s identitou prodané
dávky, David zrušenou objednávku se syntetickým vrácením. Veroničina rodinná
objednávka má 3 původní vstupenky, z nichž byla jedna skutečně zrušena kanonickým
vlastníkem; dvě místa zůstávají aktivní, cena je 1300 Kč a přeplatek 650 Kč nebyl
vydáván za provedenou refundaci. Existuje samostatný účet pouze pro čtení.

Přes skutečné UI a místní backend bylo ověřeno:

- Jana, objednávka 4: změna kontaktu na `jana.novotna@example.invalid`, uložení bez
  odeslání a fyzický reload. Historie přibyla o jeden záznam, počet zpráv zůstal 4.
  Historická zpráva stále uvádí `jana.chybny-kontakt@example.invalid`.
- Klára, objednávka 9: hotovost 100 Kč přes dosavadní platební formulář a příkaz;
  transakce a souhrn přežily fyzický reload. Objednávka zůstává částečně uhrazená.
- Ověření přerušeného kontaktního příkazu použilo původní uloženou identitu.
  Následné výslovné odeslání Janě vytvořilo právě jeden nový požadavek v
  `email_messages`, počet zpráv 4 -> 5. Nový požadavek čeká; není označen za doručený.
- Místní Auth JWT -> místní `download-ticket` Edge Function -> skutečný PDF soubor
  o 51110 bytech, ověřená hlavička `%PDF-`. Použit současný kanonický výchozí template.

## Ověření

- Registrovaný SQL runner `pnpm --dir web_client exec node scripts/run_db_tests.js`
  spustil 5 cílených souborů: `order_admin_detail_test`, `order_email_recovery_test`,
  `seating_assignment_test`, `capacity_resources_test`, `resource_admission_test`.
  Všechny prošly. Finální kontraktní test byl zopakován po doplnění historického
  snapshotu zrušené vstupenky a prošel. Pokrývá readonly/outsider, chybný scope,
  soukromé helper ACL, přesné vazby, read fingerprint a čtení bez změny objednávek/spotů.
- Flutter testy byly skutečně sbírány a spuštěny s `--concurrency=1`: cílený běh
  vieweru, kontaktu, plateb, historie a dosavadního viewportu měl 27 passing případů;
  výběrový command/contact běh 15. Designové a dialogové e-mailové případy prošly
  po přizpůsobení selektorů nové primární akci. Nový durable recovery test prošel;
  finální konflikt/dvojklik test také prošel po zavedení společné zápisové závory.
- Public `VenueLayoutViewer` byl ověřen přes jeho veřejný focus/hit kontrakt i
  skutečného Flutter spotřebitele; stávající viewport testy prošly. SDK ani
  dependency minima se neměnila a balíček nebyl publikován.
- Cílený Dart analyze: bez chyb a warningů, zůstávají informační stylové linty.
  Flutter release build dokončen, HTTP a SHA-256 obsluhovaných bytes ověřeny.
  `git diff --check` prošel. Mechanický UI detector nevrátil nálezy.
- Terra použila izolované headless ztlumené browser sessions. Ověřila pět záložek,
  původní otevření zákaznické buňky (po připomínkách nahrazeno dvojklikem), oddělený checkbox a kopírování, save-only a reload,
  transakce/historii, skutečný enqueue, mapu seznam -> místo -> rozbalená vstupenka,
  draft napříč záložkami a rozšířením, pokračování/zahození, zavření -> další
  objednávka, browser Back/Forward, přímý odkaz, mobil 320/390 px a rozšířený desktop.
  Readonly účet načetl detail a platby bez `get_occasion_for_edit_v1`; zápis byl zakázaný.
- Kompletní read-only browser průchod porovnal orders/history/tickets/email,
  celé spots včetně holdů a alokací, OPT, blueprints/layout/revision, seat/area
  bindings, group products a inventory contexts/pools. Otisk před i po:
  `74c8da91ad9afd33181149d922bec01a`. Nebyly pozorovány mutační RPC při prohlížení.
  Poslední přesný build prošel přímým otevřením bez falešného upozornění na filtr,
  zavřením a otevřením jiné objednávky. Automatické browser sessions jsou zavřené.

## Snímky a hranice

- [Finální E-maily](order-detail/final-artifact-email.png)
- [Rozšířený plánek vedle vstupenek](order-detail/final-expanded-tickets.png)
- [Primární save-only](order-detail/final-email-primary.png)
- [Mobil 390 px](order-detail/mobile-390-overview.png)
- [Mobilní platby 320 px](order-detail/mobile-320-payments.png)

Výchozí provider události a ledgerové pohyby jsou označené syntetické scénáře,
nikoli důkaz skutečné banky, fyzického tisku, doručení nebo lidského otevření.
Banka, karty, externí doručování, OAuth a push nebyly ověřovány ani aktivovány.
Fronta je `paused=true`, `worker_url=NULL`, cron má vypnuté spouštění aktivních
jobů; produkční provider credentials nebyly přidány. Nebyly zkoušeny skutečné
externí karetní refundace ani jejich finanční účinky. Lokální Auth/REST/SQL,
ukládání a PDF fungují bez nahrazování jejich výsledků.

Frontend i vlastněný backend zůstávají běžet pro uživatele. Produkční vydání vyžaduje
samostatný výslovný pokyn. Význam všech 27 e-mailových položek a skutečné chování
popisuje [lokální dokumentace](../../development/order-detail-local-2026-11-01.md).


## Úpravy po připomínkách k sedmi snímkům

- Astra Medium implementovala stavový barevný štítek, lokalizované počty a
  texty, obsah objednávky s produktovým dialogem pro příslušnou vstupenku či
  přihlášku, rozlišení jedné přihlášky a více účastníků, automatické otevření
  jediného plánku a mobilní zavření/zvětšení vpravo nahoře.
- Jedno kliknutí vybírá buňku; needitovatelná datová buňka otevírá detail až
  dvojklikem. Číslo objednávky je samostatné textové tlačítko. Kopie a checkbox
  detail neotevírají. Celý aktivní řádek má trvalé orámování podle ID detailu,
  nezávislé na aktuální buňce a hromadném výběru. Identita se bere z
  řádkového modelu; SQL sloupec `id` a projektovaný grid sloupec `orderId`
  se nesmějí zaměňovat. Tento rozdíl pokrývá doplněná skutečná grid regrese.
- Hranice tabulky a detailu je posuvná, s klávesnicovým ovládáním, mezemi
  520-760 px a minimem tabulky 480 px. SharedPreferences ukládá šířku pouze
  do místního prohlížeče na daném počítači; účet ani DB tuto volbu nepřenáší.
  Přechod na mobilní šířku nepřepisuje desktopovou volbu.
- Šedá plocha byla skutečně zopakována v prohlížeči. Cílený červený widget
  test reprodukoval `bool is not a subtype of double?`: rozbalení a scroll
  sdílely identifikátor PageStorage. Oddělené identifikátory rozbalení,
  obsahu a posunu závadu odstranily, včetně rozbalených SelectableTextů.
- Finální cílený Flutter běh na těchto vstupech: **49/49 prošlo**, vždy
  `--concurrency=1`. Obsahuje reálný grid s desktopovými gesty, oddělenou
  schránku/checkbox/editaci, orámování, persistenci a meze panelu, gray
  regresi, české/anglické počty 0/1/2/5, režimy přihlášek, mobilní geometrii,
  readonly a dosavadní kontaktní/dialogové scénáře včetně 320 px / 200 %. Po nálezu rozdílných názvů ID byly tři dotčené grid
  testy zopakovány s odlišným SQL a grid klíčem; všechny prošly.
- Cílený analyzer: bez chyb a warningů, existující informační linty zůstávají.
  Mechanický detector: `[]`. Tehdejší release build dokončen za 69,7 s; diskový a
  obsluhovaný SHA-256 jsou shodné s hodnotou nahoře. Kontrolní logy jsou
  soukromě v pracovním adresáři pod prefixem `revision-`.

- Skutečná produktová mutace přes UI: objednávka 5, Petr, vstupenka
  `PLES-2-2`. K původnímu vstupu 650 Kč přibylo `Dětské menu` 150 Kč;
  po fyzickém reloadu jsou oba produkty na vstupence a cena celé objednávky
  1600 Kč, přijato 1450 Kč, zbývá 150 Kč. Dřívější kontaktní a hotovostní
  úpravy byly zachovány. Nebyla vyvolána samostatná odesílací akce.

- Finální artifact: přímý odkaz na Kláru označil celý správný řádek; Další
  označilo Tomáše, Předchozí opět Kláru. Orámování zůstalo po tažení hranice.
  Jediný uložený plánek se zobrazil automaticky. Při následném prohlížení
  celého plánku, všech míst a odkazu Zobrazit místo nebyly zachyceny žádné
  síťové požadavky ani mutační RPC. Mobilní snímek potvrzuje akce vpravo nahoře.
- Snímky po připomínkách: [desktop](order-detail/revision-desktop.png),
  [mobil](order-detail/revision-mobile.png),
  [rozbalené E-maily bez šedé plochy](order-detail/revision-email.png).
  Desktop a mobil byly pořízeny na finálním artefaktu; kontakt a e-mailová
  regrese jsou navíc pokryty skutečným browser průchodem a cíleným testem.

- Závěrečný browser průchod potvrdil také číslo objednávky jako tlačítko,
  oddělené kopírování a checkbox, barevný stav, anglický singulár/plurál,
  zachování místní šířky po reloadu a původní e-mailovou regresi na finálním
  buildu. Češtinu a nezávislé obnovení preference ověřují widget testy;
  samostatný druhý prohlížeč s výchozí šířkou nebyl v browser QA zkoušen.
  [Podrobný browser receipt](order-detail/revision-browser-receipt.md).
  Obě task-owned browser sessions jsou zavřené; HTTP a Supabase zůstávají běžet.


## Druhé upřesnění vzhledu a ovládání

- Posuvník má jedinou čáru o 1 px v barvě hranic gridu; neviditelná plocha
  13 px zachovává snadné tažení. Místní preference a meze zůstávají.
- Číslo objednávky doplňuje ikona otevření. Samostatné zvětšení bylo podle
  nového pokynu odstraněno včetně rozhraní a lokálního fullscreen stavu.
  Zrušit objednávku je přímo viditelné, respektuje práva, busy/stale stav,
  používá původní potvrzení a příkaz; samotné otevření potvrzení nic nemění.
- Vstupenky mají sjednocené průhledné accordion plochy, oddělení, rozestupy,
  přístupné označení výběru a ikonu vybrané vstupenky. Výběr z mapy ji
  rozbalí a odroluje do seznamu. Výběr místa ani vstupenky nepřibližuje mapu;
  počáteční pohled zůstává celkový. Změna geometrie ani rezervace není součástí.
- Odpovědi formuláře jsou otevřené od začátku. Chybějící názvy polí používají
  překlad jejich typu, případně obecný přeložený název pole. Dlouhý seznam
  e-mailových stavů nahradilo sdílené `InfoTooltipButton` s krátkou nápovědou;
  úplná legenda 27 položek zůstává v lokální dokumentaci.
- Dotčené widget kontroly prošly: 23 prezentací, splitter, scroll regrese,
  tři skutečné grid interakce a nový spotřebitelský test mapy, celkem 29 případů.
  Mapový test používá injektovanou čtečku přes skutečný controller a widget;
  kontroluje automatický jediný plánek, přesné aktivní ID, neměnný požadavek
  kamery, žádné další RPC při výběru a neměnnou geometrii. Nepředstavuje
  důkaz skutečného Supabase - ten zajišťuje browser průchod lokální aplikací.
- JSON katalogy jsou validní, české a anglické klíče OrderDetail jsou shodné;
  nové pomocné texty byly přidány i ostatním čtyřem katalogům. Cílený analyzer
  nehlásí chyby ani warningy. Mechanický UI detector vrátil `[]`.

- Aktuální build po druhém upřesnění: Flutter release dokončen za 64,5 s,
  diskový a skutečně obsluhovaný SHA-256 jsou shodné s aktuální hodnotou nahoře.
  Logy tohoto kola mají v soukromém workdiru prefix `polish-`. Starší snímky
  a receipty výše zachycují předchozí ověřené varianty, včetně později zrušeného
  ovládání zvětšení.

- Skutečný browser průchod aktuálním buildem potvrdil tenký posuvník a jeho
  persistenci po reloadu, ikonu odkazu a oddělené kopírování, odstraněné zvětšení,
  přímé zrušení s otevřením potvrzení a návratem bez mutace. Výběr sedadla i
  položky místa označil a otevřel správnou vstupenku a ponechal celkovou kameru.
  Mobil, kompaktní česká nápověda a výchozí otevření odpovědí byly ověřeny.
  Objednávka 5 nemá odpovědi na úrovni objednávky; obsah otevřených odpovědí
  proto v tomto případě ověřují widget testy a reálné odpovědi na vstupence.
- Čeština byla zvolena skutečným přepínačem jazyka. Detail se přeložil ihned,
  již vytvořené hlavičky tabulky až po reloadu. Po fyzickém reloadu jsou česky
  tabulka i detail. Toto chování živého přepnutí starého gridu nebylo měněno.
- [Závěrečný browser receipt](order-detail/polish-browser-receipt.md),
  [česká aplikace po reloadu](order-detail/polish-cs-reload.png),
  [vybraná vstupenka](order-detail/polish-selection.png),
  [informační tooltip](order-detail/polish-help.png),
  [mobil](order-detail/polish-mobile.png).
  V tomto průchodu nebyla změněna obchodní data, automatická browser session
  je zavřená a HTTP i Supabase zůstávají běžet pro uživatele.


## Třetí upřesnění a skutečná editace odpovědí

- Minimum panelu 360 px, neviditelná plocha tažení 29 px; per-browser preference
  a maximum zůstávají. Nativní TabBar, přesunutá skrytá poznámka, horní navigace,
  přímý zákaznický přehled a stabilní ikony vstupenek jsou v cílené prezentaci.
- Nová dopředná migrace `20261101220000_order_detail_responses.sql` byla
  aplikována výhradně na vlastněný projekt na 58622. Čtečka promítá kanonická
  metadata produktových kategorií a kategorie konkrétních zakoupených ID;
  historické názvy a ceny zůstávají ze snapshotů. Server přísně odděluje
  objednávkové a vstupenkové odpovědi; objednávkové ukládá dosavadní vlastník.
- Registrovaný SQL runner: 2/2 (`order_admin_detail_test`,
  `order_detail_responses_test`). Ověřeny readonly/anon, cizí formulář/vstupenka,
  starý otisk, špatný scope pole, neexistující volba, zakázaná obcházka e-mailu,
  použité vstupenky, uchování cen a produktů i nezávislé odpovědi obou úrovní.
- Cílená Flutter sada 34/34 prošla s concurrency=1. Reálný dialog/grid
  používá existující sloupce RESPONSES a FormResponseModel; testovací writer
  ověřil přesný formulář/objednávku/vstupenku, původní pole a minimální patch.
  Dynamické čtení testuje jinak pojmenovaná pole, jejich pořadí a kategorie
  zakoupených produktů. Zahrnuté jsou také split, grid, scroll a mapové regrese.
  Tyto widget testy jsou oddělené od skutečného browser/DB důkazu.
- Cílený analyzer bez chyb a warningů; stylové info linty zůstávají. Katalogy
  JSON jsou validní, klíče českého a anglického detailu souhlasí, UI detector `[]`.

- Finální Flutter build tohoto kola dokončen za 69,0 s; disk a HTTP se shodují
  s aktuálním SHA-256 nahoře. Logy mají prefix `response-`. Po doplnění kontroly
  oprávnění a form scope také po získání zámků znovu prošel dotčený SQL writer test.
- Přes skutečný lokální Auth/API a UI se u objednávky 5 uložil telefon
  `+420 777 000 002` -> `+420 777 000 022`. U její vstupenky `PLES-2-2`, Host 2,
  se přes nastavený dropdown uložila Strava `Vegetariánská` -> `Bez omezení`.
  Obě hodnoty zůstaly po úplném reloadu; cena 1600 Kč a přijato 1450 Kč zůstaly.
  Původní změny ostatních kontaktů, hotovosti a produktů byly zachovány.
- Browser potvrdil formulář Vstupenky na zimní ples #8 nad kontaktem i v editoru,
  poznámku přímo pod kontaktem, standardní záložky, stabilní ikony a hlavičku
  včetně navigace/zavření v panelu širokém 360 px. Tažení fungovalo i 12 px
  mimo viditelnou čáru. Mapa po změně odpovědí opět automaticky načetla plánek;
  produktová kategorie `Seats` vychází z uložené definice, není pevný UI text.
- [Závěrečný browser receipt](order-detail/response-browser-receipt.md),
  [hlavička a zdroj formuláře](order-detail/response-header.png),
  [uložená odpověď objednávky](order-detail/response-saved.png),
  [uložená odpověď vstupenky](order-detail/response-ticket-saved.png),
  [úzký panel](order-detail/response-narrow.png).
  V tomto kole změnil browser jen schválené místní odpovědi. Neodeslal zprávu
  ani nezrušil objednávku. Jeho vlastní session je uzavřená; HTTP a Supabase
  zůstávají běžet pro uživatele. Produkční operace nebyly provedeny.


## Čtvrté upřesnění - jednotlivá pole a Escape

- Odpovědi a poznámka používají společný InlineOrderField: tužka, vlastní
  vstup a Uložit/Zrušit. Poznámka má jediný nadpis. Předchozí tabulkový modal
  byl odstraněn; kanonický datový model a scoped SQL writer zůstávají stejné.
  Controller registruje rozepsaná pole pro ochranu při zavření, návratu a
  změně objednávky. Chyba zápisu ponechává vstup; potvrzený zápis se kvůli
  chybě následného čtení znovu neodesílá.
- Úchop je viditelný, má 40px hit oblast a žádný překážející tooltip.
  Normální wheel posouvá rodičovskou stránku i nad mapou; Ctrl/Cmd wheel a
  pinch zůstávají přiblížením. Nový opt-in flag sdíleného vieweru nemění
  ovládání ostatních spotřebitelů. Přidat platbu je nad finančním souhrnem.
- Zrušení používá jediný confirmOrderCancellation pro tabulku i detail,
  sdílený DataGridActionConfirmation, výčet skutečných modelů a upozornění
  na nemožnost dalších úprav i neautomatické vrácení peněz. Nápověda začíná ikonou.
- Escape: dialogy zpracují klávesu první. Detail používá scoped shortcut pro
  vstupy, late handler pro nezpracované klávesy a opt-in shortcut gridu po
  ukončení jeho vlastního editoru. Nepoužívá globální hardware listener, který
  by obcházel potvrzení dialogů. Původní kolize byla při browser QA zopakována
  a opravena; test ověřuje modal, grid i aktivní buňku a další test textové pole.
- Cílené kontroly: 40 passing případů napříč prezentací, per-field draft/save,
  gridem, splitterem, consumer viewerem, parent wheel scrollem, mapovým přehledem,
  PageStorage regresí a dosavadními package viewport testy. Vždy concurrency=1.
  Passing výsledky nezměněných vstupů byly zachovány, dotčené testy zopakovány.
  Analyzer bez chyb a warningů, překladové JSON validní, CS/EN klíče shodné,
  mechanický UI detector bez nálezů. SQL kontrakt se v tomto kole neměnil.

- Finální build tohoto kola: 74,6 s, diskový i HTTP SHA-256 odpovídá aktuální
  hodnotě nahoře; soukromé logy `inline-*`. Závěrečný browser ověřil přesné
  chování na tomto artefaktu: Escape ve fokusovaném rozepsaném telefonu otevře
  ochranu změn, Pokračovat zachová text, další Escape/Zahodit zavře detail.
  Nepotvrzená hodnota 042 nebyla uložena. Escape nad platebním dialogem zavře
  pouze dialog; další čistý Escape zavře detail.
- Skutečně uložené místní změny: Petr #5 telefon 022 -> 032, Host 2 na
  PLES-2-2 Strava Bez omezení -> Vegetariánská, původně prázdná poznámka
  `Lokální ověření poznámky.`. Po reloadu zůstaly; cena 1600 Kč/přijato 1450 Kč,
  ostatní dřívější kontakty a hotovost byly zachovány. Nová platba ani zrušení
  nebyly provedeny, žádná zpráva nebyla výslovně odeslána.
- Browser potvrdil úchop bez tooltipu, individuální úpravy a jejich akce,
  tlačítko platby před souhrnem, kanonické potvrzení s varováním a informační
  ikonu před textem. Pokus headless CLI o wheel neposouval ani prázdnou oblast,
  proto není vydáván za skutečné browser ověření wheel chování. Průchod wheel
  události do rodičovské stránky je ověřen cíleným widget testem skutečného
  PointerScrollEvent; přímé uživatelské kolečko zůstává k lokální kontrole.
- [Aktuální browser receipt](order-detail/inline-browser-receipt.md).
  Vlastní browser je uzavřený. HTTP a lokální Supabase zůstávají běžet;
  produkční migrace, publikace ani nasazení nejsou součástí tohoto kola.


## Páté upřesnění - samotná čára a společné Uložit změny

- Další úchop byl podle upřesnění odstraněn. Jediná 1px čára má po celé
  výšce neviditelnou 48px oblast s přesně totožným horizontálním středem,
  kurzorem změny šířky a bez tooltipu. Test ověřil nepřítomnost úchopu,
  souměrnou geometrii a tažení z obou stran čáry u jejího začátku i konce.
  Minimum, maximum a per-browser persistence zůstávají.
- Per-field ukládací akce nahradila společná lišta Uložit změny/Zahodit změny
  přímo pod záložkami mimo scrollovaný obsah. Zůstává viditelná napříč
  záložkami, když jsou změny. Kontaktní e-mail používá stejnou globální akci
  přes dosavadní recoverable repair owner s resend=false; explicitní posílání
  zpráv není součástí uložení. Samostatné existující kontaktní dialogy se nemění.
- Controller ukládá registrované změny přes dosavadní doménové vlastníky,
  po každé potvrzené změně posune čtecí otisk. Pozdější selhání uchová jen
  zbývající rozepsané změny; již potvrzený zápis se neopakuje. UI rozlišuje
  také úspěšný zápis a selhané následné čtení. Plánek je při tomto batch save
  pozastavený, aby jeho automatické obnovy nesoutěžily s readbackem zápisů.
- Cílený běh 56/56 prošel: globální orchestrátor včetně kontaktu bez resend,
  zachování draftů a obnovení po částečném neúspěchu, společná lišta pro více
  polí a globální discard, přesná geometrie a tažení čáry, existující
  kontaktní a e-mailové regresní scénáře. Dodatečný dotčený běh se čtením
  plánku a globálním save prošel 4/4. Bez změn SQL kontraktu tohoto kola.
- Finální úprava ponechává záložkám původní lokalizované názvy; společná
  lišta je jediným indikátorem neuložených změn. Její cílené prezentační
  testy prošly 29/29. Analyzér dotčených souborů bez chyb a warningů,
  kontrola překladů a diff whitespace prošly.
- Finální lokální Flutter release build dokončen za 78,7 s. SHA-256 na disku
  a přes HTTP je shodný s aktuální hodnotou nahoře. Server nebyl restartován.
- Skutečný browser ověřil jediné společné uložení napříč záložkami: Petr #5
  telefon na +420 777 000 052, interní poznámku s doplněním Global test.
  a Stravu Host 2/PLES-2-2 na Bez omezení. Vše zůstalo po plném reloadu.
  Cena 1600 Kč a přijato 1450 Kč se nezměnily. Společné zahození obnovilo
  více polí; Escape/Pokračovat zachovalo rozepsané změny. Uživatelská
  hodnota telefonu 44334 nebyla přepsána.
- Browser ověřil kurzor ew-resize přímo na čáře i 20px na obě strany,
  u horní i dolní části, skutečné tažení oběma směry a absenci úchopu.
- Na finálním artefaktu browser potvrdil společnou stále viditelnou lištu,
  původní anglické názvy záložek i během editace a globální zahození bez zápisu.
  [Browser receipt](order-detail/global-save-browser-receipt.md),
  [společné ukládání](order-detail/global-save-final.png),
  [samotná dělicí čára](order-detail/divider-final.png).
  Izolovaný browser je uzavřený; HTTP a lokální Supabase zůstávají běžet.
  Produkce nebyla měněna a čeká na výslovný pokyn.

## Šesté upřesnění - zdroj formuláře, přímá poznámka, nadpis

- Zdrojový formulář se zobrazuje jen pro více formulářů ze stejného bundle,
  který určuje sloupec formuláře v tabulce. Není odvozován z počtu objednávek.
- Poznámka používá kanonický překlad OrderGridColumns.hiddenNote, tedy
  Skrytá poznámka. Oprávněný uživatel píše přímo bez tužky; zápis dál patří
  společnému Uložit změny a zahození. Bez oprávnění zůstává pouze čitelná.
  Po uložení, zahození a obnovení se synchronizuje jen čistý draft; rozepsaný
  text zůstává chráněn. Pole si samo nebere fokus při otevření objednávky.
- Nadpis s číslem objednávky je tučný. Cílený analyzér tří dotčených souborů
  bez chyb a warningů, jen dosavadní stylová info. SQL ani data se nemění.
- Flutter release build dokončen za 73,6 s; diskový a HTTP SHA-256
  jsou shodné s aktuální hodnotou nahoře. Lokální server běží dál.
- Skutečný browser potvrdil český název, přímou editaci poznámky bez tužky,
  nepřítomnost lišty u čistého stavu, její zobrazení po změně a společné
  zahození obnovující původní poznámku. Zdroj jediného formuláře není uveden,
  nadpis je tučný. Další objednávka se otevře čistá bez automatického fokusu.
  Nebyly provedeny žádné zápisy do DB. [Receipt](order-detail/note-polish-browser-receipt.md),
  [snímek](order-detail/note-polish-final.png). Vlastní browser uzavřen,
  lokální HTTP/Supabase běží dál; produkce beze změny.

## Sedmé upřesnění - kurzor těsně u dělicí čáry

- Měření skutečného browseru před změnou, viewport 1280x900, DPR 1,
  visual scale 1: čára x679, kurzor ew-resize x656..703 při y600 i y210.
  Oblast tedy nebyla posunutá; její šířka 48 px zapínala kurzor už 24 px
  od středu. Hlavička tabulky má navíc samostatné platné tažení sloupce
  x590..626, které se v těle nevyskytuje a neřídí šířku detailu.
- Aktivní oblast detailu zúžena na 24 px, stále přesně vystředěná na čáře,
  po celé výšce a bez viditelného úchopu. Na vzdálenější části tabulky
  se už kurzor detailu neobjeví. Ukládání šířky per PC beze změny.
- Cílený test splitteru prošel: tažení z obou stran blízko čáry, shodné
  středy, plná výška, meze, klávesnice a místní persistence.
- Flutter release build 67,7 s. Diskový i HTTP SHA-256 shodný
  s aktuální hodnotou nahoře; lokální server bez restartu.
- Finální browser: čára x679, ew-resize x668..691 při y160, y600,
  y880; 20 a 40 px od čáry se kurzor detailu neaktivuje. Skutečné tažení
  doprava u horní a doleva u dolní části funguje; původní šířka obnovena.
  [Receipt](order-detail/divider-tight-browser-receipt.md),
  [snímek](order-detail/divider-tight-final.png). Žádné DB zápisy;
  vlastní browser uzavřen, lokální služby běží dál, produkce beze změn.

## Osmé upřesnění - širší oblast po potvrzení uživatele

- Uživatel upřesnil, že problémem je úzká šířka, nikoli výška oblasti.
  Oblast je rozšířena z 24 na 40 px (20 px na každou stranu čáry),
  po celé výšce, stále bez úchopu a bez změny jejího středu.
- Cílený test splitteru prošel, včetně skutečného tažení z obou okrajových
  částí oblasti (+/-18 px), geometrie, mezí a místní persistence.
- Flutter release build 70,9 s, aktuální diskový a HTTP SHA-256 shodný.
  Naservírováno lokálně; v tomto drobném kole nebyl opakován browser průchod.
  Žádné DB zápisy ani produkční změny, lokální prostředí běží dál.

## Deváté upřesnění - kurzor a skutečný začátek tažení

- Předchozí změny rozměru neřešily samotné zahájení tažení. Na starém
  artefaktu skutečný browser reprodukoval: x661, y600 (18 px vlevo od
  čáry x679), kurzor ew-resize, primární stisk a pohyb 1 px nepohnuly čárou.
- GestureDetector čekající na práh vodorovného gesta nahrazen Listenerem
  ve stejné neprůhledné hit-test oblasti jako MouseRegion. Primární pointer
  se zachytí při stisku a změna šířky odpovídá už prvnímu pixelu pohybu.
  Souřadnice jsou globální, takže pohyb samotné oblasti neposouvá počátek.
  Up/cancel ukládá místní šířku; klávesnice, meze a žádný úchop zachovány.
- Cílený test prošel včetně pohybu 1 px z obou krajů, následného tažení,
  geometrie, mobilního přepnutí a persistence.
- Skutečný browser na novém artefaktu potvrdil pohyb 1 px z obou stran,
  mimo oblast +/-22 px bez kurzoru a bez pohybu; tažení pokračuje i po
  opuštění oblasti. [Receipt](order-detail/cursor-drag-browser-receipt.md).
  Build tohoto kroku 75,2 s.

## Desáté upřesnění - podporovaný obsah vstupenek

- Chybný syntetický seed přidával name/select_one jako is_ticket_field,
  přestože TicketEditorWidgets nabízí produkty, místa a volitelnou poznámku.
  Generický renderer je pak vydával za podporované odpovědi vstupenky.
- Z karet odstraněny obecné odpovědi i odvozené jméno držitele. Produkty
  s cenou z uloženého snapshotu a jejich původní ProductsDialog zůstávají,
  stejně jako místa a existující poznámky. Odpovědi patří jen objednávce.
- Odstraněna per-ticket větev SQL writeru i p_ticket; stará pět parametrů
  přijímající varianta se odstraní. Čtyřparametrový wrapper dál deleguje
  existujícímu update_order_responses. Ticket pole odmítá. Oprávnění,
  immutable kontroly a otisky proti přepisu zachovány.
- Opraven seed a přidán idempotentní sandboxem chráněný korekční SQL.
  Místně odstraněny jen syntetické definice #33/#34 a jejich hodnoty,
  přidáno produktové pole Doplňky. Záloha v soukromém workdir s režimem 0600.
  Porovnání kompletních objednávek a vstupenek podle ID potvrzuje zachování
  všech ostatních hodnot včetně produktů, cen, kontaktů, poznámek a plateb.
  Historické auditní snapshoty se nepřepisují; databáze se neresetovala.
- Flutter testy 31/31 a SQL regression 1/1 v disposable runneru prošly.
  Kontrolují order-only scope, odmítnutí ticket pole, absenci staré RPC,
  práva readera, otisky, volby a oddělený e-mailový owner. Analyzér bez
  chyb/warningů; pouze stylová info. Lokální SQL aplikován, produkce ne.
- Finální build 66,7 s; diskový a skutečně obsluhovaný HTTP SHA-256
  odpovídají aktuální hodnotě nahoře.
- Finální browser: Eva #7/PLES-4-1 bez odvozeného jména držitele,
  bez Jména účastníka a Stravy, se skutečným produktem za 650 Kč.
  Původní ProductsDialog otevřen a uzavřen beze změn. Petr #5 zachovává
  menu, částky 1600/1450 Kč, telefon končící 052 a stávající poznámku.
  [Receipt](order-detail/ticket-scope-browser-receipt.md),
  [český snímek](order-detail/ticket-scope-final.png).
  Vlastní browser uzavřen; HTTP a lokální Supabase běží dál. Žádné další
  browser zápisy ani produkční změny nebyly provedeny.

## Jedenácté upřesnění - kurzor má stejný životní cyklus jako tažení

- Předchozí testy ověřovaly hover a následný pohyb, ale ne kurzor během
  zachyceného tažení mimo původní pás. Přímo reprodukováno na artefaktu
  3a2a7038: při stisku na x679/y600, pohybu do x1200 a dosažení meze byla
  čára x919, tažení zůstávalo aktivní, ale body i hit element měly cursor auto.
  Při návratu x900 se čára opět pohybovala a kurzor se vracel na ew-resize.
- Nový widget test před opravou selhal přesně na očekávaném resizeLeftRight
  proti skutečnému basic. Příčinou bylo oddělení statické MouseRegion od
  aktivního pointeru, jehož události přicházejí i mimo původní hit oblast.
- Aktivní pointer nyní současně vlastní dočasný kurzor v kořenovém Overlay.
  Kurzor proto platí po celou dobu tažení nad celou aplikací. Stejná koncová
  obsluha ho odstraní po up/cancel, hover bez tlačítka, ztrátě fokusu i dispose.
  Místní preference se při samotném stisku bez pohybu nepřepisuje clampingem.
- Relativní pohyb po každé události posune i výchozí bod. Návrat od min/max
  tedy reaguje hned, místo čekání na vyrovnání předchozího přetažení za mez.
  Šířka 40 px při hoveru a vzhled samotné čáry se nemění.
- Cílený test prošel: 15 míst nahoře/uprostřed/dole mají shodnou dostupnost
  resize kurzoru a skutečného pohybu; kurzor během zachyceného tažení mimo
  oblast; min/max a návrat o 1 px; release/cancel/inactive, nové tažení,
  dispose během tažení a zachování dřívější persistence a ovládání klávesnicí.
  Logy resize-capture-red / resize-capture-sweep-tests v soukromém workdir.
- Flutter release build 64,9 s, diskový a HTTP SHA-256 shodné s aktuální
  hodnotou nahoře. Beze změn databáze a produkce.
- Finální skutečný browser zopakoval původní chybu na novém artefaktu:
  při stisku a tahu x679 -> x1200 zůstaly body i hit element ew-resize,
  čára na mezi x919. Návrat o 1 px na x1199 hned posunul čáru na x918.
  Při tahu do x100 druhá mez x519, návrat o 1 px posunul čáru na x520.
  Kurzor zůstal posouvací po celou dobu. Po puštění mimo oblast se obnovil
  auto a nové tažení obnovilo původní šířku/čáru x679. Bez DB zápisů.
  [Browser receipt](order-detail/resize-capture-browser-receipt.md),
  [snímek](order-detail/resize-capture-final.png).

## Dvanácté upřesnění - skutečný nativní kurzor nad HTML vrstvou přístupnosti

- Předchozí browser kontroly četly především document.body.style.cursor,
  což je nastavení kurzoru Flutter enginu, nikoli nutně výsledný kurzor
  nejvyššího HTML elementu pod myší. Widget testy tento rozdíl nemohou zachytit.
- Přesná reprodukce uživatelova idle problému na artefaktu ddef52cd:
  čára x679, body ew-resize x660..698, ale skutečný nejvyšší hit INPUT
  type=range/role=slider měl cursor default x662..700 a pointer-events all.
  Jeho rect [661.5,138,40,760]; rodič FLT-SEMANTICS [659.5,136,40,764].
  Pouze x660..661 mělo skutečný ew-resize, tedy úzký proužek vlevo od čáry.
  Stejné výsledky y160/y600/y800. Toto odpovídá hlášenému chování.
- Příčinou je native range input, který webový engine vytváří pro slider
  v Semantics. Flutter nastavuje kurzor pouze na body, zatímco input ho
  svým default přepisuje. Vlastní Flutter hit-test a možnosti tažení přitom
  zůstávaly správné, proto dřívější widget testy a čtení body chybu minuly.
- Lokální diagnostická změna pointer-events none na tomto sémantickém
  rodiči v izolovaném browseru chybu odstranila v celé oblasti včetně čáry.
  Zdrojová oprava používá oficiální SemanticsHitTestBehavior.transparent
  pouze u splitteru. Neodstraňuje přístupnost: slider, label a increase/decrease
  zůstávají; pointer a kurzor obsluhuje dosavadní Flutter vrstva. Žádný globální
  CSS zásah a žádná změna ostatních sliderů.
- Cílený test prošel včetně skutečného vyvolání sémantických akcí increase
  a decrease, klávesnice, shody míst kurzoru s tažením, zachyceného pointeru,
  obou mezí, lifecycle a persistence. Nativní HTML kurzor se ověřuje browserem.
- Flutter release build 70,9 s; diskový i skutečně obsluhovaný HTTP SHA-256
  shodné s aktuální hodnotou nahoře. Databáze a produkce beze změn.
- Finální browser po čistém reloadu, bez diagnostických stylů: range input
  zůstává role=slider/type=range; rodič má pointer-events none vytvořené
  enginem a input je dědí. Skutečný nejvyšší hit má ew-resize na x661,
  x679 i x697 při y160/y600/y800; mimo oblast x657 auto a x701 text.
  Pohyb o 1 px ze tří míst posunul čáru 679 -> 680 -> 681 -> 680;
  původní šířka obnovena na x679. Kontrola tedy měřila skutečný nativní
  kurzor a skutečný pohyb, nikoli jen nastavení body.
  [Receipt](order-detail/resize-native-cursor-browser-receipt.md),
  [snímek](order-detail/resize-native-cursor-final.png).
  Vlastní browser uzavřen, žádné DB zápisy; lokální HTTP/Supabase běží dál.

## Třinácté upřesnění - tužka napravo u řádku odpovědi

- Readonly řádek odpovědi nyní seskupuje label a hodnotu vlevo a jedinou
  ikonu tužky napravo, s vertikálním zarovnáním ke celému řádku. Žádný
  textový Edit/Upravit action; lokalizovaný tooltip a klávesnicová dostupnost
  zůstávají. Poznámka je dál přímo editovatelná, ostatní readonly pole bez akce.
- Kontaktní e-mail v přehledu má stejnou pravou tužku místo TextButton.icon.
  E-mail mezi odpověďmi se otevře inline; neodvádí uživatele na E-maily.
  Je svázán přímo s existujícím c.email, takže používá jediný recoverable
  contact owner a společné Uložit změny, bez dalšího RPC nebo duplicitního draftu.
  Samostatný kontaktní/e-mailový editor a jeho odesílací akce se nemění.
- Externí text controller vlastní rodič; pole pouze připojí a odpojí listener,
  nepřeregistrovává jeho uložení a nedisponuje controller. Odstraněna stará
  callback větev onEditEmail/onEdit odvádějící editaci mimo řádek.
- Cílené testy 56/56 prošly: geometrie pravé tužky, okamžité otevření e-mailu,
  shodný canonical controller a jediný globální draft, discard, inline scalar
  chyby/readonly a dosavadní kontaktní/recovery scénáře. SQL a DB beze změny.
- Flutter release build 94,7 s; diskový i HTTP SHA-256 odpovídají aktuální
  hodnotě nahoře. Lokální server dále běží.
- Finální český browser: řádky odpovědí mají tužky úplně napravo bez
  textového Edit/Upravit. E-mail se otevřel inline beze změny URL či záložky,
  jediná společná Save/Discard lišta obnovila host2@example.invalid.
  Telefon se otevřel inline a discard zachoval číslo končící 052.
  [Receipt](order-detail/answer-pencil-browser-receipt.md),
  [snímek](order-detail/answer-pencil-final.png).
  Žádné DB zápisy, vlastní browser uzavřen; HTTP a lokální Supabase běží dál.
  Produkce beze změny.

## Příprava povoleného vydání 2026-11-02

- Uživatel výslovně povolil nasazení a změnil české obchodní akce na
  Stornovat. Týká se objednávek, vstupenek/přihlášek, potvrzení, storno stavů,
  souvisejících notifikací a e-mailových UI textů. Dismiss, zahození úprav
  a odvolání naplánované cenové změny zůstávají Zrušit. CLAUDE.md aktualizován.
- Změny izolovány od jiných rozpracovaných úloh v čisté větvi z aktuálního
  origin/main 7fbbfff3757d137a073a9cab1eedaf941eea66a0. Scope pouze
  prod/festapptickets, vstupenky.online, canonical org 3 / generation 1.
  Předchozí prod tip accd791bc, verze 0.20.480+986. Žádný jiný tenant není v scope.
- Release kontrola našla a opravila regresi zachování skupinového výběru:
  opakované předání výchozí Trina konfigurace při rebuild panelu vracelo
  runtime row selection do cell selection. Konfigurace nyní zachová aktuální
  selection mode. Vyčištění notificationGroup samo nespouští nové načtení.
  Jednorázové otevření viditelné objednávky také obnoví fokus řádku bez
  tichého rušení filtrů a bez fokusu skryté mobilní tabulky.
- Fixture notifikací odpovídá kontextu reálné akce a desktopovému rozložení;
  explicitní symbol zůstává vstupem do detailu, zákaznický přehled je v headeru.
- Nově ověřeno 12/12 notifikačních scénářů (retained routing, návrat z historie,
  skutečné kliknutí na zvonek a zachování hromadných checkboxů). Další cílený
  běh grid/presentation/public SDK viewport/navigation prošel 40/40.
  Oba SQL reader/writer regression testy prošly z čisté větve v lokálním
  disposable projektu. Ostatních 77 scénářů původního release běhu prošlo;
  selhání notifikační fixture a související regrese jsou pokryty novým green během.
- Žádné produkční DDL ani nasazení zatím nebylo provedeno. Read-only preflight
  ověřil profil, hostname, runtime databázi a organizaci. Existující chráněný
  release manifest byl oficiálním provisioning workflow přenesen a ověřen
  mimo repozitář; žádné privátní hodnoty nejsou součástí commitu.
