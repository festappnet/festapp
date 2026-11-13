# Implementovat variantu B Nastavení celé akce ve Flutteru

Pracujte v `/Users/miakh/source/festapp`. Přečtěte platné AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md, potom celý autoritativní plán:

`docs/plans/occasion-settings-layout-b-plan-2026-11-11.md`

Výsledek: skutečné Flutter Nastavení **celé akce** podle propracované B, desktopový grid funkcí a editor přes celou šířku pod vybraným řádkem, mobilní kapitoly a jeden sloupec. Zachovat všechny původní editory, oprávnění, koncept, HTML, validaci, Save/Discard a samostatné uložení ticket layoutu. HTML reference je `docs/previews/occasion-settings-variants/variant-b-refined.html#features`; není výsledným UI ani zdrojem obchodních pravidel.

Pracovní kořen má rozsáhlé cizí změny. Použijte čistý worktree z aktuálního main; nepřepínejte ani neuklízejte cizí pracovní kopii a nekopírujte celý dirty diff. Pokud současný zdroj vyvrátí faktický předpoklad plánu, opravte plán a přizpůsobte dotčený krok.

UI delegujte podle požadavku uživatele na **gpt-6-astra, reasoning medium, fork_turns="none"**, s krátkým samostatným zadáním a výhradním vlastnictvím konkrétních souborů. Žádné opakování návrhového průzkumu ani další nezávislé audity. Primární agent integruje, připraví fixture a behaviorální testy. Browser kontrolu a nové aktivní otevření hlavního Chromu delegujte Terra; mimo tyto předepsané role není další delegace součástí plánu.

Nejdříve vytvořte průchod se skutečnými Flutter komponentami a bezpečnými místními daty; poté dokončete celý dokument a odeberte nahrazenou starou cestu. Žádné placeholdery skutečných editorů, druhý draft model, obcházení původní validace, autosave, paralelní V2 nebo nový feature flag. Editor nesmí při close/switch/search/resize přijít o controllery. Vypnuté funkce nesmějí začít blokovat validaci a zapnuté skryté ji nesmějí obejít.

Preview musí použít stejné widgety a skutečné veřejné validační/save cesty s explicitně místními I/O službami. Nestačí pouze nahradit loader a nechat Uložit, upload, ticket nebo refresh volat produkci. Pro náhled není potřeba produkční login ani úplný Supabase. Flutter HTTP runtime je oprávněný; HTML/server napodobující Flutter není výstup.

Plánování je low-risk, implementace společné validace/ukládání standard. Respektujte jedinou Flutter úlohu na workstation, vždy fvm, testy `--concurrency=1`. Proveďte jednu cílenou finální dávku z plánu na konečných zdrojích, skutečně registrujte nové test suites a doložte počty. Preview server ukončete před testy a po nich znovu spusťte pro uživatele.

Tento soubor je zadání pro později autorizovanou realizaci, nikoli automatický spouštěč. Nynější úloha autorizuje pouze plán. Implementaci, commit/push, tenant overlay, migraci ani produkční deploy nespouštějte bez odpovídajícího dalšího zadání; případná publikace zachová aktuální CI a release pravidla a explicitní scope.

Při předání stručně uveďte změny pro desktop/mobil, zachované původní komponenty a vlastníky, odstraněné staré UI, výsledky kontrol a konkrétní Flutter preview URL otevřenou v hlavním Chromu. Vizuální fixture není důkaz backendového nebo OAuth integračního testu.
