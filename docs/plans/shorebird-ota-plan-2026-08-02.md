# Bezpečné OTA aktualizace mobilní aplikace přes Shorebird

Date: 2026-08-02  
Status: Ready for execution after blockers B1–B4 are resolved  
Verification: standard

## Outcome

Festapp bude umět doručovat podepsané opravy Dart kódu do již vydaných Android a iOS aplikací přes Shorebird bez čekání na další schválení ve storech. OTA cesta bude volitelná pro každou white-label variantu, jednoznačně navázaná na její skutečné bundle/application ID a standardně povede přes staging, ověření na fyzických zařízeních a výslovné povýšení do stable.

Výsledkem nebude obecná náhrada App Store/Google Play releasů. Změny nativního kódu, Flutter enginu, pluginů, assetů, oprávnění a store metadat budou nadále vydávány standardním store releasem. Současný store-update prompt zůstane zachovaný jako kompatibilní cesta pro tyto verze.

„Funguje na sto procent“ je pro tento plán definováno jako deterministický a auditovatelný proces s bezpečným selháním, nikoli jako příslib okamžitého doručení všem zařízením nebo garance schválení Applem. Zařízení offline nebo uživatel, který aplikaci znovu nespustí, patch ihned nepřevezme; iOS interpretuje patchovaný Dart kód a store pravidla zůstávají externí autoritou.

## Scope

### In scope

- Konfigurovatelný provider `none|shorebird` v jediném zdroji konfigurace projektu.
- Jednoznačné mapování Shorebird `app_id` na skutečnou store identitu aplikace.
- Deterministicky generovaný a verzovaný `shorebird.yaml`.
- Reprodukovatelné Flutter závislosti včetně verzovaného kořenového `pubspec.lock`.
- Povinné RSA podepisování release/patch artefaktů a proces správy klíče mimo repozitář.
- Kanonické skripty pro preflight, Shorebird release, staging patch, promotion a rollback.
- Oddělené Android/iOS operace, explicitní verze release a dohledatelný zdrojový commit/tag.
- Strojově kontrolovaná klasifikace změn na patchovatelné a store-only.
- Fyzický pilot na iOS a Androidu, ověření aplikace patche i rollbacku.
- Zachování dosavadního store-update mechanismu a webového update promptu.
- Provozní runbook, kvóty, incidentní postup a pozdější ručně spouštěná CI automatizace.

### Out of scope

- Self-hosting Shorebirdu; oficiální služba ho nepodporuje.
- Obcházení bezpečnostních kontrol, store review nebo klamavé změny účelu aplikace.
- OTA aktualizace nativního kódu, Flutter enginu, pluginů, assetů, překladových JSONů, fontů, ikon, mapových balíčků nebo oprávnění.
- Automatické publikování stabilního patche při pushi do GitHubu.
- Vynucený restart, vlastní download progress UI nebo runtime řízení updateru v první etapě.
- Nahrazení `UpdateService`, App Store/Google Play releasů nebo webového deploy procesu.
- Migrace všech white-label větví najednou; první implementace je pilot pro jednu potvrzenou store identitu.
- Změny backendového autorizačního modelu. OTA klient nesmí být bezpečnostní hranicí.

## Constraints

- `automation/project.conf` je zdroj pravdy a `automation/apply_config.sh` propaguje konfiguraci; Shorebird konfigurace nesmí vytvořit druhý ručně spravovaný zdroj.
- Flutter je připnutý na `3.44.8`; každý Shorebird release musí tuto verzi uvést explicitně a patch musí cílit na přesnou existující release verzi.
- Repozitář obsahuje nativní pluginy (`onesignal_flutter`, MapLibre, scanner, SQLite a další). Přidání nebo změna pluginu je store release, i když související Dart změna sama vypadá patchovatelně.
- Překlady v `assets/translations`, fonty a další data z `pubspec.yaml` jsou Flutter assets, nikoli bezpečně patchovatelný obsah.
- iOS patchovaný Dart běží interpretovaně; výkonnostně citlivé změny map, skenování, importů, offline synchronizace a rozsáhlých seznamů vyžadují fyzický iOS test.
- Shorebird updater kontroluje a stáhne update na pozadí a standardně jej použije při dalším spuštění. Proces nesmí blokovat start ani porušit offline režim.
- Shorebird je open-source tooling/updater nad hostovanou službou, nikoli plně self-hostovatelný stack. Free tier má aktuálně 5 000 úspěšných instalací patchů za měsíc, jednoho vývojáře a bezplatně zahrnuje staging, rollback a podepisování; před produkcí se musí ověřit aktuální podmínky a očekávaný počet aktivních zařízení.
- Apple i Google povolují jen omezené interpretované/downloadované změny. Patch nesmí zásadně měnit deklarovaný účel aplikace, obcházet review ani stahovat nativní executable code.
- Produkční release, patch promotion, rollback, vytvoření účtu/aplikace, správa tajemství, store upload, commit a push jsou externí nebo destruktivnější akce a vyžadují samostatnou autoritu.
- `CONTRIBUTING.md` zakazuje agentovi automatický commit. Implementace musí skončit před commitem/pushem, pokud uživatel výslovně nepovolí opak.
- GitHub workflow je nyní webový deploy. Mobilní OTA nesmí být přimícháno do automatického produkčního web deploye.

## Current-state evidence

| Claim | Evidence | Consequence |
|---|---|---|
| Konfigurace má jeden zdroj pravdy. | `automation/project.conf`; `automation/apply_config.sh` | OTA přepínač, identita a veřejná metadata patří sem a `shorebird.yaml` má být generovaný. |
| Projekt používá Flutter 3.44.8. | `.fvmrc`; `.fvm/fvm_config.json` | Verze je Shorebirdem podporovaná, ale musí být explicitní součást release příkazu. |
| Kořenový lockfile není verzovaný. | `.gitignore: *.lock`; `git check-ignore -v pubspec.lock` | První baseline není reprodukovatelná, dokud se `pubspec.lock` výslovně nepovolí a nezapíše. |
| Aplikace obsahuje nativní pluginy a assets. | `pubspec.yaml: dependencies, assets, fonts` | Patch gate musí být konzervativní a nativní/asset změny odmítat. |
| Store fallback již existuje. | `lib/data_services/update_service.dart`; `RightsService.updateAppData` | Tento mechanismus se zachová pro nové plné verze. |
| Web má vlastní update mechanismus. | `automation/emit_version_manifest.sh`; web update prompt | Web není součástí Shorebird integrace. |
| iOS release má existující Fastlane upload. | `automation/release/ios_build_and_upload.sh`; `ios/fastlane/Fastfile` | Shorebird nahradí pouze build krok; upload/submission zůstane samostatný. |
| iOS skript mění adresář relativně vůči volajícímu. | `automation/release/ios_build_and_upload.sh: SCRIPT_DIR, cd ..` | Při úpravě se musí přejít na explicitní repo root odvozený ze `SCRIPT_DIR`. |
| Android nemá ekvivalentní verzovaný release wrapper. | absence Android release skriptu v `automation/release` | Je nutné přidat build wrapper; automatický Play upload není podmínkou pilotu. |
| Mobile identity neodpovídá názvu větve. | `android/app/build.gradle: fstapp.jm2025`; Xcode project: `festapp.jm2025`; větev `prod/csmostrava2026` | Shorebird app se nesmí pojmenovat/mapovat jen podle větve. Nejdřív se ověří skutečný store listing. |
| Několik prod větví sdílí nebo historicky nese stejné identifikátory. | porovnání vzdálených `prod/*` konfigurací | Špatné `app_id` by mohlo poslat patch jiné white-label aplikaci se shodnou verzí. Identity guard je bezpečnostní podmínka. |
| Pre-commit běžně zvyšuje build číslo. | `automation/pre_commit_check.sh`; `automation/increment_version.js` | Patch cíluje již vydanou verzi a nesmí ji odvozovat z právě změněného `VERSION` nebo z `latest`. |
| Aplikace nemá vzdálený crash reporting. | `lib/utils/app_logger.dart` a absence Sentry/Crashlytics | Pilot se opře o Shorebird eventy, device logy a řízený test; observability rozšíření je samostatná práce. |
| Android má internetové oprávnění. | `android/app/src/main/AndroidManifest.xml` | Updater nepotřebuje nové Android permission. |

Současný tok je `project.conf -> apply_config.sh -> Dart/web/native build vstupy -> Flutter/Fastlane`. Cílový tok doplní `project.conf -> validace identity -> generovaný shorebird.yaml -> podepsaný Shorebird release`, z něhož mohou později vzniknout pouze kompatibilní podepsané patche přes `staging -> fyzické ověření -> explicitní promotion stable`.

Externí kontrakty byly ověřeny proti oficiální dokumentaci: [Code Push overview](https://docs.shorebird.dev/code-push/), [initialize/configuration](https://docs.shorebird.dev/code-push/initialize/), [Flutter version support](https://docs.shorebird.dev/getting-started/flutter-version/), [release](https://docs.shorebird.dev/code-push/release/), [patch](https://docs.shorebird.dev/code-push/patch/), [staging](https://docs.shorebird.dev/code-push/guides/staging-patches/), [rollback](https://docs.shorebird.dev/code-push/rollback/), [patch signing](https://docs.shorebird.dev/code-push/guides/patch-signing/), [CI](https://docs.shorebird.dev/code-push/ci/generic/), [pricing](https://shorebird.dev/pricing), [FAQ](https://docs.shorebird.dev/code-push/faq/), [Apple App Review 2.5.2](https://developer.apple.com/app-store/review/guidelines/) a [Google Play Device and Network Abuse](https://support.google.com/googleplay/android-developer/answer/16273414).

## Target architecture and invariants

### Canonical owner and contract

Kanonickým vlastníkem statické OTA konfigurace bude `automation/project.conf`. Obsahuje pouze veřejná a značková fakta:

- `OTA_PROVIDER=none|shorebird`
- `SHOREBIRD_APP_ID=<uuid>` pouze při provideru `shorebird`
- `SHOREBIRD_AUTO_UPDATE=true|false`, v první implementaci povinně `true`
- `ANDROID_APPLICATION_ID=<skutečné store applicationId>`
- `IOS_BUNDLE_IDENTIFIER=<skutečné hlavní bundle ID>`
- `SHOREBIRD_PUBLIC_KEY_PATH=<repo-relativní cesta k veřejnému klíči>`

`automation/apply_config.sh` hodnoty syntakticky i relačně zvaliduje, porovná deklarované identity s Android/iOS projektem a při provideru `shorebird` deterministicky vytvoří verzovaný `shorebird.yaml` a jeho označený asset entry v `pubspec.yaml`. Při provideru `none` oba své generované výstupy bezpečně odstraní, protože chybějící soubor uvedený v assets by rozbil běžný Flutter build. Token, privátní klíč, rollout track ani cílová release verze do `project.conf` nepatří.

Kanonickým vlastníkem operací bude sada úzkých wrapperů v `automation/release/`. Sdílený preflight načte konfiguraci, ověří identitu, čistý a dohledatelný zdroj, CLI, klíče, lockfile a způsobilost změny. Wrappery budou mít oddělené operace:

1. vytvořit release pro jedinou explicitní platformu,
2. vytvořit podepsaný patch do `staging` pro explicitní release verzi,
3. povýšit konkrétní číslo patche do `stable`,
4. vrátit konkrétní release na předchozí patch/base.

Runtime bude v první verzi používat výchozí Shorebird auto-update engine. Do `lib/main.dart` ani do závislostí se nepřidá `shorebird_code_push`; aplikace zůstane spustitelná offline a update se projeví při následujícím startu. Vlastní UI nebo manuální `checkForUpdate/downloadUpdate` je až samostatné rozhodnutí podložené potřebou.

### Invariants

1. Každá distribuovaná store aplikace má právě jedno potvrzené mapování `(platform, application/bundle ID) -> Shorebird app_id`; větev ani marketingový název nejsou identitou.
2. `shorebird.yaml` a jeho označený `pubspec.yaml` asset entry jsou deterministické výstupy `project.conf`; ruční editace se při kontrole projeví jako drift.
3. Při `OTA_PROVIDER=none` nesmí žádný release skript volat Shorebird; při `shorebird` nesmí být release vytvořen bez identity checku a veřejného podpisového klíče.
4. Privátní podpisový klíč ani `SHOREBIRD_TOKEN` nikdy nejsou v repozitáři, logu nebo generovaném configu. Veřejný klíč je verzovaný.
5. Každý patch je podepsaný stejným klíčem, jehož public část byla vložena do cílového store release.
6. Každý release explicitně používá Flutter `3.44.8`; každý patch explicitně uvádí existující release verzi. `latest` je zakázané.
7. Patch se vytváří nejprve pouze do `staging`. `stable` vznikne výhradně samostatnou explicitní promotion konkrétního app ID, platformy, release verze a patch čísla.
8. Wrappery nikdy neposkytují `--allow-native-diffs` ani `--allow-asset-diffs`; jejich výskyt v automatizaci je chyba.
9. Změny v `android/**`, `ios/**`, Flutter verzi, plugin/asset deklaracích, lockfile, assets, fontech, oprávněních, store identitě a signing konfiguraci jsou store-only.
10. Patchovatelný Dart kód nesmí nevratně změnit lokální persistentní formát. Změna cache/dat musí být zpětně i dopředně kompatibilní s předchozím patchem i base releasem, jinak jde přes store release.
11. Backend změna použitá patchem následuje expand/contract: nová kompatibilní serverová cesta existuje před patchem, stará zůstává po celou rollback window a odstraní se až po potvrzené adopci nového store baseline.
12. Selhání sítě nebo Shorebirdu nebrání startu; zařízení pokračuje na posledním validním patchi nebo base releasu.
13. iOS a Android jsou samostatné release jednotky. Úspěch jedné platformy nesmí maskovat neúspěch druhé.
14. Web deploy, store update prompt a OTA patching jsou tři oddělené cesty s oddělenými vlastníky.
15. Automatický on-device rollback chrání před nevalidním/crashujícím loadem, ale sémantická chyba vyžaduje provozní rollback a následný restart zařízení.
16. Verze Shorebird CLI použitá pro každý baseline i patch je strojově ověřená proti verzovanému toolchain kontraktu a zapsaná v release záznamu; tichý self-update nástroje nesmí změnit release proces.

### Entry points and forbidden bypasses

- Povolené vstupy: `automation/apply_config.sh`, nový `shorebird_release.sh`, `shorebird_patch.sh`, `shorebird_promote.sh`, `shorebird_rollback.sh` a upravený iOS orchestrátor.
- Přímé `shorebird init --force` je zakázané: vytváří nové app ID a může rozbít mapování existující identity.
- Přímé produkční `shorebird patch --track stable` je zakázané.
- Přímé patchování bez `--release-version`, z dirty worktree nebo bez podepsaného baseline je zakázané.
- Přímý Flutter release build je pro Shorebird-enabled variantu zakázaný, protože nevloží updater/signing contract. Pro `OTA_PROVIDER=none` zůstává standardní Flutter build vědomě podporovanou vnější hranicí.
- Ruční úprava `shorebird.yaml`, ukládání secrets do `project.conf` a sdílení jednoho Shorebird app ID mezi různými store identitami jsou zakázané.

## Decisions, assumptions, and blockers

### Decisions

- **D1:** Shorebird je jediný OTA provider; žádná paralelní vlastní updater implementace nevznikne.
- **D2:** První integrace používá výchozí `auto_update: true` bez runtime balíčku a bez startup UI. Minimalizuje tím nový aplikační kód a zachovává non-blocking/offline start.
- **D3:** Všechny produkční patche jsou od prvního baseline povinně podepsané RSA-2048. Soukromý klíč bude mimo repo se dvěma bezpečnými zálohami; jeho ztráta vyžaduje nový store release.
- **D4:** Pilot bude nejprve manuální přes verzované wrappery. CI `workflow_dispatch` se přidá až po prokázaném release, staging patchi a rollbacku; stable nikdy nebude push-triggered.
- **D5:** Počáteční eligibility policy bude konzervativní. Jakákoli nejasná změna compiled-mobile vstupu se odmítne a vyžádá store release; pravidla se mohou později bezpečně uvolnit na základě důkazu.
- **D6:** `pubspec.lock` se začne verzovat před prvním baseline. Změna `pubspec.yaml` nebo lockfile vždy znamená store release v počáteční politice, i když čistě Dart balíček může být technicky patchovatelný.
- **D7:** Současný `UpdateService` se zachová. Shorebird řeší urgentní kompatibilní kódové opravy, nikoli dlouhodobé vynechávání store releasů.
- **D8:** Rollout track není značková konfigurace. `staging` je default operace a `stable` je výslovný provozní přechod se čtyřmi explicitními identifikátory.
- **D9:** Každý store baseline dostane anotovaný git tag obsahující stabilní klíč aplikace, platformu a release verzi. Patch preflight používá tento tag jako zdroj klasifikace diffu, nikoli pohyblivou větev.
- **D10:** Shorebird nebude používán k podstatné změně deklarovaného účelu aplikace. Taková změna je store release a případně nové review metadata.
- **D11:** Shorebird CLI dostane vlastní verzovaný toolchain contract. Implementace zvolí a otestuje konkrétní aktuální verzi; její změna je samostatný reviewovaný toolchain update, nikoli vedlejší efekt release dne.

### Assumptions

- **A1:** Free tier bude pro pilot dostačující; impact if false: patch delivery se zastaví na kvótě nebo vyžádá placený plán; resolve by: před produkcí zjistit měsíční aktivní instalace ze store/OneSignal a přidat rezervu pro rollback/reinstalace.
- **A2:** `fstapp.jm2025` / `festapp.jm2025` je skutečná identita existujícího CSM store listingu, nikoli omylem zděděná hodnota; impact if false: patch by mohl cílit jinou aplikaci; resolve by: porovnat Play Console/App Store Connect listing, signing team a poslední publikovaný build.
- **A3:** Současné signing a Fastlane oprávnění umí vytvořit nový iOS baseline; impact if false: pilot skončí před store distribucí; resolve by: read-only archive/signing preflight na stroji vlastníka certifikátu.
- **A4:** Uživatelé přijmou aplikaci patche při dalším startu; impact if false: požadavek na okamžitější UX vyžádá runtime package a restart prompt; resolve by: ověřit produktové SLA před Wave 6.
- **A5:** Shorebird endpointy jsou z cílových sítí dosažitelné; impact if false: patch se nestáhne, base app však poběží; resolve by: staging test na reálné mobilní síti, Wi-Fi a případné firemní síti.
- **A6:** Stávající privacy/vendor dokumentace může Shorebird evidovat jako dodavatele; impact if false: produkční nasazení se odloží; resolve by: projít DPA/privacy a datové toky před store baseline.

### Blockers

- **B1:** Vlastník musí v App Store Connect a Play Console potvrdit skutečnou identitu aplikace a vztah CSM Ostrava k historické JM2025 aplikaci.
- **B2:** Vlastník musí založit/vybrat Shorebird účet/organizaci a vytvořit právě jednu app pro potvrzenou identitu; vzniklé `app_id` je externí vstup. Nesmí se automaticky použít `init --force`.
- **B3:** Vlastník musí schválit a zajistit custody podpisového privátního klíče (password manager/KMS/secure CI secret), druhou zálohu a seznam osob oprávněných k promotion/rollbacku.
- **B4:** Je nutné doložit Android release/signing/upload postup a přístup k Play internal testing; v repozitáři dnes chybí ekvivalent iOS release orchestrace.
- **B5:** Produkční promotion a store upload zůstávají blokované, dokud neproběhne fyzický staging a rollback test na obou platformách.

## Deletion ledger

| Artifact | Current role | Final action | Removal proof |
|---|---|---|---|
| `.gitignore: *.lock` pro kořenový `pubspec.lock` | Globálně ignoruje lock soubory | Přidat úzkou výjimku `!/pubspec.lock`; ostatní lock pravidla neměnit | `git ls-files --error-unmatch pubspec.lock` a čistý `flutter pub get --enforce-lockfile` |
| Přímý `fvm flutter build ipa --release` v `ios_build_and_upload.sh` | Staví běžný iOS release | Pro provider `shorebird` delegovat na kanonický Shorebird release wrapper; pro `none` vědomě zachovat standardní cestu | Shell test/stub pro oba providery a search přímých build vstupů |
| Relativní `cd ..` v iOS release skriptu | Předpokládá cwd volajícího | Nahradit repo rootem odvozeným z `SCRIPT_DIR` | Spuštění preflightu z jiného cwd |
| Zastaralý název iOS skriptu v dokumentaci | Odkazuje na neexistující `build_and_upload.sh` | Opravit na kanonický název a popsat OTA/store hranici | `rg 'build_and_upload\.sh' docs automation` |
| Ručně spravovatelný `shorebird.yaml` | Po init by mohl být druhým zdrojem pravdy | Generovat výhradně z `project.conf`; soubor má generated header a drift check | Shodné hashe YAML/pubspec výstupů po dvojím `apply_config.sh` |
| Implicitní cílení `latest` | Pohodlná, ale neauditovatelná patch volba | Nikde nepodporovat; vyžadovat exact release + baseline tag | Negativní shell test a `rg -- '--release-version[ =]latest'` |
| Přímé stable publikování | Může obejít staging a device test | Stable ponechat jen v samostatném promotion wrapperu s potvrzením | Negativní test patch wrapperu; search track stable mimo promotion |
| Store update prompt | Upozorňuje na plný update | Retain boundary: zůstává pro store-only změny | Existující update-service testy beze změny |
| Web version manifest/prompt | Řeší nový web bundle | Retain boundary: není napojen na Shorebird | Web testy beze změny |

## Implementation waves

### Wave 0 — Potvrzená identita, vlastnictví a provozní hranice

**Goal**

Odstranit možnost technicky správné integrace do nesprávné store aplikace a vyřešit autority ještě před změnou build systému.

**Changes**

- App Store Connect a Play Console — zaznamenat listing ID, hlavní bundle/application ID, signing team/cert identity, aktuální live verzi/build a vlastníka.
- Shorebird Console — ručně vytvořit app v odsouhlasené organizaci a zaznamenat public `app_id`; nevytvářet duplicitní app pro název větve.
- Security custody — vytvořit RSA-2048 keypair podle Shorebird kontraktu, uložit private key mimo repo, dvě obnovitelné zálohy a public key připravit pro verzování.
- Provozní rozhodnutí — určit osoby oprávněné k release, staging, promotion a rollbacku; zapsat očekávané MAU a limit free tieru.
- Vendor/privacy evidence — zaznamenat Shorebird jako hostovaného dodavatele, jeho provozní metadata a absenci self-host varianty.

**Migration/deletion**

- Žádná kódová migrace. Marketingový název/větev se výslovně přestává považovat za technickou identitu.

**Failure and compatibility**

- Neshoda store identity s repozitářem zastaví další vlny; neopravuje se automatickým přejmenováním, protože to může znamenat nový store listing nebo migraci signing identity.

**Validation**

- Čtyřstranné porovnání Play Console, App Store Connect, Android Gradle a Xcode IDs — prokazuje cílovou aplikaci.
- Ověření obnovy private key ze záložního umístění bez vypsání jeho obsahu — prokazuje custody.

**Exit condition**

- B1–B4 mají jmenovaného vlastníka, potvrzené hodnoty a nejsou řešeny odhadem.

### Wave 1 — Reprodukovatelná a strojově ověřená konfigurace

**Goal**

Vytvořit jediný konfigurační kontrakt, který nemůže tiše spojit release se špatným Shorebird app ID.

**Changes**

- `.gitignore` — povolit pouze kořenový `pubspec.lock` a verzovat lock vytvořený přes FVM.
- `automation/project.conf` — přidat veřejná OTA pole, potvrzené Android/iOS identity a veřejný key path.
- `automation/apply_config.sh` — validovat provider enum, UUID, boolean, existenci public key a přesnou shodu hlavních native IDs; generovat `shorebird.yaml` deterministicky s generated headerem.
- `pubspec.yaml` — přes stabilní označený blok přidat generovaný `shorebird.yaml` do assets jen pro provider `shorebird`, jak vyžaduje Shorebird runtime contract; tato změna je součást prvního plného store baseline.
- `shorebird.yaml` — verzovaný výstup s `app_id` a `auto_update: true`; žádná secrets ani neověřené konfigurační klíče.
- `automation/tests/fixtures/project.conf` a `automation/tests/apply_config.test.sh` — pokrýt enabled/disabled, idempotenci, chybějící ID, chybný UUID a identity mismatch.
- `automation/test_all.sh` — zahrnout nový config contract test do automation skupiny.

**Migration/deletion**

- Jednorázový `shorebird init` slouží pouze k externímu založení aplikace. Poté se jeho `app_id` přenese do `project.conf` a `apply_config.sh` převezme vlastnictví YAML.
- Při `OTA_PROVIDER=none` smí skript odstranit pouze YAML označený vlastním generated headerem a pouze vlastní označený asset entry; ručně vytvořený soubor nebo cizí asset řádek nesmí smazat.

**Failure and compatibility**

- Chybějící/neshodná identita je hard failure před přepsáním výstupu.
- Stávající konfigurace s `none` musí nadále projít bez Shorebird CLI a bez private key a nesmí odkazovat na chybějící YAML asset.
- Výjimka lockfile nesmí začít verzovat webové/vendor lockfiles, které nejsou již sledované.

**Validation**

- `./automation/tests/apply_config.test.sh` — všechny config varianty a ochrana ručního souboru.
- `./automation/test_all.sh automation` — stávající automatizační kontrakty.
- `fvm flutter pub get --enforce-lockfile` — reprodukovatelnost root dependencies.
- Porovnat hash relevantních generovaných souborů po prvním a druhém `./automation/apply_config.sh` — idempotence bez předpokladu čistého worktree během implementace.

**Exit condition**

- Z jediné potvrzené konfigurace vzniká opakovaně stejný validní `shorebird.yaml`; neshoda store identity zastaví proces.

### Wave 2 — Podepsaný release jako kanonická build cesta

**Goal**

Umět vytvořit auditovatelný Shorebird-enabled store artefakt pro jednu platformu bez změny upload oprávnění.

**Changes**

- `automation/release/shorebird_cli.version` — připnout konkrétní verzi CLI ověřenou při implementaci; změna souboru vyžaduje opakování dry-run kontraktů.
- `automation/release/shorebird_common.sh` — bezpečné načtení public configu, repo rootu, Flutter/CLI verze, clean worktree, tracked lockfile, ID shody a signing paths; redakce secrets v logu.
- `automation/release/shorebird_release.sh` — vyžadovat `--platform android|ios`, `--expected-version <name+build>` a source ref; ověřit očekávanou hodnotu proti build vstupům a před potvrzením i proti CLI summary, poté volat `shorebird release <platform> --flutter-version=3.44.8 --public-key-path=...`; podporovat `--dry-run` bez uploadu/mutace. Wrapper nesmí předstírat neexistující release `--release-version` flag; případný override provádí jen přes oficiální `--build-name`/`--build-number` a po přesné validaci.
- `automation/release/ios_build_and_upload.sh` — opravit cwd; pro `shorebird` delegovat build do release wrapperu, ale ponechat Fastlane upload/submit jako oddělený, výslovně autorizovaný krok; pro `none` zachovat standardní FVM build.
- `automation/release/android_build.sh` — přidat symetrický build vstup pro podepsaný AAB a vypsat cestu/hash artefaktu; žádný automatický Play upload.
- `automation/tests/shorebird_release.test.sh` — s fake CLI ověřit přesné argumenty, provider dispatch, selhání bez klíče/ID/lockfile a absenci secretů v logu.
- `automation/release/README.md` — vysvětlit rozdíl „create Shorebird release“, „store upload“ a „store rollout“.

**Migration/deletion**

- Shorebird-enabled iOS release přestane mít paralelní přímou `flutter build ipa` cestu.
- Existující Fastlane lanes se nemění, dokud jejich skutečný store kontrakt nevyžaduje úpravu.

**Failure and compatibility**

- Vytvoření Shorebird release a store upload jsou dvě externí operace. Pokud upload selže, release se nesmí označit za distribuovaný; opakování musí používat stejný zdroj, CLI verzi a app verzi nebo vytvořit nový vědomý baseline.
- Android/iOS se spouštějí odděleně. Partial success se zaznamená a nesynchronizuje se falešně druhou platformou.
- Přerušení nebo nedostupnost Shorebirdu nesmí změnit `project.conf`, tagy ani store stav.

**Validation**

- Shell contract testy s fake `shorebird`/`fvm` — ověří příkazy bez externí mutace.
- `shorebird doctor` — ověří lokální toolchain.
- `shorebird release android --dry-run ...` a `shorebird release ios --dry-run ...` přes wrapper — ověří build integraci bez publikace.
- Hash a podpis výstupního artefaktu — naváže store artefakt na zdroj.

**Exit condition**

- Obě platformy umí z čistého potvrzeného refu vytvořit dry-run artefakt s updaterem a public key; žádný artefakt ještě nebyl bez autority uploadován.

### Wave 3 — Konzervativní patch gate, staging, promotion a rollback

**Goal**

Zabránit tomu, aby pohodlí OTA obešlo kompatibilitu, podpis, staging nebo přesné cílení.

**Changes**

- `automation/release/shorebird_classify_diff.sh` — porovnat HEAD s explicitním anotovaným baseline tagem; hard-fail pro native/toolchain/plugin/lock/asset/identity/signing změny a pro neznámé compiled-mobile vstupy.
- `automation/release/shorebird_patch.sh` — vyžadovat platformu, app key, exact `--release-version`, baseline tag, private/public key; default a jediný create track `staging`; před uploadem spustit klasifikaci a `--dry-run`.
- `automation/release/shorebird_promote.sh` — samostatná produkční operace s app ID, platformou, exact release version, patch number a interaktivním/CI environment potvrzením; nesmí odvozovat `latest`.
- `automation/release/shorebird_rollback.sh` — stejné explicitní identifikátory, incident reason a potvrzení; dokumentovat, že efekt nastane až při další check/restart sekvenci.
- `automation/tests/shorebird_patch.test.sh` — negativní matice pro assets, native dirs, `.fvmrc`, pubspec/lock, dirty tree, nepodepsaný release, `latest`, stable bypass a zakázané allow-diff flags.
- `automation/release/README.md` — eligibility decision tree včetně persistence, backend expand/contract a iOS performance pravidel.

**Migration/deletion**

- Žádná volná „spusť Shorebird CLI“ cesta nebude dokumentovaná jako podporovaná. Přímý CLI zůstává pouze break-glass nástroj podle incident runbooku se stejnými identifikátory.

**Failure and compatibility**

- Nejasnost klasifikace znamená store release, ne operátorské přepsání přes `--allow-*-diffs`.
- Backend rollout musí být kompatibilní s base i patchem. Destruktivní contract fáze čeká na ukončení rollback window.
- Patch měnící lokální persistentní data musí přežít střídání `base -> patch -> rollback`; jinak je nezpůsobilý.
- Pokud rollback narazí na kvótu, zařízení se může vrátit až na base release; proto musí být base stále funkční vůči backendu.

**Validation**

- `./automation/tests/shorebird_patch.test.sh` — rozhodovací a argumentový kontrakt bez sítě.
- `rg -n -- 'allow-(native|asset)-diffs|release-version[ =]latest' automation/release .github/workflows` — absence nebezpečných bypassů.
- Fake CLI důkaz, že patch vždy začíná ve staging a stable existuje pouze v promotion wrapperu.

**Exit condition**

- Patch nelze vytvořit pro zakázaný diff, nepřesnou verzi, neznámou identitu nebo bez podpisu; promotion a rollback jsou oddělené autorizované operace.

### Wave 4 — End-to-end pilot mimo produkční stable

**Goal**

Prokázat celý životní cyklus na fyzickém iOS a Android zařízení dříve, než Shorebird začne obsluhovat produkční instalace.

**Changes**

- Vytvořit podepsané Android/iOS testovací baselines z jednoho zaznamenaného source refu a přes interní store kanály je nainstalovat na fyzická zařízení.
- Baseline označit anotovanými tagy ve tvaru např. `mobile/<app-key>/<platform>/<version>` a k provoznímu záznamu uložit commit, Flutter verzi, Shorebird app ID, store build a hash artefaktu.
- Připravit záměrně neškodnou Dart-only diagnostickou změnu bez assetu/native diffu, publikovat ji do staging a previewnout exact patch.
- Ověřit první start bez změny, background download, následující start s patchem, offline start, cold start, přihlášení, OneSignal start, mapu, skenování, SQLite/offline data a běžný update prompt.
- Provést rollback a ověřit návrat po check/restart; zaznamenat Shorebird eventy a device logy.

**Migration/deletion**

- Diagnostická pilotní změna se po testu odstraní nebo nahradí skutečnou patch změnou; nesmí zůstat jako skrytá produkční funkce.

**Failure and compatibility**

- Pilot není úspěšný jen proto, že CLI hlásí upload. Musí být pozorován na fyzickém iOS i Android zařízení ve skutečném store-signed buildu.
- Výkon iOS se porovnává s base u citlivých flows. Významná regrese znamená store release nebo přepracování změny.
- Pokud staging/rollback selže na jedné platformě, druhá se nepovýší do produkční stable jako náhrada za chybějící důkaz.

**Validation**

- Device test matrix s přesnou platformou/OS/verzí/patch číslem — důkaz aplikace i rollbacku.
- Shorebird Console/CLI eventy `download/install` a device logs — důkaz síťové a runtime cesty.
- Store update prompt na starší plné verzi — důkaz zachované fallback cesty.

**Exit condition**

- Podepsaný staging patch a rollback byly prokázány na obou fyzických platformách a všechny B5 podmínky jsou uzavřené.

### Wave 5 — První produkční baseline a provozní readiness

**Goal**

Vydat první Shorebird-enabled plnou verzi přes standardní store proces a být připraven bezpečně řešit incident.

**Changes**

- Spustit normální repo release gate a podepsané Shorebird release buildy z čistého, tagovatelného refu.
- Uploadnout artefakty do TestFlight/Play internal, následně podle explicitní autority do produkce a uložit store status/build IDs.
- Dokončit runbook pro patch eligibility, staging preview, approval, stable promotion, rollback, ztrátu klíče, Shorebird outage, quota exhaustion a store fallback.
- Nastavit měsíčního vlastníka kontroly successful patch installs a prahové upozornění pod 5k free limitem; počítat s tím, že rollback/download staršího patche může spotřebovat instalaci.
- Zajistit, že backend drží base kompatibilitu nejméně po celou podporovanou rollback window.

**Migration/deletion**

- Žádný předchozí store build se „nemigruje“ na OTA. Patchovat lze až nový Shorebird-enabled baseline distribuovaný storem.

**Failure and compatibility**

- Store rejection nebo signing problém se řeší standardním releasem; Shorebird nesmí být použit k obcházení review.
- Pokud Shorebird služba není dostupná, vydaná aplikace musí dál fungovat a další oprava jde přes store.
- Pokud se ztratí private key, žádný nepodepsaný patch se nepovolí; vydá se nový baseline s novým public key.

**Validation**

- `./automation/test_all.sh` a repository release checks — kódová kvalita před store buildem.
- TestFlight/Play internal install z reálného artefaktu — store signing a updater přítomnost.
- Incident tabletop: semantic bug -> rollback -> base compatibility -> případný emergency store release.

**Exit condition**

- V obou storech je potvrzený Shorebird-enabled baseline a operátor umí podle runbooku staging, promotion i rollback bez improvizace.

### Wave 6 — Ručně schvalovaná CI automatizace a kontrakce dokumentace

**Goal**

Po úspěšném manuálním pilotu odstranit opakovatelnou lidskou chybu bez automatizace produkčního rozhodnutí.

**Changes**

- `.github/workflows/shorebird.yml` — až nyní přidat `workflow_dispatch` pro dry-run/release/staging patch; přesná platforma, app key, release version a baseline ref jsou povinné inputs.
- GitHub Environment — production promotion/rollback chránit required reviewerem; `SHOREBIRD_TOKEN` a signing secret uložit mimo repo, logy redigovat.
- Použít aktuální podporovaný Shorebird CI login/token kontrakt; nepoužívat deprecated `login:ci`.
- CI smí vytvářet staging patch, ale stable promotion zůstává samostatný environment job s konkrétním patch number a approval.
- `CONTRIBUTING.md`, `automation/README.md`, `docs/setup/howto.md` a release README — sjednotit terminologii, správný název iOS skriptu, identity mapping, eligibility a no-bypass pravidla.

**Migration/deletion**

- Odstranit dočasné pilotní poznámky a zastaralé příkazy, které obcházejí wrappery.
- Neodstraňovat `UpdateService`, standardní provider `none`, Fastlane upload ani web deploy; jde o explicitně oddělené hranice, ne legacy duplikaci.

**Failure and compatibility**

- CI není podmínkou fungování lokálního break-glass procesu. Token rotation nesmí vyřadit podepisovací klíč a obráceně.
- Fork/PR workflow nesmí získat production secrets.

**Validation**

- Workflow syntax/action lint a dry-run dispatch bez uploadu — CI wiring.
- `rg` absence deprecated loginu, nebezpečných flags, chybných script names a nechráněného stable tracku.
- Čerstvý operátor podle dokumentace provede fake/dry-run scénář bez znalosti interních detailů.

**Exit condition**

- Existuje jediná dokumentovaná cesta pro každou operaci, production mutations mají approval a všechny položky deletion ledgeru jsou odstraněné nebo výslovně ohraničené.

## Rollout and rollback

1. Lokálně implementovat a ověřit Waves 1–3 bez vytvoření externí Shorebird app/release, pokud B1–B4 nejsou vyřešené; fake CLI a dry-run nesmí mutovat produkci.
2. Po samostatné autoritě dokončit Wave 0 externími hodnotami a provést Wave 4 pouze přes interní distribuci/staging.
3. Teprve po fyzickém důkazu vytvořit nový plný store baseline. Staré instalace bez updateru se nadále aktualizují jen přes `UpdateService`/store.
4. První reálný fix nejprve patchnout pro každou platformu zvlášť do staging, previewnout exact release a ověřit dvě spuštění. Promotion do stable je samostatné rozhodnutí.
5. Při sémantické regresi okamžitě zastavit další promotion, spustit explicitní rollback pro postiženou platformu/release a komunikovat nutnost restartu. Base a předchozí patch musí zůstat kompatibilní s backendem.
6. Při nativní/asset/toolchain změně, ztrátě signing klíče, Shorebird outage, vyčerpané kvótě nebo nejasnosti store policy použít nový standardní store release.
7. Periodicky vydávat plný store baseline i při úspěšném OTA provozu, aby se nezvětšovala vzdálenost od base, iOS interpretační výkon a rollback kompatibilita.

Rollback neznamená okamžité stažení kódu ze všech běžících procesů. Zařízení změnu zjistí při další updater kontrole a použije po restartu. Automatický crash rollback neodhalí chybná data nebo nesprávnou business logiku; proto jsou device evidence, backend kompatibilita a ruční incidentní rollback povinné.

## Verification strategy

| Risk or invariant | Verification seam | Command/observation |
|---|---|---|
| Konfigurace má jednoho vlastníka | apply-config fixtures a idempotence | `./automation/tests/apply_config.test.sh`; shodné hashe výstupů po dvojím apply |
| Reprodukovatelné dependencies | verzovaný lock | `git ls-files --error-unmatch pubspec.lock`; `fvm flutter pub get --enforce-lockfile` |
| Store identity odpovídá app ID | config/native/store cross-check | preflight + ruční Play/App Store evidence |
| Provider `none` nic nerozbije | dispatch shell test | fake CLI test bez volání Shorebirdu |
| Podepsaný přesný release | wrapper argument contract | fake CLI test + obě `shorebird release ... --dry-run` |
| Native/assets nejdou do patche | diff classifier negativní matice | `./automation/tests/shorebird_patch.test.sh` |
| Neexistuje bypass | statická absence | `rg -n -- 'allow-(native|asset)-diffs|release-version[ =]latest' automation/release .github/workflows` |
| Staging před stable | oddělené entry points | fake CLI logs; stable pouze v promotion testu |
| Runtime update skutečně funguje | interní store build na zařízení | baseline -> staging download -> druhý start -> visible diagnostic |
| Rollback funguje | explicitní incident flow | rollback -> check/restart -> předchozí patch/base na obou platformách |
| Offline start je zachovaný | fyzické zařízení bez sítě | cold start a klíčové offline flows |
| iOS výkon je přijatelný | citlivé flows na fyzickém iOS | porovnání mapy, scanneru, sync/importu a seznamů proti base |
| Backend přežije smíšené klienty | expand/contract integrační test | base i patched klient proti rozšířenému backendu |
| Store fallback zůstává | existující update-service seam | cílené Flutter testy + ruční starší store build |
| Repo regresní riziko | standardní suite | `./automation/test_all.sh` jednou po koherentní implementaci |
| CI nevystaví secrets | GitHub environment/fork boundary | workflow review, redacted dry-run logs, žádné secrets v PR jobu |

Netestovat lokalizované texty runbooku. Testovat pouze strojové protokoly: provider, identity, explicitní verzi, track, podpisové argumenty, klasifikaci diffu a exit codes.

## Definition of complete

- [ ] Každý release/patch entry point prochází kanonickým configem, identity guardem a preflightem.
- [ ] `pubspec.lock` je verzovaný a release používá přesně Flutter 3.44.8.
- [ ] Shorebird app ID je potvrzené proti skutečné Android/iOS store identitě.
- [ ] `shorebird.yaml` je generovaný, verzovaný, idempotentní a bez secrets.
- [ ] První store baseline obsahuje public signing key a všechny patche jsou podepsané odpovídajícím private key.
- [ ] Patch gate odmítá native, asset, toolchain, plugin, lockfile, identity a nejasné compiled-mobile změny bez override flagu.
- [ ] Exact release version, staging-first a explicitní promotion/rollback jsou vynucené testy.
- [ ] Fyzický iOS a Android prokázaly baseline, download, aplikaci patche, offline start a rollback.
- [ ] Backend/local persistence změny splňují rollback kompatibilitu.
- [ ] `UpdateService`, web update a standardní store release zůstávají funkční a jasně oddělené.
- [ ] Runbook pokrývá outage, quota, ztrátu klíče, semantic bug a emergency store release.
- [ ] Deletion-ledger položky jsou odstraněné nebo záměrně ohraničené a absence je prokázaná.
- [ ] Standardní validační sada projde; produkční kroky jsou buď výslovně autorizované a ověřené, nebo přesně označené jako pending.
- [ ] Žádný commit, push, store upload, stable promotion ani rollback neproběhl bez samostatné autority.

## Residual risks

- Apple/Google mohou změnit pravidla nebo konkrétní update odmítnout; žádný nástroj negarantuje „obejití store“ pro libovolnou funkcionalitu.
- Shorebird cloud je externí single-vendor dependency bez self-host varianty. Outage nevyřadí base aplikaci, ale znemožní nové OTA zásahy.
- Free tier může být nedostatečný pro produkční počet zařízení nebo incidentní rollback.
- Auto-update má minimálně dvouspuštěcí latenci a offline zařízení mohou zůstat dlouho na starém kódu.
- Interpretovaný iOS patch může mít měřitelnou výkonnostní regresi.
- Bez vzdáleného aplikačního crash/behavior monitoringu zůstává detekce některých sémantických regresí závislá na Shorebird eventech, supportu a ručním ověření.
- Ztráta private key nebo chybná custody vyžaduje nový store baseline; kompromitovaný klíč je produkční incident.
- White-label historie repozitáře vytváří trvalé riziko lidské záměny; identity guard ho snižuje, ale externí store evidence musí zůstat aktuální.
