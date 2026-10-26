# Implementace vlastních URL záložek

Pracuj v `/Users/miakh/source/festapp`. Přečti `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/tab-deep-links-plan-2026-10-03.md`

Implementuj všechny jeho vlny v pořadí. Výsledek: vlastní stabilní URL navigačních tabů a podtabů obou administrací, jednotky, objektových detailů a datumového stavu; přímé odkazy, reload, login návrat a historie zobrazují stejný obsah. Ověřování: standard.

Použij stávající AutoRoute jako jediného vlastníka navigace, typované routy a jeden úzký sdílený prezentační shell. Zachovej feature/práva, retenci editorů a ochranu neuložených změn. Odstraň nahrazený navigační stav podle deletion ledgeru; ponech jen vyjmenované vstupní redirecty a dočasné prezentační výjimky. Generovaný router upravuj výhradně build_runnerem.

Konkrétní vzory: `OccasionHomePage`/`OccasionTab` pro retenční taby a metadata, knihovní `AutoTabsRouter.tabBar` pro controller, `ScheduleNavigationPage` + nested `EventRoute` pro seznam/detail a canonical root při přímém odkazu. Zachovej dosavadní public tab reselection reset; admin klik na aktivní tab je no-op. Nezaváděj vlastní synchronizační controller, absolutní navigaci mezi vnořenými detaily ani plošný refaktor public home.

Nezaváděj placeholdery, alternativní router, ruční browser history, URL odvozené z indexu/překladu ani V1/V2 paralelní implementaci. Pokud aktuální kód vyvrátí premisu plánu, nejprve oprav plán s konkrétním důkazem a přizpůsob příslušnou vlnu bez změny výsledku.

Ověř pracovní stav; sdílený kód vlastní `main`, aktuální větev při plánování byla `release/ticket-editor-ui-20261003`. Zachovej cizí změny a lokální opravu zarovnání breadcrumb šipky, která vznikla samostatně při plánování.

Proveď cílené testy a izolované browser scénáře z plánu. Nespouštěj nezávislé agentní audity. Commit, push, produkční mutace, deploy a rollout tenantů vyžadují samostatné zadání. Handoff stručně uvede implementovaný kontrakt, odstraněné staré mechanismy, výsledky ověření a přesné zbývající blokery.
