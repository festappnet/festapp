# CI/release flow - lokální výsledek

Implementace: `/Users/miakh/source/festapp-ci-release-flow-20261110`, větev
`refactor/ci-release-flow-20261110`, základ `bdea2039cfa2332e5e746b2ca4c462bc12a6c612`.
Uživatel výslovně přijal změnu politiky vlny 1. Původní dirty checkout zůstal
nedotčený. Žádný commit, push, PR merge ani produkční build/deploy nebyl proveden.

## Dodané změny

| Vlna | Lokální implementace | Dosud neprovedené provozní exit kritérium |
|---|---|---|
| 1 | Cílené lokální testy, autoritativní GitHub lanes; shodná pravidla a kanonický release skill, installer spuštěn a symlink ověřen | Publication timeline |
| 2 | Jediná mapa v checks.json, stejný owners() pro lokální/hosted výběr; odstraněny inputs.json, affectedInputs a step kopie | Hosted affected-selection ověření po publikaci |
| 3 | Přímé execution receipts s API/job/attempt/artifact/digest/checkout/toolchain vazbou; interní PR -> main reuse, konzervativní vykonání při nejistotě | Nový skutečný PR/main scénář a nový baseline |
| 4 | Exact-source gate v každém hosting adaptéru přes společný builder, startup scénáře vlastní CI, hotový bundle má navíc modulový smoke | Jeden povolený tenant build a skutečný browser smoke |
| 5 | Receipt ve version manifestu, ochrana zdrojů/configu/flags/toolchainu/výstupů, zachování starých artefaktů a timeline build/upload/live probe | Skutečné pokračování uploadu a end-to-end měření |

## Ledger a inventář

Osm veřejných check names zůstalo stejných. Počet jednotek 36 -> 34: odstraněny
jen `image-server-install` a `image-server-policy`. Jejich příkazy mají původního
vlastníka `image-install`/`image-policy`. MCP/auth sada zůstala v server-policy.
Všechny ostatní příkazy jednotek jsou stejné, s výjimkou deploy-contract, kam
přibyl test hotových modulových vstupů.

Z původních 956 evidovaných testovacích vstupů nebyl odstraněn žádný; přibyl jeden
Node test (957 celkem). SQL inventář 409 testů, SQL skupiny i skutečný upgrade
zůstaly beze změny. Python kontraktní testy se dále automaticky sbírají existujícím
CI příkazem. Z builderu zmizelo opakované volání celé startup sady, její CI vlastník
zůstal. Source gate před buildem i uploadem zůstává. Pravidla a globální release
skill nyní určují direct deploy jako výchozí executor, hosted Deploy jen výslovně.

## Ověření a časy

- Finální Python dávka: 52 testů PASS, 5,393 s. Pokrývá skutečné Git stromy,
  merge/squash/rebase, změněný base, původ důkazů, neplatné artefakty, expiry,
  attempts, API výpadek, zákazy řetězení i změny build vstupů a výstupů.
- Po poslední úpravě zachování pozměněného artefaktu: cíleně 3 receipt testy
  PASS, 0,492 s. Neplatný build nelze znovu uploadovat, ale nový build může
  pokračovat po uchování starých bytů pro diagnostiku.
- Test hotových modulových vstupů: 1 test PASS, celý Node proces 0,086 s.
- Deploy workflow a direct-deploy kontrakty PASS. Syntaxe změněných shell/JS
  vstupů, git diff --check a skutečný inventory check PASS.
- Závislosti validačního rendereru byly nainstalovány pomocí pnpm 11.24.0 a
  frozen lockfile. PyYAML 6.0.3 je v odděleném dočasném venv.

Časy jsou jednotlivá lokální měření, nikoliv medián ani celkový čas releasu.
Celková kritická cesta před/po nebyla změřena; cold GitHub běh, PR/main převzetí,
produkční kompilace, upload retry ani živý smoke nejsou součástí této autorizace.
Procentní ani časové zrychlení produkčního toku se proto netvrdí. Dřívější
opakované či neúspěšné vývojové dávky nebyly měřením release výkonu.

## Hranice před publikací

Nová politika není publikována. První hosted běh vytvoří nový plně vykonaný
baseline; staré receipts nový kontrakt nesplní. Před autorizovanou publikací je
nutné fetch/integrace aktuálního upstreamu, kontrola branch protection a ověření
změn, které tím přibudou. Plánované skutečné GitHub a produkční scénáře zůstávají
otevřené. Není oprávněné považovat lokální fixtures za jejich náhradu.

Strojový inventář, přesné příkazy a logy:
[ci-release-flow-evidence-2026-11-10.json](ci-release-flow-evidence-2026-11-10.json).
