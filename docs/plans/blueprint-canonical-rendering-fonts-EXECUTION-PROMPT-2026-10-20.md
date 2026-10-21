# Realizace: kanonický Blueprint render a kvalitní fonty

Pracuj v hostu `/Users/miakh/source/festapp-blueprint-cutover-release-20261019`
a package `/Users/miakh/source/venue-seat-picker-blueprint-b-20261019`.
Přečti repository instrukce a celý nový autoritativní plán:

`docs/plans/blueprint-canonical-rendering-fonts-plan-2026-10-20.md`.

Tento plán nahrazuje staré pořadí auditního plánu. Jeho původní ST/CT/PH/TX/PR/IO/MG/UI/PF
acceptance zůstává závazná; nový plán ji mapuje a přidává T1-T8. Zachovej současné
necommitnuté změny a před začátkem porovnej HEAD/diff/digests s baseline v plánu.
Nepracuj automaticky v dirty původním `/Users/miakh/source/festapp`.

Cíl: jeden dokument 2, resolver a text-layout owner, stejné positioned glyph paths
pro Flutter a web, skutečné řezy a kvalitní typografie. Text se shapuje v souvislém
kontextu, ne součtem samostatných šířek znaků. Poté lze použít jednotlivé glyph
paths nebo spojenou cestu labelu. Cache obrysů nesmí zrušit kontextový shaping.

Začni vlnou 0: uzavři jediný engine, jeho připnuté verze, face support, Unicode
algoritmy a Edge/latency proof. Fontkit.layout je primární kandidát; neprojde-li
corpus proti HarfBuzz oracle, nahradit jediný backend v téže hranici, ne přidat
runtime fallback. Vlnu 1 nepovažuj za hotovou: mask admission a derived ×N glyph
regrese jsou stále otevřené. Pak dokonči vlny 2-7 v závislostním pořadí.

Verification: standard. Jediný Flutter task na workstation, testy s
`--concurrency=1`, disposable backend s ověřeným markerem, browser izolovaně/headless.
Používej owning suites a skutečné extrahované distribuční artefakty. Nezaměňuj
neprázdné paths ani archive boot za přesnou paritu nebo raster kvalitu.

Zachovej aggregate revision, receipts, frozen retry bytes, spot/ticket identity,
SQL finance/holds a live guardy historie. Capture/restore není dostatečný undo guard.
Nepřidávej druhý font katalog, renderer, business autoritu ani editorový framework.
Odstraň nahrazené cesty podle deletion ledger; importer 1 jen na vstupní hranici.

Při změně faktického předpokladu aktualizuj plán s důkazem. Žádné placeholders,
faux B/I, tiché náhrady glyphů, schema downgrade nebo neplánované kompatibilní cesty.
Každá vlna má vlastní exit důkaz; konči až po všech lokálních podmínkách dokončení,
ne po prvním passing font probe. Žádný nezávislý paralelní agentní audit bez zadání.

Produkční tenant/rollout nebyl určen. Produkční převod/deployment, commit/push a
registry publication vyžadují samostatnou autoritu. Na konci předej canonical ownery,
odstraněné cesty, přesné parity/font-quality výsledky a oddělené provozní kroky.

Upřesnění uživatele 2026-10-20: migrační nejasnosti rozhodni automaticky, zachovej identity, aktuální produkty a materializované polohy, nejistý produktový záměr ulož jako vlastní přiřazení. Rozhodnutí zaznamenej do receipt; běžné nejasnosti nečekají na ruční schválení.
