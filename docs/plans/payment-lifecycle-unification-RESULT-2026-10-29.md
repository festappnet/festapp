# Realizace sjednocení platebního životního cyklu

Datum: 2026-10-29
Výchozí zdroj: `main`, HEAD `42977b39e`
Ověřování: `standard`
Stav: implementace a lokální brány dokončeny; publikace na `main` podle navazujícího pověření. Produkce a backfill neprovedeny.

Společný `reconcile_order_payment_internal_v1(bigint,text)` nyní rozhoduje pro
bankovní fakta i skutečné produktové změny. Používá uloženou zálohu omezenou
aktuální cenou, zachovává bezplatnost, chráněné vstupenky a provider hranici.
Původní recalculate zůstává adaptérem; product edit již nemá svůj finanční
CASE ani jednostranný UPDATE vstupenek. Nový helper nezapisuje historii.
Version bump proběhne jednou: při promotion jej vlastní původní paid primitive,
v ostatních účinných změnách společný owner. Ruční mark-paid neposílá email.

Pairing drží původní transaction lock (nutný také pro matcher/ingest), potom
zamyká všechny uložené původní a cílové form/order scopes a oba payment rows
v deterministickém pořadí před platebními zápisy. Po acquisition znovu kontroluje
uložené order/form/payment vazby; jejich změna vyvolá retryable `40001`.
Souběh prokazuje oba směry pairing/edit, oba směry unpair/edit, cancellation,
stale acceptance a přesun platby mezi dvěma formuláři. Deadlock ani timeout
nejsou považovány za úspěch.

## Finální brány

| Brána | Výsledek nad finálními vstupy |
|---|---|
| Fresh baseline + všechny forward migrace včetně nové | 29 SQL souborů prošlo, 0 selhalo |
| Fresh concurrency | 7 scénářů prošlo, 0 selhalo, 0 skipů |
| Upgrade z `20261029180000` přes standardní migration engine | Aplikována pouze `20261029190000` |
| Upgrade: existující ordered/paid/sent/deposit fixtures | 4 kompletní snapshoty order/payment/tickets/OPT/history/emails beze změn |
| Upgrade: stejná SQL sada | 29 souborů prošlo, 0 selhalo |
| Upgrade concurrency | 7 scénářů prošlo, 0 selhalo, 0 skipů |
| BankSync webhook `handler_test.ts` | 4 testy prošly, 0 selhalo |
| Migrační assembler `--check`, baseline manifest, `git diff --check` | Prošlo |
| Helper ACL po upgrade | anon/authenticated nemohou EXECUTE; postgres/service_role mohou |

Jde o **29 unikátních SQL souborů + 7 souběhových scénářů + 4 Edge testy**;
fresh a upgrade představují dvě instalační cesty, ne další unikátní testy.
SQL sada obsahuje původních 15 navazujících souborů, 5 lifecycle souborů a
9 BankSync souborů. Nová matrix má 8 scénářových DO bloků.

Před instalací opravy byly zachyceny tři původní regrese a další capped-deposit
nekonzistence. Tři původní charakterizační soubory prošly. Během integrace byly
opraveny výhradně chybné předpoklady nových fixtures/harnessu: blueprint seat
vazba, nullable paid, service claim pro interní email validation, expired pouze
na order, validní Stripe account ID, JSON parametr a načasování PID/version
měření. Původní tři stavová očekávání nebyla oslabena. Finální zbývající
selhání: **0**.

Provider acceptance i vynucené selhání enqueue jsou označené test doubles;
skutečný emailový provider nebyl volán. Neproběhl Flutter/web build.

## Reprodukce a izolace

Vývoj/fresh použily vlastní `festapp-payment-exec-20261029`, loopback port 57652.
Upgrade měl samostatný `festapp-payment-upgrade-20261029`, port 57662,
bootstrappovaný z archivovaného předchozího HEAD a jeho migračního ledgeru.
Obě instance měly cron disabled, email capacity paused a worker_url NULL.
Upgrade s předem uloženými fixtures nepoužil instalaci snapshotu přes existující
data. SQL runner a concurrency harness běžely vždy postupně, nikdy současně
nad stejnou DB. Vlastní instance byly po dokončení odstraněny; cizí instance
nebyly obnoveny, zastaveny ani měněny.

SQL výběr (explicitní `DATABASE_URL` na vlastní disposable loopback DB):

```sh
DATABASE_URL='<vlastní disposable URL>' pnpm --dir web_client exec node scripts/run_db_tests.js \
 database/tests/eshop_orders/payment_lifecycle_ \
 database/tests/eshop_orders/payment_product_transition_regression_test.sql \
 database/tests/eshop/deposit/ \
 database/tests/eshop/orders/update_ticket_products_ws_test.sql \
 database/tests/eshop/orders/cancelled_order_read_only_test.sql \
 database/tests/eshop/transactions/payment_pairing_contract_test.sql \
 database/tests/eshop_orders/orders_history_bundle_test.sql \
 database/tests/eshop_orders/customer_order_overview_test.sql \
 database/tests/eshop_orders/customer_order_access_test.sql \
 database/tests/emails/order_ticket_intents_test.sql \
 database/tests/eshop/stripe/payment_totals_test.sql \
 database/tests/eshop/stripe/admission_test.sql \
 database/tests/eshop/transactions/bank_sync_
DATABASE_URL='<vlastní disposable URL>' pnpm --dir web_client exec node --test ../database/tests/eshop/payment_product_transition_concurrency.test.mjs
```

Webhook a parity:

```sh
deno test --frozen --lock=supabase/functions/deno.lock --allow-env --allow-net --allow-read supabase/functions/bank-sync-webhook/handler_test.ts
python3 automation/assemble-payment-lifecycle-migration.py --output supabase/migrations/20261029190000_payment_lifecycle_unification.sql --check
python3 automation/baseline.py check
```

Lokální běhové logy zůstaly v `/tmp/festapp-payment-*`:
`fresh-tests.log`, `fresh-concurrency.log`, `upgrade-tests2.log`,
`upgrade-concurrency2.log`, `upgrade-verify2.log`, `upgrade-apply2.log`,
`edge.log` a příslušné bootstrap logy. Jsou to dočasné lokální artefakty.

## Zmrazené vstupy (SHA-256)

```text
82afbdb01ed514e43a82163b738e6ff79b4234346c25f4f0b52ec692db8a31d4  database/functions/eshop_orders/recalculate_order_payment_status.sql
f4ff2e0de62148c082726a87fce450dd1e6ab388c1097f0f870a3d7cff9598ac  database/functions/eshop_orders/update_ticket_products_ws.sql
7c3ac4d099eed2944790e38126c796e328916abf35b994878678ad4bf238b9b2  database/functions/eshop_transactions/apply_transaction_pairing.sql
67c088ab3bb6f578654cbe78a46e9db55f6e91cbc4d419907f1e963fa2013b32  automation/assemble-payment-lifecycle-migration.py
648c00bff71caec1bb57887fbb6aedbcbf01fed5ac373743d2ac0c7cbba61fe2  supabase/migrations/20261029190000_payment_lifecycle_unification.sql
a2dd65d03b5f5686904fed39a081e0cd8386c3187b082b7ba102169067735054  database/tests/helpers/payment_lifecycle_fixture.sql
30bbb48feea46ba8038945fe7be2c38b993f9644b8055dc8f00db2c008ef9a0f  database/tests/eshop_orders/payment_lifecycle_atomicity_test.sql
1b9477ca65a835e2a23efcbbf8268519b8470a47138aa293fef991bc2d80eb7a  database/tests/eshop_orders/payment_lifecycle_boundaries_test.sql
ce9ffe1ad117ecde7b418d40567abe620931aad342da735990fb45749bfb73ae  database/tests/eshop_orders/payment_lifecycle_history_test.sql
d3c9a2d71887c1fe2d73a72cb2db81f8622ea6efafda504d0c946f9714e471c2  database/tests/eshop_orders/payment_lifecycle_matrix_test.sql
3410c934e03a7836da60cc248f75f01da83de7687c500a8d1531f7b8a13e99c6  database/tests/eshop_orders/payment_product_transition_regression_test.sql
801ad153c65f560b859f980764d38b33694472228e584084642c5939f1aa63ec  database/tests/eshop/payment_product_transition_concurrency.test.mjs
7d4420181628b5fa6d0be80348a2a7bb5ddc55ab1df793e10d07d36dcfc9ad0f  automation/ci/checks.json
3a54ab5fc2e781305421025e12e0d1f6438a571aa66621dd29a4ec3d76e186ce  web_client/scripts/run_db_tests.js
```

## Neprovedená produkční část

Migrace `20261029190000_payment_lifecycle_unification.sql` je pouze připravená
v repozitáři. Nebyla aplikována do produkce, žádný tenant nebyl nasazen,
žádná historická objednávka nebyla přepočtena. Uživatel následně pověřil
dokončením práce včetně commitu a publikace na `main`; tento krok nemění
produkční databázi. Produkční instalace, activation/migration drift, rollback artefakt,
email health a provozní kontroly vyžadují samostatné pověření podle plánu.
Lokální důkazy nepotvrzují aktuální produkční definice.
