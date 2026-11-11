# Rychlejší webový build - výsledek

Datum: 2026-11-11. Stav: lokální implementace a ověření dokončené.
Verification: standard. Bez push, změn prod větví, uploadu nebo live změn.

Webová změna s běžným zvýšením verze nyní použije nezměněnou Flutter kompilaci.
Medián celého buildu klesl ze **123,2 s na 60,4 s**. Kompilace a kompletace
včetně finální verifikace klesla ze **78 s na 18 s**, tedy o **76,9 %**.
Hypotéza alespoň 70 % pro tuto část byla splněna. Celková úspora je **51,0 %**;
největší zbývající položkou jsou zachované startup/browser kontroly.

## Změněné hranice

- `build_web_bundle.sh` zůstává jediným orchestrátorem. Příprava, raw Flutter,
  raw Vite a kompletace mají samostatné hranice. Cache hit vynechá pouze compiler;
  preflighty, postprocessing, startup testy, PWA/CSP a ověření pokračují.
- `web_build_cache.mjs` a `web_build_inputs.json` hashují obsah, cesty, módy,
  dirty/untracked a ignorované generované vstupy, lokální/vendored balíčky,
  skutečné dependency bytes a alias bindings, SDK revizi, compiler snapshoty,
  nástroje, parametry a relevantní prostředí. CLI odmítne jiné než deklarované
  compiler parametry. Neznámý relevantní vstup invaliduje cache konzervativně.
- Pouze pro prokázané SDK/compilery se Flutter verze přesunula do kompletace.
  Čerstvé `version.json`, HTML, bootstrap, main/deferred názvy a PWA metadata
  používají novou verzi. Vite `APP_VERSION` nadále invaliduje Vite. Nativní
  PackageInfo se neměnil. Jiný SDK/compilery zůstanou konzervativní do nového důkazu.
- Help/organizer obsah má jedno renderování nad built Vite runtime. Příprava
  katalogu přes `apply_config.sh <config> --build` negeneruje druhé dokumenty.
  Sitemap se kompletují z aktuálního obsahu. SEO měnící Vite HTML stále vyvolá Vite.
- Generátory konfigurace, fontů, verzí, brandu, HTML, embed a measurement runtime
  zapisují pouze změněný obsah. Z pnpm metadata se normalizují jen `prunedAt`
  a `lastValidatedTimestamp`; skutečná závislost, nastavení či alias změnu vyvolá.
- Oba hosting adaptéry po svém posledním ověření zapisují finální receipt.
  Obsahuje source/tenant/target/version, komponentové dependency a output hashe,
  původní revize compilerů i přesnou inventuru finálního balíčku. Kompletace má
  vlastní úplný fingerprint včetně packaging-only obsahu. `--skip-build` jej
  kontroluje před uploadem, stejně jako povinné CI/image/backend gates.
- Cache se publikuje atomicky pod zámkem, obnovuje se kopiemi, poškozené či
  neúplné výstupy/provenance znamenají miss. Retence chrání aktivní položky.
  Diagnostické `FESTAPP_WEB_BUILD_CACHE=off` ponechává všechny kontroly.

## Měření

Stejný Mac arm64, Node 26.8.1, pnpm 11.24.0, Flutter 3.47.7; SDK/dependency cache
již nainstalované. Cold znamená vypnutou artifact cache, nikoli smazání SDK nebo
`.dart_tool`. Běhy byly sekvenční, nejvýše jeden Flutter task na workstation.
Všechny browser kontroly provozoval Terra agent v izolovaných muted sessions.

Snapshot zdrojů je `742d614b722bbe619b3a095f66605bd4bb536006` s tehdejšími
rozpracovanými změnami v izolovaném worktree. Disposable konfigurace modeluje
vstupenky.online: `IS_APP_SUPPORTED=false` a existující PWA limity 35/80 MiB
z `origin/prod/festapptickets@202e27b46410385d09b7e453b31219dccc8b00e7`.
Backend zůstal generický main bez produkční aktivace; nešlo o prod release.

| Scénář | Běhy | Medián | Rozsah | Flutter / Vite |
| --- | ---: | ---: | ---: | --- |
| Opakování beze změny | 3 | 58,052 s | 56,710-62,998 s | hit / hit |
| Web JS + nová verze, cache off | 3 | 123,164 s | 122,695-130,496 s | miss / miss |
| Stejné web JS + verze, reuse | 3 | 60,388 s | 59,487-62,144 s | hit / miss |
| Změna nápovědy | 3 | 59,916 s | 59,365-64,836 s | hit / hit |
| Pouze sémantická verze | 3 | 60,945 s | 52,373-61,487 s | hit / miss |
| Změna Dart souboru | 1 | 113,779 s | - | miss / hit |
| Obnovený výchozí stav | 1 | 59,825 s | - | hit / hit |

Kompilační/balicí část = Flutter + postprocessing + Vite + kompletace + finální
verifikace: cold medián 78 s (74-79), reuse 18 s (13-18). Celkový čas výše
zahrnuje i nezkrácené startup kontroly. Měřicí série má 18 úspěšných běhů.
Jeden pokus help-3 skončil po 26,149 s na CDP `Fetch.enable: Session with given
id not found`; stejný canonical běh poté prošel bez změny kontrol. Failed log
ani čas nejsou vymazané. Již úspěšné scénáře se při obnovení neopakovaly.

První obecný main build odhalil zastaralou MCP referenci a následně obecné
PWA limity 25/60 MiB neodpovídající vybranému tenantovému profilu. Reference je
opravená; její digest již nereaguje na nesouvisející překlady. Image preflight
prošel. PWA limity ani jiný produkční gate se v repozitáři nezvyšovaly. Prázdný
Cloudflare projekt neblokuje lokální static/Cloudflare build.

## Důkaz verze a parity

Dvě skutečné kompilace verzí `0.20.1+485` a `0.20.1+486` vytvořily identické raw
`main.dart.js` (14 694 097 bytes) a deferred `main.dart.js_1.part.js`
(11 679 771 bytes), včetně SHA-256. SDK revize je
`abaf9c523780a608bd46686fd5e53740a07077f8`; přesné compiler hashe jsou v manifestu.
`PackageInfoPlusWebPlugin` 10.2.2 čte runtime `version.json`; SDK jej vytváří
odděleně přes `createVersionFile`. Sémantické verze 0.20.2, 0.20.3 a 0.20.4
následně prošly skutečným cache hit a kontrolou nové JSON/HTML verze.

Párové cold/reuse inventury se shodovaly kromě interního `.last_build_id`.
Flutter jej používá pro úklid příštího incremental buildu; finální kompletace
jej nyní odstraní a původní compiler ID zůstává v raw provenance. SDK náhodný
`serviceWorkerVersion` v default bootstrapu se stampuje stabilní identitou
releasu. Aplikace nadále používá svůj původní vlastní service worker.

Finální Cloudflare adaptér byl ověřen ještě jednou na dokončených validacích:
**cold 143 s (miss/miss), warm 67 s (hit/hit)**. Oba prošly worker/PWA/CSP a
finální verifikací; všechny finální soubory bez samotného receipt jsou přesně
bajtově shodné. `web_build_cache.mjs verify cloudflare` nad skutečným packetem
prošel. Finální receipt obsahuje oddělené dependency/output hashe a původ obou
kompilací, bez `.last_build_id` v nasazovaném souborovém seznamu.

## Kontroly a předání

- Kanonický `bash automation/test_ci.sh web-startup`: **PASS, 48,72 s** na
  lokálním dirty source; zahrnuje browser a deploy-contract kontroly.
- Behaviorální cache/receipt/command-parameter/generator/digest testy prošly,
  včetně corrupted/incomplete provenance, alias změn, SDK/defines/lock/asset/
  tenant invalidace, ignorovaných/untracked vstupů, souběhu a přerušených zápisů.
- Negativní skutečný `deploy_direct.sh --skip-build` se stub uploaderem odmítá
  změněné/chybějící/přidané soubory, tenant/verzi i chybějící receipt před uploadem.
  Packaging-only změna a neúplný původ compileru jsou rovněž odmítnuty.
- Konfigurační repeat/mtime a tenant-switch testy, help/organizer render testy,
  deploy workflow/direct kontrakty, release-gate testy a CI contract prošly.
  `bash -n`, syntax cache modulu a scoped whitespace kontrola prošly.
- GitHub CI evidence reuse přes `selection.py`, ancestry/drift a release gates
  se nezměnily. Před případnou publikací jsou nadále nutné všechny ovlivněné
  canonical lanes a před releasem přesný GitHub baseMainSha gate.

Měřicí driver, logy, raw version proof, inventury, measured tooling snapshot a
ověřený finální receipt jsou uchované v
[lokálním evidence adresáři](../../.artifacts/build-speed-20261111/evidence/).
Souhrn: [summary.json](../../.artifacts/build-speed-20261111/summary.json).
Zdrojové varianty JS/help/verze/Dart byly obnovené. Jediný izolovaný worktree
zůstává dostupný pro reprodukci; neběží v něm server ani měřicí proces.

V lokálním rozsahu nezůstává blokující nebo nedokončený bod plánu. Upload a live
probe se neměřily, protože produkční rollout vyžaduje samostatnou autorizaci.

## Integrace do aktuálního mainu při publikaci

Autoritativní main od měřicího snapshotu přidal telemetry, sdílený Flutter slot,
CI DAG a kanonický `automation/release/build_receipt.py`. Integrace zachovává
všechny tyto hranice i hlavní marketing runtime. Node modul nově vlastní pouze
komponentovou cache a fingerprint/provenance; existující Python receipt vlastní
jediné finální seal/verify/preserve. Kompaktní atestace zůstává ve
`festapp-version.json.buildReceipt`, úplná inventura v `build/web-build-receipt.json`
mimo nasazovaný web. Podrobný receipt se zachovává i u archivovaných artefaktů.
Původní samostatná `.festapp-build-receipt.json` ani druhé časování se nepublikují.

Aktuální main již přesunul source startup suite za přesný CI gate. Integrace ji
proto znovu nepouští v produkčním buildu. Časy výše jsou řádně označená měření
původního snapshotu se sériovými startup kontrolami. Tenant overlay/baseMainSha
je packaging vstup, takže samotná nová revize releasu neinvaliduje kompilaci;
skutečnou tenantovou identitu nadále vlastní celý generovaný config.

The measurement receiver generator remains unchanged from canonical main because its source bytes identify separately deployed receiver workers. Its output already stays byte-identical; changing that independent deployment identity is outside this tenant release.
