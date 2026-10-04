# Implementace plánovaných cen produktů

Pracuj v `/Users/miakh/source/festapp`. Přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý autoritativní plán:

`docs/plans/product-price-scheduling-plan-2026-10-04.md`

Implementuj tabulkový přehled aktuální ceny a budoucích změn, intuitivní dialog create/edit/cancel a ověřené serverové provádění se zachováním synchronizace. Podpora více změn jednoho produktu v různých datech je povinná: úplná chronologická osa v dialogu, nejbližší změna a počet dalších v tabulce, samostatné vložení/přesun/zrušení termínů bez přepsání ostatních cílových cen. Historie do tohoto UI nepatří. Verification: standard.

Dodrž pořadí databázový kontrakt -> spouštěč a nákup -> UI -> cílené ověření. Zachovej eshop.planned_changes jako jediné úložiště a public.apply_planned_changes() jako entrypoint; odstraň rozdíl kanonického SQL zdroje proti efektivní sync implementaci. Nepřidávej paralelní scheduler, placeholdery nebo tiché fallbacky.

Respektuj existující necommitované změny i pravidla main/tenant. Pokud aktuální kód vyvrací předpoklad, aktualizuj plán s důkazem. Neprováděj nezávislý agentní audit. Pro lokální E2E přečti festapp-local-e2e a agent-browser skills; použij izolovanou DB a headless session.

Dokončení vyžaduje funkční autorizované RPC, cenu správnou i při opakování/souběhu, čitelné a přístupné UI, cílené SQL/Flutter testy a ověření nové vs. existující objednávky. Neoznačuj produkci za ověřenou pouze podle zdrojů nebo lokálních testů.

Bez samostatné autorizace neprováděj produkční migrace, deploy, commit ani push. Předání: stručný výsledek, evidence validace a přesný zbývající provozní krok.
