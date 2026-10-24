# Zmenšení repozitáře bez změny chování aplikace

Datum: 2026-10-21  
Stav: Dokončeno pro ověřenou hranici K `20260906140000`; novější upgrade vstupy zůstávají aktivní. [Výsledek a důkazy](repository-size-cleanup-RESULT-2026-10-21.md).
Verifikace: standard kvůli migracím a sdílenému nativnímu chování.  
Základ průzkumu: větev `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`, včetně rozsáhlého necommitovaného pracovního stromu.

## Výsledek a rozsah

Odstranit nepotřebné pracovní výstupy a opakovanou instalační SQL historii; zachovat současné mapy, databázové kontrakty a obnovitelnost. Výsledek měřit odděleně jako počet verzovaných textových řádků, objem souborů a objem lokálních cache. Přesun do `docs/archive` nezmenšuje repozitář. Označení generovaných souborů nemění jejich skutečný počet řádků.

Rozsah: MapLibre patche, `.codex-artifacts`, dokončené plánovací podklady, baseline/migrace a jejich spotřebitelé. Fonty, fontové assety a jejich runtime katalog zatím ponechat. Žádný deployment, změna produkční databáze, přepis Git historie ani plošný úklid celého disku. Tento plán rozšiřuje rozsah vedle [dřívějšího plánu mrtvého kódu](obvious-code-cleanup-plan-2026-10-18.md); jeho jednotlivé kandidáty znovu nepovažovat za potvrzené a neprovádět druhý široký audit.

## Potvrzené důkazy

| Fakt | Důkaz a dopad |
|---|---|
| Historický nárůst činí přibližně 513 tisíc textových řádků | Git blob obsah: `72c510241^` 201 046, HEAD 714 032; nejsou to řádky čisté aplikační logiky. |
| Dva největší generované soubory mají 174 558 řádků | `packages/maplibre_android/lib/src/jni.g.dart` 140 959; `packages/maplibre_ios/lib/src/maplibre_ffi.g.dart` 33 599. |
| Aktuální publikované balíčky stále neobsahují všechny patche | Dne 2026-10-21 přímé API a archivy pub.dev potvrdily `maplibre`, `maplibre_android`, `maplibre_ios`, `maplibre_platform_interface` ve verzi 0.3.6, publikované 2026-08-25. Srovnání archivů s lokální kopií odhalilo níže uvedené aktivní rozdíly. |
| MapLibre skutečně používáme přes lokální overrides | `pubspec.yaml: dependency_overrides`; `lib/components/map/maplibre/maplibre_map_surface.dart` předává `active`. |
| `.codex-artifacts` není aplikační závislost v prověřených zdrojích | Vyhledání doslovné cesty v automation, CI, aplikaci, core, SQL, webovém klientu, workerech a dokumentaci našlo pouze historickou zmínku v `docs/archive/plans/ticket-product-type-cutover-implementation-2026-10-13.md`. `.gitignore` ignoruje `.codex-local`, ale zatím ne `.codex-artifacts`. Dynamické globy je nutné ověřit při úklidu. |
| SQL bootstrap má konkrétní vlastníky a starou hranici | `automation/bootstrap_local_db.sh` načítá baseline 20260805230000, označuje starší migrace za pokryté a spouští novější. Stejnou hranici používá rehearsal bootstrap. |
| Historické SQL potřebují i další spouštěče | `automation/run_occasion_setup_local.py`, `automation/email-delivery/rehearse-local.sh`, `automation/canonical-source-contract.json`, generátor inventáře operací a migration-history tooling. Email rehearsal explicitně reprodukuje starší cutover; nesmí přijít o své vstupy. |
| Historické migrace jsou neměnné release záznamy | `automation/assemble-operations-foundation-migration.py` generuje výhradně konkrétní forward migraci a odmítá historické cíle; jiné assemblery mají vlastní manifesty. |
| Už stará baseline pokrývá část SQL historie | V průzkumu 215 aktivních SQL migrací; 66 souborů / 23 139 řádků má verzi nejvýše 20260805230000. Kandidát na odstranění z aktivního stromu, nikoli automatický souhlas se ztrátou upgrade vstupů. |
| Velké JSON inventáře nejsou pouhé odpadní logy | `automation/client_test_inventory.json` používá test runner pro zachování sémantických testů; `docs/architecture/operations/inventory.json` generuje `automation/generate_operation_inventory.mjs`. Jejich prosté smazání není součást úklidu. |
| Lokální backups již nejsou verzované | `/backups/` je v `.gitignore`, při průzkumu asi 40 MB. Mazání neřeší nárůst Git zdrojů. |

Primární externí zdroje: [publikované verze](https://pub.dev/packages/maplibre/versions), [changelog](https://pub.dev/packages/maplibre/changelog), API `https://pub.dev/api/packages/{maplibre,maplibre_android,maplibre_ios,maplibre_platform_interface}`. Dočasné diffy nejsou trvalým důkazem; rozhodnutí stojí na publikovaných verzích, uvedených lokálních souborech a opakovatelném srovnání archivů.

## Rozhodnutí a cílové invarianty

1. MapLibre teď ponechat. Dokumenty `packages/maplibre_*/FESTAPP_PATCH.md` mají stále platné důvody. Úsporu 175 tisíc řádků proto nezahrnovat do slíbeného výsledku.
2. Provozní pracovní výstupy patří mimo verzovaný strom, do ignorovaného `.codex-local`. Potřebné doklady uchovat v řízeném archivu; ponechaná dokumentace musí mít platné odkazy.
3. Vlastníkem aktuálních SQL funkcí zůstává `database/functions`. Nová baseline je reprodukovatelný instalační výstup, forward migrace zůstávají neměnnými release vstupy.
4. Baseline pokrývá přesnou verzní hranici K a manifest vstupů. K neurčuje jen nejvyšší název souboru; musí být doložená sada úspěšně aplikovaných migrací bez mezer a závislosti na neověřeném budoucím releasu.
5. Čistá instalace a upgrade existující databáze jsou dva explicitní kontrakty. Nový snapshot se nikdy neaplikuje přes existující produkční data a kvůli úklidu se nepřepisuje produkční migration ledger.
6. Odstraněné jednorázové datové kroky se neztratí: splněné kroky mají doloženou historii, dosud potřebné upgrade kroky zůstávají dostupné, nezbytná referenční data čisté instalace mají samostatný seed.
7. Žádné plošné `git clean`, reset/stash cizí práce, automatické mazání cache ani přesouvání celého obsahu plánu do dalšího repo archivu.

## MapLibre: podmínky budoucího odstranění

Přímé srovnání nejnovějších publikovaných archivů zjistilo aktivní odchylky v Android `map_state.dart`, `style_controller.dart`, `android/build.gradle.kts`; iOS `map_state.dart`, `style_controller.dart`, generovaném FFI, `MapLibreIos.h`, `Helpers.swift`; platform interface `style_controller.dart` a `widget/map.dart`.

Před odstraněním všech tří override závislostí musí jedna stabilní sada upstream balíčků prokazatelně pokrýt:

- `addImageWithPixelRatio`, fyzické/logické rozměry ikon a ostré Retina zobrazení;
- `MapLibreMap.active`, skutečné pozastavení skryté mapy a senzorů, návrat na teplou mapu;
- neblokující Android style-loaded callback a spolehlivé načtení stylu;
- reprodukovatelnou Android build konfiguraci včetně současného explicitního native pinu 13.5.1 nebo zdůvodněné stabilní náhrady;
- dostupnost `MapLibrePlugin` při čistém iOS Release buildu;
- dosavadní iOS navigační přesnost a distance filter uživatelské polohy.

Náhradou není nezdokumentovaný fork ani stažení a přepis závislostí během každého buildu. Pro tento úklid není důvod zavádět nový dependency distribuční systém. Případný budoucí upgrade musí odstranit balíčky, overrides i patch dokumentaci společně a zachovat regresní kontrakty.

## Postup implementace

### Vlna 1: přesný soupis a pracovní výstupy

**Změny:** na začátku zaznamenat HEAD, seznam uživatelských změn a hashe pouze dotčených souborů. Nepřepínat větev. Znovu vyčíslit počet souborů a řádků, protože vedlejší práce může pokračovat. Pro `.codex-artifacts` a `docs/plans` vytvořit krátký explicitní soupis: smazat reprodukovatelný výstup, přesunout potřebný doklad mimo repo, nebo ponechat aktivní kontrakt.

**Mazání:** odstranit pouze jmenované dokončené logy, screenshots, náhledy a experimentální patche bez aktivního spotřebitele. SQL evidence, migrační soubory a doklady nezavřených release gates nejprve zachovat s kontrolním součtem mimo repo. Přesunout potřebné lokální artefakty do `.codex-local`, odstranit původní adresář po ověření. Přidat `/.codex-artifacts/` do `.gitignore`, aby se scratch výstupy znovu nenabízely ke commitu. V historické zmínce upravit umístění evidence nebo výslovně zaznamenat retenční stav.

**Ověření:** scoped hledání přesných cest i obecných globů v build/deploy skriptech a CI; ověřit konzumenty každé smazané skupiny a opravit příchozí odkazy. `git check-ignore` ověří pravidlo. Samotné odstranění výstupů nevyžaduje Flutter build.

**Konec:** každý smazaný soubor je v soupisu s důvodem; žádný aktivní build/test/runtime vstup nechybí. Potřebná evidence má dosažitelný retenční cíl.

### Vlna 2: nový databázový instalační základ a parity gate

**Změny:** před úpravou určit hranici K z lokálně ověřitelného uceleného release stavu. Zmrazit manifest původního baseline + SQL do K (verze, SHA-256, pořadí, nezbytné seeds, assemblery a jejich manifesty). Pracovní strom obsahuje nesledované SQL, takže samotné HEAD nestačí jako archiv. Ověřit obnovitelnost těchto vstupů; nic necommitovat bez samostatného pokynu.

Na izolované lokální DB A přehrát původní podporovanou instalační cestu do K. Z jejího aplikačního schématu vytvořit nový schema-only baseline; nevycházet z živých produkčních tenantů ani testovacích řádků. Vyloučit privátní data, secrets, providerem spravované objekty a prostředí specifické cron konfigurace. Neztratit autentizační hooky, extension závislosti ani potřebné grants na spravovaných schématech: jejich explicitní bootstrap kontrakt zachovat mimo dump. Potřebná referenční data oddělit od testovacích a tenantových seedů.

Na prázdné DB B přehrát nový baseline + stejné nezbytné seeds. Porovnat katalogy: tabulky/sloupce, constraints/indexy, sequence vlastnosti a ownership, views, funkční signatury/těla, security/search_path, owner/ACL/default ACL, RLS policies, technické triggery a extensions. Každý ignorovaný environment rozdíl musí mít uzavřený důvod. Stávající `schema-fingerprint.mjs` použít jen jako referenci pro rozsah; samotný nemusí pokrývat všechny požadované objekty ani lokální použití.

**Kompatibilita:** současný test bootstrap cílí na PG15, self-hosted rehearsal na PG17. Paritu dokazovat vždy mezi stejnými major verzemi; podpora obou prostředí musí zůstat ověřená, dokud ji samostatně nezměníme. Cron jobs v testovacím prostředí nesmějí zahájit skutečné externí operace.

**Ověření:** nový deterministický baseline parity check plus cílené SQL regresní sady pro oprávnění, kanonické mutation parity a dotčené instalační kontrakty. Přesné existující SQL testy vybrat z `database/tests` podle změněných objektů. Žádné testy jen pro počty řádků.

**Konec:** stejné výsledné aplikační schéma a potřebná referenční data, žádné nevysvětlené rozdíly. Do té doby se staré SQL nemaže.

### Vlna 3: přepojení všech SQL spotřebitelů a vyřazení staré instalační cesty

**Změny:** zavést jeden baseline manifest s cestou, K, původním zdrojovým manifestem a hashi. Upravit `automation/bootstrap_local_db.sh`, `automation/hetzner-supabase/rehearsal/build-canonical-schema.sh`, `automation/run_occasion_setup_local.py`, `automation/canonical-source-contract.json`, `automation/generate_canonical_source_contract.py`, `automation/generate_operation_inventory.mjs` a `automation/tests/migration_layout.test.sh`. Zrušit redundantní baseline konstanty; bootstrap přímo instaluje nový základ a spouští pouze migrace za K.

Pro migration ledger nové DB definovat přesný kompatibilní zápis pokryté historie z manifestu. Otestovat, že `supabase migration up` znovu nespustí pokryté datové operace. Ledger existující DB neměnit. Migration-history inventory má rozlišit aktivní forward SQL, baseline pokrytí a historický upgrade artefakt, nehlásit vše pokryté automaticky jako chybějící migraci.

Email rehearsal reprodukující historický cutover (`automation/email-delivery/rehearse-local.sh`) přepojit na obnovitelný, checksumem ověřený historický kit s kompletními SQL a fixture vstupy. Zachovat tento test, pokud stále chrání podporovaný upgrade; nepřepsat jej testem pouhé čisté instalace. Odstranit jej až s doloženým koncem tohoto podporovaného upgrade kontraktu.

**Mazání:** z aktivního stromu odstranit baseline před K, překryté migrace a jejich výhradně historické assemblery/manifesty až po splnění parity a obnovitelnosti. Git historie je dostatečný archiv jen pro skutečně zachované objekty s ověřeným recovery postupem. Nesledované nebo dosud nepublikované migrace do K zachovat v ověřeném lokálním kitu; do případné publikace neztratit jedinou kopii. Historický kit nepřidávat jako velký dump jinam do stejného repozitáře.

**Upgrade hranice:** před smazáním určit podporované výchozí DB verze. Pro každou zachovat proveditelnou cestu z původního ledgeru do K a ověřit ji na reprezentativních lokálních datech: zachování ID, platebních referencí, email receiptů a retry/adoption chování. Neověřená produkční aplikace migrace znamená ponechání dotčených upgrade vstupů, nikoli domněnku, že jsou hotové. Pokud není dostupný důkaz o provozním stavu, dokončit lokální baseline a tuto část kontrakce explicitně odložit.

**Ověření:** `bash automation/tests/migration_layout.test.sh`; cílené contract testy bootstrapu a rehearsal; `python3 automation/generate_canonical_source_contract.py --check`; čistá lokální instalace, no-op následný migration up a podporovaný upgrade. Historické generátory přeřadit před spuštěním jejich starých checků, aby CI neobnovovala smazané soubory.

**Konec:** aktivní instalační cesta má jediný baseline, pouze forward migrace za K, všechny konzumenty přepojené a doloženou podporovanou upgrade cestu. Žádný odkaz na odstraněný soubor nezůstává v aktivním tooling/CI.

### Vlna 4: dokončená dokumentace a souhrn úspory

**Změny:** projít pouze největší dokončené skupiny v `docs/plans`: Google sign-in reference, scanner evidence/gallery, SEO previews a experimentální patch HTML editoru. Stav dokončení ověřit z vlastní dokumentace a spotřebitelů; jméno souboru nestačí. Užitečné aktuální rozhodnutí sloučit do existujícího vlastníka dokumentace. Smazat nepotřebné náhledy a duplikované výstupy; neuzavřené gates a jejich důkazy ponechat.

**Ponechat:** testové fixture PDF/QR, které testy skutečně čtou; fonty; test semantic inventory a operations inventory. Změna formátování JSON pouze kvůli optickému snížení řádků není přínosem této vlny.

**Ověření a konec:** jeden cílený průchod odkazů v dotčených dokumentech, `git diff --check` pouze nad změnami této práce, před/po metriky stejnou metodou a uzavřený mazací soupis. Po přesunech do Git archivu nevykazovat falešnou úsporu. Celkové výsledky nezaměňovat s objemem `.git` databáze; její historii nepřepisovat.

## Mazací soupis a záměrné ponechání

| Skupina | Výsledek | Důkaz dokončení |
|---|---|---|
| `.codex-artifacts` pracovní výstupy | Odstranit z aktivního stromu; potřebnou evidenci uchovat mimo verzované zdroje | Bez aktivních konzumentů, platné odkazy, ignorované budoucí výstupy |
| Dokončené plans/prototypes/screenshots | Explicitní soupis odstranění podle vlny 4 | Bez ztráty aktivních fixture a nezavřených gates |
| Staré baseline a pokryté migrace | Odstranit až po vlnách 2-3 | Schema/seed parity, ledger no-op, upgrade a obnovitelný historický kit |
| Historické assemblery a jejich manifesty | Odstranit nebo převést k historickému kitu podle jejich skutečných konzumentů | CI je nevyžaduje ani znovu nevyrábí odstraněné SQL |
| Tři lokální MapLibre balíčky | Ponechat s podmínkami odstranění | Nejnovější publikované balíčky stále nesplňují kontrakt |
| Fonty a potřebné JSON inventáře | Ponechat | Existující runtime/test konzumenti dál fungují |
| `/backups`, tool caches, build outputs | Ponechat mimo tento úklid | Nejsou zdrojem Git nárůstu |

## Autorizace, rollback a zbývající nejistoty

Tento dokument pouze plánuje. Implementace, commit/push, produkční SQL a deployment se tímto krokem neprovádějí. Produkční stav nebyl dotazován; schválení SQL konsolidace zde neznamená schválení aplikace baseline do živé DB. Případné budoucí produkční operace mají samostatný rozsah a existující release safeguards.

Před kontrakcí musí jít původní instalační řetězec obnovit z ověřeného zdroje. Při selhání lokální parity zachovat starou cestu, opravit nový baseline a neopakovat žádné produkční adoption/data operace. Rollback zdrojů nesmí přepsat souběžné uživatelské změny.

Odhad přínosu zůstává podmíněný: pracovní artefakty v prvním měření asi 16 tisíc řádků, celý `docs/plans` asi 44 tisíc, ale jen část je odstranitelná. SQL má významný potenciál podle výsledné hranice K; přesnou čistou úsporu spočítat po vytvoření baseline. Nový baseline sám část řádků vrátí. Celých 175 tisíc generovaných MapLibre řádků nyní zůstává.

## Hotovo znamená

- Každé odstranění má důvod, ověřené konzumenty a případně retenční cíl.
- Aplikační chování map a aktivní testové kontrakty zůstaly zachované.
- SQL čistá instalace i deklarované upgrade cesty mají doloženou paritu a jednoho vlastníka baseline.
- Historické vstupy lze obnovit; necommitované SQL ani jediná evidence se neztratily.
- Jsou uvedené skutečné před/po metriky, provedené cílené kontroly a případná přesně vymezená odložená SQL kontrakce.

## Realizační výsledek 2026-10-21

Vlny 1-4 jsou dokončené pro konzervativní hranici K `20260906140000`.
Po samostatně autorizovaném read-only ověření živého ledgeru je do K všech
111 zdejších migrací zaznamenaných; první nezaznamenaná verze je
`20260910070000`. Pozdější verze se nekontrahují a zůstávají dostupné.

Nový jediný baseline manifest, referenční seed a pokrytý ledger mají ověřenou
PG15 i PG17 paritu, čistou instalaci, následný migration no-op a upgrade od
původní baseline s reprezentativními daty. Historický emailový upgrade běží
z checksumem ověřeného Git kitu se správnou dobovou fixture. Supabase CLI
vyžaduje soubory pokrytých verzí, proto je jednotný upgrade příkaz rekonstruuje
do dočasného workspace; v aktivním stromu zůstávají jen forward migrace.

Odstraněno 198 přesně vyjmenovaných souborů, včetně původní baseline,
111 migrací a historického generátoru. Potřebné pracovní důkazy zachovává
lokální retenční kit. MapLibre, fonty, aktivní JSON a neuzavřené Google/SEO
důkazy zůstávají. Původní provozně zaznamenaná migrace `20261020120000` zůstala
bajtově neměnná; nalezený source-contract problém opravuje nová forward migrace.

Výsledkový záznam obsahuje úplný mazací soupis, postup obnovy, cílené testy
a skutečné metriky včetně přidaných souborů. Commit/push, produkční změny
ani deployment neproběhly. Další kontrakce za K vyžaduje nový důkaz aplikace
a zachování příslušných upgrade kontraktů; není součástí uzavřené hranice K.
