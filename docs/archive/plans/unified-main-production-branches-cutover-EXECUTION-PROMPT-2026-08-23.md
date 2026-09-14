# Execute: Jedna kanonická aplikace Festapp a tenké produkční branche

Nejprve v `<repo-root>` přečti níže uvedený plán z absolutní
cesty. Je zatím necommitnutý v dirty CSM worktree, takže nový main worktree jej
automaticky neuvidí. Do současného dirty worktree nevstupuj s implementací;
podle Wave 0 vytvoř hashovaný inventory, čistý izolovaný cutover worktree a oba
plan artifacts do něj přenes beze změny.

Použij repository instructions v `AGENTS.md`/uživatelských instrukcích,
`docs/architecture/ai_context.md`, `CONTRIBUTING.md` a verification `standard`.
Autoritativní plán je:

`<repo-root>/docs/archive/plans/unified-main-production-branches-cutover-plan-2026-08-23.md`

Před editací jej přečti celý. Proveď všechny vlny v pořadí. Výsledkem musí být
jeden canonical shared source v `main`; `prod/csmostrava2026` a
`prod/hvezdamorska` smějí lišit pouze explicitními, reprodukovatelnými tenant
overlays. Přenes všechny aktivní CSM/HM změny, včetně aktuální HM product-type
description opravy, do main. Nestačí, že nový happy path funguje: odstranění
branch-only shared implementací, starých fallbacků a nezařazených rozdílů musí
být prokázáno ledgerem, drift gate, content-generation proof a targeted testy.
Drift policy, allowlist a checker vždy načítej z recorded main SHA; nikdy z
produkční branche, kterou právě kontroluješ. Expected tenant tree sestavuj z
čistého main tree + povolených source/data overlays + fresh config generation.
Neveřejné security/provisioning hodnoty, provozní kódy a seed payloads patří do
uživatelova repa `private configuration repository`, ne do Festappu. Security/authorization logika a
public input schema naopak patří do main. Ověřený private owner je
`the private configuration repository`, lokálně `<private-config-repo-root>`; publishing
manifest je `release/store-listings/csm-ostrava-2026/config.json`. Credential
soubory ponech pouze v ignorovaném `release/private/` nebo schváleném secret
manageru.

Nevytvářej placeholders, paralelní business implementace, branch-name runtime
podmínky, speculative fallbacky ani plošné `ours` conflict resolutions. Pokud
aktuální repository evidence vyvrátí fakt v plánu, aktualizuj přímo autoritativní
plán a přizpůsob dotčenou wave, aniž bys tiše změnil požadovaný outcome.

Nespouštěj production migrace, deploy, store release, force push, commit ani push
bez samostatného oprávnění. Před každým commitem postupuj podle
`CONTRIBUTING.md`: ukaž staged stav a vyžádej potvrzení. Na závěr odevzdej main,
CSM a HM SHAs, ledger coverage, canonical contract, odstraněné legacy cesty,
validation results, retained boundaries a přesný seznam unapplied operational
kroků či blockerů. Netvrď, že CI drift gate nelze obejít, dokud není samostatně
ověřené i external branch protection / required status check nastavení.
