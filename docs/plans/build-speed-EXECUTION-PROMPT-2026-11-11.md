# Implementace rychlejšího webového buildu Festapp

Pracuj v `/Users/miakh/source/festapp`. Přečti applicable AGENTS.md, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/build-speed-plan-2026-11-11.md`

Implementuj jeho vlny v pořadí. Cílem je bezpečné reuse nezměněné Flutter/Vite kompilace, čerstvá kompletace koherentního releasu a ověřování prebuilt balíčku před uploadem. Ověřování je standard. Zachovej existující gates, kanonický main/tenant kontrakt a cizí rozpracované změny.

Začni časováním a baseline. Cache založ na úplných skutečných vstupech, nikoli samotném Git SHA. Verzi vyřaď z kompilačních vstupů až po důkazu, že výsledné klientské metadata zůstávají správné. Nezaváděj druhou build cestu ani obcházení receiptů či CI. Dokončení vyžaduje negativní testy invalidace a prebuilt uploadu, změřené přínosy a odstranění nahrazených duplicit.

Pokud současný kód vyvrátí předpoklad plánu, aktualizuj v něm důkaz a příslušnou vlnu. Neměň tiše cíl. Dodrž jeden Flutter task na workstation, testy `--concurrency=1` a pnpm 11.24.0. Browser práci deleguj na Terra podle AGENTS.md; nezadávej nezávislý agent review.

Toto zadání je pro lokální implementaci a měření. Bez samostatné autorizace neprováděj push, zápis do prod větví, produkční build/deploy ani live změny. Chybějící preflight credentials nebo tenant výběr uveď jako konkrétní blocker a pokračuj částmi, které na nich nezávisí. Při předání uveď upravené hranice, výsledky požadovaných kontrol, naměřené časy a přesné nedokončené body.
