# Exekuce: XSS opravy, CSP a GitHub ochrany Festapp

Pracuj v `/Users/miakh/source/festapp`. Přečti kompletně autoritativní plán:

`docs/plans/web-security-hardening-plan-2026-10-18.md`

Implementuj celý jeho rozsah: bezpečný detail akce a SVG plánek, funkční CSP reporting a následný enforcing po kompatibilitní gate, GitHub secret scanning/push protection a další dostupné schválené ochrany. Zachovej rich HTML, statické SVG, rezervace, login/OAuth, administraci a Flutter/PWA. Limity kontejnerů/hostu řeší jiná session a jsou mimo rozsah.

Nejdříve čti aktuální `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md`, `CONTRIBUTING.md`. Verification standard; dodrž také povinné publication/release gates. Kořenový checkout obsahuje cizí rozsáhlý diff: založ izolovaný checkout z aktuálního main a nic z něj nepřenášej plošně. Při novém faktickém rozporu aktualizuj plán s důkazem.

Jediný rollout tenant je `festapp` / `prod/festapp` / `live.festapp.net`. Sdílený kód patří main. Ověř canonical aktivaci, identitu zdrojů a tenant ancestry. Routine local build/deploy přes `automation/deploy_direct.sh` a live-version ověření deleguj podle AGENTS.md na `gpt-6-luna`, low, `fork_turns=none`, s přesným SHA a gates. Nespouštěj GitHub Deploy workflow ani další tenanty. Pokud tenant identity neodpovídá předání, vyřeš konkrétní nesoulad před deployem.

Pokyn k exekuci tohoto promptu zahrnuje implementaci, repository publication podle jejích pravidel, uvedený single-tenant release a výslovně schválené GitHub nastavení. Nežádej znovu obecné schválení téhož. Neopravňuje k placeným produktům, produkčním testovacím objednávkám, rozesílání zpráv, změně backendových limitů nebo jiným tenantům.

Nevynechej Worker HTML response větve, přesné inline hashes z finálních artefaktů, bezpečný report endpoint ani fallbacky. Neřeš kompatibilitu globálním unsafe-inline/unsafe-eval, regex SVG sanitizerem nebo vrácením raw malformed SVG. Nepokládej Report-Only za dokončený enforcing. Rollback CSP musí zachovat XSS opravy.

Spusť cílené testy z plánu a povinné repository gates, skutečnou izolovanou browser matici a readback GitHub nastavení/live hlaviček. Nevypisuj secrets. Nespouštěj nezávislý subagent audit; delegace je zde určena rutinnímu release.

Dokončení zaznamenej do `docs/operations/web-security-hardening-result-2026-10-18.md`: source/live SHA, testy a kompatibilitní důkazy, CSP režim a příjem reportu, GitHub stav a přesné případné blokery. Skonči krátkým souhrnem výsledku; neoznačuj nesplněnou CSP gate nebo nenastavenou ochranu za hotovou.
