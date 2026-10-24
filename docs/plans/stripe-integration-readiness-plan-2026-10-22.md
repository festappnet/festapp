# Stripe: příprava začlenění a nasazení

## Výsledek a autorita

Připrav čistou, ověřenou sadu změn Stripe vůči aktuálnímu autoritativnímu `main`, která půjde samostatně začlenit a následně nasadit s novými Stripe platbami vypnutými. Neimplementuj integraci znovu. Tento plán navazuje na `stripe-client-owned-plan-2026-10-21.md`; doménový kontrakt zůstává jeho vlastnictvím. Tento dokument určuje následující přípravu a publikační brány.

Samotné zadání navazujícího promptu autorizuje přípravu v izolovaném worktree a lokální ověření. Neautorizuje commit/push, merge, produkční migrace, nasazení, instalaci scheduleru ani živé platby/refundace. Tyto akce proveď pouze při následném výslovném zadání. Souhlas s nasazením kódu není souhlas s aktivací ostrých plateb. Dřívější souběžný release výslovně bez Stripe není autoritou pro publikaci Stripe.

Ověřování: `standard` pro platby, oprávnění a migrace. Pro skutečné později autorizované nasazení platí aktuální pravidla repozitáře a jeho release gates.

## Fakta a otevřené předpoklady

- Při přípravě 2026-10-22 je původní checkout na `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`, s 2384 položkami změn. Je to výchozí pozorování, nikoli autoritativní release revize. Změny různých úloh se překrývají; nepřenášej celý diff ani celou větev.
- `stripe-client-owned/IMPLEMENTATION-STATUS.md` obsahuje implementaci a doklady pro JS a Flutter web, skutečné simulované sandboxové platby a explicitní limity. Native není ověřené na zařízení. Ruční kontrola čtečkami obrazovky a přijetí na vybraném hostu zůstávají otevřené.
- Finální opravy ingestu, zrušení objednávky a reportů byly aplikovány a testovány jednotlivě po předchozím čistém replay. Dosavadní důkaz proto není čerstvý replay konečné celé sady migrací.
- `stripe-client-owned/PILOT-RUNBOOK.md` vlastní provozní konfiguraci, recovery, akceptaci a rollback. Před aktivací vyžaduje přijetí 31minutové rezervace, dispute hold, online-only vstupu Stripe a pravidel refundace/pozdní platby.
- Aktuální vzdálený `main`, stav souběžného releasu a budoucí vybraný tenant musí být zjištěny při provedení. Nepředpokládej, že historická verze v jiné konverzaci stále odpovídá produkci.

## Vlna 1: bezpečný zdroj

Přečti AGENTS.md, CLAUDE.md, `docs/architecture/ai_context.md`, původní doménový plán, implementační status a runbook. Zjisti aktuální worktree a souběžné úlohy. Fetchni autoritativní upstream a vytvoř samostatný worktree z jeho `main`; původní checkout zachovej. Před přenosem zaznamenej zdrojový HEAD a seznam kandidátních souborů včetně untracked.

Sestav manifest Stripe změn z implementačního statusu a skutečných deklarací/callerů. U sdílených souborů přenes konkrétní hunks a potřebné závislosti, nikoli celou starší verzi. Zachovej novější změny z `main`, zejména UI průvodce, dialogy, lokalizace a routování. Neber jiné úlohy jako implicitní závislosti. Nepoužívej reset/clean/stash původního stromu ani plošné `git add .`.

Zahrň SQL zdroje, migrace/generátory, obě klientské implementace, Edge Functions a společné hranice, order/email rendering, runtime router/recovery tooling, testy a sanitizovanou dokumentaci. Hledej citlivé soubory bez vypisování jejich obsahu. Secret store, soukromé fixture, raw capability URL a lokální logy nepatří do změn.

Výstup: izolovaný patch proti zaznamenanému upstream SHA a manifest s důvodem zahrnutí sdílených změn. Žádná příprava nesmí přepsat práci jiné úlohy.

## Vlna 2: konečné migrace a kompatibilita

Nejdřív zkontroluj aktuální migrační historii `main`. Tři dosud nepublikované migrace `20261021160000_stripe_foundation.sql`, `20261021170000_stripe_connections.sql`, `20261021180000_stripe_checkout_ingest.sql` musí odpovídat výsledným kanonickým zdrojům. Jestli se od jejich vzniku v `main` objevily pozdější migrace, ověř pořadí a chování skutečného runneru pro doplňované starší timestampy. Nenutit je do produkce jako údajně již provedené. Je-li nutné přečíslování nepublikovaných migrací, uprav generátor, kontrakt a dokumentaci společně. Publikované migrace nepřepisuj.

Spusť `python3 automation/assemble-stripe-migrations.py --check` a `python3 automation/generate_canonical_source_contract.py --check`. V samostatné disposable databázi proveď aktuální kanonický baseline a finální forward migrace skutečným pořadím runneru, s vypnutými externími cron dispatchi. Zvlášť ověř upgrade z aktuálního `main` bez Stripe; samotný fresh install neprokazuje upgrade existující instalace. Sdílený harness neresetuj a produkční databázi nepoužívej.

Ověř `/stripe` kolizi, konečné funkční definice/digesty, service-only oprávnění, RLS a absenci přímých klientských grantů na privátní tabulky i persistentních aplikačních triggerů. Porovnej staré bankovní objednávky a nové Stripe DTO, přesné částky, plné zrušení objednávky, reporty, online admission a send-time email eligibility. Ověř bankovní cestu při vypnutém Stripe bez nakonfigurovaných provider secrets. Generátor není důkazem úspěšného SQL replay.

Výstup: přesné revize, pořadí migrací, readback a reprodukovatelné výsledky obou databázových cest. Odstraněné či nahrazené artefakty eviduj; nevytvářej druhý platební engine ani kompatibilní trigger.

## Vlna 3: cílené ověření výsledného patche

Z implementačního statusu vyber kontroly podle souborů změněných při izolaci a integraci. Již platné sandboxové důkazy zachovej s původní revizí a limity; nevydávej je za nové ověření výsledného `main`.

Povinné jsou konečný SQL replay/upgrade, generátory a cílené bankovní/Stripe SQL regrese dotčených definic. Při změně autority souběhu spusť `web_client/tests/database/stripe_concurrency.test.js` podporovaným lokálním runnerem: jeden Node test obsahuje šest reálných held-lock races. Vyžaduje existující loopback harness `55432/postgres` a klonuje vlastní databázi; nespouštěj ho proti produkci a neresetuj sdílený harness. Počet skutečně vybraných testů ověř, skip není úspěch.

Podle přenesených úprav spusť příslušné Deno provider/email testy a typecheck, JS testy a cílenou Dart analýzu/widget testy. Používej pnpm 11.24.0 a repository test runnery. Flutter smí běžet jen jeden na celé workstation, testy s `--concurrency=1`; cizí proces neukončuj. Browser jen izolovaně headless podle skillu `agent-browser` a pravidel repozitáře. Nedělej plošný audit ani opakované nezměněné testy.

Výstup: přehled kontrol vázaný k výslednému patche a explicitní neověřené scénáře. Příprava musí projít bez tajných údajů ve výstupech. Aktualizuj implementační status a runbook podle skutečného výsledku.

## Vlna 4: připraveno k rozhodnutí

Připrav reviewovatelný diff, návrh commit message a krátký readiness záznam `stripe-client-owned/INTEGRATION-READINESS.md`: upstream base, source HEAD, worktree, manifest, změny oproti původním důkazům, migrace, kontroly, blokátory a přesné kroky k publikaci. Nezakládej PR jako mezikrok, pokud jej nevyžadují ochrany větve.

Bez další publikační autority zde skonči s hotovým výsledkem k posouzení. Pokud uživatel výslovně autorizoval commit/merge/push, dokonči je podle aktuálních pravidel: těsně před publikací fetchni upstream, zkontroluj intervenující commity, integruj souběh a zopakuj jen ovlivněné kontroly. Upřednostni ověřené přímé začlenění do `main`, pokud pravidla dovolují. Zaznamenej výsledný SHA. Publikace `main` sama nesmí spustit neautorizované produkční změny; před pushem prověř CI triggery.

## Následné nasazení a aktivace

Teprve po samostatné autoritě k nasazení určete jediný tenant a přesný zdroj/overlay. Přečti aktuální release/backend skills a tenant overlay policy. Připrav finální artefakt, migrační/config manifest a kompatibilní pořadí backendu, obou klientů, senderu a rendereru podle runbooku. Globální nové Stripe platby musí být vypnuté od instalace až po potvrzení přijímacích podmínek. Vypínač nezastavuje webhook, recovery ani historii existujících plateb.

Rutinní release deleguj podle AGENTS.md levnějšímu agentovi s přesnými revizemi a gates. Platí místní build a `automation/deploy_direct.sh`, nikoli GitHub-hosted deploy bez explicitní volby. Neprováděj další tenanty. Výsledek nasazení ověř skutečnou live revizí a funkčností bankovní cesty.

Aktivace živých plateb vyžaduje další explicitní souhlas s konkrétním pilotem: tenant, jednotka, formulář, měna a podporované povrchy, správný vlastní účet pořadatele, live Connect/webhook konfigurace, recovery a produktové podmínky z runbooku. Native/embed zůstávají vypnuté do vlastního přijetí. Rollback zastaví nové platby a zachová finanční historii, ingestion, návraty, reconciliation a admission/email fences.
