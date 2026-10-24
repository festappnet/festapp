# Oprava doručení objednávky - lokální ověření 2026-10-24

Vlny 1-3 jsou implementované v `fix/notification-production-theme-20261024` nad výchozím HEAD `76b7e7afd`. Vlny 0 a 4 se neprováděly. Žádný push, produkční SQL ani zákaznický transport.

## Změna

Přesný autorizovaný cíl upozornění vede na objednávku a její zdrojovou zprávu. Řádek se posune a krátce zvýrazní bez změny checkboxů; skrytý řádek lze výslovně odkrýt v dialogu. Oba vstupy používají `OrderEmailRepairDialog` v existujícím shellu. Vlastník obrazovky předává autorizovaný rozsah, protože řádková projekce nenese occasion. Zavření spotřebuje jen vlastní cíle a chrání ostatní query hodnoty.

`repair_order_email_client_sync_v1` ve stejné transakci kontroluje práva, souběh, kontakt, stav a platební podklady, aktualizuje existující kontaktní/formulářovou projekci a případně enqueueuje jeden navázaný záměr. Používá stávající receipts, historii, registry a worker wake. Nejasný send permit a suppression nelze obejít. Předpřipravené staré kontakty se vyřadí, probíhající snapshot a historické důkazy zůstanou zachované. Platba, cena, zásoby a identita vstupenek se opravou nemění.

Souhrn přidává `current_issues`, ponechává stará pole a odděluje aktuální problém od historie. Řetěz se vyřeší až relevantním delivery; accepted/open samy nestačí. Novější bounce jej znovu otevře, starší bounce nepřepíše novější doručení. Storno je informace o zrušení, nikoli doručení nebo refund. Původní zákaznický odkaz zůstává zachovaný; při odlišném kontaktu odvozené objednávky se odkaz na společný přehled vynechá.

Jediná aditivní migrace: `20261024120000_order_email_recovery.sql`. Obsahuje přesné kanonické SQL vlastníky; žádný backfill, automatický resend, aplikační trigger ani globální čítač.

## Provedené kontroly

- SQL přes `node web_client/scripts/run_db_tests.js`: `database/tests/emails/order_email_recovery_test.sql`, `canonical_email_queue_test.sql`, `order_ticket_intents_test.sql` a `database/tests/notification_center/email_sources_test.sql`. Nenulový výběr a skutečné assertiony. ACL, cizí zpráva, replay/jiný payload/odebraná práva, konflikty, atomický rollback enqueue, wake failure, suppression, původní i navázané doručovací důkazy, staré/duplicitní události, aktuální souhrn a nezměněné finance/vstupenky.
- `node --test database/tests/emails/order_email_recovery_concurrency.test.mjs`: 7 prošlých scénářů. Dvojklik pro potvrzení i vstupenky, replay po commitu, závod s platbou, zrušením, odstraněním pole, skutečným `begin_email_send` a změnou splatnosti bez zvýšení existující verze.
- Flutter vždy sériově s `--concurrency=1`: dotčené command, email delivery, notification, projection, grid, width a nové dialog/navigation testy. Závěrečný běh command/dialog/grid/width měl 34 testů; finální vlastnický dialog má 11 případů a navigace 1. Pokryté jsou čtecí/zápisové akce, timeout se stejnou identitou, konfliktní reload, pozdní odpověď po zavření, stavové varianty, blokování příjemce a oba `ThemeConfig` motivy na 320 px při 200 % textu. Navigace zkouší dvě obrazovky, opakovaný cíl a zachování filtrů.
- Cílené `fvm dart analyze` nad změněnými vlastníky a testy: bez chyb a varování; zůstávají informativní lint hlášky. `git diff --check` a unikátnost časových značek migrací ověřené.
- Deno: `orderEmailOverview_test.ts` a `customerOrderAccess_test.ts`, 6 testů. Původní testy jsou zachované; nový případ ověřuje změnu kontaktu bez přepsání historického šifrovaného zdroje a odmítá jinou objednávku.

## Izolovaná integrace

Postup `festapp-local-e2e`, projekt `festapp-order-email-e2e-20261024`, lokální API 56521 / DB 56522 a Flutter 56531. Syntetický tenant z `test/fixtures/navigation/tenant.sql`, rezervované veřejné linky a `database/tests/emails/order_email_recovery_e2e_fixture.sql`. Fronta má `worker_url=NULL`, cron je vypnutý. `agent-browser` běžel headless v odděleném profilu s blokovanými produkčními službami.

Skutečné UI otevřelo přesné ID/symbol, opravilo kontakt jedním RPC a zobrazilo čekající navázaný záměr. `order_email_recovery_transport.ts` použil skutečný renderer, šifrování, `prepare_email`, `begin_email_send` a `sendEmailAttempt`; pouze finální transport byl falešný a povolená síť byla omezená na loopback. Replay send permitu způsobil právě jedno falešné odeslání. Delivery odstranilo varování, pozdní bounce jej obnovilo. Druhá oprava ověřila již existující historický zákaznický odkaz. Zavření odstranilo oba vlastní query cíle, checkbox zůstal nezvolený a varování u stavu znovu otevřelo stejný dialog.

Vlastní browser, Flutter a Supabase projekt byly ukončené. Provozní klíče nejsou součástí artefaktů.

## Neověřené hranice

Produkční ACL/migrace, skutečné doručování poskytovatele a nasazení nebyly provedené. Integrační UI cesta používala bezplatnou objednávku a falešný transport; živý Stripe/Fakturoid a placené QR/PDF vykreslení tím nejsou prokázané. SQL testy samostatně ověřují zachování existující nenulové platby/ceny a identity vstupenek.
