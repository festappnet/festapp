# Kapacita formuláře a náhradníci - implementační evidence

Autoritativní zadání: [plán](form-capacity-waitlist-plan-2026-10-13.md) a
[execution prompt](form-capacity-waitlist-EXECUTION-PROMPT-2026-10-13.md).
Ověřování: standard. Implementace vznikla v existujícím rozpracovaném checkoutu
`feat/occasion-setup-wizard-20261007`; cizí změny se zachovávají.
Původní implementace nepublikovala produkční změny. Uživatel následně
autorizoval commit/push, backend a web release pro `vstupenky.online` /
`prod/festapptickets`, včetně dalších připravených změn. Ostatní tenant klienti
se nepublikují.

## Izolované ověřování

- Vlastní disposable Supabase projekt: `festapp-waitlist-20261013`.
- API: `http://127.0.0.1:56521`; PostgreSQL: loopback port `56922`.
- Workdir: `/Users/miakh/.cache/festapp-waitlist-20261013`.
- Před inicializací ověřeny existující kontejnery a listenery. Host port `55432`
  vlastní SSH proces, proto se URL z obecného testovacího návodu nepoužívá.
- Obnova proběhla uvnitř vlastního DB kontejneru: baseline
  `20260805230000`, 130 forward migrací do `20261013170000` a `supabase/seed.sql`.
  Výsledek: úspěch. Jediná organizace je syntetická `Test Organization`;
  přítomen seed administrátor. Žádná produkční data ani reset jiného projektu.
- Flutter define soubor byl vytvořen privátně po ověření loopback API identity.
  Push SDK není součástí lokálního E2E; používá se existující real-app fixture.
- Oba joby obnovené baseline/migracemi (cleanup a email queue) byly ve vlastním
  projektu deaktivovány pomocí `cron.alter_job`. E-mailový provider se při
  ověřování nepouští; queue testy používají mock.

## Cílená evidence spotřebitelů

- `get_report_ws.sql`: dosavadní `valid_orders` přijímá vše kromě `storno`
  a NULL cena je anomálie. Pro waitlist musí být obě interpretace upraveny;
  náhradníci nejsou přijatí účastníci ani výnosy.
- `queue_payment_reminders.sql`: vybírá explicitně `ordered` nebo `paid`
  a vyžaduje vazbu na payment_info. Waitlisted objednávka bez platby není způsobilá.
- `order_grid_filters.dart`: dosavadní filtr historie/tickets zůstává samostatný;
  výchozí aktivní order filtr potřebuje serverovou projekci `isActive`.
- `check_order_is_mutable.sql` a doménoví callers potřebují explicitní guards
  pro regular operace a Fakturoid acceptance ve stavu `preparing`.

## Průběh

Vlny 1-6 implementovány. Backend implementoval GPT-6.1-Sol Medium, UI/UX
Astra Medium; e-maily a cílené backendové regrese samostatní implementační workeři.
Akceptační scénáře jsou ověřeny cílenými SQL, concurrency, Deno a klientskými testy
a skutečným izolovaným UI. Produkční rollout zůstává samostatný autorizovaný krok.

## Dosavadní cílené kontroly

- `deno check supabase/functions/waitlist-commands/index.ts`: PASS.
- `deno test --allow-env=EMAIL_PAYLOAD_KEY supabase/functions/_shared/waitlistEmail_test.ts`:
  PASS, 3 testy. Skutečný AES-GCM roundtrip, 256bit token, shoda hashů,
  absence plaintext tokenu v delivery DTO a kontrola tenant/recipient kontextu.
- Skutečný lokální Edge runtime: chybný POST na `waitlist-commands` vrací 400
  a hlavičky `Cache-Control: no-store` a `Referrer-Policy: no-referrer`.
- Lokální `email_capacity`: `worker_url` není nakonfigurován, `paused=true`.
  Edge běží pouze s nově vytvořeným lokálním šifrovacím klíčem a syntetickým
  odesílatelem, bez credentials e-mailového providera.


## Integrované ověření a hranice

- Finální migrace sestavena z kanonických SQL přes
  `automation/assemble-form-capacity-waitlist-migration.py` a úspěšně aplikována
  v jediné transakci do vlastního disposable projektu. V produkci neaplikována.
- [Backendové regrese](form-capacity-waitlist-evidence-2026-10-13/backend-regressions.md):
  6 nových SQL sad, 12 existujících SQL sad a 8 testů souběhu/backfill/templates PASS.
  Navíc cílený tenant-scope test `get_orders_tab_data_tenant_scope_test.sql` PASS.
- Fakturoid: dalších 6 SQL a 3 testy se samostatnými DB spojeními ověřily recovery
  po přijetí jiných osob, obnovu původních slotů a zachování mezitím změněného zbytku.
- Immutable historie registrace a full/split přijetí:
  `waitlist_history_snapshots_test.sql` PASS; původní odpovědi, stabilní person IDs,
  linked child a následné edits nerozbíjejí historický snapshot. Secret metadata
  se vyřazují. Po finálním sestavení ověřeny affected history/capability testy PASS.
- E-maily: 10 cílených Deno testů PASS (šifrování a renderer), Edge typechecks PASS.
  Skutečné queued confirmation/offer zdroje byly rozšifrovány a vyrenderovány přes
  lokální SQL context a zděděnou šablonu/wrapper. Provider nebyl volán.
- Flutter: cílené form editor/order filter/order permissions/model/runtime/startup
  testy PASS. Scoped analyze bez errors; existující style infos a mutable
  `FormPage.formLink` warning zůstávají. Startup sada 12 PASS včetně osobního fragmentu.
- Standalone klient: router 40, waitlist 8 a order result 6 cílených JS testů
  PASS; finální `npm run build` PASS. Overlay uchová osobní fragment v URL;
  změna capability hashe vytvoří nový form session přes reload. Poslední
  skutečný in-tab hashchange check nelze označit PASS: CDP network-controls
  instalace při app-triggered reload selhala (`Session with given id not found`).
  Tato změna je pokryta deterministickou regresí; cold open a fyzický reload
  osobních odkazů prošly ve skutečném browseru.
- Překlady waitlistu mají stejné keys i values mezi Flutter a web klientem pro
  cs/en/sk/de/pl/uk. Oba HTML entrypoints mají `no-referrer`.
- Skutečné Flutter UI: nastavení limitu 2/náhradníků/1h; běžná skupina 2, explicitní
  registrace skupiny 2 bez ceny a produktů, storno přijaté skupiny, návrh a potvrzení
  nabídky 2, zděděný preview a queued stav. Aktivní filtr/skupinový řádek fungují.
- Skutečný anonymní standalone web klient proti stejnému local API: nabídka
  předeplní Waiting One/Two, výběr jiné osoby vytvoří child při partial přijetí,
  obnovení odkazu ponechá Waiting One a full remaining zachová původní ID/symbol.
  Obě potvrzení vytvořila běžné objednávky 100 CZK. SQL potvrzuje 2 admitted osoby
  rozdělené mezi původní a linked child, žádné pending slots navíc.
- Anonymní standalone management: skutečná registrace Manage Person, renderer
  původního confirmation, otevření aktivního manage scope a individuální withdrawal
  prošly; osoba poté není waiting. Dokončený/revokovaný manage scope bezpečně
  odmítá přístup.
- Flutter URL strategie nadále dědí PathUrlStrategy; pouze `/form/...#waitlist?...`
  zahrne známý fragment do routy. Běžné anchors/auth fragmenty mají dosavadní
  chování. Skutečný browser reload běžného `/form/...#section` to ověřil.
  FormPage čte fragment ze scope aktuální AutoRoute routy; skutečný osobní
  odkaz po dokončení zobrazuje terminal Přijato a zachová fragment.
- Doručení reálného e-mailu není součástí lokálního ověření. Existující storno UI
  čeká na potvrzení doručení; při pozastaveném provideru může hlásit delivery error,
  zatímco SQL storno a kapacita už jsou korektně uloženy. Tato původní hranice nebyla měněna.

## Deletion ledger a produkční kroky

- Jediná waitlist identita je `eshop.orders`; osoby/nabídky jsou její evidence.
- Regular i offer caller používají `finalize_ticket_order_internal_v1`.
- Způsobilost order actions vychází z explicitního serverového kontraktu;
  náhradníci nemají produkty/platby/tickets a nepoužívají free-order paid větev.
- Všechny nové e-maily vstupují do `public.email_messages`, sdíleného rendereru
  a existujícího gated `process-email-queue`. Žádný nový sender ani fronta.
- Žádné business triggery, automatické nabídky nebo klientská autorita kapacity.
- Před produkční aktivací je nutná samostatná autorizace vybraného tenantu,
  kontrola backfill issues/counts, kompatibilní nasazení SQL/Edge/worker/klientů,
  konfigurace šifrovacího klíče stávající fronty a následná aktivace formuláře.
  Původní lokální předání neprovedlo commit, push, produkční migraci ani deploy;
  následná autorizace a release gate evidence jsou uvedeny níže.

Standalone evidence: [web-client-e2e.json](form-capacity-waitlist-evidence-2026-10-13/web-client-e2e.json).
Izolované browser sessions, Flutter, Vite, Edge runtime i vlastní Supabase projekt
byly po ověření ukončeny; ostatní projekty a uživatelův browser zůstaly nedotčené.


## Následně autorizovaný release kandidát

- Základ sjednocen s canonical main `643e8757ef176f16c649b69007a00520f867a20a`;
  původní rozpracovaný checkout zachován. Publikační kandidát obsahuje čistý diff
  proti main, žádnou historii privátního pracovního snapshotu ani provozní backupy.
- Nová migrace má unikátní version `20261013190000`; již publikovaná
  `20261013180000_allow_cancelled_order_deletion` zůstala beze změny.
- Backfill mění jen organizaci určenou explicitním
  `festapp.waitlist_backfill_organization`; bez nastavení nezapisuje žádný tenant.
  Produkční scope je 3, lokální synthetic scope 1. Celý finální SQL soubor prošel
  atomickou aplikací v jediné lokální transakci.
- Release sada po konkrétních integračních a fixture opravách: 162 SQL,
  311 web, 1247 Flutter a 299 Deno testů PASS; automatizační gates PASS.
  1 SDK fixture a 27 remote R2 integrací přeskočeno podle repository podmínek;
  tyto části nejsou označené PASS a nepoužily produkční credentials.
- Nově připravené potvrzování akcí v gridu, ticket usage a poslední změny
  produktového editoru ověřeny dalšími 105 cílenými testy PASS; analyze bez errors.
- Nový waitlist endpoint je zahrnut v canonical runtime policy a coverage:
  31 produkčních Functions, žádná neznámá ani nepokrytá. Existing encrypted queue
  key je na runtime přítomen; žádný nový provider/sender se nezavádí.
- Před produkční změnou připravena a ověřena čerstvá šifrovaná off-host záloha.
  Produkční aplikace bude vycházet z přesného publikovaného main SHA a canonical
  overlay pouze vybraného tenantu. Deploy stav se ověřuje podle konkrétního workflow
  SHA/verze, nikoli podle samotného push nebo HTTP 200.


### Skutečný integrovaný UI smoke a jediná kanonická cesta

- Finální standalone klient: běžná objednávka, čekající skupina bez financí,
  editorovo storno a ručně potvrzená nabídka, partial přijetí druhé osoby,
  fyzický reload a full remaining se zachováním původního symbolu, aktivní manage
  read a individuální withdrawal PASS. Editor ticket usage potvrzení: cancel
  nezmění data; confirm změní jen zvolenou vstupenku; reverse provedeno jednou.
- UI smoke našel skutečný transportní nesoulad, opravený před publikací:
  `normalize_form_participant_answers_internal` ověří scoped field ID/type a
  převádí starší typed+`_subFieldId` i současný numeric vstup. Osobní ledger a DTO
  používají pouze stabilní IDs přes společný `extract_participant_answers_internal`.
  Pomocný klientský `price` hint se zahodí; produkt a cenu ověřuje server.
- Běžný a nabídnutý prodej používají jediný `finalize_ticket_order_internal_v1`.
  Registrace nemá druhý prodejní engine; čekající osoby se jen uloží do existující
  order identity. Renderer a provider používají jedinou canonical email queue.
  Nebyl přidán alternativní finalizer, druhá fronta, dual pricing ani generic fallback.
- Intencionální boundary: starší běžící web/native klienti používají published
  transport s typed field names. Mechanický vstupní adaptér lze odstranit až po
  jejich aktualizaci a ověření nulového používání starého payloadu. Tento release
  aktualizuje jeden tenant klienta a nesmí ostatním rozbít prodej. Starý formát
  objednávkových snapshotů zůstává historickým vstupem existujících spotřebitelů,
  nikoli druhou business cestou.
- Nové regresní soubory `legacy_ticket_field_transport_test.sql` a
  `waitlist_personal_answer_projection_test.sql` PASS: legacy/modern shoda,
  alias/metadata absence v osobní projekci, scoped product a ignorování falešné ceny,
  full/partial konverze. Dotčené regular/free/deposit/history/Fakturoid sady PASS.
  Finální JS waitlist 9, session 9 a build PASS; finální SQL prošlo atomickou aplikací.
- Provider delivery byl pozastaven. Původní storno UI může po committed SQL hlásit
  delivery boundary error, protože čeká na provider acknowledgment; toto chování
  se neměnilo. Skutečné zákaznické e-maily se při QA nerozesílaly.
