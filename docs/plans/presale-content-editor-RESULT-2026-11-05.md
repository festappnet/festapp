# Stránka před otevřením: implementace a provozní brána

Datum: 2026-11-05. Zdroj: čistý worktree `implement/presale-content-20261105`
z `origin/main` na `7b852b297bca56b4b87e266d3f056b4369576e19`.
Pracovní kopie `/Users/miakh/source/festapp` zůstala nedotčená.
Produkční data, publikace zdroje a release nebyly provedeny.

## Dosažený kontrakt

- Samostatná část **Stránka před otevřením** používá skutečný veřejný Flutter
  renderer. Vzhled a obsah jsou ve výchozím stavu sbalené. Otevření ani zavření
  úprav nemění dokument, příznaky, historii nebo dirty stav.
- Jediný aktivní dokument zůstává `schedule.countdown_title`, v doméně
  `presaleContent`. Jediný parent Save používá stávající mediálního vlastníka,
  verze formuláře/produktů a identitu příkazu. Menu upozornění vede na stejný
  draft místo druhého dialogu s Použít změny.
- Explicitní aktivace zachovává text, obrázky a pozici existujícího e-mailu;
  blok nevkládá podruhé a neotevírá úpravy. Odstranění, Cut a klávesové mazání
  sdílejí s textem nativní historii HTML engine a pozastaví nový sběr. Obnova
  vrací přesnou předchozí pozici i stav. Vložená inertní značka sama sběr nezapne.
- Hlavička čte název vlastní akce s náhradou názvem formuláře a termín ze
  stávajícího rozvrhu. Nové formuláře mají `event_and_date`. Web i Flutter
  přijmou v BEFORE_START také prázdný dokument s pouhou hlavičkou; bez
  smysluplného obsahu a bez hlavičky zobrazí lokalizovaný termín.
- Archiv je mimo veřejná metadata, bez přímých grantů API rolím. Čtení vyžaduje
  živé `can_author_forms`; obnova dříve skrytého textu je výslovná draftová
  editace. Její staré funkční značky zůstávají inertní.

Odstraněny jsou druhý editor, aktivní modelové gettery druhého dokumentu,
veřejné připojování `before_start_message` v obou klientech a jeho aktuální MCP
writer. `CountdownContent`/`countdown_content.dart` nahrazuje `PresaleContent`;
`CountdownWidget` nadále vlastní samotný timer. Historické názvy druhých polí
zůstávají pouze v archivu, převodní/legacy ingress hranici, dokumentaci a
migračních testech. Nevznikl nový HTML wire klíč, seznam bloků ani aplikační trigger.

## Konkrétní implementační zjištění

Použitý SuperEditor dev.52 přes svůj deklarovaný kontrakt nemaže redo future po
nové editaci. Obecný controller proto ohradí vysloužilé identity jeho vlastních
transakcí. Nevzniká druhá historie. Regrese ověřuje Undo, novou textovou editaci a
odmítnutí starého Redo.

Null historického titulku při implicitním odpočtu používá pojmenovaný systémový
odstavec s tenantovým lokalizovaným fallbackem. Současné renderery jej lokalizují
podle návštěvníka. Již vydaný reader zobrazí fallback v jazyce zadaném při převodu;
bez znalosti nové značky nemůže dynamicky přeložit část již neprázdného dokumentu.
Úmyslně prázdný titulek systémový odstavec nedostává. Vědomá editace textu nebo
formátování systémového odstavce jej převede na vlastní obsah; Undo obnoví
lokalizovanou systémovou značku. Timer je materializován před
vedlejší obsah, ne až za spojený dokument.

Stávající test HTML bezpečnosti očekával odstranění neškodné barvy, zatímco
kanonický kontrakt readeru uložené formátování zachovává. Opraveno bylo pouze toto
zastaralé očekávání; sanitizer, kontrola URL a zákaz aktivních HTML prvků zůstaly
beze změny.

## Ověření

- 5 modelových testů `packages/festapp_core/test/forms/form_definition_test.dart`.
- 71 Flutter testů v `presale_content_test.dart`,
  `sale_opening_notifications_test.dart`, `html_editor_document_cases.dart` a
  `form_html_content_cases.dart`, vždy `--concurrency=1`. Pokrývají i skutečný Cut,
  range deletion, textovou historii, nezapisující otevření, media-save a společné
  renderovací fixture.
- 102 webových testů presale, upozornění, dostupnosti, překladů a sanitizace,
  včetně 19 testů čistého převodníku a historických metadata arrays. Společná data: `shared/presale/render-cases.json`.
- Skutečný PostgreSQL test `database/tests/presale_content/conversion_test.sql`:
  převod, soukromý archiv, retry, změněná identita, rollback velikosti/verze,
  aktuální i instalovaný writer, reset designu, oprávnění, UTF-8 a velikost
  transportu včetně původních version maps.
- 14 skutečných MCP/PostgreSQL settings testů v označené lokální databázi na
  portu 61032; migrace byla aplikována standardním lokálním upgradem a finální
  SQL při doplnění kontrol znovu aplikováno na tentýž lokální cíl.
- Cílený Dart analyzér bez chyb v upravených cestách. V `form_page.dart` zůstávají
  dřívější varování pro duplicitní import a nefinalizované `formLink`.
- `docs:generate` a `docs:check` úspěšné, generovaná MCP reference je aktuální.
- Skutečný Flutter web build QA fixture a izolovaný headless browser: 375 a
  1280 px, light/dark, sbalené úpravy, nezměněný dirty stav při otevření/zavření,
  opakované zapnutí, jeden e-mailový blok a parent Save. Snímky jsou v
  `/tmp/presale-browser-evidence/`. Text/Undo/Redo jsou doložené Flutter testy;
  jejich ovládání přes browser canvas nebylo spolehlivé. Samostatná QA fixture
  ponechala HTML splash plné aplikace, který byl odstraněn pouze v testovacím DOM.
  Browser i dočasný HTTP server jsou ukončené. HTTP vyžadoval Flutter engine a
  jeho moduly; nešlo o statický návrhový HTML preview.

Databáze 55432 byla pro první rollback SQL testy použitelná, ale její standardní
upgrade zastavil starší neprovedený cutover plánků na
`blueprints_canonical_layout_check`. Nebyla resetována ani nebyla obcházena
migrační podmínka. Finální SQL/MCP kontroly používají již migrovanou označenou
lokální databázi 61032; naplánované externí úlohy jsou vypnuté a e-mail pozastavený.

## Připravený produkční postup - zatím neautorizovaný

Toto zadání nejmenuje produkčního tenanta ani nepovoluje datovou migraci nebo
nasazení. Živá inventura proto nebyla prováděna a lokální fixture nejsou dokladem
velikostí skutečných formulářů. Zbývající datová brána je agregovaný preflight
celé výslovně schválené organizace a následný počet pending/blocked = 0.

1. Vybrat autorizovaného tenanta, ověřit jeho canonical activation a vazbu na
   skutečnou organizaci podle `docs/architecture/ai_context.md`. Zachovat zálohu,
   release CI a drift gates. Tento lokální výsledek není release attestation.
2. Nejprve nasadit pouze připravenou backend migraci
   `supabase/migrations/20261105170000_presale_content.sql` přes platný produkční
   workflow. Neobsahuje automatický převod dat. Zpřístupní archiv, recovery,
   ochranu starých writerů a kanonický kontrakt hlavičky. Staré nebezpečné editace
   se od této chvíle odmítají místo přepsání dat.
3. Z `web_client` spustit pod schváleným databázovým přístupem read-only preflight:

   ```sh
   node scripts/presale_content_preflight.mjs --organization ORGANIZATION_ID --actor AUTHORIZED_AUTHOR_UUID --locale cs
   ```

   `DATABASE_URL` patří jen autorizovanému kanonickému cíli; nevypisovat ji do
   evidence. Jazyk volit výslovně podle tenanta. Skript vrací pouze počty,
   maximální velikosti a ID blokovaných formulářů. Kontroluje celou organizaci,
   ne jen náhodnou podmnožinu práv. Používá stejný SQL byte-budget jako převod,
   skutečný authoring snapshot a původní product/type version maps v transportu.
4. Pokud je cokoli blokované, zastavit. Limity pole 65 536 znaků, patch 128 KiB,
   authoring snapshot 1 MiB a stávající MCP transport zůstávají zachované.
   Kontrola navíc nechává konzervativní rezervu 1024 bajtů. Nic se netruncuje,
   nevynechává ani nezveřejňuje z archivu.
5. Teprve při výslovném oprávnění k převodu zopakovat stejný příkaz s `--apply`.
   Bezpečný preflight je součástí této transakce znovu. Každý formulář se převádí
   pod vlastním existujícím parent lockem a původní verzí; archiv a změna tvoří
   jednu transakci. Identita retry je v privátním archivu. Stav kampaně, kontakty
   ani e-mailová fronta se nemění.
6. Read-only příkaz musí po převodu ukázat `pendingForms: 0`, bez blokovaných
   formulářů. Ověřit skutečný veřejný bundle a nepřítomnost archivních dat.
   Teprve potom nasadit nové veřejné klienty a současné UI pro tohoto tenanta.
   Deployment a live probes delegovat podle AGENTS.md.

Při nejasném výsledku commitu nejprve ověřit pending počty a soukromé konverzní
identity; neopakovat převod slepě. Před commitem se každá SQL chyba vrátí celá.
Po commitu se recovery provádí vědomou verzovanou editací v rozšířeném editoru a
běžným Save, nikoli obnovením staré full-metadata kopie. Rollback nesmí zrušit
writer guards, zveřejnit archiv ani vrátit dvě aktivní autorské/renderovací cesty.
