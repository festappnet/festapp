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

Průvodce začíná otázkami Název / Termín / Typ / Vzhled. Běžná akce má
formulář, koncert přidává vstupenku a ples vyžaduje sál. Platby a splatnost se
objeví podle kladných cen produktů. Přímé cíle v záhlaví a mobilní přehled
používají stabilní klíče stejného resolveru jako číslování a progress. Kopie
události je nečíslovaný vstup viditelný pouze při dostupných předlohách;
kopie formuláře se nabízí pouze pro dostupné formuláře. Přehled zahrnuje
oprávněné zdroje všech jednotek cílového tenantu, bez rozšíření copy oprávnění.

Název formuláře se odvozuje od názvu akce, včetně převzatých formulářů.
Upravený slug se při přejmenování nemění. Jeden model `appearance` ukládá
konkrétní barvy, režim pozadí a písmo; mapuje je do designu formuláře i layoutu
vstupenky. Kopírovaný vlastní vzhled zůstává zachován do výslovné volby stylu.
PDF používá axiální gradient a vložený font, Flutter stejný směr shaderu a
veřejný JS formulář CSS gradient. Náhled vstupenky autorizuje vlastní draft
s revizí přes `get_occasion_setup_ticket_preview`, bez cizího occasion ID.

Koncepty používají původní revizovaný autosave a finalizaci
`finalize_occasion_setup_draft`. Neaktivní sál/vstupenka zůstávají v konceptu,
ale SQL je nevytvoří. Prázdné pole dovolí přímý skok, nikoli dokončení;
selhání save ponechá lokální práci a zobrazí opakování. Připravenost se počítá
z aktivních otázek; 100 % vyžaduje výslovnou závěrečnou kontrolu.

Spouštěč obnoví kanonické draft/source/finalize funkce, návrhy odkazů a
validátor ticket layoutu. Existující backend neobnovuje plošně na nové schéma;
při starém baseline použij nový `FESTAPP_WIZARD_WORKSPACE` s prefixem
`festapp-wizard-`, zachovej původní data a zajisti volné porty 56821/56822.

Aktuální důkazy implementace: [typy a společný vzhled](../archive/plans/occasion-setup-types-appearance-VERIFICATION-2026-10-22.md).

## Historické konfigurace a starší ověření

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

Rozpracované koncepty jsou v `public.occasion_setup_drafts`. Teprve finalizace
materializuje skutečné řádky události, formuláře, produktů a případného plánku.
Výsledná odpověď a ID události zůstávají u konceptu pro bezpečné opakování.
Vývojový flag `FESTAPP_OCCASION_SETUP` je ve výchozím sestavení vypnutý a
v produkčním sestavení se ignoruje. Lokální spouštěč bez `--enable-wizard`
ponechává původní způsob vytvoření události.

Backend patří výhradně projektu `festapp-wizard-local` v sourozenecké složce
repozitáře. Porty API/DB jsou 56821/56822. Skript vytvoří čerstvý backend,
načte kanonický baseline, novější migrace a testovací seed. Při dalších spuštěních
zachová data a obnoví kanonické soubory `sources.sql`, `drafts.sql`, `finalize.sql`, `form_link.sql` a `email_preview.sql`. Lokální Edge runtime obsluhuje oba náhledy.
Novější obecné migrace po prvním
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

## Platnost lokálního prostředí

Následující měření a popis šesti importovaných předloh jsou dobové záznamy.
Soukromý snapshot není součástí checkoutu a nové spuštění jej automaticky
nestáhne. Před zkoušením finalizace zkontroluj schéma lokálního backendu; samotný
restart nad starou databází nezajistí nové migrace ani nejnovější finalizační RPC.

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

Při ověření 2026-10-05 byly lokální backend a Flutter preview ponechány běžet.
Tento záznam nedokládá, že tyto procesy běží nyní.
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

Výběry kopií formuláře a plánku čtou lehké souhrny autorizovaného source listu a detail načítají až po výběru. Nevybírají zdroj celé události. Zrušení výběru ponechá koncept beze změny; bezprostřední vrácení kopie formuláře obnoví i vazby plánku. Dostupnost odkazu je jen náhled, finální přidělení stále vlastní atomický serverový allocator.

V tomto checkoutu používá draft editor starší mřížkový kontrakt. Novější katalog `VenueLayoutDocument` nalezený ve worktree `festapp-setup-usability-20261021` do něj nelze načíst jako grid JSON. Minimální skutečný katalog proto nabízí prázdný plánek a upravitelné 4 řady po 8 místech; nepředstírá konkrétní existující sály. Výběr nic nevkládá před potvrzením. Uložení a návrat přijme baseline editoru až po potvrzeném flushi konceptu; selhání nechá editor otevřený.

Regrese bankovní chyby `21000` je doložená přes skutečné RPC na disposable DB při explicitní simulaci historického driftu: bez primárního klíče členství vzniknou dva řádky role a původní scalar subquery selže. Kanonický lookup používá existenční oprávnění `EXISTS` a zachovává demo guard. Simulace není důkazem skutečného stavu produkce; běžný kanonický baseline duplicitu klíčem zakazuje. Viz `database/tests/units/manager_membership_cardinality_test.sql`.
