# Lokální náhled vstupenek bez serverové přípravy galerie

Datum: 2026-10-22
Stav: Implementováno a lokálně ověřeno. Výchozí numerická přesnost geometrického testu byla opravena v navazujícím release. Merge a produkční rollout následně autorizoval uživatel; provedení se ověřuje odděleně. Výsledek: [execution evidence](ticket-preview-local-resources-RESULT-2026-10-22.md).

Změna zadání 2026-10-22: Uživatel výslovně povolil ponechat zvýšený CPU limit. Ruší se požadavek odstranit preview CPU výjimku a prokázat původní CPU rozpočet jako podmínku dokončení. Měření cold/repeated běhu a odstranění zbytečné runtime práce zůstává v rozsahu.
Verification: standard pro implementaci, protože se mění sdílený síťový kontrakt a práce se soukromými zdroji. Při tvorbě plánu nebyly spuštěny testy.
Výchozí revize: `d392ed38810cce2d8716c41b43cd4698eaf94462` v `festappnet/festapp`.

## Výsledek a rozsah

Otevření nastavení načte pouze podklady aktuální vstupenky. Otevření editoru je znovu použije. Galerie se sestaví a vykreslí v klientovi, načítá se až při otevření a její velikost nezvyšuje práci backendu. Pohyb prvků, změny rozměrů, výběr připravené šablony a undo nevolají server. PDF vzniká pouze na výslovnou žádost o PDF nebo při skutečném vydávání vstupenek.

Součástí jsou Flutter web i nativní klient, nastavení existující akce, read-only náhled, průvodce vytvořením akce, sdílená příprava písem, resource kontrakt a jeho testy. Nemění se schema uloženého layoutu 3, geometrie, obsah existujících vstupenek, práva, ukládací command, konfliktní ochrana ani jediný produkční PDF renderer. Nevzniká klientský PDF renderer. Nejde o úplný offline režim aplikace: oprávnění a čerstvá data akce nadále vyžadují backend.

Výchozí požadavek z `docs/plans/ticket-layout-editor-plan-2026-10-01.md` zůstává platný: lokální canvas, společná geometrie a věrnost PDF. Tento plán nahrazuje jeho rozhodnutí dodávat presety a všechny zdroje v každé resolve odpovědi. Serverová definice presetů zůstane autorským zdrojem, klient dostane její deterministicky generovaný artefakt.

## Ověřený stav a důvody změny

| Fakt | Konkrétní vlastník | Důsledek |
|---|---|---|
| Nastavení volá resolve při načtení, editor ho volá znovu. | `lib/components/ticket_layout/views/ticket_settings.dart`: `refresh`, `edit` | Sdílet session resources a rozpracovaný návrh místo druhého plného načtení. |
| Galerie se kreslí lokálně, ale zdroje dostává v resolve. | `ticket_layout_service.dart`: `resolve`; `views/ticket_layout_editor.dart`: výběr presetů | Přesunout dodání statických podkladů z RPC do klientských assets. |
| `allowMissingBackground` současně přidává fonty celé galerie. | `_shared/ticketGeneration.ts`: `loadLayoutResources` | Oddělit obnovu chybějícího obrázku od načítání galerie. |
| Resolve posílá base64 fonty, obrázky, QR matici i scénáře; také duplikuje výchozí font v `font` a `fonts`. | `preview-ticket-layout/handler.ts`: `handlePreview` | Nový klient potřebuje lehký kontext a adresované zdroje, nikoli jeden binární balík. |
| Studený resolver počítá metriky a ukládá zkušební PDF i pro připnuté známé fonty. | `_shared/ticketFonts.ts`: `TicketFontResolver.validate`, `fontMetrics` | Příprava při sestavení nebo prvním importu; běžný read pouze ověří identitu a načte připravený artefakt. |
| Fontová cache existuje v Dart i v paměti Edge workeru. | `TicketLayoutService._fonts`, `TicketFontResolver.cache/inflight` | Rozšířit stávající vlastníky; nezakládat další paralelní cache stejné role. Paměť workeru nestačí po restartu. |
| Soukromé fonty už používají image Worker a R2. | `_shared/ticketFontStorage.ts`, `ticketFontR2.ts`, `workers/image-worker/src/ticket-fonts.ts` | Žádný návrat do Supabase Storage, veřejný bucket ani nové libovolné font URL. |
| Existuje další režim `layout-text` s registrací zdrojů. | `handler.ts`, `TicketLayoutService.layoutTextBatch` | Nepovažovat ho za mrtvý jen podle názvu. Zachovat jeho oprávněné explicitní konzumenty; nesmí být připojen k běžnému překreslení galerie. |

Incident: oddělený canary na Edge Runtime v1.74.0 s reálným nasazeným handlerem při původním `ticket-assets/*.ttf` vrátil 400 `font_storage_config`; s `ticket-assets/**/*` vrátil 200, 5 fontů a 12 položek galerie. Byly použity syntetické údaje, bez sítě a přihlašovacích údajů. Důkaz na hostu: `/opt/festapp-supabase/runtime-evidence/ticket-preview-router-20261022T092955Z`. CPU termination se objevilo v produkčních logách stejné funkce, jeho příčinná vazba na konkrétní uživatelovu odpověď není prokázána. Zvýšení CPU rozpočtu není cílová architektura.

## Cílové vlastnictví a kontrakty

### 1. Statický katalog jako build artefakt

- Autorský zdroj: existující `_shared/ticketGallery.ts`, výchozí presety v `ticketLayout.ts`, připnutý fontový katalog a bytes v `ticket-assets`.
- Nový deterministický generátor `automation/tickets/generate-preview-assets.ts` vytvoří manifest geometrie, identit fontů, metrik a vazeb na artwork. Žádné ručně kopírované definice do Dartu. Znovupoužije `fontMetrics`; nepřepíše fit/wrap pravidla.
- Manifest ponese schema vlastního artefaktu, hash obsahu a digest každého fontu, metrik a obrázku. Identita fontu se nemění. Kontrola `--check` odhalí drift v CI i před buildem.
- Flutter přes `pubspec.yaml` zahrne potřebné fonty, metriky a artwork. Pro web jde o běžné statické assets, pro native součást instalace. `rootBundle` je načte na vyžádání. Žádné nové zveřejnění soukromých uživatelských fontů. Naměřená současná složka backgrounds a dva gallery fonty mají dohromady přibližně 908 KiB na disku; skutečný přírůstek distribučního balíku se změří při implementaci.
- Klientský `TicketPreviewAssets` v `lib/components/ticket_layout/` čte manifest, načítá bytes a sdílí registraci s `TicketLayoutService._cache`. Dekóduje viditelné položky a omezený předstih, ne všechny obrázky při vstupu na stránku. Na nativních platformách nevznikne síťová závislost statické galerie.
- PDF backend dál spotřebovává stejné zdrojové soubory a metriky. Runtime staticPatterns musí dál obsahovat podsložky, protože je používá skutečné PDF generování.

### 2. Lehký autorizovaný kontext

Rozšířit stávající `preview-ticket-layout` resolve opt-in polem `resourceProtocol: 3`. `fontProtocol: 2` zůstane fontovým kontraktem a nemění se uložené schema layoutu. Explicitní rozlišení brání rozbití už distribuovaných aplikací.

Odpověď nového kontraktu obsahuje vybraný/saved template, normalizované syntetické scénáře a produktový katalog pro danou akci, vybrané identity fontů a reference pouze na aktuální background/logo. Neobsahuje bytes, metriky vestavěných fontů, galerii ani QR matici. Žádné `deps.resources`, čtení galerie, rozměry obrázku přes `PDFDocument`, font parsing, PDF embedding nebo PDF generování na této větvi. Rozměry/layout jsou již explicitní; chybějící historická konfigurace zůstává pojmenovanou chybou, nepřevádí se skrytě.

Server dál vlastní normalizaci údajů, katalog a autorizaci. Klient nepřepočítává obchodní pravidla. Pro synthetic preview QR použije již existující knihovnu QR a stejný testovací payload a correction level M; nikdy skutečný přístupový symbol. Read-only ignoruje klientské editace; setup draft se váže na své současné uložené scope a oprávnění. Nedostupný volitelný katalog zachová současné rozlišení `catalogError`.

Do nového klienta nepatří fallback na těžký resolve. Nepodporovaný kontrakt je srozumitelná chyba a důvod opravit pořadí nasazení. Starý resolve zůstane pouze na pojmenované hranici již vydaných klientů; nikdy ho nevolá nový interní kód. Obslouží ho tentýž resolver připravených fontů. Jeho úplné odstranění vyžaduje samostatné rozhodnutí o ukončení podpory starých distribuovaných aplikací.

### 3. Připravená písma a soukromé obrázky

- Vestavěné fonty: parsing, metriky a PDF embedding probe při generování artefaktů, nikoli při otevření editoru ani při každém startu Edge workeru. Runtime ověří digest bytes a manifestu; import neověřeného fontu nepovolí.
- Ostatní registrované fonty: autorizovaný režim `font` načte pouze konkrétní chybějící font. Při prvním importu vzniknou jednou bytes a připravené metriky; potom se znovu použijí i po restartu workeru. Rozšířit současný privátní R2 transport o úzce validovaný sidecar metrik. Nezavádět další bucket ani obecný storage proxy.
- Sidecar má verzi generátoru, hash fontu a digest metrik. Vzniká výhradně v důvěryhodné serverové přípravě. Klientská metadata nejsou důkazem validace. Současné immutable font bytes se nepřepisují. Sidecar se publikuje až po úplné přípravě; paralelní import ověří vítězný obsah, neukládá částečně připravený stav jako hotový.
- Existující privátní font bez sidecaru se připraví při prvním skutečném vyžádání konkrétního fontu. Nikdy se nehromadně připravuje celý katalog při otevření stránky. Poškozený či neznámý formát se odmítne, nesmí změnit historický vzhled na jiný font.
- Běžné obrazy načítá klient existujícím `DbImages`/image Worker kontraktem. Pro soukromé zdroje zachovat autorizované čtení a expiraci; neposílat servisní token do klienta, nekonstruovat veřejnou URL. Pokud chybí použitelný klientský read pro konkrétní typ, doplnit úzký autorizovaný read přes stejný Worker před přepojením tohoto typu. PDF načítání ponechat v současném serverovém safe-fetch kontraktu.

### 4. Životnost klientských zdrojů

`TicketLayoutService` sdílí jednu načítací Future pro stejný kontext. Session drží aktuální template, syntetický kontext a reference na načtené fonty/artwork. Přechod thumbnail -> editor nevyvolá druhé resolve, pokud se kontext nezměnil. Změna draftu upraví lokální model a překreslení; nenahrazuje se starým serverovým template.

Cache dat akce je oddělená od immutable asset cache. Klíč kontextu zahrnuje tenant, uživatele, occasion/draft, aggregate/draft revision a read-only/edit scope. Po změně identity, práv nebo scope se zneplatní a proběhne nové ověření. Cache není povolení k dalším serverovým operacím. Veřejné vestavěné assets lze sdílet globálně podle hashe; privátní fonty a obrázky jsou oddělené podle identity/scope a při odhlášení nebo změně oprávnění se jejich reference a cache odstraní. Globální `_fonts` nesmí zpřístupnit privátní resource dalšímu uživateli bez nového autorizovaného přístupu. U obrázků definovat vlastnictví clone/dispose, bounded decode cache a zahazování pozdních výsledků. Chyba jedné gallery položky neblokuje současnou vstupenku. Chybějící aktivní font nemá tichý fallback.

## Invarianty a měřitelné dokončení

1. Nastavení provede nejvýše jedno lehké context resolve, načte pouze aktivní zdroje a neotevřenou galerii nestahuje ani nedekóduje.
2. Otevření editoru ze stejného nastavení nevolá druhé resolve. Galerie nevolá Edge Function ani PDF, počet serverových volání neroste s počtem šablon.
3. Po prvním lokálním načtení assetu další otevření v témže procesu znovu neregistruje font ani nedekóduje tentýž vlastněný obrázek; ukončení editoru uvolní session obrazy.
4. Nová resolve větev funguje v testu s resource loaderem, font parserem a PDF rendererem nastavenými na okamžité selhání při zavolání.
5. Známý připravený font se po vytvoření nového resolveru načte bez `fontMetrics` a bez PDF probe. Neznámý font má právě jednu sdílenou přípravu, chyba umožní bezpečný retry.
6. Canvas a skutečné PDF zachovají font bytes, metriky, zalamování, geometrii, QR a text; uložené layouty a command konfliktů zůstávají stejné.
7. Zvýšený CPU limit pro `preview-ticket-layout` zůstává podle pokynu uživatele. Rozpočet `process-email-queue` se nemění. Povinný cold/repeated runtime důkaz a metadata-only větev zůstávají; samotný vyšší limit není výsledkem.

## Implementační vlny

### Vlna 1: Jeden reprodukovatelný resource artefakt

Zavést generátor, manifest a `TicketPreviewAssets`, zapojit asset registraci a rozšířit `ticket-font-asset-proof.py` o nové manifesty a skutečně používané galerie. Zachovat verze již uložených artwork URL; lokální cesta není nová uložená URL. PDF probe provést v generátoru. Nepřevádět staré fontové identity ani layouty.

Ověření: deterministická regenerace a `--check`, hash mutation fixture, společné TS/Dart fixtures pro všechny používané fonty a presety včetně češtiny a dlouhých textů. Exit: backend i Flutter přečtou shodný manifest bez jeho ručně psané kopie.

### Vlna 2: Trvalá příprava ostatních fontů

V `ticketFonts.ts`, `ticketFontStorage.ts`, `ticketFontR2.ts` a `workers/image-worker/src/ticket-fonts.ts` oddělit import od běžného read. Přidat omezený privátní sidecar read/create a zachovat všechny dosavadní bounds, hash kontroly, oprávnění a in-flight map. Stejný připravený resource použijí editor, `layout-text` i PDF.

Ověření: font resolver a Worker testy pro cold read, novou instanci resolveru, souběh, přerušený import, chybějící/poškozený sidecar, 403 a cross-scope. Exit: běžný read nikdy nevyrábí testovací PDF ani metriky; první import je jediná explicitní výjimka.

### Vlna 3: Metadata místo binárního resolve

V `preview-ticket-layout/handler.ts` a `index.ts` přidat novou resolve větev po stejném oprávnění a limitech. Zachovat scénáře/normalizaci v `ticketRenderData.ts`; oddělit ji od QR a načítání zdrojů. Stávající `pdf`, `catalog`, `font`, `layout-text`, read-only a setup draft nesmějí získat méně přísnou autorizaci. Bounded output platí i pro metadata.

Ověření: nový resolve vrací pouze metadata a nevolá zakázané závislosti; neautorizovaný požadavek selže před čtením; read-only/draft/test invalid protocol; stávající klientský kontrakt zůstane funkční. Exit: počet šablon ani velikost artwork nemění velikost metadata resolve.

### Vlna 4: Přepojení všech klientských vstupů

Změnit `TicketLayoutService.resolve`, `TicketSettings.refresh/edit`, gallery větev v `ticket_layout_editor.dart` a setup `occasion_setup_page.dart`. Sdílet session, načítat galerii lokálně až při otevření, registrovat fonty pouze na vyžádání a QR tvořit lokálně. Zachovat explicitní PDF akci, save/conflict guard, draft restoration, jednorázové otevření pickeru a preview draft údajů. Read-only nepotřebuje editorové gallery resources.

Ověření: transport spy a widget testy pro nastavení -> editor -> galerie -> změna -> undo -> cancel/reopen, setup a read-only; nulová gallery/PDF síť a jeden context request. Ověřit výměnu přihlášeného uživatele, pozdní odpovědi a dispose. Exit: nový Flutter kód nikde nečte binární pole starého resolve ani nevolá jeho starou větev.

### Vlna 5: Měření a dokumentace

V odděleném prostředí s připnutým Edge Runtime v1.74.0 ověřit studené načtení i opakovaná otevření. Měřit CPU, čas, bytes a počty requestů stejným workloadem před/po. Nepoužívat jen lokální desktop timing. Ověřit chování worker poolu a kumulaci budgetu při jeho znovupoužití; nevymýšlet číselnou hodnotu defaultního limitu. Nový context request nesmí spouštět parsing fontů, čtení obrázků ani PDF. Galerie může fungovat i při zablokovaném preview endpointu po načtení contextu.

Ponechat preview větev v `patch-function-email-cpu-budget.py` a jejích testech podle změněného zadání. Zaznamenat cold/repeated měření při zachovaném limitu a konkrétní odstraněnou práci. Zachovat recursive staticPatterns a email budget. Aktualizovat feature README a edge reference, přestat staré plány vydávat za aktuální kontrakt a tento plán po implementaci označit výsledkem.

## Odstranění a vědomě zachované hranice

| Artefakt/chování | Akce a důkaz |
|---|---|
| Načítání gallery fontů kvůli `allowMissingBackground` | Z nového resolve odstranit; test s gallery fault nemění aktivní thumbnail. Starý klientský adapter může načíst požadovanou galerii explicitně. |
| Binary `font/fonts/background/logo/presetArtwork/qrMatrix` v novém resolve | Neexistují; schema assertion a transport test. Starý externí protokol je izolovaná obsluha vydaných klientů, nikoli fallback. |
| Nevyžádané gallery decode a druhé resolve při otevření editoru | Odstranit; měření volání/decode a session test. |
| PDF probe a výpočet metrik při běžném read | Přesunout do build/import; test po restartu resolveru. |
| CPU allowance pro preview | Výslovně ponechat podle pokynu uživatele z 2026-10-22; email allowance neměnit. |
| Starý protokol pro vydané aplikace | Výslovně zachovat pouze externí kompatibilní boundary. Odstranění až podle schváleného ukončení podpory; žádný nový interní caller. |
| PDF renderer, safe-fetch, R2 authority, `layout-text`, font registry a schema 3 | Zachovat jejich aktuální zodpovědnost; nepřidat konkurenční implementaci. |

## Ověření implementace a provozní pořadí

Před Flutter úlohou zkontrolovat volný workstation slot. Testy pouštět s `--concurrency=1`. Pro JS použít pnpm 11.24.0; pro Dart/Flutter fvm. Při plánování nic z toho nespouštět.

- Deno: cíleně `preview-ticket-layout/preview_test.ts`, `_shared/ticketFonts_test.ts`, `ticketFontStorage_test.ts`, testy nového generátoru a skutečně dotčených transportů; s `--frozen --lock=supabase/functions/deno.lock` a pouze potřebnými oprávněními.
- Flutter: `fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart --plain-name ticket_layout`; přidat dotčené setup testy do jejich existujících suite owners a spustit odpovídající filtr. Unit coverage zdrojů do současné ticket suite; nezakládat paralelní test runner.
- Automation: `node --test automation/tests/ticket_runtime_assets.test.mjs automation/tests/email_worker_cpu_budget.test.mjs automation/tests/ticket_font_catalog.test.mjs`; doplnit nový asset generation check.
- Worker: existující pnpm test script v `workers/image-worker/package.json` s filtrem pro ticket-fonts a přístup ke zdrojům; před spuštěním určit dostupný filtr z package.json.
- Vizuální shoda: společné fixtures canvas/PDF pro existující uložený ticket, galerii, diakritiku, dlouhý text, ručně změněný background a chybějící zdroj. Nic neposílat zákazníkům ani nepoužívat skutečné admission QR.
- Provozní důkaz: výše uvedený izolovaný runtime a request spy v klientovi; browser jen v headless izolované session podle agent-browser pravidel a lokálního E2E kontraktu. Žádné produkční fixtures.

Po implementaci a samostatném oprávnění k nasazení: nejdříve připravené resources/private Worker a rozšířený backend, potom klient vybraného tenantu `prod/festapptickets`; CPU výjimka zůstává zachována. Build a release podle aktuálních místních pravidel, bez dalších tenantů. Rutinní deployment delegovat levnějšímu subagentovi s přesnými SHA a gates. Tento plán sám neautorizuje commit, push, data backfill ani deploy.

Rollback může vrátit klienta na předchozí distribuovaný build, protože externí protokol zůstává podporovaný. Nemaže nové immutable assets ani sidecary potřebné pro novější klienty. Nevrací autoritu do Storage ani nepřepisuje uložené fonty. Produkční verifikace nesmí prohlásit funkční starý protokol za dokončení nového řešení.

## Předpoklady, otevřené body a rizika

- Statické galerie lze distribuovat jako app assets s existujícími licencemi; při implementaci ověřit licence všech přidaných fontů a úplnost starých artwork verzí. Nezařazovat privátní fonty mezi veřejné assets.
- U soukromých obrázků není v tomto průchodu ověřena použitelnost každého klientského read adaptéru. Vlna 3/4 musí dohledat konkrétní kontrakt v `DbImages` a image Workeru; nedostupný typ nesmí být nahrazen veřejnou URL ani skrytým těžkým resolve.
- Nové asset schéma a sidecar jsou transportní interní kontrakty, nikoli migrace customer layoutů. Pokud aktuální registry vyžadují SQL změnu, nejdříve doplnit tento plán o přesnou migraci, test a oddělený release krok.
- Cachování fontů nesmí předstírat podporu komplexního shapingu, který dnešní metriky neumí. Tento plán zachovává dnešní zobrazení; nová textová typografie je jiný úkol.
- Hlavní rizika: odchylka metrik mezi canvas/PDF, paměť dekódovaných obrázků, stale oprávnění/data a vydané staré aplikace. Výše uvedené fixtures, vlastnictví resources a oddělení protokolů jsou povinné exit gates.

Hotovo je teprve při splnění všech sedmi invariantů, odstranění nových interních závislostí na těžkém resolve, ověřené shodě PDF a canvas a doloženém cold/repeated běhu se zachovaným CPU limitem. Implementace, lokální ověření a živé nasazení se hlásí odděleně.


## Zjištění při implementaci

- `layoutTextResources.ts` přes statický import inicializoval HarfBuzz i při resolve.
  Handler nyní importuje přípravu až v explicitně autorizované větvi `layout-text`;
  její kontrakt a registrace zůstávají zachovány. Důkazem je runtime canary a
  Deno entrypoint/resource testy.
- Použitelný privátní image read již existuje na image Workeru (`/private/`, JWT,
  projectId). Klientský download byl rozšířen o tento úzký read; cizí origin
  nedostane token, redirecty jsou vypnuté. SQL migrace není potřeba.
- Celý Flutter gate má jedno stejné selhání již na čistém výchozím commitu:
  Float32 serializace Rect mění `405.16245` na `405.162109375`. Tento úkol nemění
  model geometrie ani sdílenou fixture. Přesný baseline důkaz je v result dokumentu.
