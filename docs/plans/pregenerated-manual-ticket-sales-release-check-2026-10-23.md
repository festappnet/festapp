# Plný release check předgenerovaných vstupenek

Stav: **release zastaven, plná sada není zelená**. Žádná produkční migrace,
Edge instalace, commit/push na main/prod ani produkční build nebyly provedeny.
Současná produkce není tímto checkem změněna.

## Ověřený kandidát

- Čistý pracovní strom: `/private/tmp/festapp-ticket-batches-release-20261023`.
- Větev: `feat/ticket-batches-release-20261023`.
- Testovaný commit: `5cebae636ea1cdb805e9db72e648dfa0d5e6eb76`.
- Base main: `5ab9af9fc12a9272adbb164158add00954f23fb6`.
- Srovnávací čistý main: `c83df930c` (stejné SQL, navíc samostatná oprava bootstrapu).
- Cíl případného budoucího vydání: pouze `prod/festapptickets`, organizace 3,
  `vstupenky.online`. Poslední koordinovaná živá verze: `0.20.370+867`.

Přenos respektuje aktuální canonical main: autorství plánku používá
`save_blueprint_layout_impl_internal`, inventory změny současné privátní owners,
capabilities existující `get_order_allowed_actions_internal_v1`, permissions
současné operation capabilities a transport aktuální kontrolu mutation identity.
Notifikační hooks zůstaly zachovány. Staré drafty s kolidujícími timestamps se
nepřenášejí. Jediná nová migrace je
`20261024020000_pregenerated_ticket_batches.sql`, včetně PDF/ZIP exportu.

## Celá sada

Spuštěno `automation/test_all.sh` se všemi šesti lanes, jedním Flutter workerem,
vlastní DB na localhost:57832 a oddělenou payment-reference template databází.
Celý wrapper doběhl (230 s), nikoli jen cílené testy.

| Lane | Výsledek | Důkaz / hranice |
| --- | --- | --- |
| Web | FAIL | 9 RPC kontrol nemělo dostupnou lokální REST API; další dva DB-backed testy selhaly. Neprováděly se nebezpečné testovací zápisy na produkci. |
| Databáze | FAIL | 281 PASS / 45 FAIL. Na samostatném čistém main: 279 PASS / stejných 45 FAIL. Dva nové batch SQL soubory prošly; žádné nové selhání oproti baseline. |
| Client | FAIL | Core 198 PASS, VM adaptéry 87 případů bez selhání (1 skip). Flutter: 1421 případů, 2 selhání, navíc kompilace existujícího `occasion_setup_copy_cases.dart:111` (starý typ callbacku galerie). Architektura hlásí 11 nezařazených roots, stejných i na čistém main. |
| Deno | FAIL | 587 PASS / 1 FAIL: `send-email/cancellation_handler_test.ts:28`, očekává 200, dostává 403. Stejné selhání potvrzeno samostatným během na čistém main. |
| Image integration | SKIP | Runner vrací 0, ale všech 27 testů je záměrně přeskočeno na localhost DB; nejde o passing integrační důkaz. |
| Automation | FAIL | Mimo jiné chybějící `automation/templates/web/delete-account/copy.json`, Python modul `yaml`, neaktuální server-security/source deklarace. |

Flutter selhání: existující galerie a email-authoring catalog; kompilace selhává
v existující occasion gallery fixture. Tato fixture je byte-for-byte stejná jako
na čistém main. Nebyly měněny testy za účelem obejití těchto chyb.

Lokální API bylo následně zkusmo spuštěno pro doplnění HTTP kontrol, ale Supabase
skončil na `LegacyHealthCheckTimeoutError` vlastního DB kontejneru. HTTP lane tedy
není doložena jako zelená. DB a souběžné testy před restartem normálně proběhly.

## Cílené kontroly funkce na současné architektuře

- Migrace z canonical baseline se všemi forward migracemi: PASS.
- Batch foundation/lifecycle SQL: 2 PASS.
- Skutečné souběžné PostgreSQL transakce a canonical Blueprint save: 4 PASS.
  Jsou součástí běžné web discovery v
  `web_client/tests/database/ticket_batch_concurrency.test.js`.
- Batch PDF/ZIP, delivery a Edge entrypoints: 84 PASS.
- Batch command identity/recovery/email validation a mobilní export: 4 PASS.
- Canonical source + Edge coverage automation: 10 PASS.
- Cílený analyzer: bez error/warning; stávající style info ve sdílených souborech.
- Source assembler, effective source fixture a operation inventory: PASS.

## Reprodukce a důkazy

- Kompletní receipt: `/private/tmp/festapp-batches-full-results/summary.json`.
- Client detail a JSONL: `/private/tmp/festapp-batches-full-results/client/`.
- Celý výstup: `/tmp/festapp-batches-full-test.log`.
- Srovnávací main SQL: `/tmp/festapp-batches-baseline-full-sql.log`.
- Srovnávací main Edge: `/tmp/festapp-batches-baseline-edge.log`.

Před vydáním musí být plná sada zelená. Potom znovu fetch/rebase na aktuální main,
validace dotčených změn, canonical publikace podle branch protection, příprava
odpovídajícího Edge runtime před aktivací stock příkazů, atomická migrace s ledgerem,
source/runtime/ready readback a jedno tenant vydání s drift/build/live gates.
Tento dokument není passing release receipt ani autorizace obejít gate.
