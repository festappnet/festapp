# Lokální integrovaný Wizard

Spuštění z kořene repozitáře (Docker/Colima, Supabase CLI, psql, Python 3.11+ a FVM):

```sh
python3 automation/run_occasion_setup_local.py --enable-wizard
```

Otevři http://127.0.0.1:56880/unit/1/edit a přihlas se jako `t@t.com`, heslo `test`.
Klikni na „Vytvořit novou událost“. Vyplň základ, počkej na „Uloženo“ nebo použij
„Uložit a vrátit se do seznamu“. Koncept pokračuje ze samostatné sekce seznamu
po obnovení stránky. Klávesa `r` v terminálu načte změny Flutter kódu.

Jde o skutečný `main.dart`, autentizaci lokálního Supabase, skutečný seznam
událostí a RPC konceptů. Jediná nahrazená externí hranice jsou push callbacky.
Vývojový entrypoint odmítá backend mimo `127.0.0.1:56821`; explicitní loopback
backend v debug režimu nepoužívá produkční aktivační dokument ani jeho marker.

Průvodce zobrazuje jednu otázku najednou s neutrálními popisky. Název,
společný termín (začátek i konec) a představení akce tvoří základ. Představení
umožňuje místo konání, popis, úvodní obrázek a volbu propagace. Obrázky se
nahrávají stávajícím unit-scoped image writerem; odebrání z konceptu je pouze
odpojí a nemaže sdílený soubor. Finalizace ověří vlastnictví obrázku jednotkou.
Propagace vyžaduje obrázek a sama akci nezveřejní ani neotevře prodej.

Další otázky se odvozují od aktuální konfigurace: vypnutý formulář odstraní
související editory, nulové ceny vynechají platby a cenové vlny, chybějící pole
vstupenky vynechá její vzhled a odbavení. Cenové vlny jsou volitelné; používají
stávající editor s draftovým adaptérem. Do databázové fronty se zapíší až při
finalizaci přes existující price-wave příkazy a nově mapovaná ID produktů.
Odbavení je samostatná otázka pouze po výslovném zapnutí doplňující volby u
vstupenky. U placené akce má vlastní otázku potvrzení účtu pro příjem plateb.
Nabízejí se pouze účty připojené k jednotce, které podporují měny placených
produktů. Správce může otevřít stávající správu účtů a účet vytvořit nebo
připojit; editorovi bez těchto práv zůstává možnost uložit koncept. Potvrzený
účet se připne k formuláři. Server při finalizaci znovu ověří jednotku, měny
a fingerprint platebních instrukcí; změněný účet vyžaduje nové potvrzení.
Legacy koncepty bez nového potvrzovacího pole zachovávají původní routování. Dřívější skryté volby se bez příslušné funkce neuplatňují.

Ověřená organizace otázku na ověření přeskočí; její stav je v souhrnu. Při
neznámém stavu nebo chybě načtení zůstává nepovinná otázka dostupná. Ověření
nemění podmínky dokončení. Procenta počítají pouze použitelné povinné kroky;
horní segmenty popisují polohu v aktuálním průchodu.

Adresa formuláře se navrhuje podle názvu a roku akce. Server konzultuje
kanonické globální rezervace včetně historických adres a přidává čitelný suffix.
Ruční úpravu nepřepíše další změna názvu. Dostupnost je náhled; automatický
návrh se při finalizaci znovu ověří a při kolizi přidělí další volný suffix.
Ručně zvolenou adresu server nikdy bez souhlasu nepřejmenuje. URL akce se u
tenantů bez aplikace nevyplňuje; URL formuláře zůstává samostatná.

Otázka se ukládá do `data.storyQuestion` uvnitř původního stabilního kroku;
`current_step` se nemění. Historické otázky `start`/`end` se obnoví do společného
termínu. Pokud se dříve uložená otázka přestane používat, pokračuje průvodce
následující použitelnou otázkou. Navigace Zpět / Pokračovat je mimo posouvaný
obsah a zůstává dostupná i u editorů. Nahrávání obrázku dočasně blokuje odchod.

Výchozí vstupenka bez uloženého layoutu používá společnou novou bílou šablonu
s hierarchií názvu, data, místa, účastníka a QR. Vlastní uložené šablony se
nemění. Draftový náhled doplní aktuální název, termín a místo, ale nadále
ověřuje práva a načítá zdroje pomocí skutečné autorizované předlohy.

Pro nové RPC a rozšířenou finalizaci je třeba migrace
`20261019123000_occasion_setup_adaptive_details.sql`; pouhý restart staršího
lokálního backendu ji automaticky nenainstaluje.

Nový koncept vzniká přes stejný SQL algoritmus jako běžná událost
(update_occasion_internal_v1, včetně vytvoření formuláře a produktů).
Algoritmus běží v podtransakci, jejíž zápisy se vrátí zpět; zachová se pouze
konfigurace uložená do occasion_setup_drafts. Koncept proto nevytváří trvalé
řádky událostí, formulářů ani produktů. Sekvence ID mohou postoupit.
Výchozí hodnoty se neduplikují v Dart kódu. Koncept rovnou obsahuje formulář:
povinný e-mail, vstupenku a jednu variantu produktu Spot za 100 CZK.
Editor obsahu je vložený přímo do kroku Formulář a změny průběžně ukládá
do konceptu. Pole jsou přímo na ploše bez vnořeného canvasu a scrollu. Plánek má samostatný krok za Formulářem. Vstupenka používá existující editor vzhledu,
ale jeho nastavení ukládá pouze do konceptu. Náhled vyžaduje lokálně spuštěnou
Edge Function `preview-ticket-layout`, kterou spouštěč automaticky zapne. Nastavení plateb má vlastní krok s bankovní
trasou, splatností a související komunikací.
Krok Obsah patří jen aplikacím s programem a informacemi; ve vstupenky.online
se nezobrazuje ani nepřebírá a registrace/prodej je vždy zapnutá. Starší
koncepty se při otevření přizpůsobí tomuto toku. Skutečné editory formuláře a plánku pracují s modelem konceptu a jejich
uložení pokračuje přes verzovaný databázový autosave. Dokončený koncept může
ukázat 100 %, ale samotná finalizace do nové události ještě není implementovaná.
Tlačítko na konci ukládá dokončený koncept, nepředstírá vytvoření události.
Původní samostatný prototyp byl přesunut do `lib/components/occasion/setup/`.

V lokální databázi jsou konfigurace šesti skutečných událostí z
`vstupenky.online`: r48vetrkovice, Skautský tábor 2026, Skautský ples 2026,
Sportovní ples Větřkovice 2026, Ples obce Větřkovice a Farní ples. Zdrojová
organizace 3 byla ověřena vůči aktivačnímu dokumentu a kanonickému backendu;
export běžel v read-only transakci. Jsou to soukromé lokální kopie konfigurace
bez objednávek, odpovědí, účastníků, plateb a obsazenosti. Lokální statistiky jsou
proto nulové. Zdrojové události se neměnily. Nastavení platebních účtů se
nepřenáší; v konceptu je automatická platební trasa určená k pozdějšímu ověření.

Snapshot je uložený pouze v sourozeneckém lokálním backendu s oprávněním 0600;
není součástí repozitáře. Opakovaný import zachovává existující konfigurace:

```sh
python3 automation/localize_occasion_setup_media.py ../festapp-wizard-local/vstupenky-source-configurations.json
node web_client/scripts/import_occasion_setup_sources.js ../festapp-wizard-local/vstupenky-source-configurations.json --refresh-media
```

Koncepty jsou v `public.occasion_setup_drafts`, nikdy v `public.occasions`.
Vývojový flag `FESTAPP_OCCASION_SETUP` je ve výchozím sestavení vypnutý a
v produkčním sestavení se ignoruje. Lokální spouštěč bez `--enable-wizard`
ponechává původní způsob vytvoření události.

Backend patří výhradně projektu `festapp-wizard-local` v sourozenecké složce
repozitáře. Porty API/DB jsou 56821/56822. Skript vytvoří čerstvý backend,
načte kanonický baseline, novější migrace a testovací seed. Při dalších spuštěních
zachová data a obnoví jen RPC konceptů a předloh. Novější obecné migrace po prvním
bootstrapu se automaticky nepřidávají. Nepřepisuje neoznačenou existující DB.
Klíče jsou v lokálním souboru `wizard-defines.json` s oprávněním 0600.

Ukončení: `q` zastaví Flutter. Backend zastav bez ztráty dat:

```sh
supabase stop --workdir ../festapp-wizard-local
```

Kontroly:

```sh
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:56822/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/occasion_setup
fvm flutter test --dart-define=FESTAPP_SUPABASE_URL=http://127.0.0.1:56821 test/services/backend_activation_service_test.dart
fvm dart analyze lib/components/occasion/setup lib/components/unit/views/occasions_screen.dart lib/components/occasion/occasion_creation_helper.dart lib/services/backend_activation_service.dart
```

Fyzické obnovení stránky vrací na seznam jednotky; rozpracovaný koncept se otevře
přes „Pokračovat“. Poslední krok je v databázi. Změny bez potvrzeného „Uloženo“
mohou být při zavření celé stránky ztraceny; běžný návrat v aplikaci čeká na save.

## Ověření 2026-10-05

- SQL kontrakt: 2 testy prošly (práva, jiná organizace, odebraná práva, retry,
  konflikt revizí, absence veřejné události, smazání).
- Aktivace backendu: 8 Flutter testů prošlo včetně explicitního lokálního
  override, který nepřečte marker ani nenačte produkční aktivační dokument.
- Nové Dart soubory a aktivační služba: analyzátor bez nálezů. Upravené starší
  soubory mají stávající informační linty, žádnou chybu ani warning.
- Izolovaný headless browser: přihlášení, otevření ze skutečného seznamu,
  autosave názvu/odkazu/termínu, návrat do seznamu, fyzické obnovení stránky,
  pokračování a obnovení posledního kroku i všech údajů v souhrnu. Mobilní
  souhrn vizuálně ověřen na šířce 390 px.
- Flutter sémantické kliknutí bylo použito tam, kde CDP pointer click nevyvolal
  handler. Ověření tedy dokládá tok a persistenci, nikoli všechny pointer hitboxy.

Lokální backend a Flutter preview byly ponechány běžet pro požadované zkoušení.
Produkce se neměnila. Žádné nasazení ani zveřejnění.

## Ověření rozšířeného Wizardu

Manifest předloh a draft RPC: 2 SQL testy prošly včetně všech šesti kroků,
konfigurace formuláře/produktů/plánku, zákazu cizí jednotky, odstranění
rezervačních tajemství a resetu obsazenosti. Import šesti reálných konfigurací
prošel; opakovaný import vytvořil 0 dalších událostí. Nový integrovaný Dart modul
prošel analyzátorem bez nálezů. Staré vstupní soubory mají jen původní informační
linty. Browser ověřil skutečné předlohy v seznamu a ve výběru zdroje, převzetí
formuláře Skautského plesu a uložení úpravy názvu jeho pole do DB konceptu.
Krok plánku načetl všech 182 míst stejné předlohy.

Pozadí plánků jsou zachována: SVG přímo v konfiguraci a fotografický podklad
Skautského plesu ve vlastním lokálním Storage bucketu `wizard-source-assets`.
Při přenosu se zachovají názvy sedadel i jejich vazby na skutečné produkty.
Regrese načítání produktů do draft editoru je pokrytá widget testem; oba cílené
blueprint testy prošly (produktová vazba a uložení/zahození změn velikosti).

Poslední browser kontrola ověřila i vstup „Vytvořit kopii“ ze skutečné karty
Skautského plesu: Wizard předvolil správný zdroj a skutečný editor plánku zobrazil
182 volných sedadel, původní fotografický podklad z lokálního Storage a ceny
přiřazených produktů (například Místo 450 Kč). Screenshot byl vizuálně posouzen.

## Komunikace a výchozí hodnoty organizace

Wizard nabízí zděděnou adresu pro odpovědi a tón, případně vlastní hodnoty pro
akci. Bez přepsání zůstávají adresa a tón navázané na organizaci. Připomínky a
jejich předstih se zobrazují jen u placeného formuláře. Jejich organizační
výchozí hodnoty se při založení uloží do konfigurace akce; změna výchozích hodnot
nepřepisuje připomínky existujících akcí ani jejich frontu.

Správce může vlastní hodnoty samostatným tlačítkem uložit jako výchozí pro
organizaci, také při první akci. Používá se existující verzovaný příkaz pro
uložení organizace, který při souběžné změně vrátí konflikt. Editor smí změnit
komunikaci konceptu, nikoli organizační výchozí hodnoty. Dokončení akce
nadále vyžaduje správce podle existujícího příkazu pro založení. Samotné dokončení Wizardu
organizaci nemění. Souhrn ukazuje zděděné i vlastní hodnoty.

Ověření komunikace: 33 cílených Flutter testů (komunikace, příběh průvodce a
adaptivní detaily) a 5 SQL testovacích souborů prošlo na izolované databázi.
Cílený analyzátor nemá chyby ani warningy; zůstávají informační linty pro bloky
podmínek. Překlady všech šesti jazyků jsou validní JSON. Produkce se při tomto
ověření neměnila.
