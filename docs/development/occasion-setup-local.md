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

Pro vstupenky.online je tok Zdroj, Základ, Formulář, Plánek, Nastavení plateb, Vstupenka, Kontrola.
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
