# Dokončení Blueprint integrity a webového MCP propojení

> Historical command paths below may belong to the retired migration toolchain.
> For original source/replay, use the [cleanup recovery record](../archive/repository-tooling-cleanup-2026-10-21.md).
> Current runtime and backup/recovery tooling remains supported.


Datum: 2026-10-20. Stav: lokálně dokončeno; [výsledek, uzavřený ledger a evidence](blueprint-mcp-closure-RESULT-2026-10-20.md). Ověřování: `standard`; publikace a produkční release neprovedeny, pouze s oddělenou autorizací. Níže zůstává původní prováděcí specifikace a historie ověřování.

Tento plán je autoritativní pro zbylé opravy, sjednocení kódu a závěrečnou kvalifikaci. Nenahrazuje platná rozhodnutí původního Blueprint plánu ani neopakuje jeho již dokončenou implementaci. Dosavadní stav „lokálně funguje“ nesmí být zaměněn za „začleněno do main“ nebo „nasazeno“.

## Výsledek a rozsah

Jeden aktuální integrační checkout obsahuje kanonický V2 plánek i webové MCP propojení s hromadným výběrem. Všech osm dosud neuzavřených Flutter test owners má skutečný výsledek na této společné revizi; prokazatelná regrese je opravená, zastaralá fixture je opravena podle platného kontraktu. Veřejný formulář funguje také přihlášenému administrátorovi bez závislosti na nepovoleném map editor read modelu. Cílené i požadované širší kontroly jsou zelené na finálních zdrojích a všechny nahrazené cesty mají důkaz odstranění nebo konkrétní hranici.

V rozsahu jsou testy, jejich fixture a nutné runtime opravy, bezpečné sjednocení obou připravených změn s aktuálním main/V2 základem, lokální SQL a auth kvalifikace, artefakty a předání. Mimo rozsah jsou další refaktory, nové funkce, stadionová architektura, jiní tenanti a produkční operace bez samostatné autorizace. Tento dokument ani jeho prompt neudělují oprávnění k migraci produkce, převodu skutečných dat, nasazení, publikaci package, skutečným e-mailům, commitu nebo pushi.

## Nové ověření relevance

Provedeno read-only porovnání zdrojů a uchovaných výsledků, včetně `git fetch origin main`. Aktuálně načtený `origin/main` je `ac416ae9771d50e517736b0987201ca486f8e348`. Neproběhl nový Flutter test, spuštění backendu ani živý produkční probe. [Audit s hashi](../archive/repository-artifact-followup-2026-10-21.md#blueprint) rozlišuje původní pracovní strom, oba kandidáty, vedlejší V2 pracovní strom a fetched main.

| Položka | Doložený stav | Rozhodnutí |
| --- | --- | --- |
| Blueprint | Hotový izolovaný kandidát, schema/resource protocol 2, 22 PG scénářů, skutečné nákupy všech tří fixture v obou klientech. [Výsledek](/Users/miakh/source/festapp-blueprint-1000-20261020/docs/plans/blueprint-1000-integrity-RESULT-2026-10-20.md). | Zachovat a integrovat deltu; neimplementovat znovu. |
| Osm Flutter owners | Historický běh zaznamenal osm dosud neuzavřených selhání. Jejich test soubory jsou stále shodné s vedlejším V2 checkoutem; bankovní/email testy jsou navíc shodné s fetched main. | Stále relevantní kvalifikační gate. Nejde o tvrzení, že dnes znovu selhalo přesně osm testů nebo že všechny příčiny jsou produktové chyby. |
| Font A/B/A | `ticket_layout_cases.dart` vybírá první Roboto podle family; katalog nyní na tomto místě vrací hash italic fontu `cab2…`, ale fixture `Roboto.ttf` má hash regular fontu `7f3e…`. Runtime `_register` oprávněně hlásí `Font integrity`. Russo One souhlasí. | Konkrétně doložená nekonzistentní fixture. Vybrat odpovídající immutable bytes/variantu; neoslabovat kontrolu hashe. |
| E-mail preview data | Aktuální vedlejší V2 `assets/email_templates/preview_examples.json` se liší od kvalifikovaného kandidáta: už obsahuje očekávané symboly X3425W8H2U, account defaults a rich templates s `preview_iban`. Core/loader/test zdroje jsou shodné. | Konkrétní drift generovaného vstupu, který může odstranit bank/sampler selhání bez runtime změny. Převzít jeho platný generator/sourceDigest a nejdřív znovu ověřit. |
| Admin/public formulář | Při předchozím browser běhu `Map editor places could not be loaded`; anonymní nákup prošel. `DbPlaces.getAllPlaces` volí editor RPC při `isEditor() || isEditorView()`, nikoli přes `canEditOccasion()`. Server RPC kontroluje `get_is_editor_view_on_occasion`. | Opravit předchozí nepřesnou charakteristiku; příčina permission/context/fixture zatím není potvrzená. Znovu reprodukovat s přesným role+occasion kontextem. |
| MCP | `/settings/mcp-connect` + „Vybrat vše“ připravené v samostatném kandidátovi. 8 widget a 60 Node testů, build, PWA a browser kontroly prošly; browser používal syntetický auth/broker. | Integrovat existující řešení a doplnit lokální průchod skutečným broker/exchange řetězcem, nikoli znovu psát consent. |
| Provoz | Task-owned backend byl zastaven, data zachována. Živý deployment nebyl při tomto auditu zjišťován. | Nespouštět sondy proti zastaveným portům a nepředpokládat aktuální live verzi. Nasazení je samostatná fáze. |

### Přesné neuzavřené owners a výchozí směry

Všechny názvy a původní výsledky: [UI status](/Users/miakh/source/festapp-blueprint-1000-20261020/docs/plans/evidence/blueprint-1000-20261020/ui/integrity-ui-status.md), strojový soupis `flutter-test-results.json` vedle něj. Podrobné JSONL logy jsou nyní v `/tmp/blueprint-ui-canonical-suites-3.jsonl`; při startu relevantní sanitizované výřezy převést do trvalé evidence, pokud ještě existují. Nezáviset na trvalé existenci `/tmp`.

| # | Owner suffix | Vstup a rozhodovací kritérium |
| --- | --- | --- |
| 1 | `object_route_dirty_dialog dirty bank dialog can cancel barrier dismissal` | `test/components/navigation/object_route_dirty_dialog_cases.dart:19`; původně finder nenašel TextButton „Storno“. Ověřit skutečný dirty guard a společný dialog, nikoli automaticky měnit produkční text podle testu. Cancel zachová draft i původní URL, discard zavře. |
| 2 | `ticket_layout shared Dart registration reuses bytes for A/B/A across service instances` | `test/components/ticket_layout/ticket_layout_cases.dart:829`, `lib/components/ticket_layout/ticket_layout_service.dart:_register/_cache`. Opravit výše doloženou variantu bytes; zachovat shared single-flight cache a striktní content identity. |
| 3 | `email_preview_context configured bank example follows sample currency in scalar and canonical rich values` | `test/components/email_templates/email_preview_context_cases.dart:21`; EUR scalar a rich preview musí vycházet ze stejného zvoleného účtu. Prověřit `EmailPreviewExamples.scenariosFor`, `festapp_core/.../email_preview.dart:withContext` a canonical preview_examples data. Novější vedlejší generated preview data už obsahují potřebné account bindings; nejdřív je konzistentně převzít, potom ověřit. Nezavádět paralelní HTML renderer. |
| 4-5 | `email_preview_context occasion sampler preserves ticket feature true/false even without catalog access` | Stejný test soubor, parametrizovaný blok kolem ř. 115; `loadEmailPreviewContext` už předává ticketsEnabled v base kontextu. Původní snapshot měl A001, zatímco test očekává X3425W8H2U; aktuální vedlejší generated data už očekávaný symbol obsahují. Nejprve sjednotit data, potom ověřit doménový kontrakt ticket/přihláška bez oprávnění ke katalogu. Nevymýšlet fix loaderu bez nové reprodukce. |
| 6-7 | `email_template_dialog bank metadata updates authoring examples independent of load order true/false` | `test/components/email_templates/email_template_dialog_cases.dart:79`; metadata i examples se mohou dokončit v obou pořadích. Výsledek i draft musí být shodné, nesmí dojít k přepsání uživatelova HTML nebo označení načtených metadat jako změny uživatele. |
| 8 | `email_template_dialog Escape closes mention menu before pristine parent` | Stejný soubor kolem ř. 198; `lib/components/email_templates/views/email_templates_settings_page.dart`, `lib/components/html/rich_html_editor.dart` a společný dialog. První Escape zavře aktivní mention menu, druhý pristine rodiče; dirty/fullscreen pravidla musí zůstat. |

Řádky jsou navigační body zmrazeného kandidáta, nikoli garance čísel po integraci. Odlišit izolované selhání od úniku sdíleného stavu a chyby jen při pořadí širší suite. Nepřidávat skip/expectedFailure, nemažte doménové assertions a neoznačovat selhání za „preexisting“ bez srovnatelné baseline.

## Zdroje, vlastnictví a invariants

- Výchozí repozitář `/Users/miakh/source/festapp` je rozpracovaná větev, nikoli čistý main. Neprovádět v něm checkout/reset ani přepis cizích změn. Integrační worktree založit z nově načteného authoritative main; cílovou revizi zapsat.
- Blueprint zdroje: `/Users/miakh/source/festapp-blueprint-1000-20261020`; package `/Users/miakh/source/venue-seat-picker-blueprint-1000-20261020`. Delty a zmrazená provenance jsou v `docs/plans/evidence/blueprint-1000-20261020/`: `host-canonical-integrity.patch`, `sql-canonical-safety.patch`, package delta, final-source-build manifest. Package patch nemá kompletní npm baseline; použít finální zdroje a archivy ověřené hashi, nikoli hádat chybějící diff.
- MCP zdroje: `/Users/miakh/source/festapp-mcp-select-all-20261020`; `docs/plans/evidence/mcp-web-consent-20261020/mcp-web-consent.patch` a source-validation manifest.
- Vedlejší V2 zdroj při tomto auditu: `/Users/miakh/source/festapp-blueprint-cutover-release-20261019`, package `venue-seat-picker-blueprint-b-20261019`. Před přenosem ověřit, zda je tato session stále aktivním ownerem a zda se její kontrakt neposunul. Toto není souhlas k přepsání jejího dirty stromu. Základ i převzaté dependency změny mají provenance v baseline manifestech kandidáta.
- Layout/font/resource kernel zůstává společný. Backend vlastní authorization, holds, ceny, receipts a objednávky; MCP broker/exchange owns výběr oprávněných akcí, grant i dokončení. Nezvětšovat rozsah oprávnění ani při bulk výběru.
- Public formulář nesmí získat hidden/editor data při řešení admin/public načítání. Žádný catch-403-then-legacy-reader fallback, vypnutí RLS ani obecné rozšíření RPC grantů.
- MCP bulk vybírá pouze aktuálně zobrazené akce; přístup udělí až explicitní approve. Budoucí akce se automaticky neudělují. Zachovat existující limit nejvýše 100 vybraných akcí v brokeru: má-li skutečný seznam víc než 100, řešit konzistentní UI vysvětlení podle tohoto kontraktu; limit tiše nezvyšovat ani položky neřezat.
- `/settings/mcp-connect` v browseru obsluhuje JS shell, v nativní aplikaci zůstává legitimní Flutter route. Helper okno nemá opener; pouze exact trusted issuer continuation; status=connected určuje úspěch. Při ztraceném potvrzení nedochází k druhému udělení oprávnění.
- Jediný Flutter task na celé stanici, vždy `--concurrency=1`; osobní pravidlo má přednost před starším concurrency=2 příkladem v CONTRIBUTING. Nezastavovat cizí úlohy. Browser vlastní headless profil a explicitní config, žádný uživatelův Chrome/Panerelay.

## Vlny provedení

### 0. Zafixovat společný základ a relevanci

**Cíl:** dohledatelný aktuální základ bez ztráty vedlejšího kódu.

Načíst AGENTS/CLAUDE/ai_context v cílovém checkoutu, znovu fetch main, zaznamenat HEAD/dirty stav zdrojů a manifesty. Ověřit relevantní změny main vůči auditu; rozhodnout pro každý připravený hunk „už přítomen / nutno převzít / konflikt“. Neaplikovat celé kandidáty jako starý snapshot přes novější main. Evidenci, která patří tomuto uzavření, převzít do výsledného checkoutu se zdrojem a hashem. Doplnit staré rozhodovací závěry tohoto plánu, pokud se zdroje změnily.

**Validace/exit:** uložená matice změn, jeden integrační checkout z aktuálního main a vyjmenované canonical dependencies; žádná neznámá slepá aplikace patchů. Již přítomné opravy se znovu neimplementují.

### 1. Sjednotit oba připravené výsledky

**Cíl:** oba toky používají stejnou aktuální větev a canonical V2 package.

Přenést nutné dependency/canonical V2 změny z active session až po porovnání s main. Poté integritní SQL/host/package deltu a MCP web deltu. Převzít aktuální `assets/email_templates/preview_examples.json` spolu s odpovídajícím `automation/generate_email_preview_examples.ts`, `automation/fixtures/email_preview/order.json` a skutečnými source inputs uvedenými v jeho `sources`/`sourceDigest`. Přegenerovat existujícím ownerem a ověřit shodu; neručně patchovat HTML nebo změnit pouze jeden generated JSON. Audit dokládá rozdílná preview data, ne kompletní shodu všech jejich generator inputs. Řešit překryvy podle sémantiky, zejména `form_page`, route startup, překlady cs/en, font resources, pub/npm dependency a migration/source-contract manifesty. Zachovat novější required ticket fields, form affinity, receipts a finanční guardy. Pub/npm musí používat ověřený vendor/archive, žádnou absolutní cestu do sousedního checkoutu.

U MCP přenést i Google safe return path, Cloudflare route/CSP/online-only headers a service worker výjimku; samotný JS komponent nestačí. Zachovat fungující native Flutter consent. Žádná produkční schema contraction v této vlně.

**Validace:** source/migration assembler a kontrakt podle aktuálních instrukcí; `npm ci` na finálním lockfile; targeted Dart analyze pouze změněných modulů při volném Flutter slotu. Produkční migraci ani celý build zatím neopakovat po každém hunku.

**Exit:** kanonický schema/resource 2 kontrakt, stejný package pro oba hosty, existující prepared testy jsou skutečně registrované a žádný nový implicitní fallback; evidence určuje přesnou společnou revizi.

### 2. Uzavřít osm Flutter owners

**Cíl:** žádná nevysvětlená chyba banky/fontů/email editoru.

Až po převzetí canonical preview data z vlny 1 spustit osm jmen proti společnému základu a zachytit skutečný počet; opravit koherentně skupiny dle tabulky. Font fixture zvolí explicitní family+variant odpovídající bytes/hash; runtime check zůstává. Preview změny patří do canonical festapp_core/render owneru a jeho scénářových dat, ne do kopie HTML rendereru. UI změny použijí stávající dialog/focus/draft owner.

Izolovaný úspěch při historickém broad failu není sám uzavření: ověřit postiženou registrovanou group v původním pořadí. Je-li test prokazatelně zastaralý, zapsat který kontrakt jej nahradil a opravit jeho vstup/semantickou assertion; zachovat test téhož uživatelského chování.

**Validace:** nejprve filtrované registrované roots, např. `fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart test/sessions/shared_default_2_test.dart --name '<regex pro 8 owners>' --reporter=json`; regex sestavit z přesných names výše, kontrolovat collection a právě osm owners. Po změnách affected groups; finální obě roots v jedné sériové batch až ve vlně 5.

**Exit:** pro každý z osmi owners uložen baseline outcome, příčina, dotčené soubory a passing výsledek v reprezentativním pořadí. Žádné skipy ani nevysvětlené snížení coverage.

### 3. Reprodukovat a vyřešit admin/public map načítání

**Cíl:** oprávněný přihlášený uživatel otevře veřejný formulář stejně spolehlivě jako anonym.

Použít existující task-owned backend `festapp-blueprint-1000-e2e-20261020`, porty API 59721/DB 59722, pouze po kontrole configu a markeru `festapp_test_support.disposable_environment`; instance je nyní zastavená. Bez resetu sdílené DB. Načíst festapp-local-e2e skill/runbook. Před novým bootstrappingem přečíst `automation/blueprint_local_e2e.py`: nejde o obyčejný server start, umí aplikovat forward migrace. Znovu použít data a aplikovat jen skutečně nutné místní změny.

Zachytit přesný role+tenant+occasion/form kontext, `RightsService` predikáty, větev startupu `SynchroService.refreshOfflineData`/client sync a response code `get_map_editor_bundle_v1`. SQL definice je nyní v expansion migraci `20260802234000_client_sync_v1_expansion.sql`; před úpravou najít effective forward owner, nezměnit pouze starou migraci. Ověřit schema/source contract.

Rozlišit chybnou fixture grantů, chybný active occasion kontext a zbytečnou závislost veřejného formuláře na editor-only synchronizaci. Opravit nejužší potvrzený owner; u public consumeru použít existující public read projection explicitně, ne jako fallback po zakázaném editor čtení. Přímý map editor nadále potřebuje versioned editor read model a stejná serverová oprávnění.

**Validace:** autentický browser průchod anonymous, oprávněný admin a přihlášený uživatel bez map-editor práv na stejné veřejné form; všichni způsobilí buyers mohou načíst/použít formulář. Přímé editor RPC unauthorized stále odmítá a žádná hidden data neuniknou. Pokud runtime byl správný, prokázat přesnou opravu fixture a oba permission outcomes, nikoli pouze přepnout test na anonym.

**Exit:** opakovatelný důkaz příčiny a nápravy; admin/public flow se nevyhýbá chybě vymazáním přihlášení. E-maily stále paused, worker_url NULL, cron mimo provoz.

### 4. Doplnit skutečnou lokální MCP auth kvalifikaci

**Cíl:** prepared JS komponent je ověřený i přes skutečný lokální broker/exchange/login řetězec.

Přečíst `tools/festapp/README.md`, remote config/test seams a `supabase/functions/mcp-session-exchange/{handler,config}.ts`. Spustit lokální broker i exchange s výhradně syntetickým tenant/user/event a testovacími issuer/CORS konfiguracemi. Použít lokální Supabase autentizaci a existující LoginModal. Produkční `mcp.festapp.net`, live account/callback ani obecné rozšíření resume allowlistu se pro test nesmějí používat. Je-li nutný lokální endpoint, využít existující validovaný test/config seam; produkční exact-origin guard se nesmí povolit na libovolnou origin. Nelze-li bezpečně reprodukovat native client callback, ohraničit syntetický klient a mít skutečný broker/Edge/session/receipt readback; explicitně označit zbylou native hranici.

Ověřit přihlášení s původním request, partial/all/clear, povolené IDs, explicitní approve, dokončení a cancel, expirovaný request, cizí event/tenant, nedostupné potvrzení bez druhého grantu a vyprázdněný seznam. Zachovat Google exact safe return path. Provider Google redirect se v lokálním testu simuluje na jeho hranici, žádné live Google přihlášení se nevyžaduje. Ověřit, že root startup nehází browser na Flutter ani na admin před consent; že generated hosting i service worker volí JS bez cached Flutter fallbacku.

**Validace:** prepared 60 Node/8 widget controls pro affected inputs, aktuální `tools/festapp` remote test entry a Edge handler tests podle jejich normal runneru; izolovaný headless browser s reálnými lokálními requests a autoritativním broker/grant readbackem. Počet a příkazy zapsat, syntetickou provider/client hranici pravdivě označit.

**Exit:** jeden request se promítne nejvýše do jednoho grantu pouze pro zvolené oprávněné akce; UI success odpovídá serveru; žádná citlivá data v URL logu, screenshotu nebo evidence. Browser nezatíží Flutter runtime pro consent.

### 5. Finální kvalifikace společného výsledku a odstranění zbytků

**Cíl:** dokázat výsledek po integraci, nikoli slepit passing logy různých zdrojů.

Po freeze kódu spustit jednou obě registrované Flutter roots, relevantní JS groups, package/archive gates při změně package a nové source/migration parity. V task-owned DB ověřit forward migration na fresh i sold/held fixture, pokud se proti původně kvalifikovanému vstupu změnilo SQL/schema; změněné lock/finalize SQL vyžaduje skutečné PG races. Unchanged immutable core důkazy lze ponechat pouze při shodě source/toolchain/artifact hashe.

Finální skutečný Flutter i JS host musí zachovat všechny tři fixture (chairs1000, tables100x10, mixed950+standing50), nákup/price/ID/hold-clear a reload, admin save/reopen 1000 bindings a atomickou pohovku. Převzít starou kvalifikaci pouze tehdy, odpovídá-li finálním vstupům; integrace auth/forms/shared core typicky invaliduje affected journeys. Browser evidence u JS nyní pochází z Vite development transportu: finální společný JS production build spustit s task-local backend configem a zopakovat dotčený checkout/reload, nebo výslovně ponechat tuto production-mode gate neuzavřenou. Build módy nezaměňovat. Přeměřit 1000-seat profil jen pro změněné relevantní inputs; existující rozpočty neoslabovat.

Aktualizovat READMEs/aktuální plán podle skutečného stavu a zapsat deletion ledger níže. Historické výsledky přesměrovat na nové closure evidence, neměnit zpětně jejich hashe a netvrdit, že byly úspěšné již tehdy. Task-owned služby po skončení zastavit a potvrdit porty/kontejnery; neodstraňovat cizí data.

**Exit:** osm owners i obě roots zelené, map permission flow doložen, MCP skutečný lokální grant ověřen, společné artefakty/seams odpovídají zdrojům a finální manifest spojuje přesné source/build/SQL hashes s provedenými kontrolami. Při gate failure neopisovat závěr „hotovo“; opravit v rozsahu nebo uvést přesný blocker a nesplněný exit.

## Ledger odstranění a zachování

| Cesta | Výsledná akce | Důkaz |
| --- | --- | --- |
| Legacy/staged public a admin blueprint read fallback | Ponechat odstraněné; nepřenést ze staršího main/B snapshotu. | Oba legacy rollout routine names absent, oba readers bez layoutu explicitně reject; poison test. |
| Původní interní renderer/style/geometry owner | Ponechat odstraněný; host montuje společný V2 package. | Call graph + archive/consumer testy, žádný load-error fallback. |
| Absolutní sibling pub override / druhý npm package | Nahradit přesným vendorem/immutable archive pro společný výsledek. | package resolution a archive SHA; clean consumer. |
| `/settings/mcp-connect` → Flutter browser shell | Odstranit hosting/router/SW handoff pro web; zachovat legitimní Flutter route pouze pro nativní aplikaci. | Generated router + PWA + browser network evidence bez Flutter. |
| Nesprávný Roboto variant fixture / assertions navázané na starý ukázkový text | Opravit podle platného kontraktu, zachovat semantic coverage. | A/B/A identity/single-flight, ticket vs přihláška, EUR rich+scalar, dirty guard. |
| Chybná permission/context závislost public form | Odstranit pouze prokázanou chybu/fixture; bez rozšíření server práv a editor fallbacku. | 3 identity scénáře + unauthorized RPC reject. |
| Oddělené dirty kandidáty jako zdroj runtime dependency | Použít jako evidence/zdroj delty, nikoli provozní dependency. Historické worktrees nemaž bez samostatné potřeby. | Jeden integrovaný source/build manifest, žádné absolutní runtime importy. |
| Legacy DB archivy/offline importer, receipts, cenové snapshoty | Zachovat pojmenovanou offline hranici a původní obchodní ownery. Fyzická contraction není autorizovaná. | Stávající deletion ledger + historické identity/ceny po forward migraci. |

## Publikace a provozní fáze po samostatné autorizaci

Předání má zvlášť stavy: připravené změny, začlenění do main, produkční DB migrace, klientský rollout, ověřený live stav. Tento prompt končí připraveným společným lokálním výsledkem. Následné oprávnění k publikaci nelze odvozovat z tohoto dokumentu.

Při budoucí autorizaci: ověřit aktuální main a jednoho vybraného tenanta z configu/activation; inventura skutečných layoutů a klientů, záloha, offline dry-run se zachováním IDs, bezpečná forward expanze/guardy před kompatibilními klienty, lokální direct web release a live version+flow readback. Existující tenant scope je ticketing; přesnou branch/domain potvrdit activation/configem, nikoli jen názvem kandidáta. Žádné další prod/* větve. Nevracet nechráněný finalize, aktivní SVG nebo legacy writer při rollbacku. Rutinní deploy/build monitoring delegovat dle AGENTS až po explicitním oprávnění k nasazení.

## Kompletnost a zbývající nejistoty

Hotovo znamená jeden zdroj, uzavřených osm owners, map/public průchod i zachované permission fences, ověřený JS consent+bulk+grant, společné finální artefakty a jednoznačný operační stav. V žádném bodě není přípustný pouze „passing isolated test“ jako náhrada za selhávající registrovanou suite.

Nejistoty mají konkrétní řešení: stav novější vedlejší session určí vlna 0; dnešní reprodukci osmi owners vlna 2; příčinu mapy vlna 3; proveditelnou bezpečnou lokální callback hranici vlna 4. Produkční autorizace není blocker lokální implementace. Produkční aktivace zůstává odděleně neprovedená, dokud není skutečně povolena a potvrzena.

## Aktualizace při provádění

- Authoritative main při startu cc80f32ee, po koordinaci s MCP ownerem aktualizováno na 079d9ed832b8e6ee0d3556a9c1c42ec42d935865. MCP schema2 používá `access` a živou projekci get_operator_access_v1; starý `occasions` payload není platný. Web adaptaci vlastní tato closure, backend/produkci druhá session.
- Novější main obsahuje platný generator preview_examples a opravu renderAccountNumber. Přegenerování vytvořilo beze změny 54 scénářů; starší generator ze sousední session se nepřebírá.
- Flutter osm owners: pět zelených na baseline, tři reprodukovaná selhání (Roboto varianta, zastaralý text bankovního guardu, early Escape interception). Po opravách osm prochází v celé registrované sadě. Broad sada navíc odhalila pět neplatných fixture odpovědí (Blueprint acknowledgement, čtyři command identity); doplněny platné odpovědi bez oslabení runtime. Konečná sada se opakuje po sjednocení r37.
- V2 owner předal stabilní r37 a provenance r37-vs-blueprint-1000-provenance.json. Jeho novější UI/kernel změny se slučují se zachováním integrity delty. Flutter slot je koordinovaný, souběžné cizí úlohy se nezastavují.
- Importované nepublikované V2 migrace kolidují timestampy s main. Dostávají jedinečný timestamp +100 (19120000,19130000,20120000,20150000,20210000); jejich těla zůstávají beze změny. Historické hashe se nepřepisují.
- Lokální DB marker potvrzen; outbound paused, worker_url NULL, 0 aktivních cron. Reprodukovaný anonymní public form navíc narazil na zbytečný offline sync a chybějící nový news RPC v zachované DB. Je nutné vyřešit úplný public context průchod, ne jen mapovou chybu skrýt novou fixture.

- Po aplikaci chybějících main forward definic na označeném lokálním backendu reprodukován přihlášený editor public form: map RPC vrací 200 podle novějšího permission owneru, ale nepotřebný offline refresh následně volá information editor bundle (403). Public FormPage načítá vlastní veřejný form projection; jeho context bootstrap proto používá refreshOffline:false. Editor permissions/granty se nemění.
- Registrované obě Flutter roots na r37 prošly 701 testy; samostatný MCP soubor navíc odhalil chybějící test import dart:async po převzetí bulk testu. Finální frozen batch musí zahrnout i MCP.

## Navazující kanonizace oprávnění

Na výslovné zadání uživatele vznikl [follow-up plán](canonical-authorization-plan-2026-10-20.md) a [execution prompt](canonical-authorization-EXECUTION-PROMPT-2026-10-20.md). Pokrývá společná SQL pravidla operací pro běžné requesty, MCP a RLS, projekci pro UI, odstranění duplicit a měřený výkonový gate. Jde o samostatný budoucí cutover; nerozšiřuje implementační rozsah této closure a nenahrazuje její dosud neuzavřené gates.
