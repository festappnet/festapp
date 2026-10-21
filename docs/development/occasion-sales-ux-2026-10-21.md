# Průvodce a stav prodeje - implementace

Pracovní větev `feat/occasion-setup-ux-20261021`, samostatný checkout `festapp-occasion-ux-20261021`, základ `origin/main` na `63551cb5e`. Původní rozpracovaný checkout zůstal nedotčený. Produkční nasazení není součástí této změny.

## Odsouhlasené chování

- Karta má výšku 126 px a dvouřádkový název. Zachovává statistiky a stávající nabídku, přidává jediný štítek vpravo nahoře.
- Více formulářů: `V prodeji 2/5` nebo `Náhradníci 1/3`. Aktivní počet zahrnuje nákup i přijímání náhradníků; při kombinaci má přednost prodej. U jednoho formuláře se počet nepřidává. Bez aktivních formulářů se ukazuje slovní stav.
- Příprava, naplánovaný začátek, prodej, náhradníci, vyprodáno, pozastavení, ukončený prodej a proběhlá akce jsou odlišné stavy. Stav nevychází z počtu objednávek. Samostatný štítek „Nová“ se nepoužívá.
- Odpočty výslovně uvádějí `Prodej začíná za ...` nebo `Prodej končí za ...`. Používají dny, hodiny a minuty, správné plurály a přesný termín v podrobnostech. Bez odpočtu je před začátkem `Prodej od ...`. U více aktivních formulářů má přednost stav s počtem; konec odpočtu se nezaměňuje s koncem pouze jednoho z více formulářů. Odpočet konce jediného formuláře se ukazuje v posledních třech dnech.
- Průvodce nabízí ponechání v přípravě, naplánované otevření a otevření ihned. Výchozí konec je konec akce; dřívější termín je možný. Zobrazení odpočtu je nezávislá volba.
- Produkty a ceny zůstávají uvnitř skutečného editoru formuláře, příslušné produktové části jsou rozbalené. Nevznikl druhý katalog ani druhý datový model vstupenek.
- Kontrola má checkbox a jediné finální vytvoření. Popisek tlačítka odpovídá zvolenému otevření prodeje. Autosave konceptu zůstává zachován.
- Dokončení obsahuje serverem potvrzený prodejní odkaz, popsané tlačítko Kopírovat a otevření formuláře. Návrat do přehledu novou kartu jednou zvýrazní; posun na kartu i zvýraznění respektují omezené animace. Odkaz ani kopírování nepřibyly do karet.

## Pokrytí ostatních nálezů

Všech sedm bodů původního UX auditu je zahrnuto:

1. **Co po vytvoření:** dokončovací obrazovka, skutečný prodejní odkaz, kopírování, stav prodeje a návrat na zvýrazněnou kartu.
2. **Produkty a ceny:** rozbalený kanonický editor včetně limitu vstupenek na objednávku. Nový starter má názvy „Vstupné“ a „Základní vstupenka“ místo „Spot“ / „Variant 1“. Převzaté názvy, identity, ceny a limity se automaticky nepřepisují.
3. **Potvrzování:** jeden checkbox a jedna finální akce, skutečné validační problémy oddělené od informace o neveřejné akci.
4. **Pohled zákazníka:** před vytvořením je dostupný izolovaný náhled skutečných formulářových polí a výpočtu ceny. Potvrzovací e-maily používají existující renderer a zděděné šablony cílové organizace, případně výslovně kopírované šablony zdrojové akce. Krok pro vzhled vstupenky je přístupný v obou variantách aplikace. V organizaci bez jediné autorizované předlohy zůstává stávající omezení: editor oznámí nedostupnost ticketového náhledu; nevytváří kvůli němu pomocnou živou událost. Náhled neobsahuje checkout ani rezervační volání; konkrétní místa v něm nelze rezervovat. E-mail používá jasně označenou ukázkovou objednávku, nezávislou na rozepsaných náhledových polích. Nedostupná preview služba se zobrazí jako nedostupný náhled, nikoli jako ověřený výsledek. Stávající emailové ukázky obsahují české a anglické scénáře.
5. **Provozní nastavení:** zděděná adresa pro odpovědi zůstává konkrétní; pokud se použije systémový odesílatel, načte se jeho skutečná adresa přes stávající authoring-context službu cílové organizace. Při jejím výpadku UI nepředstírá znalost adresy. Nepropojený bankovní účet má přímo v průvodci vysvětlení ručního potvrzení platby a dopadu na doručení vstupenky; správa účtů zůstává v existujícím rozhraní.
6. **Dostupnost průvodce:** pojmenované volby postupného a rychlého vytvoření jsou dostupné přímo u tlačítka nové události i v aplikační variantě.
7. **Orientace:** zůstal jeden ukazatel pozice v otázkách. Jeho tlačítko otevře číslovaný seznam pojmenovaných kroků ovladatelný dotykem i klávesnicí. Druhé procento dokončení se nezobrazuje.

Technické nálezy z předchozích dvou handoffů jsou již v základu `63551cb5e` / PR #547: obsazenost při kopii, terminální receipt konceptu, volba bez plánku, oprava vazeb po výměně formuláře, stabilní ID předloh, kapacita a náhradníci, vazby vzhledu vstupenek i konfigurace programu. Stávající SQL regresní soubory pro tyto hranice byly při tomto rozšíření znovu zahrnuty v osmi úspěšných SQL kontrolách. Historické ticket-layout schema 1/2 vyžaduje existující offline konverzi; nevznikla druhá runtime konverze ani zásah do produkčních předloh.

## Datový kontrakt

Nové nastavení se při finalizaci zapisuje do existujícího `forms.is_open` a `data.schedule`. Naplánovaný formulář používá běžnou kontrolu časového okna, nepotřebuje nový scheduler. Otevření formuláře nepřepíná katalogovou viditelnost akce. Kopírované historické termíny i ploché legacy klíče jsou nahrazeny nastavením nové akce.

`data.schedule.sale_preparation` rozlišuje počáteční přípravu od pozdějšího pozastavení. Běžný příkaz otevření i existující plánovaný příkaz přípravu ukončí. Neodvozuje se to od testovacích ani placených objednávek.

Existující autorizovaný katalog `get_all_occasions_for_edit_v212` vrací bezpečný souhrn všech formulářů v `sale_forms`. Interní projekce není veřejně volatelným RPC. Využívá stávající režim registrace, kapacitu, čekací listinu a inventář produktů/plánku včetně blokací a dočasných držení. U běžných vstupenek kontroluje skutečné vnořené produktové pole, nikoli pouze obal `ticket`. Jde o informativní snapshot; rezervaci dále rozhoduje existující checkout.

Receipt finalizace je rozšířený o skutečný `formLink` a režim prodeje. Opakování příkazu vrací tentýž receipt. Migrace `20261021220000_occasion_sales_setup_and_catalog.sql` obsahuje kanonické zdroje; v produkci nebyla spuštěna.

## Ověření

Výsledek závěrečného cíleného Flutter běhu: **54/54 testů** (13 occasion, 35 stávajících testů průvodce a clipboard komponenty, 6 navigačních/layoutových testů shellu). SQL: **8/8 souborů**. Nové kontroly pokrývají také lidské názvy starteru bez změny ceny/ID a bez přepisování kopie, izolaci náhledových polí od uloženého konceptu a dotykový seznam pojmenovaných kroků. Závěrečná analýza 11 dotčených souborů rozšíření nehlásila chyby ani warningy; 47 hlášení jsou stylová info. Dřívější analýza pokryla 24 souborů základní změny.

Před commitem proběhlo povinné `apply_config.sh` (bez změny konfigurace), sjednocení Flutter/web překladů a seřazení češtiny podle angličtiny. Obsah již testovaných Flutter textů se tím nezměnil. Parita SQL zdrojů a validita lokalizačních katalogů prošly.

```sh
fvm flutter test --no-pub --concurrency=1 test/sessions/shared_czech_test.dart test/sessions/shared_default_2_test.dart test/components/occasion/occasion_setup_story_shell_test.dart --name 'occasion_sale|copy_button|occasion_setup_story|occasion_setup_details|story shell|segments expose|named question|segment navigation'
# DATABASE_URL směřuje výhradně na výše uvedený disposable localhost:
pnpm --dir web_client exec node scripts/run_db_tests.js occasion_setup/sales_test.sql occasion_setup/finalize_test.sql occasion_setup/feature_choices_test.sql occasion_setup/copy_configuration_test.sql canonical_mutation_source_parity_test.sql operations/configuration_version_writers_test.sql performance/get_occasions_payload_size_test.sql eshop/product_price_scheduling_test.sql
```

Lokální Supabase `festapp-occasion-repair-20261021`, API `127.0.0.1:56931`, DB `127.0.0.1:56932`. Pouze syntetická data. Prohlížeč měl vlastní headless profil; uživatelův Chrome zůstal nedotčený.

- Skutečné UI: přihlášení, vytvoření `UX Prodej 20261021`, úprava názvu/ceny produktu, okamžité otevření, jeden finální checkbox, dokončovací obrazovka, prodejní adresa a návrat do seznamu. DB readback: akce 284, formulář `ux-prodej-20261021`, otevřený.
- Skutečné UI: kopie této otevřené akce, výchozí příprava a samostatný nový odkaz. DB readback: akce 293, formulář `ux-prodej-20261021-kopie`, zavřený, příprava. Ověřen i mobilní layout dokončení.
- Přepnutí na plánované otevření bylo ověřeno v UI. Výběr data, UTC převod pro Europe/Prague a nezávislost odpočtu mají widgetový test. Všechny tři režimy a časové brány mají skutečné SQL testy.
- Widgetové testy: slučování stavů, poměry formulářů, plurály 1/2/3/5/21, odpočty začátku i konce, úzké karty při 1x/2x textu, kliknutí na stav bez otevření akce, kopírování potvrzené adresy přes platformní clipboard kanál, dokončení a odhalení karty mimo lazy viewport.
- SQL testy: finalizace, konfigurace kopie, aktivní feature volby, nové sales případy, inventář plánku, zdrojová parita funkcí, verze plánovaných změn, katalogový payload a plánované ceny produktů.
- Test ochrany měny formuláře původně očekával historický JSON error adapter. Stejné selhání bylo reprodukováno na nezměněné funkci z HEAD v rollback transakci. Test nyní kontroluje skutečnou typovanou validační výjimku a zachování měny; platební logika nebyla změněna.
- Všech šest lokalizačních katalogů je validní. Cílená analýza nehlásila chyby ani warningy; dotčené stávající soubory mají stylová info hlášení.

Nově přidaný zákaznický náhled byl ověřen widgetovým testem; úplný browser průchod ani živá authoring-context služba pro e-mailový náhled po tomto doplnění ověřeny nebyly.

Browser clipboard byl omezen oprávněními izolovaného automatizovaného kontextu (`NotAllowedError`); skutečný zápis do systémové schránky proto tímto browser průchodem není doložen. Zápis správné serverem potvrzené adresy a jeho zpětná vazba jsou ověřené existujícím platform-channel testem i novou variantou s popsaným tlačítkem. Veřejný produkční formulář nebyl v testu otevírán a žádné skutečné objednávky ani externí e-maily se nevytvářely.

## Náhledy

- [Odsouhlasená interaktivní maketa](../design/occasion-sales-preview/index.html)
- [Dokončení v reálném Flutter UI na mobilu](../design/occasion-sales-preview/implemented-completion-mobile.png)
- [Karty v reálném Flutter UI na mobilu](../design/occasion-sales-preview/implemented-cards-mobile.png)
