# Realizace Make review a přechodu na jednotné API

V repozitáři Festapp přečti `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní [plán](make-review-and-cutover-plan-2026-11-19.md). Použij standardní ověření.

Oprav připomínky Make v existujícím ticketu #2351677 a stejné aplikaci `vstupenky-online-buoz5u`. Posuzovanou definici identifikuj podle živého readbacku a říjnového digestu. Připrav opravený konektor přímo nad regionálním OpenAPI a aktualizuj ho ve stejném review. Dolož přesný produkční callback, report s mikrosekundami, OAuth a všech pět modulů. Odeslání odpovědi, publikaci a produkční změny proveď v autorizovaném rozsahu.

Před odebráním původní cesty ověř schválenou katalogovou verzi, produkční OAuth a přechod doložených konzumentů. Poté odstraň `/make/v1` i související aktivní alternativy podle plánu. Pokud zjistíš odlišný živý stav, zaznamenej důkaz a uprav pořadí v plánu při zachování schvalovací brány.

Výsledek dolož stavem review, katalogu, přesnými běhy, CI a důkazem o odstranění legacy transportu. Rozpracovanou fázi označ konkrétní zbývající podmínkou.
