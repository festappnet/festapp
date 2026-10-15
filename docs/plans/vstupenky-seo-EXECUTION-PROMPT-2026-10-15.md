# Navazující realizace SEO vstupenky.online

Pracuj v `/Users/miakh/source/festapp`. Nejprve přečti příslušné AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý autoritativní plán:

`docs/plans/vstupenky-seo-plan-2026-10-15.md`

Cíl: sjednotit canonical host, doplnit obsah pro pořadatele bez automatického vrácení skrytého homepage úvodu, zlepšit katalog a provést pouze prokázané optimalizace fontů. Dodrž standard ověření veřejných kontraktů a hlaviček, jeden cílený validační balík po koherentních změnách. Nevytvářej další implementaci katalogu ani speciální obsah pro roboty.

Veškerý grafický a UX/UI návrh a jeho implementaci přiděl podle výslovného přání uživatele subagentovi Astra Medium: `model: "gpt-6-astra"`, `reasoning_effort: "medium"`, `fork_turns: "none"`. Dej mu celý plán a doprovodné zadání `docs/plans/vstupenky-seo-UX-UI-2026-10-15.md`, konkrétní oprávněný rozsah a vlastnictví souborů. Hlavní agent integruje technické SEO, data, generování a runtime routing. Dodrž závislosti T0-T5/U1-U2/O1-O2/M1 a nikdy nenech dva agenty současně upravovat společné HTML nebo katalogový komponent. Výsledný UI kontrakt převezmi před integrací. Použij existující design a logo; redesign ani návrat skrytého úvodu nejsou zadány.

Pracovní strom obsahuje rozsáhlé cizí změny a není důkazem živého releasu. Odděl vlastní práci, nezahrnuj celý diff do SEO releasu. Zdroj routování je worker generovaný v automation/cloudflare_build.sh, nikoliv samotné _headers/_redirects. Tenantová metadata generuj z konfigurace. Před úpravou publikace akcí zjisti její existující kontrakt; názvy `(Copy)` neopravňují k mazání nebo skrytí dat.

Postupuj po etapách plánu. Změněné faktické předpoklady oprav přímo v plánu s důkazem. Nenechávej placeholdery ve veřejném obsahu, falešné reference, ceny, paralelní redirect pravidla ani nepoužívané fontové požadavky. Chybějící skutečné podklady pro veřejná tvrzení eviduj jako závislost. GA, ads.txt a SPF hodnoty nepřidávej jen kvůli skóre auditora.

Implementace vyžaduje nový pokyn uživatele; tento prompt sám ji neautorizuje. Bez dalšího oprávnění nepublikuj, neměň DNS/Cloudflare ani produkční data, necommituj a nepushuj. Pro případný schválený release platí jediný tenant vstupenky.online, lokální buildy a automation/deploy_direct.sh s repository gates. UX/UI delegace je výslovně požadovaná; další nezávislé subagent audity nejsou zadány. Při předání uveď skutečný výsledek, cílené ověření včetně převzetí UI od Astra Medium a přesně zbývající provozní kroky.
