# Implementace zkrácení CI a release přípravy

Přečti celý autoritativní plán
`docs/plans/ci-release-latency-plan-2026-11-13.md` a platné AGENTS.md,
CLAUDE.md, ai_context.md a CONTRIBUTING.md. Pracuj v režimu ověřování standard.

Implementuj jeho kroky v čistém worktree z aktuálního autoritativního main.
Původní workspace obsahuje rozsáhlé cizí změny a starší CI; nepřebírej je.
Pokud nové důkazy zneplatní předpoklad, oprav plán a pokračuj podle doloženého
stavu. Začni existující telemetrií/preflightem a cíleným Git checkoutem.

Zachovej osm required checks na přesném baseMainSha, ověřování skutečné
exekuce a původu artefaktů, stejné semantic case ID a skip důvody, všechny
resource limity a jeden Flutter task s --concurrency=1. Nesnižuj pokrytí,
nepřijímej pending/failed evidence, nepřidávej skip flagy, neověřené reuse,
nový frontovací/cache systém ani plošný sleep. Zachovej upload gate a live probe.

Dokončení dolož baseline/head SHA, cílenými kontraktovými testy, povinnými
affected CI mirror lanes a srovnatelným měřením před/po. U Flutter slučování
prokaž inventář i izolaci; bez úspory nebo při úniku stavu změnu vynech.
Výsledky zapiš k plánu. Nezanechávej placeholdery ani dočasné alternativní cesty.

Tento prompt sám neautorizuje push, změnu branch protection, placený runner ani
produkční deploy. Při odděleném zadání publikace/releasu dodrž standardní gates,
aktuální main a tenant scope; implementace ani zelené lokální testy je nenahrazují.
