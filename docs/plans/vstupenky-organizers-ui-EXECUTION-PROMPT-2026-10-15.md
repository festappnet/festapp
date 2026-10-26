> Historický plán. Veřejnou prezentaci služby dnes vlastní homepage `/`; pro aktuální směrování platí `automation/release/organizers/README.md`. Tento dokument není zadání k obnově původní samostatné stránky.

# Jedna session: UI stránky pro pořadatele a dokončení katalogu

Pracuj v `/Users/miakh/source/festapp`. Přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý autoritativní plán:

`docs/plans/vstupenky-organizers-ui-plan-2026-10-15.md`

V jedné session dokonči implementaci a cílené i vizuální ověření. Z katalogu odstraň počet v hlavním nadpisu proběhlých událostí a modrou čáru, zachovej viditelné události a roční členění. Přepracuj `/pro-poradatele` na profesionální stránku se skutečnou společnou hlavičkou, stavem účtu, jednotným tématem a dotaženým mobilním vzhledem. Použij existující komponenty a bootstrap, odstraň nahrazenou hlavičku/styly; nevytvářej druhý auth ani alternativní routing. Zachovej SSR/SEO, PWA opravu, tenantový branding a pravdivý obsah.

Pracuj z aktuálního mainu v čistém worktree, zachovej nesouvisející lokální změny. Bez delegace do dalších session. Ověřování podle plánu, významné screenshoty v izolovaném headless prohlížeči. Pokud se změnily věcné předpoklady, aktualizuj plán podle důkazů a pokračuj ke stejnému výsledku. Žádné placeholdery nebo nedokončené varianty.

Samotný tento prompt nespouští publikaci. Pokud uživatel současně zadá nasazení, dokonči ve stejné session release pouze pro `prod/festapptickets` podle existujících pravidel a ověř produkci. Nepřebírej jednorázové výjimky review z předchozího releasu. Na konci stručně uveď výsledek, kontroly, vizuální důkazy a případný přesný blokující krok.
