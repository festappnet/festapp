# Zadání pro další realizační session

> Toto původní zadání je nahrazeno
> [novým execution promptem](blueprint-canonical-rendering-fonts-EXECUTION-PROMPT-2026-10-20.md).
> Pro další realizaci použij nový plán kanonického renderu a kvalitních fontů.

Implementuj stabilizaci datového modelu Blueprintu podle autoritativního plánu:
`docs/plans/blueprint-data-model-audit-plan-2026-10-20.md`.
Reprodukce současných chyb:
`docs/plans/evidence/blueprint-data-model-audit-20261020.md`.

Tento soubor je připravené zadání pro příští session. Jeho vytvoření samo
nespouští implementaci v nynější plánovací session.

## Výchozí pracovní kopie

- Host `/Users/miakh/source/festapp-blueprint-cutover-release-20261019`,
  baseline `a3a0637d8eeec1b0d5d3a5292e6db62fdcb4f5d1`.
- Package `/Users/miakh/source/venue-seat-picker-blueprint-b-20261019`,
  baseline `0b881853bd9071784fd66102a03a1606a81afa79`.
- Nejdřív přečti repository instrukce, celý plán a porovnej aktuální head/diff.
  Zachovej cizí změny; původní `/Users/miakh/source/festapp` není automaticky
  správná pracovní kopie. Plán se vztahuje k výše uvedeným baseline.
- `verification: standard`; jediný Flutter task na workstation, Flutter testy
  s `--concurrency=1`. Používej owning suites a izolovaný disposable backend.

## Cíl a pořadí

Postupuj sedmi vlnami plánu. Nejdřív scoped-font save/read chyba, potom kontrakt
2 a čistý importer, fyzické operace/styling, transakce a bindings, async save a
projekce, převodní corpus/UI/výkon a nakonec distribuované artefakty/cutover gate.

Výsledek má jeden interní model a renderer, sparse stylové deklarace s leaf
resetem/provenance, explicitní child seat styl, oddělenou fyziku, placement
union, integer grid boundary + uložený modul a product assignment mode.
Zachovej node/spot/ticket identity, SQL finanční autoritu, aggregate revision,
receipted retry a historii celého aggregate. Undo/redo musí projít současnými
live guardy, ne slepě obnovovat host checkpoint.

Bezpečnostní invarianty a acceptance ST/CT/PH/TX/PR/IO/MG/UI/PF v plánu jsou
součástí zadání. Neodvozuj záměr produktu shodou ID, nesnapuj staré obrysy při
loadu, nededuplikuj explicitní styl shodný s defaultem a nespouštěj reflow při
rigidním přesunu. Font/inline editor/scéna/resource collector mají jeden resolver.
Nepřidávej CRDT, druhý runtime formát ani obecný plugin/command framework.

## Důkaz a hranice

Každou vlnu uzavři jejím exit důkazem. Nestačí neuložený náhled: ověř save ->
read -> render -> copy ve Flutteru i skutečném distribuovaném JS kernelu.
Diagnostický passing probe F9 potvrzuje chybu; cílový TX2 má opačné očekávání.
Odstraň staré cesty podle deletion ledger, importer 1 ponech jen na pojmenované
vstupní hranici. Aktualizuj plán, pokud se konkrétní předpoklad změnil, s důkazem.

Produkční tenant ani rollout tímto zadáním nejsou určeny. Produkční převod,
deployment, commit/push nejsou součástí tohoto připraveného zadání; pro ně je
nutný odpovídající další rozsah. Žádný nezávislý paralelní agentní audit bez
výslovného zadání. Na konci předej kanonické ownery, odstraněné cesty, výsledky
parity a přesně oddělené neprovedené provozní kroky nebo blokery.
