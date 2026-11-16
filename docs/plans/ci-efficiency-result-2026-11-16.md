# CI efficiency - výsledek 2026-11-16

Implementace dokončena lokálně: větev `perf/ci-efficiency-20261116`, čistý worktree od
main `2b9ca14268ce4d95e577a3ce2346bdd7684687fd`. Publikace CI byla následně autorizována uživatelem; ověřování hosted běhů probíhá. Produkční tenant rollout není součástí této změny.
Cíl 30 % se v tomto původním běhu nepovažoval za naměřený výsledek.

## Navazující měření instalované CMS matice

Následný audit zjistil, že hlavní část čekání tvoří postupný start služeb,
nikoli interakce checkoutem. Hosted výchozí job Wix trval 502 s, z toho CMS
412,8 s; samostatný seat browser scénář v checkout jobu trval 8,6 s. Tato čísla
pocházejí z runů `43852923883` a `43852923451` na main `e6850dae`.

Na stejném Macu prošla stejná devítipřípadová matice před změnou za 223,5 s
a po omezeném souběhu přípravy a úklidu za 138,5 s: o 85 s, tedy 38 % méně.
Oba běhy potvrdily nezměněné vstupy a všech devět scénářů. Cache a síť mohou
výsledek ovlivnit; jde o naměřený lokální běh, nikoli záruku hosted času.
Servisní databázová jednotka klesla ze 125,3 na 93,8 s; její souběh má vlastní
lease, jeden ze dvou DB slotů a zachovaný zámek generování zdrojů.

Celý následný lokální mirror všech osmi jobs na kódu `40bd4182` prošel za
471,34 s, `complete:true`, `inputsUnchanged:true`. Zachoval původní CMS matrix,
ochranu COOP, Chromium/Firefox/WebKit, kontroly oprávnění i cold upgrade.
Kontrakty výběru navíc dokazují, že samostatná změna objednávkové Edge Function
nezneplatní instalovanou CMS jednotku, zatímco změna formuláře, schématu,
sdíleného runtime nebo neznámý vstup ji stále spustí. Nová definice vyžaduje
čerstvé úplné hosted ověření před dalším produkčním rolloutem.

## Baseline

[Uložený vzorek](ci-efficiency-baseline-2026-11-16.json) vznikl read-only
z GitHub API, posledních sedm dní, nejvýše 100 runů na workflow. Obsahuje joby,
attempts, SHA, odkazy, výsledky, checkout/selector/provisioning/DAG časy a součet
runner minut včetně failure/cancelled. Runner minuty nejsou billing. Čekání
creation/start zahrnuje scheduling/concurrency; dostupná API neoddělují čisté
čekání na runner. Stav cache není zpětně známý. Třídy změn jsou pouze explicitně
popsaná heuristika z dostupných lokálních Git diffů, nikoli důkaz spotřebovaných
vstupů. Full/reuse jsou oddělené podle skutečného starého DAG kroku.

## Změna

- Jeden kontrakt obsahuje nové Wix quick/adapter/CMS a seat payment/order/delivery/service jednotky. Každý původní příkaz byl porovnán jako multiset a zachován právě jednou; SQL skupiny jsou přejmenované bez změny členství. Inventář rozšířen o integrační testy, jejichž předchozí chybějící registrace bránila jemnému výběru.
- Selector sdílí výpočty v rámci jednoho rozhodnutí, nejdřív porovnává main vstupy, ignoruje reuse-only joby před ZIP a ukončí síťový proces i potomky podle zbývajícího rozpočtu 20 s. API/kandidáti/download bytes jsou měřené. PR zůstává vázané na validovaný merge tree.
- Schema 2 odlišuje executed a reused řádky. Aktuální úplný aggregate, jednotkové fingerprinty, příprava, přímý původ artefaktu, attempt, stáří a toolchain se ověřují při výběru i konzumaci. Smíšený run má odlišný marker, reuse-only run nemá přímý exekuční marker. Staré schema neposkytuje jednotkový důkaz.
- Explicitní local stále běží celý. Každá SQL jednotka má vlastní lease, cluster zásahy jsou výlučné. Lokální přechod na Node Wix počká na všechny ostatní konzumenty. Cold upgrade je stále povinná kontrola; přímá shodná evidence může splnit ověřovací závislost, skutečné consumer prostředí se připraví znovu.
- CMS používá jednu frozen WordPress tool instalaci v rámci runu, soukromé kopie CMS stavu a nezměněnou devítipřípadovou browser matici. Hosted cache obsahuje jen browser binaries, klíčované platformou/lock/config. System dependencies se stále instalují; DB/CMS ani plovoucí image tagy nebyly přidány. Velké archivy image layers nejsou zavedené bez důkazu ceny přenosu.

## Validace a měření

- `python3 -m unittest discover -s automation/ci -p 'test_*.py'`: 72 testů PASS (5,57 s, izolovaný Python s PyYAML 6.0.3); stejná sada prošla i v image lane. Inventář: 462 SQL souborů, explicitní integrační testy. Source fingerprint všech 39 jednotek na osmi jobs: 1,14 s, pouze lokální výpočet, nikoli hosted selector/API benchmark.
- `automation/test_ci.sh` s task-owned DB `festapp-ci-efficiency-20261116:55742`: FAIL (wix-cms), sedm dalších lane PASS; elapsed 548.00 s, inputsUnchanged=True. Testy i runtime byly reálné; Flutter souběh 1, každý SQL domain vlastní lease. CMS scénář HTML selhal na 30s popup timeoutu, zaznamenáno bez přebarvení failure na PASS. Ostatních 38 jednotek prošlo. Sedm lane bylo PASS.
- Cílený následný `automation/test_ci.sh client-contract wix-checkout-compatibility`: PASS, 257.62 s, inputsUnchanged=True. Oprava mezi běhy pouze přesunula nonzero kontrolu subprocessu dovnitř měřené CMS fáze, aby její failure nebyla chybně označená success. Neměnila popup chování ani timeout. Tím je všech osm lane lokálně pokryto; nejde o jeden zelený full run. Devět CMS případů zůstává nezměněných. Intermitentní popup timeout zůstává rizikem k pozorování.
- Cold browser install 44,52 s, warm 0,76 s v prvním finálním mirroru. Prázdná samostatná browser cache měla 0 B, po instalaci 1 745 084 993 B; jde o instalované bajty, nikoli prokázaný síťový transfer. Docker image layers už byly lokálně přítomné: nejde o plnou cold infrastrukturní matici. Hosted cache transfer/restore cenu nelze odvodit z tohoto lokálního měření.
- První dva vývojové průchody (365,94 s a 253,16 s) mají inputsUnchanged=false a nejsou finální lane evidence. V obou prošlo všech devět CMS scénářů. Prvnímu běhu změna vstupů při aktivní SQL lease správně zablokovala nested acquire; příčina zmizela na zmrazeném zdroji. Jejich cenu evidujeme stejně jako pozdější failed pokus.
- [Lokální receipts a fáze](ci-efficiency-local-2026-11-16.json) zachovávají všechny pokusy, outcome a původní immutable cesty. Dokumentace a naměřená data byla dopsána po skončení testů; testovaný implementační kód zůstává stejný. Žádné GitHub runs nebyly dispatchovány, žádná produkce změněna. Task-owned runtime/CMS procesy a kontejnery byly uklizeny.

Baseline obsahuje 785 job observations a 2045.25 runner minut v omezeném
historickém vzorku. Nejde o spotřebu implementace nebo novou cenu CI. Tabulka níže
je popis starého stavu, nikoli před/po srovnání:

| Lane | N | Runner minuty včetně failure/cancelled | Runtime p50 s | Runtime p95 s |
|---|---:|---:|---:|---:|
| image-contract | 100 | 116.90 | 67.0 | 153.0 |
| web-startup | 99 | 200.23 | 154.0 | 232.0 |
| wix-checkout-compatibility | 100 | 301.47 | 93.0 | 498.0 |
| navigation-interactions | 100 | 245.93 | 180.0 | 266.0 |
| server-policy | 98 | 205.08 | 142.0 | 243.0 |
| client-contract | 98 | 250.57 | 187.0 | 279.0 |
| seat-checkout | 95 | 421.82 | 326.0 | 495.0 |
| ticket-preview-and-delivery | 95 | 303.25 | 234.0 | 335.0 |

Mediány a p95 jsou pouze popis tohoto omezeného vzorku; full/reuse rozpad a
workflow/job waiting jsou v JSON oddělené. Chybějí prokazatelné cold/warm a
per-unit hosted vzorky. Bez těchto dat nelze uznat cíl 30 % runner minut ani
30 % kratšího času k výsledku. Dlouhé historie reuse-only běhů mohou vyčerpat
20s budget a zvýšit spotřebu fallbackem; po publikaci sledovat hit rate i celkové
runner minuty. První změna definice vynutí cold exekuční baseline.

## Hosted dokončení

Po autorizované publikaci musí první změna CI definice skutečně provést celý
rozsah. Přesný release gate a všech osm jmen zůstávají povinné. Z běžných
následných běhů pak vyhodnotit dostupné srovnatelné třídy (alespoň pět pozorování),
oddělit cold/warm, full/reuse a frontu od exekuce. Přičíst bootstrap i opakované
pokusy. Nezakládat umělé runs pro naplnění tabulky a nedispatchovat duplicitní
workflow kvůli čekání. Lokální rychlost není důkaz 30% úspory hosted runner minut.

## Příprava autorizované publikace

Změna byla aktualizována na main `6c2273ed9474d49583dce5d96900c4751cf0c03f`.
Oba intervenující commity byly zkontrolovány; nový provider-live-state test zůstává
v kanonické web-measurement lane i inventáři. Před publikací bylo doplněno
vlastnictví sdílených SQL helperů v automation/lib, DB fixture modulů a společného
terminology JSON. Jejich změny nyní zneplatní všechny skutečné konzumenty.
To rozšiřuje konzervativní pokrytí; žádný povinný test nebyl odebrán.

Po aktualizaci základu: 73 CI kontraktových/negativních testů PASS (5,09 s),
`run.py inventory` PASS a konfigurace aplikována beze změny projekcí verze.
Canonical mirror `seat-checkout`: PASS; společný pokus trval 173.64 s
a Wix blok zastavila kolize s portem jiné session před vytvořením prostředí.
Následný canonical Wix mirror na vlastním bloku portů 61900: PASS,
211.62 s včetně cleanup, všech devět CMS scénářů, inputsUnchanged=true.
Fixture podporuje `FESTAPP_CMS_FIXTURE_BASE_PORT`; výchozí port zůstává 61000.
Původní pokus s kolizí portů je zachován jako neúspěšný.
