# Lokální podklady náhledu vstupenek - výsledek

Datum: 2026-10-22. Výchozí commit: `d392ed38810cce2d8716c41b43cd4698eaf94462`.
Implementace je ve worktree `festapp-ticket-preview-cpu-20261022`, bez commitu,
push nebo produkčního nasazení. Verification: standard. Zvýšený CPU limit
preview zůstává podle výslovné změny zadání; email budget se nemění.

## Výsledný kontrakt

- Nový klient používá pouze `resourceProtocol: 3`, stále s `fontProtocol: 2`.
  Resolve vrací autorizovaný aktuální template, syntetické scénáře, katalog,
  identity fontů a aktuální image reference. Nevrací font/image bytes,
  metriky, galerii ani QR matici. Nepodporovaný kontrakt nemá legacy retry.
- Jeden generátor vlastní manifest z existujících TS presetů, šesti přesných
  fontových souborů a 21 historických artwork verzí. Backend i Flutter čtou
  stejný manifest. Build/CI `--check` a mutation proof kontrolují drift/hash.
  Schema layoutu 3 ani uložené URL/identity fontů se nemění.
- Vestavěné fonty mají metriky a PDF probe připravené při generování. Ostatní
  fonty po důvěryhodné validaci publikují bytes a immutable metrics sidecar
  do stejného privátního R2 kontraktu. Cold read nové instance neparsuje font
  ani nevyrábí zkušební PDF. Chyba/cizí digest/konflikt selhává uzavřeně.
- Nastavení sdílí context a klonované image handles s editorem. Viditelné
  gallery cards načítají místní podklady. Veřejná image cache má limit
  24 MiB / 16 položek, session vlastní své disposable klony. Privátní fonty
  nepatří do globální cache; JWT/private image read používá stávající Worker,
  neposílá token jinému originu a nepovoluje redirecty. Změna práv, identity
  nebo odhlášení zneplatní session i pozdní odpovědi, včetně návratu A-B-A.
- Samostatná galerie setup draftu používá tentýž lokální katalog a font owner.
  Draft revision vstupuje do kontextového klíče. Save/conflict commands,
  read-only a setup autorizace, explicitní PDF, jediný renderer i `layout-text`
  zůstávají zachované. HarfBuzz se importuje až pro explicitní `layout-text`.
- Legacy binary resolve zůstává výhradně pro již distribuované aplikace.
  Galerie jejich externího protokolu je vědomě zachovaná hranice.

Přírůstek deklarovaných raw statických assets proti původnímu jedinému
`font-catalog.json` je 1 422 728 bytes, včetně licencí a všech zachovaných
artwork verzí. Je to skutečný obsah Flutter asset bundlu, nikoli měření
komprimovaného release APK nebo přenesených webových assets. Galerie se v novém
klientovi před otevřením neregistruje ani nedekóduje.

## Runtime důkaz

Reprodukovatelný příkaz:

```sh
python3 automation/tickets/verify-preview-runtime.py \
  --baseline d392ed38810cce2d8716c41b43cd4698eaf94462 \
  --evidence /absolute/new/evidence-directory
```

[Sealed receipt](../../build/ticket-preview-runtime-sealed/result.json) obsahuje
hash měřených zdrojů, skriptu, připnutý image digest a všechna měření. Hashy
měřeného backendu odpovídají finálním souborům.

Běh: Edge Runtime v1.74.0, 1 CPU, 3 studené workery + 20 opakování každého
protokolu, zachovaný soft/hard budget 20/30 s. Šest workerů obsloužilo všech
46 requestů bez retirementu. CPU je container cgroup `usage_usec`, včetně routeru,
bootu workerů a spotřeby syntetické odpovědi.

| Metrika | Výchozí binary resolve | Nový metadata resolve |
|---|---:|---:|
| Odpověď | 1 453 930 B | 5 274 B |
| Cold CPU, tři běhy | 678,816 / 562,664 / 512,856 ms | 171,231 / 313,409 / 251,256 ms |
| Medián CPU, 20 opakování | 38,646 ms | 2,343 ms |
| Medián času, 20 opakování | 36,334 ms | 2,136 ms |
| Resource loader v posledním opakovaně používaném workeru | 21 volání | 0 volání |

Workload používá skutečný handler a renderer s výhradně syntetickými
occasion/catalog/auth adaptéry. Příprava ESZIP může stahovat veřejné závislosti;
měřený běh má síť odpojenou, žádné host bindy/porty ani produkční credentials.
Deno JS bundler zabalí přesné připnuté WASM/trie bytes a doplní standardní Node
globals; nenahrazuje shaper, font parser ani renderer mockem. Nejde o měření
produkční Auth/SQL latence ani o tvrzení o původním implicitním CPU limitu.

## Ověření

- Deno: 65 testů prošlo v cílené společné sadě. Po poslední změně metadata
  background hranice prošlo všech 30 preview testů. Patří sem zakázané
  resource/font závislosti, setup/read-only, autorizace, původní protokol,
  prepared cold fonts, poškozené sidecary, souběh/retry a všechny galerie/PDF.
- Image Worker: 111 unit testů prošlo; `pnpm run typecheck` prošel. Sidecar
  testy dokazují trusted service boundary, immutable create/replay, validaci
  metrik a existenci font bytes před publikací.
- Automation: 12 testů prošlo. Generátor `--check` prošel; manifest/artwork
  mutation je odmítnuta. Recursive staticPatterns i oba CPU budgety zůstaly.
- Flutter: finální společná sada `ticket_layout|occasion_setup` se skutečným
  raster exportem má 118 úspěšných testů a jeden nepovinný raster test přeskočený bez evidence env;
  po release opravě testovací přesnosti je společný gate zelený.
  Následné cílené lifecycle/transport/setup kontroly mají 6/6 úspěchů.
  Targeted Dart analyze nemá chyby ani warnings; stávající lint infos zůstávají.
- [Samostatný lokální Canvas/PDF report](../../build/ticket-preview-evidence/index.html)
  obsahuje 20 skutečně vykreslených scén: všech 18 presetů, češtinu, dlouhé
  a chybějící údaje. Headless spot-check klasické, serifové a konferenční
  kompozice odpovídá rozměry, textem, zalomením a artworkem. Všech
  [40 raster QR](../../build/ticket-preview-evidence/qr-proof.json) z canvasů
  i PDF se dekóduje na přesně stejný syntetický payload. Knihovny mohou zvolit
  odlišnou platnou QR masku; nikde se nepoužil skutečný admission symbol.
  Interaktivní chování aplikace ověřují widget/transport testy, nikoli tento
  statický browser report. Izolovaná browser session byla ukončena.

## Výchozí selhání a zbylý provozní krok

`shared valid and invalid geometry fixtures agree with Dart` při aktuálním FVM
přesně porovnává `405.162109375` s `405.16245`. Stejné selhání bylo znovu
prokázáno na čistém samostatném worktree původního commitu, bez změn tohoto
úkolu. [Baseline log](../../build/ticket-preview-runtime-sealed/baseline-geometry.log)
a finální client log uchovávají stejný rozdíl. Model geometrie ani fixture se
v této implementaci nemění. V navazujícím autorizovaném release byla opravena pouze testovací přesnost:
JSON pole a text se dál porovnávají přesně, Rect souřadnice s tolerancí
0,001 pt a normalizovaný crop s 0,000001. Běhová geometrie ani fixture data
se nezměnily. Cílená společná sada nyní prochází (118 testů).

Uživatel následně autorizoval merge i produkční rollout. Zbývá provést: nejprve rozšířený
privátní image Worker, potom Functions včetně připraveného manifestu, následně
lokální build a direct deploy klienta pouze `prod/festapptickets` podle aktuálních
release gates. Produkční canary ověří protokol 3 a skutečný přístup ke zdrojům.
Žádná SQL migrace, backfill ani změna storage authority není součástí změny.
CPU výjimka preview zůstává; nic se nepropagovalo do jiných tenantů.
