# Osobní přehled objednávky - lokální realizace

Stav 2026-10-15: implementováno a cíleně ověřeno, bez commitu, push, produkční migrace a deploye. Verification: standard.
Autoritativní zadání: [follow-up plán](order-overview-waitlist-follow-up-plan-2026-10-13.md).

## Ověřený výchozí kontrakt a úpravy plánu

Aktuální kapacita používá pouze `eshop.tickets`, `order_product_ticket`, offer slots a `source_waitlist_order_id`. Registrace i partial/full přijetí jsou hotové. Nepřidává se person ledger, nové ticket ID při přijetí ani druhý finalizer. `people[].id` v přehledu je přímo ticket ID; příslušnost vychází z reálných vazeb. Historické partial children po abortu bez ticketů se zahrnou do výjimky pouze s odpovídajícím aborted recovery journalem. Ostatní chybné vazby čtení odmítají.

Schéma follow-upu vlastní samostatný `order_overview_schema.sql`, aby nebylo nutné regenerovat publikovanou kapacitní migraci. Nový scoped assembler `automation/assemble-order-overview-migration.py` sestavuje migraci `20261015170000_customer_order_overview.sql`; `--check` porovnává obsah. Původní assembler ani migrace 1900/2000 nebyly touto prací přepsány. Z email_queue se do nové migrace bere pouze dotčený `email_intent_valid`, nikoli ostatní souběžně upravované queue funkce.

## Výsledek

- Jedna stránka formuláře v JS i Flutteru zobrazí čekání, nabídky a samostatné výsledné objednávky. Aktivní nabídka pod souhrnem používá původní výběr osob, produkty a accept/decline. Manage ponechává původní potvrzené ukončení čekání. View samotné má jen refresh a navigaci; zákaznické storno nebylo přidáno.
- `get_customer_order_overview` vrací allowlist nad konzistentním STABLE snapshotem. Ověřuje přesný root, tenant/form/occasion, vlastnictví ticketů a accepted slots každého partial child. Vrací uložené objednané položky, nikoli dnešní katalogové ceny, a DISTINCT tickets bez QR/symbolů nebo skrytých odpovědí. Přehled respektuje ticket feature.
- SQL odděluje stav objednávky od evidované úhrady. Obsahuje zálohu, doplatek, termíny, přeplatek a samostatnou vratku. Nejednoznačné ruční potvrzení, chybějící finance či nesoulad měny mají `unknown` bez platebních instrukcí. `sent` není použití; obnovené čtení sleduje i administrátorské used -> paid.
- Samostatný 256bit `order_view` capability má hash v SQL a encrypted source mimo email retention. Expiruje max(90 dní po konci akce, 30 dní od vydání). Revokace/expirace platí i pro terminal read. `#order?...` je oddělené od write fragmentu `#waitlist?...`; bearer se neposílá v query, browser storage, sync feedu ani history.state.
- Registrace ukládá view source v téže transakci přes existující enqueue owner. Edge přidává URL až po durable receipt a při replay dešifruje původní uložený source. UI přechází přímo do stejného přehledu. Selhání doplňkového přehledu neoznačí registraci/přijetí za neúspěšné.
- `customer-order-access` umožní bootstrap pouze z aktivního manage/offer scope, pod root lockem. Dva skutečné souběžné požadavky vracely tutéž generaci. Dokončený manage, terminal/expired/revoked offer ani view samotné bootstrap neodemknou. Editor může explicitně reissue; SQL ověřuje editor práva, revokuje starou generaci a audituje příkaz. Opakování starého příkazu po expiry/cleanup neprodlužuje přístup.
- Editorovo nové doručení používá zděděnou šablonu `ORDER_OVERVIEW`, encrypted prepared snapshot a tutéž `email_messages` frontu s vypnutým trackingem. Retry nevytvoří druhý intent. Send-time predicate kontroluje aktuální view capability i pro stornovanou historii. Žádný nový sender ani přímé odeslání.
- Nové waitlist sources jsou v2. Immutable v1 zůstávají čitelné původním způsobem bez nového odkazu. U nových e-mailů renderer zachová dědičnost i existující proměnné a doplní odkaz, i když starší vlastní šablona neobsahuje novou proměnnou. Zdroje po expiraci čistí stávající bounded expiry job.

## Ověření

Vlastní disposable projekt `festapp-order-overview-20261015`, DB výhradně `127.0.0.1:59152`, API `127.0.0.1:59151`. Porty byly před přidělením ověřeny. Žádný produkční tunel ani převzatá DB nebyly použity. Inicializace: kanonický baseline `20260805230000`, 138 forward migrací, seed. Cron byl v tomto projektu deaktivován. Finální sestavená migrace prošla atomickou aplikací a assembler `--check` shodou. Finální SQL kontroly běžely na čistém syntetickém stavu, odděleně od browserových fixture s pevnými tokeny.

- SQL **7/7 PASS** přes `DATABASE_URL=<owned loopback DB> node web_client/scripts/run_db_tests.js` s explicitním seznamem: `customer_order_overview_test.sql`, `customer_order_access_test.sql`, `waitlist_capabilities_test.sql`, `waitlist_lifecycle_test.sql`, `waitlist_fakturoid_recovery_test.sql`, `waitlist_fakturoid_swap_recovery_test.sql`, `waitlist_email_queue_test.sql`.
- Nové SQL sady pokrývají read ACL, cross-tenant/root tampering, vazby partial/full, obnovu ticket stavu a více produktů, zálohy/část/full/free/vratku/přeplatek/unknown/EUR RF, uzavřený formulář, revokaci/expiry, odmítnutí write scope, bootstrap/reissue/replay/cleanup, gated redelivery a zděděné šablony. Chybějící end_time se simuluje pouze uvnitř rollback transakce dočasným uvolněním NOT NULL; kanonické schéma chybějící konec normálně nepřipustí.
- JS **69/69 PASS**: overview, waitlist_flow, order_result a router_service. Po poslední izolované úpravě keyboard focus dalších **5/5 overview PASS**. `npm run build` PASS.
- Flutter **29/29 PASS**: customer_order_overview, order_finish_screen, waitlist_runtime, waitlist_models, app_bootstrap a app_router_deep_link. Scoped analyze nemá errors; existující mutable-widget warnings a style infos v dotčených starších souborech zůstávají.
- Deno **13/13 PASS**: customerOrderAccess, orderOverviewEmail, waitlistEmail a waitlistEmailRenderer. `deno check` obou Edge entrypoints PASS. Použit syntetický AES klíč a lokální transport; skutečný provider nebyl volán.
- Překladový namespace `OrderOverview` je shodný mezi oběma klienty v cs/en/sk/de/pl/uk.

Při původním běhu JS regrese odhalila předexistující pořadí hydratace ticket DOM: update před vložením do seznamu byl ignorován guardem. Přesunutí hydratace za append zachovává hodnoty po přidání další osoby; 14 waitlist testů prošlo. Flutter skutečný průchod odhalil potřebu oznámit úspěšné zavření dialogu po dokončení route popu, aby se zavřel i preview. Regrese ověřuje právě jeden callback; následný skutečný návrat do přehledu prošel.

## Skutečný izolovaný UI průchod

Použity skills festapp-local-e2e a agent-browser, oddělené headless sessions, lokální Vite a skutečná Flutter aplikace s loopback defines. Externí notifikační callbacky byly stubované fixture, ne součástí ověření. Pro in-tab navigaci nebyl instalován CDP network hook; známý canonical produkční host byl blokován browser DNS pravidlem a aplikační backend byl lokální.

Ověřeno:

1. JS nová registrace po potvrzení přejde na view fragment a zobrazí tutéž přihlášku. Skutečný registration retry vrátí stejnou URL a jediný source; durable receipt neobsahuje raw view token.
2. Skupina dvou: partial acceptance druhého ticketu vytvoří child 100 Kč; čekající zbytek a child jsou ve stejném přehledu. Následující full remaining ponechá původní root a vytvoří jeho samostatnou platbu 100 Kč. Ticket ID a jména zůstala oddělená.
3. Flutter partial přijetí -> původní success -> tlačítko Přehled objednávky -> view URL, jedna přijatá osoba, jedna zbývající nabídka a možnost pokračovat z paměti. Reload view ztratí write scope a ponechá jen read. JS dokončil remaining na stejné root a ukázal původní success s platebním blokem nad dvěma kartami objednávek.
4. Skutečný JS view -> jiný view hash ve stejném tabu přenačetl jinou root bez starých osob. Reload obou klientů znovu četl přehled bez další acceptance. Preview a success zachovaly primární capability fragment, nikoli token v history.state.
5. Synteticky nastavené backendové platební skutečnosti `amount=1000`, `paid=300`, `deposit=300`, `order.state=paid` zobrazily zálohu a doplatek 700 v obou klientech. `used` se po refresh zobrazilo jako použitá vstupenka; následné `paid` znovu jako nepoužitá, bez slibu historického času použití. [Token-free readback](order-overview-waitlist-follow-up-evidence-2026-10-15/browser-readback.json).
6. Queue byla `paused=true`; počet provider send starts byl 0. Žádný skutečný e-mail se neposílal.

Vlastní browser sessions, Flutter/Vite/Edge procesy byly po smoke ukončeny. Ostatní browser okna a projekty zůstaly nedotčené.

## Oddělený repository gate

Doplňkový `automation/tests/hetzner_supabase_inventory.test.mjs` má mimo tuto implementaci blocker: existující souběžně přidaný `exchange-sign-in-code` není klasifikovaný v runtime writer policy. Přehled i jeho waitlist dependency jsou klasifikované. Tento nezávislý auth endpoint se zde nemění; celkový inventory gate proto není označen PASS. Před případným vydáním musí jeho vlastník doplnit klasifikaci a související celkové počty.

Produkční rollout nebyl autorizován. Případné vydání musí nejprve aplikovat backend/read ACL, Functions a producer, poté klienty pro samostatně zvolený tenant. Nové UI pro administrátorské reissue není součástí tohoto follow-upu; autorizovaný endpoint podporuje reissue a zařazení doručení do stávající fronty.

Následné upřesnění uživatele: při budoucím deployi zahrnout i všechny ostatní aktuální změny v checkoutu pro zvolený tenant. Před vydáním ověřit společný výsledný stav včetně výše uvedeného runtime inventory blockeru. Tímto upřesněním nebylo zahájeno nasazení.
