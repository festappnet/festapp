# Payment policy - plán zjednodušení

Rozsah: implementovat čtyři odsouhlasené příležitosti nad hotovou lokální policy. Ověření standard (platby, oprávnění, migrace). Bez produkčních operací, commit/push/deploy. Zachovat celý cizí dirty tree a předchozí policy; výchozí tracked patch a frozen digests v `.git/payment-policy-refactor-20261112/`.

## Invarianty a hranice

Jeden registry/policy/operation engine a jedna email queue. Žádné doménové triggery, pouze existující last-updated metadata. Fence se bere před hierarchy/row locks; epoch se zvyšuje pouze po skutečném template/wrapper write. Změna A-B-A stále invaliduje staré snapshots. Replay a stale conflict nemají nový side effect. RBAC, scope, ready/support, veřejné RPC signatures, uložené peníze a jazyky UI zůstávají stejné.

## 1. Čistý runtime SQL a frozen historie

`database/functions/payment_providers/method_policy.sql` bude obsahovat pouze opakovatelně instalovatelné funkce/ACL. DDL a jednorázový backfill zůstanou jednou autoritativně ve frozen additive migraci160000; nebudou duplikované v runtime source ani znovu prováděné při reloadu. Additive160000 i contraction170000 zachovat byte-for-byte, chránit SHA256. Změněné authoring funkce dostanou nový forward180000 a explicitní manifest. Prokázat reload runtime po contraction bez staré stripe_unit_features a beze změny dat.

## 2. Skutečné změny místo invalidace při každém save

V existujících update_email_template, delete_entity_email_template a update_entity_email_banner zachovat autorizaci a lock-before-read. Porovnat uložený obsah/scope nebo smazat přesnou existující override; invokovat scoped epoch owner pouze pokud opravdu proběhl zápis. Opakované uložení identické šablony/banneru a reset bez override nezmění epoch ani platnost prepared emailu. Skutečná změna a A-B-A zůstanou blokované pro starý snapshot. Nepřidávat cache ani triggery.

## 3. Jedna deklarativní kontrola migračních vlastníků

Sdílený migration_forward_owners bude číst deklarativní registry s frozen SHA256, source manifesty a pořadím explicitních forwardů. Přesunout access/wallet source seznamy do manifestů. Odstranit dynamické importování assemblerů ze společné kontroly a zpětné vzájemné volání. Zachovat CLI názvy jako tenké adaptéry a jejich --check kontrakt. Společný checker ověří history digest, nesupersedované source bloky, výslovné pozdější vlastníky, aktuální effective function bodies a kompletní nový forward. U method_policy je výslovná hranice: schema/backfill již patří frozen historii, runtime deklarace musí odpovídat effective head. Negativní testy pro změněnou historii, neohlášený drift a chybějící forward.

## 4. Typované policy UI

Přidat malé immutable policy/method/impact/preview/change DTO a úzkou DB službu. JSON a RPC zůstanou uvnitř této hranice; widget bude pracovat s typy, doménovými enumy a existujícími callbacks. Přesunout současné RPC načtení, preview a command do služby; zachovat generation guard proti pozdním odpovědím, oprávnění, onboarding, impact potvrzení a error/retry. Unit caller přejde z nested Map na typed property. Žádná změna vizuálního návrhu ani obecný formulářový framework.

## Odstranění

- Runtime DDL/backfill/staré Stripe tabulkové reference: odstranit z method_policy.sql, retained pouze frozen history.
- Invalidace při nezměněném save/reset: odstranit ve všech třech writer owners.
- importlib a doménové znalosti konkrétních assemblerů ve společném checkeru: nahradit registry; odstranit duplikované access/wallet seznamy a checker větve.
- Map traversal a přímé RPC ve PaymentPolicySettings: odstranit, všechny callers převést na typed DTO/službu.
- Zachované hranice: existující veřejné RPC a assembler CLI jsou tenké adaptéry, frozen migration artefakty se nikdy neregenerují.

## Ověření a dokončení

Batched SQL na vlastní disposable55452: skutečné saves/reset/no-op + prepared validity + A-B-A + scope/ACL; existing template/email testy; runtime function reload po contraction. Skutečná PostgreSQL concurrency14 přes actual authoring RPC. Fresh bootstrap a3 upgrade scénáře. Python tooling testy včetně negativních history/drift cases, všechny dotčené assembler --check a canonical source/operation inventory. Dart model/service tests a existující policy widget retry/stale-scope testy, targeted analyzer; pouze jedna Flutter úloha a testy --concurrency=1. Finální canonical8 lanes podle konzervativního inputs.json (SQL/Flutter/neklasifikovaný automation); browser delegovat Terra dle AGENTS až po source freeze. Passing evidence znovu nepouštět bez relevantní změny.

Postup a výsledky udržovat v `payment-policy-refactor-RESULT-2026-11-12.md`. Hotovo až po všech4 krocích, removal důkazech a green kontrolách. Produkce zůstane beze změny.

Realizováno a ověřeno: všechny4 kroky dokončeny. Finální canonical8lane batch green; konkrétní evidence a zachované hranice jsou v [realizačním záznamu](payment-policy-refactor-RESULT-2026-11-12.md), checkpoint4.
