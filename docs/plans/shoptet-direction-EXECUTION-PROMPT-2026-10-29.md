# Shoptet - pokračování podle zjištěného platformního kontraktu

Historický výzkum a návrh z 29. 10. 2026, začleněný 6. 11. 2026. Nejde o implementaci ani novou autorizaci realizace. Tehdejší záznamy o neodeslání jsou překonané [stavem potvrzeným vlastníkem 1. 11.](shoptet-partner-onboarding-2026-10-26.md): návrh byl odeslán, čeká se na odpověď a další podání se neposílá.

Toto je historické zadání. Pro další práci je jedinou aktuální autoritou [Commerce Connectors execution prompt](commerce-connectors-EXECUTION-PROMPT-2026-10-29.md), který respektuje společné jádro pro další e-shopy a trvající zákaz odesílání.

Pracuj v `/Users/miakh/source/festapp-shoptet-research-20261029`. Přečti AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md; ověřování standard.

Autoritativní podklad pro směr a rozhodovací brány je `docs/plans/shoptet-direction-plan-2026-10-29.md`, přečti jej celý. Ověřený veřejný kontrakt a jeho hash je v `docs/plans/shoptet-direction-evidence-2026-10-29/public-contract.json`.

Vlastník vybral A a požaduje samostatné ověření bez opakovaného psaní Shoptetu. Přečti také `docs/plans/shoptet-self-verification-2026-10-29.md` a důkaz veřejného frontend kódu. Q1-Q7 nejsou automatické dotazy k odeslání; přednost mají dokumentace a připravené sandboxové scénáře S1-S10. Cílem není automaticky implementovat kvótu. Vybraný směr je společná rezervace přes zvlášť schválený shipping-request / digitální doručení. Potvrď dostupnost a Q1-Q7, zejména vynucení nabídky pro aktuální položky, revizi a finalitu před uvolněním kapacity. Pouhá expirace a webhook bezpečnost neprokazují. Až podle výsledku rozhodni mezi A, kvótou B a výhradním prodejem C; omezení C vyžaduje rozhodnutí vlastníka. Externí checkout není tichý fallback.

Trvá výslovný zákaz cokoli odesílat: žádné e-maily, podání, zápisy do externích formulářů, rezervace, košíky, testovací objednávky ani placené operace. Zatím pokračuj jen lokální přípravou a veřejným čtením. Po získání nové konkrétní autorizace proveď pouze jí pokrytou etapu; přístup k sandboxu sám neopravňuje k libovolným mutacím.

Neprováděj produkční migraci, reload, deploy, commit nebo push. Nevytvářej další agenty bez požadavku. Nevydávej přítomnost API endpointu, marketingové tvrzení nebo úspěšný lokální SQL test za důkaz Shoptet souběhu. Při nové skutečnosti oprav autoritativní podklad a navazující doporučení. Handoff musí jasně odlišit ověřený fakt, návrh a nezískanou platformní garanci.
