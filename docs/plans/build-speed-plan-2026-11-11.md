# Rychlejší webový build Festapp

Datum: 2026-11-11
Stav: Lokální implementace a ověření všech vln dokončené. Reálný medián web-only
releasu s novou verzí 123,2 -> 60,4 s; kompilační/balicí část 78 -> 18 s.
Viz `build-speed-RESULT-2026-11-11.md`.
Ověřování implementace: standard, protože změna zasahuje produkční release tooling.

## Výsledek a rozsah

Při změně veřejného webu, nápovědy nebo balení releasu znovu nekompilovat nezměněný Flutter. Opakovaný upload používá tentýž ověřený balíček. Změna Dart kódu nebo jiného skutečného vstupu Flutteru nadále vyvolá kompilaci.

Rozsah je kanonický webový build, jeho lokální cache a přímé nasazení jednoho vybraného tenanta. Android, iOS, změna frameworku, runtime přesun tenant konfigurace a hromadný rollout nejsou součástí. Implementace vzniká na main; tento plán sám nepovoluje push, změny prod větví ani nasazení.

## Doložený současný stav

| Fakt | Místo | Důsledek |
| --- | --- | --- |
| Každý build spouští Flutter i Vite a následně skládá jeden balíček. | `automation/build_web_bundle.sh` | Chybí opětovné použití komponent podle vstupů. |
| Před sestavením se mažou `build/web` a `web_client/dist`, nikoli celá `.dart_tool`. | `automation/build_web_bundle.sh` | Nelze tvrdit, že dnes vždy probíhá úplný clean build. Mazání finálního stagingu zachovat proti příměsi jiného tenanta. |
| Konfigurace se generuje před kompilací, některé soubory se zapisují bez porovnání obsahu. | `automation/apply_config.sh` | Rozlišovat změnu obsahu a pouhou změnu mtime. |
| Verze se propisuje do pubspecu, JS modulu a obou HTML vstupů. | `automation/configure_version.js` | Oddělení verzování vyžaduje důkaz, které výstupy závisejí na verzi. |
| Flutter klient čte PackageInfo. | `lib/data_services/update_service.dart`, `lib/services/platform_helper.dart` | Nová verze nesmí vytvořit rozpor mezi klientem a release manifesty. |
| Fonty se optimalizují, JS se kompaktuje a poté se přepisují názvy hlavního i deferred JS. | `automation/optimize_web_fonts.mjs`, `automation/compact_flutter_javascript.mjs`, `automation/emit_version_manifest.sh` | Do cache patří výstup před stampováním; cache se při kompletaci nesmí mutovat. |
| Startup testy včetně skutečného browseru jsou součástí buildu. | `automation/test_web_startup.sh`, `automation/tests/deploy_workflow.test.sh` | Cache kompilace sama nenahrazuje testovací gate. |
| Přímé nasazení má `--skip-build` a kontroluje zdrojové CI před buildem i uploadem. | `automation/deploy_direct.sh` | Před uploadem doplnit ověření identity a úplnosti prebuilt artefaktu; CI kontroly zachovat. |
| CI má samostatnou politiku reuse podle vstupů a stáří evidence. | `automation/ci/selection.py`, `automation/ci/inputs.json` | Cache artefaktů není CI evidence a nemá měnit její pravidla. |

Současná cesta: preflight -> konfigurace a závislosti -> Flutter -> postprocessing a stamp -> startup testy -> Vite -> obsah a PWA -> Cloudflare worker a verifikace -> upload -> live verifikace.

Průzkum nedoložil časy jednotlivých fází. Označení Flutteru za hlavní časovou položku je hypotéza k měření, nikoli výsledek benchmarku.

Implementační důkaz 2026-11-11: výchozí lokální pokus `bash
automation/build_web_bundle.sh static` skončil ve fázi preflight po 2 s na
`MCP reference is stale. Run: pnpm --dir tools/festapp run docs:generate`.
Nejde zatím o doložený problém credentials. Aktuální `main` navíc nemá nastavený
`CLOUDFLARE_PROJECT_NAME` ani tenantovou backend aktivaci. Kompilátory nebyly
spuštěny. Tehdejší cache proto ponechávala verzi i zdroje generovaného obsahu mezi vstupy;
navazující důkaz níže tuto dočasnou konzervativní hranici odstranil.

Navazující realizace: MCP reference byla přegenerována a její dependency digest
nyní zahrnuje pouze skutečně používané MCP překlady. Image preflight prošel.
Prázdný Cloudflare projekt neblokuje lokální static build. Pro disposable
ticketing měření byla použita existující tenantová politika
`origin/prod/festapptickets@202e27b46410385d09b7e453b31219dccc8b00e7`
(IS_APP_SUPPORTED=false, PWA 35/80 MiB), bez produkční aktivace či zápisu do větve.
Dvě skutečné kompilace SDK 3.47.7 mezi verzemi +485/+486 měly identické main a
deferred JS. Kompletace proto obnovuje aktuální `version.json`, HTML i bootstrap;
Vite nadále kompiluje změnu `APP_VERSION`. Limity ani povinné gates nebyly
zmírněny. Nápověda a organizer dokumenty se nově generují jednou po kompilaci.

## Cílový kontrakt

`automation/build_web_bundle.sh` zůstane kanonickým orchestrátorem pro cloudflare/static. Přidat jediný interní modul `automation/lib/web_build_cache.mjs` a deklaraci vstupů `automation/web_build_inputs.json`. Hostingové adaptéry nesmějí mít vlastní odlišnou cache logiku.

Oddělit tři hranice:

1. Příprava: povinné preflighty, generování konfigurace, přesné verze nástrojů a závislosti.
2. Sestavení komponent: nestampovaný Flutter a Vite výstup podle jejich vlastních úplných vstupů.
3. Kompletace: čerstvý staging, stampování verze, obsah, PWA, CSP, hostingový worker, finální verifikace a receipt.

### Cache

- Lokální per-user cache mimo Git a finální staging, například `${XDG_CACHE_HOME:-$HOME/.cache}/festapp/web-build/`. Klíč zahrnuje tenant identitu; nesdílet výstupy mezi tenanty.
- Klíč je hash obsahu vstupů, cest a relevantních módů souborů, verze schématu cache, skutečné revize SDK, nástrojů, lockfilů, platformy a build parametrů. Git SHA a mtime samy nestačí; zahrnout i necommitované a relevantní untracked soubory.
- Hashovat skutečné generované vstupy až po přípravě. Flutter zahrnuje transitivní lokální/vendored balíčky, assety, fonty, web shell, pubspec, lockfile a build defines. Vite zahrnuje své zdroje i importy a generátory mimo `web_client/`.
- Začít konzervativní deklarací: neklasifikovaný relevantní soubor invaliduje oba komponenty. Explicitně klasifikovat zdroj nápovědy a organizer obsahu; nevyřadit z klíčů plošně `automation/`, `docs/` ani `assets/`.
- Dependency hash a output hash jsou různé údaje. Záznam obsahuje oba, seznam výstupů, velikosti a skutečné verze nástrojů. Neukládat privátní release manifesty, tokeny ani hodnoty prostředí do receiptů.
- Cache se zveřejní atomicky až po úspěšném sestavení. Poškozený nebo nekompletní záznam je miss a vede k rebuild, nikoli k uploadu.
- Cache je immutable. Obnovený obsah se kopíruje do stagingu bez hardlinků, které by následné přepsání poškodilo. Stejný klíč chránit zámkem; ošetřit přerušený zápis a uvolnění zámku.
- Přidat jedinou diagnostickou volbu `FESTAPP_WEB_BUILD_CACHE=off`; vypne reuse, nikoli povinné kontroly. Cold a warm musí používat stejné kompilační příkazy.

### Identita releasu a upload

Finální receipt vzniká až po hostingovém workeru a posledním ověření. Obsahuje výsledný seznam souborů a jejich hashů, komponentové klíče, jejich původní zdrojové revize, aktuální zdrojovou revizi balení, tenant, hosting target a verzi. Původ kompilace se nesmí přepsat na novější Git SHA.

`deploy_direct.sh --skip-build` před uploadem ověří receipt, přesnou množinu souborů včetně nepovolených přídavků, tenant, target, verzi a shodu aktuálních vstupních fingerprintů. Rozpor upload zablokuje a vysvětlí nutný rebuild. Pouhé přejmenování souborů nebo přítomnost `_worker.js` nestačí.

Povinné image/backend preflighty, drift a ancestry pravidla, přesný CI gate, startup testy, finální verifikace a live probe zůstávají. CI důkazy lze znovu použít pouze již schválenou cestou `selection.py`. Privátní sealed backend manifest není build-cache receipt.

## Implementační vlny

### 1. Změřit výchozí stav

Změny: přidat kompaktní časování do orchestrátoru a `deploy_direct.sh`. Odděleně zaznamenat preflight, přípravu konfigurace, instalace, kompilaci Flutteru, postprocessing, startup testy, Vite, kompletaci, upload a live verifikaci. Zaznamenat úspěch i selhání a celkový čas od začátku pokusu.

Přidat měřicí výstup bez tajných hodnot a bez hashování logů prostředí. Lokální měření nesmí spustit upload. Časy uploadu doplnit až při samostatně autorizovaném releasu.

Ověření: syntaktická kontrola upravených shellů a jeden výchozí lokální build vybraného tenanta, pokud jsou dostupné požadované preflight vstupy. Před Flutterem ověřit volný workstation slot.

Hotovo: máme časy a seznam prostředí pro výchozí build, nebo přesně uvedený blocker. Bez baseline neuvádět procentní úsporu.

### 2. Zpřesnit generování a oddělit staging

Změny: v `apply_config.sh` a skutečně volaných generátorech zapisovat pouze při změně obsahu. Najít jen generátory na doložené build cestě. Zachovat jejich obsah a tenant preflight.

Rozdělit Flutter, Vite a kompletaci na interní fáze při zachování vstupních skriptů `build_web_bundle.sh`, `cloudflare_build.sh` a `ci_build.sh`. Pro miss nejprve oddělit nestampovaný výstup, poté provést původní postprocessing v definovaném pořadí na staging kopii. Neměnit zároveň optimalizační flagy kompilátoru.

Ověření: kontrakt generátoru pro první běh, opakování a změnu tenanta; opakování nemění obsah ani mtime nezměněného souboru. Kontrakt pořadí kompletace a zachování deferred JS. Nepotřebujeme další celý build, pokud změny pokrývají cílené testy; plný důkaz naváže vlnou 3.

Hotovo: jediný orchestrátor má oddělené fáze a identický výsledný produkt; finální staging zůstává vždy čistý.

### 3. Zavést cache komponent a finální receipt

Změny: implementovat výše popsaný cache modul, konzervativní manifest vstupů a receipts. Nejprve Flutter reuse, poté stejný kontrakt použít pro Vite. V obou případech všechny preflighty a gates pokračují. Při hit se vynechá pouze práce pokrytá cache kontraktem.

Pro `cloudflare_build.sh` i `ci_build.sh` dokončit receipt až po jejich finálním host-specific ověření. V `deploy_direct.sh` ověřovat prebuilt balíček ještě před uploadem. Zachovat `--skip-build`, odstranit jeho dosavadní nedostatečné spoléhání na existenci worker souboru.

Ověření: nové behaviorální testy `automation/tests/web_build_cache.test.mjs` a `automation/tests/web_build_receipt.test.mjs`. Pokrýt hit, miss po změně lib/lockfilu/SDK/defines/lokálního balíčku/assetu, relevantní dirty a untracked vstupy, přepnutí tenanta, poškozenou cache, přerušený zápis a souběžné žadatele bez spuštění skutečných paralelních Flutter procesů. Receipt musí odmítnout změněný, chybějící i přidaný soubor a nesprávného tenanta/verzi.

Hotovo: teplé opakování stejných vstupů nevyvolá kompilátory; změna pouze `web_client/src` nevyvolá Flutter, pokud opravdu nezměnila jeho transitivní vstupy. Nejasná klasifikace vede k miss.

### 4. Umožnit reuse při nové verzi a změně obsahu

Změny: dohledat všechny konzumenty verze a zjistit, zda změna pubspec verze skutečně mění kompilovaný Dart JS nebo jen metadata. Do této chvíle verze konzervativně invaliduje cache.

Prokázané packaging vstupy přesunout mimo kompilační klíč a v kompletaci znovu vytvořit `version.json`, HTML, `festapp-version.json`, jména hlavního a deferred JS, bootstrap a service worker. Přesné názvy a obsah metadata výstupů odvodit z reálného buildu použitého SDK. `APP_VERSION` ve Vite zůstává kompilačním vstupem, dokud není implementován a otestován ekvivalentní kanonický zdroj verze.

Pokud Flutter JS verzi opravdu obsahuje, nevylučovat ji z klíče. Zdokumentovat konkrétní konzument a navrhnout samostatnou omezenou změnu před další optimalizací; nevytvářet tichou chybu jen kvůli cíli rychlosti. Neměnit chování nativního PackageInfo.

Explicitně oddělit nápovědu a organizer obsah od kompilace jen tam, kde důkaz importů a assetů dovolí jeho vygenerování při kompletaci. Pokud Vite dnes kopíruje stejný obsah, odstranit duplicitní generování až po převodu všech konzumentů na jednoho vlastníka.

Ověření: v lokálních výstupech změnit jen release verzi a porovnat nestampovaný Flutter JS; pokud je kompatibilní, prokázat cache hit a správnou novou verzi ve všech klientských metadatech. Verifikovat bootstrap, deferred importy, service worker i výsledek `verify_web_build.mjs`. Startup browser kontrolu obsluhuje delegovaný Terra agent v izolované muted session, podle pravidel repozitáře.

Hotovo: změna veřejného webu doprovázená běžným zvýšením verze může bezpečně použít starší Flutter kompilaci, nebo je tento scénář výslovně veden jako nevyřešený s přesným důvodem. V druhém případě se nesmí tvrdit dosažení hlavního cíle pro takové releasy.

### 5. Změřit přínos, odstranit duplicity a zdokumentovat provoz

Porovnat na stejném stroji a stejném tenantovi: cold build, opakování bez změny, změnu veřejného JS, nápovědy, samotné verze a Dart souboru. Cold znamená vypnutou artifact cache; uvést zvlášť stav SDK/dependency cache. Neprovádět produkční obsahové změny pro benchmark; použít disposable worktree a obnovitelné lokální varianty.

Pro hlavní scénáře provést tři měřené běhy a uvést medián i rozsah; levné scénáře ověřující pouze invalidaci stačí jednou. Nesouběžit s jiným Flutter úkolem a neodstraňovat cizí cache. Porovnat shodu artefaktů cold/warm; pokud existují nedeterministické soubory, přesně je pojmenovat a ověřit jejich sémantický kontrakt namísto plošného ignorování rozdílů.

Teprve podle měření přesunout nezávislé čisté kontroly mimo sériovou cestu. Generátory sdílených assetů a změny `build/web` nesmějí běžet souběžně. Nespouštět více Flutter úloh. Neredukovat startup gate bez samostatné platné evidence podle repo pravidel.

Do `CONTRIBUTING.md` doplnit cache, miss důvody, diagnostické vypnutí, bezpečné opakování uploadu a cestu k měření. Přidat omezenou retenci cache, která chrání rozpracované/zamčené záznamy; nemazat aktivní cizí worktree. Ověřit, zda `automation/ci/inputs.json` nové soubory již konzervativně zahrnuje; výjimky přidávat jen s důkazem.

Hotovo: doložené časy pro hlavní scénáře a právě jedna kanonická cesta buildu. Hypotéza pro přijetí je alespoň 70% úspora času kompilační a balicí části u web-only releasu s reuse Flutteru; není to příslib ani důvod obejít kontroly. Uvést také celkový čas včetně testů, protože ten může mít jiný limit. Nesplněný cíl znamená přesné pojmenování zbývajícího bottlenecku.

## Odstranění a záměrně zachované hranice

| Položka | Výsledná akce | Důkaz |
| --- | --- | --- |
| Bezpodmínečné spuštění kompilátorů | Nahradit jediným rozhodováním hit/miss. | Behaviorální test počtu spuštění pro scénáře. |
| Opakované přepisování stejných generovaných souborů | Nahradit write-if-changed. | Obsah a mtime beze změny při opakování. |
| Nedostatečné ověření prebuilt uploadu | Nahradit validací receipt a výstupů. | Negativní testy před upload boundary. |
| Druhé kopie generování stejného obsahu | Odstranit po nalezení a převodu konzumentů. | Jediný vlastník a integrační test výsledných cest. |
| Čistý staging, statický hosting adaptér a ruční GitHub deploy fallback | Zachovat, všechny používají kanonický kontrakt. | Test obou targetů a `deploy_workflow.test.sh`. |
| Povinné gates a stávající CI selection | Zachovat beze změny pravidel. | Odpovídající CI mirror lanes. |

## Validace a předání

Při psaní tohoto plánu se testy ani build nespouštějí. Při implementaci používat behaviorální testy cache a receipt, `bash -n` na změněné shelly a `bash automation/tests/deploy_workflow.test.sh`. Existující source-string testy upravit na finální strukturu jen při zachování skutečného gate chování.

Před publikací spustit dotčené kanonické lanes přes `automation/test_ci.sh`, výběr odvodit z finální změny a aktuálního CI kontraktu. Nesnižovat je na ručně vybrané unit testy. Flutter testy výhradně `--concurrency=1`; jeden Flutter task na workstation. pnpm výhradně 11.24.0 a frozen lockfile. Zachovat cizí rozpracované změny.

Produkční rollout je samostatný autorizovaný krok pro jediný pojmenovaný tenant. Primární agent předá validovaný main a přesné revize; rutinní build/deploy a live ověření deleguje podle AGENTS.md. Všechny CI jobs na přesném baseMainSha musí projít release gate. Po uploadu ověřit koherentní live verzi standardním probe.

Rollback cache problému: rebuild s `FESTAPP_WEB_BUILD_CACHE=off` stejným kanonickým orchestrátorem. Chybný prebuilt receipt se nikdy neobchází. Produkční rollback používá existující schválený release postup, nikoli přeznačení starého balíčku.

## Podmínky dokončení a zbývající rizika

- Existuje jedna build cesta s cache, bezpečným miss a ověřeným prebuilt uploadem pro oba hosting targety.
- Je doloženo, které změny vynechají Flutter, včetně běžného zvýšení verze nebo přesně popsaného blockeru.
- Změny SDK, tenanta, závislostí a skutečných vstupů spolehlivě vyvolají rebuild.
- Výsledné verze, deferred JS, PWA, CSP a tenant identita jsou koherentní a povinné gates zůstaly účinné.
- Výsledek obsahuje naměřené srovnání a residual bottleneck, nikoli pouze počet odstraněných příkazů.

Hlavní rizika: neúplná transitivní množina vstupů, mutace cache při stampování, vazba verze na kompilaci a testy dominující celkovému času. První dvě řeší konzervativní invalidace a immutable staging; druhé dvě musí rozhodnout měření a explicitní kontrakt. Rychlejší úplná kompilace při změně Dart kódu není garantována tímto plánem.
