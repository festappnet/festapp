# Implementuj fonty editoru vstupenek a cache pro PDF

Pracuj v `/Users/miakh/source/festapp`. Přečti AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md, potom celý autoritativní plán:

`docs/plans/ticket-fonts-plan-2026-10-03.md`

Cíl: výběr oblíbených i dalších fontů stejnou logikou jako ve formulářích, identické fontové bajty v editoru a všech PDF cestách a jeden resolver s omezenou paměťovou a trvalou cache. Uložený layout připíná konkrétní font; staré layouty zachovají vzhled. Dokonči všech pět vln včetně SQL ochrany schema 2, historických generátorů, odstranění bypassů, testů a dokumentace.

Pracovní strom obsahuje mnoho cizích změn a untracked souborů včetně editoru. Zachovej je. Začni cílenou kontrolou driftu proti důkazům v plánu, neopakuj celou rešerši. Pokud se faktický předpoklad změnil, oprav tento plán a příslušnou vlnu; nezaváděj potichu alternativní cache, provider nebo fallback. Žádné placeholdery ani rozpracované druhé implementace.

Verification: standard kvůli kontraktu, SQL a sdílenému generování. Implementuj souvislé vlny, potom spusť cílenou validační sadu z plánu. Použij malé lokální font fixtures a fake síť/storage; netestuj přes produkci. Úspěšné kontroly neopakuj bez změny jejich kódu. Nevypisuj velké katalogy či soubory; využij scoped rg a úzké reads. Bez dalšího zadání nespouštěj subagenty ani nezávislý audit.

Nenasazuj, nemigruj produkci, neprováděj live inventuru, commit/push ani rollout tenantů bez samostatného zadání. Tyto provozní kroky jsou v plánu oddělené od lokální implementace. Neznámé legacy font URL neschovávej fallbackem; uveď je jako přesný rollout blocker.

Na konci stručně uveď výsledek, důkaz shody náhledu/PDF a cache hitů, odstraněné bypassy, validaci a dosud neprovedené provozní kroky. Hotovo znamená splněný kontrakt i deletion ledger, nikoli jen fungující dropdown.
