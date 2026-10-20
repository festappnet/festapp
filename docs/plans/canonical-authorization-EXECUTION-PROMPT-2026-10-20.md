# Provedení: kanonická oprávnění aplikace a MCP

Přečti applicable AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý autoritativní plán:

`docs/plans/canonical-authorization-plan-2026-10-20.md`

Použij verification: standard. Začni z aktuálního fetched authoritative main v izolovaném checkoutu, zachovej rozpracované closure/V2 změny a domluv vlastnictví s aktivními sessions. Plán vychází z lokální closure delty nad `48d8b6db0479818b556e3852c7ea50ead4035d11`; současný kód může být novější. Změněné premisy oprav v plánu s konkrétní evidencí.

Proveď vlny 0-4. Cíl je jedna SQL definice oprávnění pro každou doménovou operaci, sdílená RPC/RLS, běžnými klienty a MCP. MCP navíc omezuje request uděleným souhlasem a OAuth scope. Zachovej dnešní práva, tenant/demo ochranu, transakční authorization, receipt/replay a podporované vnější kontrakty. Role fakta nemigruj do nového ACL enginu. UI používá projekci stejných pravidel; neduplikuj business policy v Dart/JS/Edge ani v konfiguračním katalogu.

Pilot není celé dokončení. Inventář musí pokrýt všechny aktivní entry points včetně RLS, přímých grants, service jobs a dynamických registrací. Odstraň obsolete implementace dle deletion ledgeru; každý nutný vnější adaptér jednotlivě zdůvodni a připoj ke kanonickému owneru. Žádné nové fallbacky ani autoritativní role cache. Sporné rozšíření práv neprováděj pod názvem refaktor.

Změř stejné workloady před/po: plány, buffers, p50/p95, throughput a počet RPC. Splň výkonový gate z plánu, bez N+1 nebo nového síťového preflight. Skutečné SQL testy musí prokázat revokaci, průnik souhlasu, tenant hranice a souběžný přesun resource; samotné UI/mocks nestačí.

Testuj pouze prokazatelně task-owned lokální data se zakázaným odesíláním emailu. Flutter nejvýše jeden task na stanici, tests --concurrency=1; browser vlastní izolovaný headless profil. Bez samostatného zadání nespouštěj review/subagent audit. Produkční migraci, deploy, commit/push, publikaci a skutečné emaily neprováděj bez samostatné autorizace.

Předej zdrojové/migrační hashe, inventory a uzavřený deletion ledger, skutečné výsledky doménových a výkonových gates a přesně označené neprovedené provozní kroky. Neoznačuj celek hotový při neuzavřeném vstupu, duplicitní policy nebo neprůkazném výkonu.
