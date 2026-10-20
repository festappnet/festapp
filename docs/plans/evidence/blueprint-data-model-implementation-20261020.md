# Realizace auditu datového modelu Blueprintu

Datum: 2026-10-20. Verification: standard.
Stav po opakované kontrole: vlna 1 je částečná, exit brána znovu otevřena; celý sedmivlnový plán dokončen není.

## Výchozí stav a rozsah

Host worktree `/Users/miakh/source/festapp-blueprint-cutover-release-20261019`
měl tracked head `a3a0637d8eeec1b0d5d3a5292e6db62fdcb4f5d1` bez tracked změn;
plán, execution prompt a původní auditní evidence už existovaly jako untracked.
Package `/Users/miakh/source/venue-seat-picker-blueprint-b-20261019`
měl čistý head `0b881853bd9071784fd66102a03a1606a81afa79`.
Původní dirty `/Users/miakh/source/festapp` nebyl měněn.

Databázové změny se aplikovaly výhradně na existující disposable backend
`127.0.0.1:59522`, s předem ověřeným markerem
`festapp_test_support.disposable_environment.project = festapp-blueprint-b-e2e-20261019`.
Použity transakčně rollbackované syntetické fixtures. Produkční tenant nebyl určen,
produkce nebyla oslovena. Existující backend ani fixture nebyly resetovány.

## Vlna 1: ownery a odstraněné cesty

- `database/functions/blueprint/resources.sql`:
  `blueprint_layout_font_dependencies_internal` vlastní SQL closure deklarovaných
  fontů a fontů výsledného textu, včetně vlastních preset dokumentů. Kind style
  přebije nemaskovanou lokální hodnotu, explicitní override přebije kind style.
  Reader už nemá původní neúplný UNION default font + node font.
- `database/functions/blueprint/validation.sql`: stejná closure pro font readiness
  a glyph coverage; closed appearance kind/key/type/range validace. Odstraněn
  nezávislý chybný node-first výběr fontu. Nezobrazované seat/couch/bar labels
  nevyžadují glyphy; deklarovaná font ID stále potřebují připravený outline.
- `blueprintLayoutFontCharacters` v host resources používá core
  `effectiveNodeProperties` a samostatné defaults presetů. `_prepareFonts`
  připravuje znaky podle fontu, ponechává číslice/count symboly dokumentovému
  fontu a při superseded generation vyhodí chybu místo tichého void-success.
- Forward migrace `20261020100000_blueprint_scoped_font_dependencies.sql`
  obsahuje aktuální kanonické SQL resources + validation. Historické migrace
  se neměnily. Aplikována pouze lokálně, přes extension-owning supabase_admin.
- `test/fixtures/blueprint/scoped-font-sql-roundtrip.json` obsahuje skutečné
  syntetické SQL readbacky admin/public/setup/copy. Export proběhl v transakci
  přes stejný layout integration test, přes transaction-local setting
  `festapp_test_support.blueprint_font_roundtrip`; nakonec ROLLBACK.
  Žádná zákaznická data ani credentials nejsou součástí corpus.

Core a JS regrese ověřují dokument, resources, obě zobrazená označení B/C a
neprázdné glyph paths. Scoped B má jen glyph B; own C jen glyph C, takže
chybná priorita se nemůže schovat za shodnou glyph coverage. SQL navíc ověřuje
missing font/glyph a malformed appearance s nezměněnou revizí i počtem bindingů.

## Rozdíl distribuovaného artefaktu

Původní skutečně nainstalovaný `@festapp/venue-layout` 0.2.2 odmítal corpus:
`appearance.table.fontId: unknown_appearance_property` a
`nodes.appearanceOverrides: invalid_appearance_overrides`.
Flutter core z package baseline stejný dokument přijímal.

Package `tool/build_web.sh` sestavil kernel z nezměněné core baseline.
Npm package version byla zvýšena na 0.2.3, poté skutečné `npm pack` a
`npm install --offline --ignore-scripts --no-audit --no-fund` v host web_client.
Původní 0.2.2 archiv se nepřepsal. Žádné registry publication ani Git operace.

- Source revision: `0b881853bd9071784fd66102a03a1606a81afa79`.
- Source digest: `1e6315e387f200ec988a47717af79583572aff26de1dbdd26ac8086b0fad38e8`.
- Kernel SHA256: `f9ab80bbc99131fae9686f49cc43b020fbb655bb95814d5ebf9fe2fd28fb8e7a`.
- Kernel: 206968 bytes, gzip 65806 bytes.
- Vendor archive SHA256: `4c5c7daf3fdf4d7195e4f5b750193babff571e9a44a6ff2161e8d18583c3552f`.

## Provedené ověření

- `node web_client/scripts/run_db_tests.js database/tests/blueprint/layout_integration_test.sql database/tests/blueprint/copy_setup_test.sql`
  s explicitní loopback DATABASE_URL: oba testy PASS na finálních zdrojích.
- `canonical_layout_cutover_test.sql` a `setup_draft_integration_test.sql`
  přes psql s lokálním fixture_form: canonical gate PASS, setup finalize/replay,
  nové identity a rejected-finalize rollback PASS. První pokus spustit canonical
  test Node runnerem selhal na psql `:fixture_form`; opraven způsob spuštění,
  ne test nebo aplikační kód.
- `fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart --plain-name blueprint_layout_assets`:
  7 skutečně spuštěných testů PASS, včetně dependency priority/preset scope,
  hidden labels a SQL save/read/copy scene corpus.
- `node --test tests/components/blueprint_*.test.js` z web_client:
  19 testů PASS se skutečným novým vendor kernelem.
- `fvm dart analyze lib/components/blueprint/views/blueprint_layout_host.dart`:
  bez errors/warnings, 11 existujících stylistických info pro závorky mimo změněné řádky.
- Package `python3 tool/check_architecture.py --host <host-worktree>`:
  PASS, 275 production imports. `git diff --check`: PASS.

Při prvním lokálním použití celé SQL source migrace byl nutný správný
extension-owning migration role; následně byla opravena PL/pgSQL CASE závorka a
syntetické font ID/metadata podle skutečných table constraints. Finální migrace
prošla transakčně (`psql -1 -v ON_ERROR_STOP=1`).

## Dosud neprovedeno

Vlny 2-7 v autoritativním plánu zůstávají otevřené: model/schema 2 a importer,
jednotný resolver s leaf reset/provenance, fyzika/placement/grid, atomický host
prepare/history a TX2, product assignment mode, captured async save/glyph subsets,
UTF-8 budgety, migrační corpus, uložené UI journeys a výkonové měření, archive gate
pro celý konečný kontrakt. Nový host font collector je současná schema-1 hranice;
ve vlně 2/5 se má převést na cílového core resolver/collector ownera, nikoli
ponechat jako nezávislý paralelní runtime formát.

Nebylo provedeno kompletní browser E2E, celé package archive_check ani produkční
inventář. Produkční převod, rollout, commit/push nejsou tímto zadáním autorizovány.

## Opakovaná architektonická kontrola

Na žádost uživatele byla znovu posouzena současná implementace proti plánu.
Závěr: architektura zatím není uzavřená a ani první vlna nemá úplnou exit bránu.
Předchozí formulace o dokončené první vlně byla příliš široká a je výše opravena.
Následující nálezy nejsou tvrzením o změněných produkčních záznamech.

1. **P1 - SQL/core admission se rozchází na override maskách.**
   Na kopii skutečného syntetického SQL readbacku byl u uzlu C nastaven
   `appearanceOverrides:["fontId","fontId"]`. Přímé volání
   `validate_blueprint_layout_internal` prošlo, ale skutečný vendor kernel 0.2.3
   vrátil `nodes.appearanceOverrides: invalid_appearance_overrides`.
   SQL nemá odpovídající validaci typu, whitelistu a unikátnosti masky.
   Byla ověřena tato validační hranice, nikoliv celý nový business save request.
2. **P1 - Chybí glyph coverage odvozených capacity labels.**
   Do stejného corpus dokumentu byl přidán furniture parent a první dvě židle
   dostaly tohoto parenta. Jedna atomic selection unit obsahovala tyto dvě
   židle. `kernel.validate` vrátil prázdné issues a SQL validátor také prošel.
   `kernel.compileScene` nad načtenými SQL resources ale vrátil
   `glyph_unavailable`, glyph `×`, na furniture parentu. Renderer odvozuje badge
   `×2`, zatímco SQL collector prochází pouze authored text/label. Host přidává
   číslice/× samostatně, takže nejde o jednotnou sémantiku všech tří cest.
3. **P2 - Jediný resolver/kontraktový owner dosud neexistuje.**
   Host helper, SQL font priorita a pravidla textu/scény zůstávají samostatnými
   implementacemi. Nová SQL appearance validace ručně opakuje whitelist/ranges.
   To je mezistav vlny 1, nikoliv finální architektura kontraktu 2. Generovaná
   metadata a core collector z plánu zůstávají nutné.
4. **P1 - Transakční a obchodní problémy z původního auditu zůstávají.**
   Package undo/redo znovu kontroluje pouze core protected-seat geometrii a poté
   restore obnovuje host binding checkpoint bez přípravy proti aktuální live
   autoritě. Host applyGroupsProduct stále odvozuje dědění rovností product ID.
   Potvrzeno čtením stejných nezměněných cest; nová TX2 regrese nebyla spuštěna.
5. **P2 - Dosavadní parity evidence má užší význam.**
   Flutter/JS testy oba kontrolují nulové issues, label B/C a neprázdné paths.
   Neporovnávají vzájemně celé paths po kvantizaci, selection units ani transformace.
   Corpus je uložený syntetický readback; běžný JS/Flutter test jej znovu přes SQL
   negeneruje. Neprokazuje ani uložený browser close/reopen journey nebo PF brány.

Diagnostika běžela z host checkoutu přes Node `pg`, jen proti dříve ověřenému
loopback disposable markeru. Každý běh provedl BEGIN, assertions helper a existující
layout integration test pro přípravu fontů/corpus, následně diagnostické volání,
a v finally ROLLBACK. První pokus navíc obsahoval masku `[42]`; ta kvůli ztrátě
fontId override skončila na glyph guardu a zabránila dokončení badge části téhož
běhu. Badge diagnostika proto proběhla zvlášť a dokončila se výše uvedeným výsledkem.
Aplikační kód ani databázové migrace se při této kontrole neměnily.

Další pořadí: nejprve doplnit tyto dvě regrese první vlny, poté pokračovat
kontraktem 2 a zbývajícími vlnami. Neřešit duplicity dalším paralelním fontovým
frameworkem nebo deklarovat architekturu za hotovou jen podle passing smoke corpus.
