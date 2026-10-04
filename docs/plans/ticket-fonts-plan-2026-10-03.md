# Fonty vstupenek: společný výběr, věrný náhled a trvalá cache pro PDF

## Aktualizace pro rollout na současný main (2026-10-03)

Níže zachovaný průzkum vycházel ze starého working tree b7b62b899. Při rolloutu
má přednost tato aktualizace podle origin/main e0b14ccade70:

- Main již sjednotil generování přes ticketGeneration/importTicketTemplate/drawLayoutTicket;
  generateNamedTicket.ts byl odstraněn. Neobnovovat historické generátory.
- Schema 1 již obsahuje uzavřený enum font (futura, robotoSlab, roboto, russoOne).
  Při explicitním Apply povýšit všechny existující sloty na schema 2 a převést enum
  na obsahově připnuté fontId. Čtení nic nemigruje; zachovat geometrii a vzhled.
- Zachovat přesné čtyři aktuální bundled soubory z ticket-assets/SOURCES.md:
  Futura, statický Roboto Slab 400, rozbalený Roboto a rozbalený Russo One.
  Výjimka pro historický variabilní font se týká pouze zachovaných bundled bajtů;
  současný Slab baseline je již statický. Nové Google fonty mají přísnější validaci.
- Podporovat obě známé historické CDN URL Roboto a Russo One. Produkční inventura
  organizace 3 potvrdila 14 uložených Roboto Slab, 1 Russo One a jednu legacy Russo URL.
- Zachovat současné bold/italic/underline, flow, QR kontrast, paletu barev,
  obnovu chybějícího pozadí, plnou kvalitu uploadu, onboarding a public product RPC.
- Protokol 1 zachová čtyři původní fonty pro dosud nasazené klienty; protokol 2
  přenáší ID a ověřené bajty/metriky. Oba protokoly používají jeden resolver.
- Publikovat nejdříve chráněný main přes povinný PR a až potom prod/festapptickets.
  Uživatelské zadání autorizovalo tento rollout, nikoli jiné tenanty.


Datum: 2026-10-03
Stav: lokálně implementováno; nic nenasazeno
Výchozí bod: main, b7b62b899 + aktuální rozpracovaný working tree
Ověřování implementace: standard (sdílené generování, síťová bezpečnost, SQL kontrakt)

## Výsledek a hranice

Editor nabídne oblíbené fonty stejně jako nastavení designu formuláře a vyhledání dalších podle názvu. Zachová Futura PT a zpřístupní Google Fonts dostupné v připnutém katalogu aplikace, včetně Roboto Slab, Roboto a Russo One. Neznamená to automaticky každý nově publikovaný Google Font: katalog se aktualizuje vědomě s verzí závislosti. Nepodporovaný nebo pro PDF nečitelný font se nesmí tvářit jako úspěšně vybraný.

Náhled, PDF náhled, stažení i e-mail použijí pro konkrétní uložený font stejné bajty. PDF nebude při každé vstupence stahovat font od poskytovatele. Přes restart runtime jej uchová trvalé úložiště; zahřátý runtime použije paměť. Změna fontu nesmí tiše měnit starší uložené vstupenky.

V rozsahu: sdílený Flutter výběr, katalog, registr fontů a cache, kontrakt layoutu, všechny existující generátory a cílené testy. Jeden výchozí font šablony a volitelná výjimka pro textový prvek. QR a logo font nemají. Pro tuto iteraci jeden skutečný normální řez rodiny, přednostně 400; bez nového UI pro tučnost/kurzívu, uploadu vlastních fontů, kompletního shaping enginu nebo refaktoru veřejného webového formuláře.

Pouze lokální implementace. Nasazení, produkční migrace, publikace a rollout na tenanty vyžadují samostatné zadání. Nezasahovat do ostatních rozpracovaných změn. Existující soubory editoru jsou zčásti untracked, nejde o čistý checkout a nelze je obnovit z HEAD jako „referenci“.

## Ověřený současný stav

| Fakt a místo | Důsledek |
|---|---|
| `lib/components/forms/views/form_design_settings.dart`: `_popularFonts` má 12 rodin; `_validateAndSetFont` používá `GoogleFonts.getFont`; vlastní jméno, reset a odkaz na Google Fonts | Sdílet tuto logiku, nikoli udržovat druhý ruční seznam. Samotné `getFont` nedokazuje dokončené stažení ani schopnost vložení do PDF. |
| `ticket_layout_service.dart: resolve` dostává base64 font a metriky; registruje vše jako `TicketLayoutFont` | Jedno globální jméno by při více fontech způsobovalo kolize. |
| `ticket_layout_canvas.dart` + `ticket_text.dart`: jednotlivé znaky a explicitní advances | Náhled není běžný odstavec GoogleFonts. Musí používat serverové bajty i metriky vybraného fontu. |
| `_shared/ticketGeneration.ts: fontBytes/loadLayoutResources`: vždy lokální `ticket-assets/font.ttf`, metriky se počítají znovu | Nový editor ve zkoumaném stromu nemá volitelnou rodinu. README identifikuje soubor jako Futura PT Book. |
| `_shared/generateTicket.ts: fetchTicketResources`: GitHub URL Roboto Slab; `generateNamedTicket.ts: fetchNamedTicketResources`: `occasion.data.font` nebo CDN Roboto WOFF | Dvě historické cesty načítají font po síti. Nestačí opravit pouze custom layout. |
| `prepareTicketRenderer` obsluhuje `download-ticket` a `send-tickets`; pro e-mail připravuje resources jednou před dávkou | Zachovat existující sdílení v dávce. Přidat cache mezi žádostmi, nevytvářet druhý renderer. |
| `preview-ticket-layout/handler.ts`: autorizace před resources; resources se dnes načtou před parsováním draft layoutu | Změnit pořadí, jinak by změna fontu v draftu načítala uložený font. |
| Dart/TS/SQL používají `schemaVersion: 1`; SQL `merge_ticket_layout_features` kontroluje expected/next a chrání nepodporované schema | Pouhá nová nepovinná pole ve v1 by starší klient mohl zahodit. Nutná verzovaná ochrana. |
| Nainstalováno `google_fonts` 8.2.1 dle `.dart_tool/package_config.json`; `pubspec.yaml` deklaruje ^8.0.1 | Verzi generátoru odvodit z lockfile a package_config, ne z absolutní lokální cesty. |
| Balíček obsahuje `GoogleFontsFile(expectedFileHash, expectedLength)` a URL `https://fonts.gstatic.com/s/a/<hash>.ttf` v `lib/src/google_fonts_descriptor.dart`; `google_fonts_parts` obsahují varianty | Katalog lze reprodukovat z již použitého balíčku bez nového API klíče a CSS scraperu. Interní formát je build-time vstup, ne runtime import. |
| `docs/operations/supabase-self-hosted/storage-authority.md`: canonical self-hosted Storage existuje vedle samostatného R2 image systému | Použít vlastní privátní Storage bucket; nerozšiřovat image-worker na obecný font proxy. |

Screenshotový seznam čtyř fontů se ve zkoumaných zdrojích editoru nenašel. Plán vychází z aktuálního produkčního toku v repozitáři, ne z předpokladu, že screenshot odpovídá tomuto working tree. Před editací stačí zkontrolovat změny přes `git diff --name-only` a cíleně relevantní soubory; nový architektonický průzkum není potřeba.

## Rozhodnutí: zdroj pravdy a kontrakt

### 1. Katalog, bez nové externí služby

Nový generátor `automation/generate_ticket_font_catalog.mjs` přečte package_config a připnutý balíček. Mapuje veřejný display name rodiny na příslušnou metodu a její varianty, nikoli pouze na interní `fontFamily` bez mezer. Bere skutečný normální 400 řez, pokud není, nejbližší normální váhu s deterministickým tie-breakem směrem k nižší váze. Skutečnou váhu eviduje. Rodinu bez normálního řezu označí jako nepodporovanou pro ticket.

Výstup: kontrolovaný `supabase/functions/_shared/ticket-assets/font-catalog.json`, Flutter metadata asset a SQL seed registru, vše deterministicky generované z jednoho vstupu. Žádné ruční tři seznamy. Pole: stabilní `id`, display family, váha/style, SHA-256, byteLength, source kind, package version/provenance; URL se konstruuje pouze pro známý hash. Google ID `gf:<sha256>`; výchozí Futura `builtin:futura-pt-book:<sha256>`. Identita je konkrétní soubor, nikoli rodina ani proměnlivá URL.

`--check` ověřuje shodu generovaných výstupů a zamčené verze, při neznámém formátu zdroje selže. Výstup nemusí stahovat celý katalog fontových souborů. Dostupnost a PDF kompatibilita vybraného souboru se ověří při prvním resolve. Uchovat provenance a potřebné licenční informace, Futura zůstává ve stávajícím privátním/bundled distribučním rozsahu.

Sdílený Dart widget `lib/components/fonts/font_family_picker.dart`: oblíbené rodiny, vyhledání/jméno, reset, vybraný font a stav načítání/chyby. Seznam 12 popular z formuláře přesunout do sdíleného ownera. Formulář dál ukládá `fontFamily` string/null a používá svůj dosavadní GoogleFonts rendering. Ticket adaptér vybírá ID a čeká na ověřený serverový resolve. Futura a dosavadní ticket rodiny jsou navíc dostupné jen v ticket kontextu. Nevynucovat Futura jako nový formát formulářů.

Nevytvářet náhled tisíců rodin přes `GoogleFonts.getFont` při otevření seznamu. Vyhledávání je lokální a omezené/virtualizované; skutečný font se načítá až při výběru. V ticketu je vidět ukázka v načteném vybraném fontu.

### 2. Uložený layout a kompatibilita

Schema 2 přidá `templates.<type>.fontId` jako výchozí font a `elements[].style.fontId` jako nepovinnou výjimku pro text. Žádné klientské URL ani raw bytes. Font se počítá jako element override -> template default; v1 bez voleb používá přesný historický Futura soubor.

Čtenáři podporují v1 i v2. Nový editor při explicitním Apply vytvoří v2 se zachováním obou template slotů a všech geometrických hodnot. Žádná hromadná migrace uložených layoutů při čtení. V1 obsahující nová fontová pole odmítnout; jinak by jiný reader mohl vykreslit jiný font. Nepodporované budoucí schema zachovat bez editace. SQL nedovolí downgrade existující v2 na v1; explicitní odstranění layoutu přes současný expected/next kontrakt zůstává možné.

Registr `public.ticket_font_assets` je append-only seznam povolených identit a metadat, naplněný generovaným seedem. Zápisy pouze release/service role; běžný authenticated ani anon jej nemění. SQL validátor kontroluje existenci ID; nepřebírá URL od klienta. Seed při změně katalogu nedělá delete starých ID. Starší uložené ID musí stále projít validací a být dohledatelné z registru i po aktualizaci katalogu. Změna validátoru z IMMUTABLE na STABLE je nutná, pokud čte registr; upravit i volající `merge_ticket_layout_features`, který dnes deklaruje IMMUTABLE.

### 3. Jeden font resolver a dvě úrovně cache

Nový `_shared/ticketFonts.ts` vlastní `resolveTicketFont(id)` -> immutable `{id, bytes, metrics, family, weight}`. Současný `fontMetrics` přesunout sem. Všechny fontové cesty jej používají; resources připraví pouze distinct IDs skutečně vykreslovaných prvků. Maximálně 12 IDs na layout a nejvýše 4 současná načítání v požadavku.

- L1: module-scope LRU, počátečně max. 32 fontů a 24 MiB odhadované celkové velikosti bajtů + metrik. Držet pouze neměnné bajty/metriky, nikoli `PDFFont` nebo `PDFDocument`. Embedding je vždy document-local. In-flight map sdílí promise pro stejné ID, chybu ve finally odstraní; neúspěch neotráví cache. Krátký bounded backoff 5 s brání opakovaným výpadkovým fetchům, po něm lze zkusit znovu. Fontů s obří characterSet se limit týká i při výpočtu metrik.
- L2: privátní canonical Storage bucket `ticket-fonts`, objekt `sha256/<hash>.ttf` (legacy WOFF s vlastní skutečnou příponou). Kontrolované serverové zápisy, žádná public policy ani klientský write. Naplní se jen použité fonty. Zapsání a ověření musí dokončit resolve před úspěšným výběrem, ne fire-and-forget. Žádné automatické TTL nebo mazání podle posledního přístupu: staré layouty musí fungovat.
- Tok: L1 -> bundled asset, je-li dostupný -> L2 -> pevná katalogová HTTPS adresa -> validace -> create-if-absent L2 -> L1. Bundled fallback Futura nepotřebuje síť ani dostupné Storage. Běžný cold start stáhne existující soubor pouze z vlastního úložiště; warm hit nestahuje nic.
- Dva současné isolates mohou při úplně prvním missu stáhnout tentýž soubor dvakrát. Atomický create-if-absent a digest zajistí jeden správný objekt; při konfliktu načíst a ověřit vítěze. Neslibovat globální exactly-once download a nepřidávat distribuované zámky kvůli tomuto neškodnému závodu.
- Provider timeout 8 s, hard byte cap 8 MiB i pro chunked body, kontrola délky a SHA-256, rozpoznání TTF/OTF/legacy WOFF a skutečné fontkit parse + PDF embedding probe při prvním importu. Odmítnout HTML, prázdné/corrupt soubory a nepodporované color/variable formáty. Nesmí projít pouze podle Content-Type. Žádné CSS nebo text-specific subsets, chyběla by diakritika.
- Pro nové fonty pouze přesně konstruovaná `fonts.gstatic.com/s/a/<hash>.ttf`, redirect nepovolit. Žádné klientské URL, volný proxy endpoint ani DNS/SSRF bypass. Storage 404 znamená miss; 401/403/5xx znamená provozní chybu, ne spuštění fallback downloadu u každé vstupenky. Corrupt objekt je viditelná chyba a provozní oprava, ne tiché přepsání identity.
- Neznámý font, chybějící asset nebo upstream výpadek nevede k tichému Roboto/Futura fallbacku. Editor drží předchozí draft; generování skončí s rozlišitelným kódem chyby. Stávající výchozí volby jsou explicitní kontrakt, nikoli rescue fallback.

Paměť je optimalizace, nikoli trvalé úložiště. Supabase popisuje [dočasné úložiště Edge Functions](https://supabase.com/docs/guides/functions/ephemeral-storage); skutečná životnost isolates v tomto self-hosted runtime není během plánování měřena. Žádné sliby odvozené z parametrů hosted platformy.

Alternativní [Google Fonts Developer API](https://developers.google.com/fonts/docs/developer_api?hl=en) poskytuje metadata a varianty, ale potřebuje API klíč. Zde ho nezavádět, protože připnutý Flutter balíček již potřebná metadata obsahuje.

### 4. Historické generátory

Zachovat výstupní geometrii a konkrétní historické fontové bajty. Výchozí Roboto Slab wide a Roboto WOFF named jednorázově připnout do katalogu/bundlu s hashem; nenahradit je automaticky současným Google regular fontem, mohlo by to změnit zalamování. Nestabilní GitHub main nesmí zůstat runtime zdrojem.

`occasion.data.font` je existující URL kontrakt pouze pro legacy named. Před přepojením dohledat jeho lokální writery a fixtures. Nezavádět další zadávání URL. Čtecí kompatibilitu omezit na explicitní registry aliasů stará URL -> pinned ID; známé existující zdroje připravit při rollout inventuře na canonical backendu. Neznámá URL musí skončit pojmenovanou chybou a být rollout blocker pro postiženou událost, ne přístupem na libovolnou síťovou adresu. Lokální implementace nevyžaduje živou inventuru ani oprávnění k migraci zákaznických dat.

Zachovat historické větve rendereru pro layout absent; odstranit z nich pouze vlastní stahování fontů. Rozhodnutí o custom/legacy rendering nadále vlastní `prepareTicketRenderer`.

### 5. Preview a životní cyklus editoru

`preview-ticket-layout` po authorize nejdříve validuje a vybere draft/stored template, potom načítá jeho fonty. Stávající resolve odpověď rozšířit pro schema 2 o font resources map podle ID; pro v1 zachovat starý single-font tvar pro staršího klienta. Volbu schema 2/podporovaného font protokolu posílá nový klient explicitně; absence znamená starý protokol. V2 layout starému klientovi vrátí srozumitelnou unsupported chybu, nikdy jej nezploští na Futura.

Přidat autorizovaný režim `font` v existujícím endpointu s occasionId a fontId pro načtení jedné volby bez obrázků, QR, SQL produktů a PDF. Stejné can_edit_ticket_layout ověření před cache i fetch. Metadatový seznam je lokální asset, endpoint není veřejný katalogový downloader.

Dart registruje font jen jednou jako `TicketFont_<sha256>`, cache bytes/metrik a Future je sdílená napříč editory. Resource drží reference podle ID; nikdy globální „aktuální font“. Flutter FontLoader nemá zde ověřený mechanismus unload, proto nestahovat všechny položky při scrollování a neslibovat přesný bound nativní fontové paměti.

Při výběru zachovat starý font do dokončení load; commit draft+metriky provést atomicky jako jeden undo krok. Generation token per selection/editor zahazuje odpověď staršího výběru, dispose nebo Cancel. Undo/redo obnovuje identitu fontu; Apply/PDF v pending stavu blokovat. Změna velikosti, posun a zoom stále nevolají server ani PDF. Zachovat ostatní template slot, zámky prvků a expected/next konflikt.

Canvas, galerie, thumbnail, fitText a PDF čerpají metriky přes effective font ID každého prvku. Zachovat současné explicitní glyph advances; font-size, zalamování, výška a baseline musí vycházet z příslušného fontu. Diakritiku otestovat textem „Příliš žluťoučký kůň, Ľščťžýáíé, 0123456789 Kč €“. Chybějící glyph dál signalizovat; řetězce s komplexním shapingem nejsou touto změnou nově garantované.

## Implementační vlny

### 1. Katalog a bezpečný kontrakt

- Přidat generátor, katalog/Flutter asset, sdílená metadata popular a SQL registr. Použít package_config dynamicky; úzce otestovat display-name mapování a chybějící 400, nikoli snapshotovat tisíce řádků.
- Upravit `models/ticket_layout.dart`, `_shared/ticketLayout.ts` a canonical `database/functions/others/ticket_layout.sql` pro v1/v2, IDs, downgrade guard a zachování slotů. Pro SQL změny nová migration s unikátním timestampem, včetně registru a seed; neměnit již vydané migrations.
- Změnit hardcoded schemaVersion v `ticket_settings.dart`, `ticket_layout_editor.dart`, preset wrappers a validačních voláních v rendererech. Fixture v1 zachovat a přidat v2 valid/invalid případy.
- Výstup: obě verze round-trip, neznámé IDs odmítnuty SQL/Edge, starý klient nesmaže nové fonty. Ověření připravit do společné závěrečné sady, průběžně jen generátor `--check` při ustálení jeho výstupu.

### 2. Resolver a trvalá cache

- Přidat `ticketFonts.ts` a úzký Storage adapter; dependencies injectovat pro testy, bez importování produkčních secrets do čistého resolveru. Canonical SQL bucket konfigurace a migration nastaví privátní `ticket-fonts`; otestovat, že jiné broad policies nedávají clientům přístup.
- Zavést limity, integrity check, LRU, in-flight dedup a rozlišení Storage miss/error. Přesunout výpočet metrik. Futura a pinned legacy defaults dodat do produkčního bundlu.
- Prověřit `automation/hetzner-supabase/runtime/build-production-function-bundle.sh` a jeho manifest/proof: katalog i binární assety se musí dostat do `_shared`; nic neřešit ručním kopírováním na server. Dle skutečného bundleru upravit asset include, ne naslepo hosted `static_files`.
- Výstup: opakované a dávkové použití nepotřebuje upstream; restart používá L2. Cache testy předdefinovat podle matice níže.

### 3. Všechny PDF a preview cesty

- Přepojit `ticketGeneration.ts`, `generateTicket.ts`, `generateNamedTicket.ts` a preview handler/index na canonical resolver. Odebrat přímé fetch fontů. Produkty/background/logo ponechat stávajícím ownerům.
- Custom Resources map podle ID; embed nejvýše jednou pro každý distinct použitý font v každém dokumentu. `send-tickets` zachová jedno prepare na dávku, `download-ticket` stejné resources. Pro preview změnit pořadí a přidat režim font s bezpečnou chybovou odpovědí (bez stacku/secrets).
- Kompatibilitu named URL řešit explicitní alias mapou, místní fixtures defaultů připnout; pro neznámé live URL zaznamenat konkrétní inventurní rollout krok.
- Výstup: draft vybraný font se shoduje s PDF, auth proběhne i při cache hitu, historické fixture PDF zůstávají vizuálně/obsahově stejné.

### 4. Společný výběr a Flutter renderer

- `forms/views/form_design_settings.dart` přepojit na společný picker při zachování string/null contractu; nepřepisovat ostatní design controls ani web klienta.
- `ticket_layout_service.dart`, controller, properties, editor, settings a canvas rozšířit o resources podle ID, default a element override, pending/error, undo/redo a stale-response ochranu. Doplnit lokalizaci přes strings ownera a cs/en.
- Aktualizovat lokální `test/components/ticket_layout/editor_preview.dart`, galerie a resolve fixtures na nové resources; starý resolve protokol nechat jen v označeném external boundary pro staré klienty.
- Výstup: po výběru jde poznat skutečný řez, velikost i zalomení; návrat A -> B -> A používá již načtená data, změna v jednom editoru neovlivní jiný.

### 5. Jedna cílená validace a dokumentace

Po souvislé implementaci spustit níže uvedenou cílenou sadu, neopakovat úspěšné části bez změny pokrytého kódu. Standard opravuje konkrétní nalezené regrese; nespouštět automaticky nezávislé audity ani celý release pipeline.

Aktualizovat `lib/components/ticket_layout/README.md`, `docs/backend/edge_functions.md`, `supabase/functions/test-coverage.json` a bundle coverage dle změněných entrypointů. Popsat cache, katalog refresh, provozní opravu corrupt objektu a rollback minimum. Vypsat neprovedené rollout kroky.

## Ověření: přesná matice a příkazy

| Oblast | Povinný důkaz |
|---|---|
| Cache | 20 souběžných resolve stejného ID v jednom isolate = 1 upstream fetch + 1 import; 100 renderů dávky nesmí přidat font fetch. |
| Cold start | Nová instance resolveru nad stejným fake L2 = 0 upstream fetch a 1 storage read; dva IDs nezaměňují bajty/metriky. |
| Závod mezi isolates | Dva importy do stejného klíče: create conflict vrací ověřené stejné bytes; žádný partial overwrite. |
| Chyby/limity | Timeout, 404, 403/5xx Storage, HTML, špatný hash, chunked oversize, corrupt font, redirect, neznámé ID; žádná poisoned promise; retry po backoff; LRU eviction a bounded parallelism. |
| Bezpečnost | Preview bez práv nevolá ani resolver; client bucket read/write a změna registru jsou zakázané; žádné arbitrary URL. |
| Kontrakt | Stejné Dart/TS/SQL fixtures pro v1/v2; v1+font pole zakázané, v2->v1 downgrade zakázán, unknown future schema zachováno, expected/next konflikt funguje. |
| PDF | Aspoň 3 různé rodiny + mixed-font template, české/slovenské znaky, bounds a baseline parity. Skutečné embedded font resources v PDF, ne jen `%PDF` nebo screenshot menu. Font z preview draftu má stejný digest jako download/e-mail. |
| Legacy | Historické wide/named PDF fixtures, přesné default bytes, named alias, unknown alias error a layout absent routing. |
| Flutter | Popular/custom/reset formuláře, volba mimo popular, selhání fontu zachová draft; A/B race, dva editory, undo/redo/Cancel, zámek prvku, pending Apply/PDF; žádné implicitní PDF volání. |
| Balení | Runtime asset proof obsahuje katalog a všechny bundled defaulty; pinned katalog lze regenerovat bez velkého font downloadu. |

Základní příkazy po implementaci (nové testy vytvořit pod uvedenými názvy):

```sh
node automation/generate_ticket_font_catalog.mjs --check
node --test automation/tests/ticket_font_catalog.test.mjs
fvm dart analyze lib/components/fonts lib/components/ticket_layout lib/components/forms/views/form_design_settings.dart
fvm flutter test test/components/fonts/font_family_picker_test.dart test/components/ticket_layout/ticket_layout_test.dart
# Zachovat existující permission flags používané repository Deno runnerem.
deno test --allow-env --allow-net --allow-read supabase/functions/_shared/ticketFonts_test.ts supabase/functions/_shared/ticketLayout_test.ts supabase/functions/preview-ticket-layout/preview_test.ts
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/ticket_fonts_test.sql
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/ticket_layout_settings_test.sql
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/ticket_sized_pdf_pages_test.sql
```

Font testy mají malé připnuté lokální fixtures a fake fetch/storage/clock, nespoléhají na živý Google ani produkci. Pokud lokální SQL baseline neobsahuje nové migrace, použít repository izolovaný bootstrap dle CONTRIBUTING; nikdy remote DB jako náhradní test. Přidat nejbližší existující bundle test pouze pokud změněno balení. Před případným pozdějším commit/push platí zvlášť gates CONTRIBUTING, nikoli pouze tato cílená sada.

## Odstranění a záměrně ponechané hranice

| Současná věc | Cílový stav a důkaz |
|---|---|
| `_popularFonts` v konkrétním form widgetu | Jediný shared popular owner; žádná druhá ruční ticket kopie. |
| Globální `TicketLayoutFont` | Content-addressed jména; výskyt může zůstat jen ve v1 protokol fixture, ne v novém painteru. |
| `fontBytes` a opakované `fontMetrics` v orchestration | Resolver; případné testy přepsat, neponechávat alternativní produkční loader. |
| `CUSTOM_FONT_URL`, `DEFAULT_FONT_URL`, přímé font fetch v legacy generátorech | Pinned IDs a resolver; přes scoped rg doložit nepřítomnost bypassů. |
| v1 uložená data a legacy geometrie bez layoutu | Záměrně podporovaná externí kompatibilita, žádná hromadná změna vzhledu. |
| `occasion.data.font` | Jen read alias -> pinned ID; noví writeři nevznikají. Úplné odstranění pole není součást této iterace. |
| Single-font preview reply | Jen v1/starý klient boundary; v2 cesta nepoužívá placeholder první font. |

## Rollout, předpoklady a zbývající rizika

1. Před nasazením ověřit tenant activation na canonical `api.festapp.net` podle ai_context, storage dostupnost a skutečný seznam legacy named font URL. Za plánování nebyla produkce dotazována. Neznámé URL připnout pod kontrolou, nikoli automaticky fetchovat jako uživatelský input.
2. Po samostatném povolení: schema/bucket/registry seed -> backend s podporou v1+v2 a assety -> lokální/canonical smoke a prewarm popular/default fontů -> klient vybraného tenantu. Nikdy klient první. Nešířit na jiné prod/* větve.
3. Rollback klienta nevyžaduje mazání dat/cache; jakmile existuje schema 2, backend a SQL musí nadále umět schema 2. Starý klient může zobrazit unsupported, nesmí změnit layout. Cache a historické registry IDs zachovat.
4. Předpoklad: interní metadata balíčku lze deterministicky extrahovat. Ověřený formát obsahuje hash a délku, ale při upgradu může změnit strukturu; generátor musí fail-closed a agent pak upraví generátor i tento plán. Nezavádět alternativní live API za běhu.
5. Ne všechny rodiny musejí obsahovat české glyphy či být podporované fontkit. Při výběru zobrazit chybějící glyphy/unsupported font; nezkreslit náhled tichým systémovým fallbackem. Komplexní shaping zůstává omezen současným rendererem.
6. Trvalá cache obsahuje bajty veřejných fontů sdílené napříč tenanty, žádná order data; oprávnění editoru se přesto kontroluje před každým resolve. Růst je konečný vůči povolenému katalogu/verzím, bez automatického GC používaných fontů. Změřit a zaznamenat počet assetů/bytes, cache hit source a trvání; nelogovat jména držitelů ani font bytes.
7. První použití nové rodiny potřebuje síť a zdravé trvalé úložiště. Výpadek poskytovatele po naplnění L2 neblokuje její další generování. Bez L1 může každé nové isolate číst vlastní Storage; plán zaručuje odstranění opakovaných provider downloadů, nikoli nulové I/O při každém cold startu.

## Definice hotovo

- Stejná logika výběru jako formuláře, širší katalog a zřetelně ověřený výběr; žádné načítání celého fontového katalogu v binární podobě.
- Identita fontu přežije save/reopen, kopii template, undo a backend/client upgrade; stejné bajty v canvasu a všech PDF cestách.
- Resolver je jediný owner bajtů/metrik a projde cache/error/concurrency testy; historical download bypassy odstraněny.
- SQL chrání fontová ID, v2 a práva; assety jsou v runtime bundlu; cílené testy prošly nebo přesný nezávislý environment blocker zdokumentován.
- Dokumentace a krátký handoff uvádějí skutečné limity a neprovedené produkční kroky. Implementační „hotovo“ se nesmí vydávat za nasazeno.


## Lokální implementace 2026-10-03

Dokončeny vlny 1-5. Generátor produkuje 1 895 podporovaných identit (včetně
3 bundled defaultů), nepodporovanou normal variantu Molle eviduje zvlášť.
Zdroj obsahuje také jednořádkové variantové záznamy; generátor podporuje oba
ověřené formáty a stále odmítá nerozpoznané metadata. Display names a normální
váha se berou ze skutečného package mapování, verze se porovnává s konkrétním
blokem google_fonts v lockfile. Historický wide variable soubor je výslovná
bundled výjimka; nové variable fonty jsou odmítnuty.

SQL migrace `20261003130000_ticket_fonts.sql` obsahuje registr, append-only
seed, privátní bucket/restrictive client policy a oba STABLE validátory.
Byla aplikována jen na izolovanou lokální DB 127.0.0.1:55432. Starší Google
identity mimo aktuální katalog se ověřují přes registr; refresh je nemaže.
Produkční PDF loads připravují pouze effective IDs viditelného textu. Resolve
navíc připravuje Futura pro současně vykreslovanou galerii presetů. Resources
map je jedinou schema 2 cestou; single-font data zůstávají pouze v1 boundary.

Deletion ledger splněn: odstraněn form `_popularFonts`, globální loader
`TicketLayoutFont`, orchestration `fontBytes`/výpočet metrik a přímé historické
font downloads (`CUSTOM_FONT_URL`, `DEFAULT_FONT_URL`). Preset v1 wrappers a
v1 fixtures jsou záměrná kompatibilita. Lokální preview používá produkční
resolver s lokálními třemi Google fixtures a bundled assets, bez provider sítě.

Cílené testy dokazují in-flight dedup, 100 renderů bez dalšího font downloadu,
cold-start L2, závod create-if-absent, chyby/integritu/timeout, LRU a čtyři
souběžná načítání. PDF font streams nesou přesné digests tří fixture rodin;
smíšený template používá jejich advances i baseline. Historické drawing/resource
streams zůstávají shodné s fixtures. Flutter ověřuje picker, A/B race, dva
editory, undo/redo, Cancel/dispose, zámek, pending Apply/PDF a sdílené A/B/A
registrace. SQL testy ověřují schema 2, unknown IDs, downgrade/conflict/future
schema, zachování slotů a client bucket/registry ochrany. Bundle proof zapisuje
catalog a tři defaultní assety do manifestu.

Neprovedeno: živá inventura, produkční migrace, deployment, prewarm, rollout,
commit/push. Přesný compatibility blocker je `legacy_font_alias_unknown` pro
jakoukoli neprázdnou named URL kromě
`https://fonts.cdnfonts.com/s/12165/Roboto-Regular.woff`. Konkrétní postižené
occasion IDs a jejich URL zjistí až samostatně autorizovaná canonical inventura.

Závěrečná validační sada: katalog `--check` prošel; 4 katalog/bundle-proof testy
+ 8 existujících bundle/promotion testů, 32 Deno testů, 27 Flutter testů a všechny
3 cílené SQL soubory prošly. `deno check` prošel pro produkční preview entrypoint
a lokální fixture host. Dart analyze nemá chyby; zůstaly 4 původní deprecated
info ve form design controls. `git diff --check` pro měněné tracked soubory je
čistý. Přímý integrační test porovnává digest volby `font`, resources map pro
canvas, PDF preview a dvě generování přes společný download/e-mail renderer.

## Stav ověření při přípravě publikace (2026-10-03)

Implementace byla přenesena do izolovaného čistého checkoutu současného main
(e0b14ccade70); původní rozpracovaný strom se neměnil. Celá sada test_all:
web a automatizace bez selhání, 99 SQL souborů na izolovaném localhost:55432,
849 Flutter testů (1 skip) a 209 Deno testů. Chybějící Vitest závislosti v novém
checkoutu byly doplněny; integrační část poté 3 passed / 27 skipped, protože
není připojen živý Supabase testovací projekt. Katalog/check a asset proof prošly;
Dart analýza bez errors/warnings, zbývají informační lint/deprecation notices.

Produkční migrace ani Function bundle zatím nebyly aplikovány. main vyžaduje
PR s jednou schválenou review; tento požadavek neobcházet. Produkční SSH
root@46.224.187.4:22 aktuálně timeoutuje, Access SQL identitu databáze ověřil.
Po sloučení main: vytvořit čistý synchronizovaný main checkout a ověřený Function
bundle, obnovit schválený hostový přístup, nasadit migraci/bundle, ověřit staré
šablony i nový protokol, až poté publikovat/build/deploy prod/festapptickets.
Další tenanty jsou mimo rozsah. Návrh strojového přístupu je samostatně v
operations/supabase-self-hosted/agent-access-proposal-2026-10-03.md.
