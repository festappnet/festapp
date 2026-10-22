# Exekuční prompt: připrav Stripe k začlenění a nasazení

Pracuj v repozitáři `/Users/miakh/source/festapp`. Dokonči vlny 1-4 autoritativního navazujícího plánu:

`docs/plans/stripe-integration-readiness-plan-2026-10-22.md`

Přečti jej celý, aktuální AGENTS.md, CLAUDE.md a `docs/architecture/ai_context.md`. Přečti také původní doménový plán `docs/plans/stripe-client-owned-plan-2026-10-21.md`, implementační důkazy `docs/plans/stripe-client-owned/IMPLEMENTATION-STATUS.md` a provozní `docs/plans/stripe-client-owned/PILOT-RUNBOOK.md`. Ověřování je `standard`.

Výsledek: čistá samostatná sada změn Stripe proti aktuálnímu upstream `main`, ověřená finálním SQL replay i upgradem z `main`, s manifestem a readiness záznamem. Integraci nepiš znovu. Původní checkout obsahuje smíšenou práci: zachovej ho a pracuj v novém worktree. Přenášej konkrétní Stripe změny včetně untracked a závislostí, u společných souborů integruj hunks do aktuálního `main`. Nepřebírej celou feature větev ani celý dirty diff.

Zachovej bankovní cestu, SQL autoritu, immutable provider recipient/amount/currency, oddělené capability scope, webhook signature/account/mode binding, refund/admission audit, přesné částky, frontu emailů a recovery. `payment_method` není `payment_type`. Konečné migrace musí odpovídat kanonickým zdrojům a skutečnému pořadí aktuálního migračního runneru. Nepřidávej placeholdery, druhý engine, aplikační triggery ani neplánované fallbacky. Vyvrátí-li aktuální důkazy faktický předpoklad, oprav navazující plán a dotčené kroky.

Kontroly vybírej podle změněných hranic a existujících důkazů. Skip není úspěšný test. Sandboxové důkazy jsou simulace z dřívější revize, nikoli důkaz nasazení. Používej pnpm 11.24.0; před Flutter ověř volný workstation slot a testuj s `--concurrency=1`. Cizí testovací procesy/databáze nerestartuj. Secrets a raw chráněné odkazy nedávej do repozitáře ani výstupů. Nezahajuj nezávislý agentní audit.

Dokonči veškerou nezávislou přípravu a vytvoř `docs/plans/stripe-client-owned/INTEGRATION-READINESS.md` s base/source revizemi, manifestem, výsledky, zbývajícími gates a konkrétními publikačními kroky. Nekonči pouhým dalším plánem. Běžné implementační volby řeš samostatně.

Samotný tento prompt neautorizuje commit/push/merge, produkční migrace, deploy, scheduler ani živé platby/refundace. Pokud uživatel tyto kroky následně výslovně zadá, pokračuj odpovídající částí plánu a zachovej publikační/release gates. Nasazení kódu s novými Stripe platbami vypnutými a aktivace ostrého pilotu jsou dvě samostatná rozhodnutí. Předchozí release výslovně bez Stripe nepoužívej jako autoritu pro Stripe.

Při předání stručně uveď připravený výsledek a jeho cestu, co bylo skutečně ověřeno, konkrétní blokátory a další potřebné rozhodnutí. Neoznač přípravu za merge, deploy nebo ostrý provoz.
