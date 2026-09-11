# Execute: Bezpečné OTA aktualizace mobilní aplikace přes Shorebird

Work in `<repo-root>`.

Použij repository instructions a verification mode `standard` zaznamenaný v plánu. Produkční/store operace mají vlastní release gate a samostatnou autoritu.

Implementuj celý autoritativní plán:

`docs/plans/shorebird-ota-plan-2026-08-02.md`

Před editací jej celý přečti. Cílem je volitelná, identitně bezpečná a podepsaná Shorebird OTA cesta pro Android/iOS, která pouští pouze kompatibilní Dart patche přes staging a explicitní promotion, zatímco nativní/asset změny dál používají store release.

Nezačínej tím, že spustíš `shorebird init --force`. Nejdřív ověř aktuální repo evidence a stav blockerů B1–B4. Pokud chybí skutečná store identity, Shorebird app ID nebo schválená custody privátního klíče, implementuj jen části, které lze dokončit s bezpečnými fixtures/fake CLI, a přesně označ zbývající externí krok; nevymýšlej produkční hodnoty.

Proveď waves v dependency pořadí. Zachovej `automation/project.conf` jako jediný zdroj veřejné OTA konfigurace, generuj `shorebird.yaml`, začni verzovat kořenový `pubspec.lock`, vynucuj skutečnou Android/iOS identitu, Flutter 3.44.8, podpis, exact release version a staging-first. Nikdy nepoužívej ani nevystavuj `--allow-native-diffs`, `--allow-asset-diffs`, `latest` nebo přímé stable patchování. Privátní klíč a `SHOREBIRD_TOKEN` nesmí vstoupit do repozitáře ani logů.

Nevytvářej runtime update UI ani nepřidávej `shorebird_code_push`, pokud nové ověřené repo/produktové evidence nevyvrátí rozhodnutí D2. Zachovej a otestuj ohraničené cesty `UpdateService`, webový update manifest, Fastlane upload a provider `none`; nejsou to legacy duplikace. Odstraň nebo ohranič každou položku deletion ledgeru a dolož absence proofs.

Pokud aktuální repository evidence vyvrátí faktickou premisu, aktualizuj autoritativní plán s konkrétním důkazem a uprav dotčenou wave bez tiché změny požadovaného výsledku. Nenechávej placeholdery, druhé konfigurační zdroje, paralelní release implementace, spekulativní fallbacky ani nechráněné produkční vstupy.

Spusť jen validace požadované plánem a repository rules; seskup je podle low-output pravidel a po selhání proveď nejvýše jednu zaměřenou diagnosis/fix iteraci, pokud nové riziko nevyžaduje standardní eskalaci. Nespouštěj nezávislý review ani subagent audit bez výslovné žádosti.

Bez samostatné autority neprováděj vytvoření/změnu Shorebird účtu či app, upload release/patch artefaktu, stable promotion, rollback, App Store/Play upload nebo rollout, změnu billing plánu, commit ani push. `--dry-run`, fake CLI testy a read-only kontroly jsou povolené.

Při handoffu uveď kanonický config/operation contract, skutečně potvrzené identity, migrované release vstupy, odstraněné bypassy, výsledky validace a každý přesný blocker nebo dosud neprovedený externí/produkční krok.
