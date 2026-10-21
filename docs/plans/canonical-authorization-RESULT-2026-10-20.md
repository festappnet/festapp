# Kanonická autorizace - výsledek lokální implementace

Stav: **vlny 0-4 dokončené lokálně**, verification: standard.
Produkční migrace a deploy **nebyly provedeny**. Samostatně autorizovaná příprava PR je popsaná níže.

## Rozsah a prostředí

Implementace je v izolovaném checkoutu
`/Users/miakh/source/festapp-canonical-authorization-20261020`, nad fetched main
`ce77a1e40057841bff9abe9f28ba0a4f0c4510dd`. Původní rozpracovaná kopie
zůstala nedotčená. Paralelní vlastníci byli informováni, že tato nepublikovaná
změna není součástí jejich release.

Skutečné SQL testy a měření běžely výhradně proti vlastnímu PostgreSQL 15.8
na `127.0.0.1:61022`, s markerem `festapp-authz-20261020`,
`cron.launch_active_jobs=off`, `email_capacity.paused=true`, `worker_url=NULL`.
Pristine baseline z původního commitu se nezávisle rekonstruovala na portu
61024; její DB je zastavená. Produkce ani skuteční emailoví/bankovní provideři
se při ověření nepoužili. Benchmark fixtures jsou pouze syntetická lokální data.

## Jeden vlastník pravidla

SQL operation predikáty a soukromá immutable boolean pravidla vlastní doménová
oprávnění. RPC, RLS, transakční commandy, service adaptéry a projekce používají
stejné ownery. Členské tabulky zůstávají živým zdrojem faktů; nevznikl ACL engine,
nová role tabulka, tokenový permission snapshot ani autoritativní cache.

- Vytvoření a setup akce dovoluje samostatně unit editor nebo unit manager.
  To opravuje uživatelem výslovně odmítnutý souběh obou rolí v původním writeru.
- Banka je výslovná výjimka: správce skutečně připojeného pořadatele **a** admin
  bankovního účtu. Nový link ověřuje cílového pořadatele; tenant admin tyto role
  nenahrazuje. Podrobnosti jsou v [bankovní matici](canonical-authorization-BANK-2026-10-21.md).
- Objednávky, layouty, formuláře, uživatelé, recepce, scanning, mapy, program,
  skupiny, informace, aktivity, inventory, emaily, finance, media a unit/tenant
  administrativa mají v evidenci své skutečné SQL ownery a odlišné kontrakty.
  Discovery samo neuděluje právo k operaci.
- MCP přidává OAuth scope a původní souhlas. SQL ověřuje živé právo a stored
  resource ve stejném requestu jako čtení/zápis a před receipt replay.
  Přesun mimo delegovaný unit ani odvolání práv neobejdou transakční kontrolu.
- Dart/JS čtou capabilities ve stávajícím context requestu. Chybějící capability
  odmítá; invalidace vyprázdní projekci a zahodí opožděný výsledek. Odmítnutý
  zápis se neopakuje. Role data pro formuláře, štítky a vazby zůstávají daty.
  Navigace úklidové čety a kontroly vstupu také používá SQL projekci.
  Členství v četě se nerozšiřuje na editorův dohled nad reporty.

Projekce sdílí authored výrazová pravidla. Build-time generátor
`automation/generate_authorization_projection.py` je bezpečně rozvine do SQL
konstruktoru; neinterpretuje policy na klientovi a neukládá výsledek mezi requesty.
Tím odstraňuje režii prvního plánování desítek drobných funkcí. Index
`occasions_unit_start_time_authorization_idx` omezuje unit katalog před agregací.
Write overhead je zahrnut v měření.

## Nalezené a opravené průchody

Starý `scan_ticket_v2` přijímal NULL scan kód kvůli tříhodnotové SQL podmínce.
Skutečný negativní test nejprve prokázal vrácení dat, potom prošel po opravě.
Legacy ticket scan, moderní session a scanner directory nyní používají jeden
resolver skutečného stored secretu. Platný starý kód zachovává původní obálku;
NULL, cizí a odvolaný kód se odmítnou.

Byly odňaty přímé API DELETE grants na `images` a `log_notifications`.
Skutečný katalogový test vyhodnocuje table **i column** privileges spolu s RLS
jako anon/authenticated a prokazuje absenci efektivního přímého write bypassu.
Zkouší také skutečné zamítnutí DELETE. Kanonické gallery mazání dál prochází.

Service-only enqueue je actor-bound a kontroluje práva před dedupe.
Waitlist sdílí order writer pravidlo, s odděleným raw membership faktem pro
původní read kontrakty. Odebrání unit přístupu, reviewed demo Blueprint zápis
a odstranění objednávky po čekání na zámek používají živého vlastníka pravidla.

## Inventář a kontrakce

[Domain ledger](evidence/canonical-authorization-20261020/domain-ledger.json)
pokrývá všech **1 162 katalogových funkcí**, jejich ACL, zdroj, digest, SQL
vazby, operation ownery, actor/technical hranice a reference na testy.
Součástí je **408 RLS policies**, úplné table/column grants, oba cron jobs
včetně jejich vypnuté lokální execution hranice a všechny řádky runtime writer
registry. Dvě popisné registry položky nejsou zaměňované za jména funkcí.
Původní sync rollout `cutover_ready` flagy se tímto úkolem nemění.

Samostatný [boundary ledger](evidence/canonical-authorization-20261020/boundary-ledger.json)
klasifikuje všech 58 transportních a 41 dynamic-SQL kandidátů včetně type/DI
false positives. [Dispatch evidence](evidence/canonical-authorization-20261020/transport-resolution.json)
obsahuje 42 source-bound dynamických dispatch míst a žádné nevyřešené místo.
Všechny statické RPC callery mají existující katalogový cíl. Aktuální přímé
klientské table přístupy jsou čtení; nebyl nalezen aktivní Storage/Realtime producer.

Ledger jednotlivě uvádí **71 ponechaných veřejných adaptérů**, jejich vlastníka,
konkrétní callery, důvod zachování obálky a podmínku odstranění. Zachovává se
veřejný protokol přítomný na zaznamenaném base commitu; nebyla dotazována
telemetrie instalovaných klientů a netvrdí se znalost jejich verzí. Adaptéry
neobsahují druhou implementaci rolí. Inventář konzervativně slučuje SQL overload
call kandidáty; tato strukturální evidence se nezaměňuje za provedený test.

Deletion ledger je uzavřený: fyzické obsolete writery, starý unit-wide bank
connection reader, nepoužívané overloady a draft constructor se odstraňují
pomocí dependency/registry/cron guardů a DROP RESTRICT. Canonical source contract
obsahuje 19 retired signatures. Test kontroluje také všechny funkce zmizelé
proti pristine baseline, staré JWT role helpery a absenci přímých write cest.
Původní ticket-layout policy, MCP detached preflight a klientské funkční role
výpočty již nejsou paralelní ownery. Historické migrace zůstaly nezměněné.

## Ověření a výkon

Skutečně provedené příkazy, výsledky i opravené dřívější pokusy jsou v
[validation.json](evidence/canonical-authorization-20261020/validation.json).
Hlavní konečné výsledky:

- SQL/MCP: **66 pass, 0 fail, 0 skip**, včetně 2048 kombinací rolí, demo/tenant,
  consent, revokace, receipt replay, skutečných dvouspojení race testů a full ACL.
- Závěrečný SQL batch: **14 pass**, zahrnuje celý scanning, canonical source
  parity, oba duplication kontrakty a setup feature choices.
- Další doménové SQL kontrakty: 11 pass; waitlist/email/order actor batch 5 pass.
- Web: **527 pass, 25 skip**. Deno domain handlers: 60 pass, dále bank fetch
  3 pass a app-links 3 pass; provideři mockovaní. Dotčené Edge entrypoints typecheck prošly.
- Flutter: bank cases **46 pass**, poslední navigace/Rights/crew/reception
  **23 pass**, organization/unit widgety 3 pass; související lifecycle/revocation
  průchody jsou uvedené v receipts. Jeden Flutter task, concurrency 1.
  Poslední cílený analyzer: žádné chyby/warnings, 3 původní style infos.
- Generátory projekce, capability IDs, policies, writer contractu, forward
  migrace a canonical source contractu prošly `--check`.

[Performance summary](evidence/canonical-authorization-20261020/performance-summary.json)
a raw artefakty uzavírají lokální gate: střídavé A/B, stejné fixture,
8/1000 akcí, 4/50 bank členství, p50/p95, throughput, buffers/plány a jeden RPC
na doménový request. Šest workloadů prošlo sériově i se čtyřmi klienty.
Nejvyšší konečný nárůst p95 je 3,5 % u malého souběžného write; jeho throughput
se zlepšil o 3,3 %. Ostatní workloady mají nižší p95.

Poslední navigační změna přeměřila pouze dotčený context; ostatních pět
měřených call closures zůstává shodných. Zahřátý context p95 klesl sériově
36,9/58,9 % a souběžně 52,5/33,2 %. Čtyři final first-request scénáře na novém
DB spojení také prošly; p95 se nezhoršil. Shared buffers a OS cache zůstaly
zahřáté, nebyly flushovány. Nejde o měření produkčních latencí.

## Předání a neprovedené kroky

Forward migrace je
`supabase/migrations/20261021100000_canonical_authorization.sql`.
Zdrojové, migrační a evidenční SHA256 jsou v
[source-hashes.json](evidence/canonical-authorization-20261020/source-hashes.json).
Catalog-after souhlasí s authored SQL a skutečnými grants; předchozí úplné ACL
jsou doložené samostatnou pristine baseline receipt.

Implementace a místní ověření jsou dokončené. **Produkční aplikace, deployment
a skutečné emaily zůstávají neprovedené**, přesně podle
execution promptu. Lokální syntetický výkon nenahrazuje budoucí provozní
sledování skutečné distribuce členství a dat při samostatně autorizovaném rollout.


## PR requalification on current main

PR preparation rebased the implementation onto authoritative main
`6f6c5aa5108f0f67e150fb915d4c8bad9612c66c`. The original benchmark baseline
above remains the recorded pre-authorization source, not a claim about a new
production baseline. Newer Blueprint release integration and order-seating
migrations were preserved byte-for-byte and applied only to the owned local DB
before the regenerated authorization forward migration.

The current header preserves main's organization-settings menu and consumes
live SQL capabilities without its former permission preflight. Newly added
background-drop controls in the ticket editor now use the same scoped layout
capability, including checks after async uploads. The obsolete duplicate
`users/delete_unit_user.sql` source was removed; `unit_access_deletion.sql`
remains the sole authored owner. Source tests distinguish retired identities,
retained overloads and guarded migration DROP metadata.

Post-rebase checks: 66 SQL/MCP pass,531 web pass/25 skip,120 Flutter pass,
8 Node source-contract tests and9 Python source-contract tests pass, plus all
projection/source/immutable-migration generator checks. Five selected SQL
contracts for seating/checkout/source parity passed. A sixth selected upstream
public-hold script requires psql variables and its own different fixture
project, so this generic runner invocation is recorded as an invalid selection,
not as a product failure or an executed passing gate. Full release CI remains
the contract for that separate fixture. Existing performance evidence is reused
only after verifying all six measured call closures are unchanged; unrelated
new main function differences are listed explicitly in the performance summary.

The user's PR request separately authorizes committing and publishing this
branch. Production database application, tenant build/deployment and merge are
not performed as part of PR preparation. Backend migration must precede the
capability-consuming client rollout; missing capabilities fail closed.
