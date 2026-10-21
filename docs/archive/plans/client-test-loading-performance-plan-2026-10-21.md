# Zrychlení klientských testů odstraněním opakovaného načítání

Datum: 2026-10-21
Stav: Dokončeno - naměřený cíl 15 % splněn; následná integrace viz závěr
Příprava plánu: low-risk, bez spouštění testů
Implementace: standard - mění sdílené testovací prostředí

## Výsledek a priority

Zachovat všechny dnešní klientské regresní scénáře a zkrátit celý příkaz
`./automation/test_client.sh` především odstraněním redundantního načítání
Flutter sad. Primární cíl je alespoň 15 % z mediánu srovnatelné nové baseline;
20 % je ambiciózní cíl. Procenta nejsou předem slíbený výsledek.

Nejprve přesunout významný balík kompatibilních sad. Teprve podle výsledku
optimalizovat konkrétní drahé scénáře. Nevytvářet nový testovací framework,
dynamický registr, obecnou vrstvu resetování singletonů ani nový benchmark runner.

## Pevný bod a ověřené podklady

Průzkum vychází z čistého zdrojového snapshotu `35e421e27a26f1d4e4dc45016767669e760e4f48`
v `/Users/miakh/source/festapp-test-reliability-20261021`.
Původní pracovní adresář `/Users/miakh/source/festapp` obsahuje rozsáhlé rozpracované
změny. Implementovat v odděleném čistém worktree z aktuálního autoritativního main;
předchozí pracovní adresář ani cizí změny nečistit a nepřenášet hromadně.

Podklady v uvedeném snapshotu:

- `docs/archive/test-reliability-performance-2026-10-21/results.json`,
  klíč `canonical-baseline` a `flutterRoots`.
- `.codex-artifacts/test-reliability-20261021/measurements/canonical-baseline/`:
  `summary.json`, `measurement.json`, `flutter.jsonl`, `core.jsonl`, `adapters.jsonl`.
- `automation/client_test_classification.json`, `automation/client_test_inventory.json`.

| Ověřený fakt | Hodnota | Důsledek |
|---|---:|---|
| Poslední celý PASS na snapshotu | 204,85 s | Historická orientace, nikoli nový referenční medián |
| Flutter kritická cesta | 191,17 s | Core/adaptéry nejsou první optimalizační cíl |
| Součet syntetických loading událostí, 71 Flutter kořenů | 74,292 s | Velký prostor pro méně samostatných kompilací/načtení |
| Součet skutečných scénářů Flutteru | 110,318 s | Druhá priorita po konsolidaci |
| Framework setup/teardown události | 1,485 s | Samotný setUpAll není dominantní náklad |
| Samostatné kořeny s obecným zdůvodněním „Existing canonical-main regression...“ | 38, loading 36,571 s | Důvod v klasifikaci sám neprokazuje nutnost samostatného procesu |
| Inventář předchozího PASS | 1 890 případů, 1 existující skip | Zachovat identitu, multiplicitu a skip stav |

Loading událost zahrnuje náklady nástroje a načtení/kompilace. Není to čistý čas
startu enginu ani zaručená uspořitelná část. Součet přesunutých loading časů je
pouze horní orientační potenciál před přidanými náklady cílové session.
Core a adaptéry se překrývají; časy paralelních lanes nesčítat.

Předchozí zamítnutý přesun dvou kořenů zasáhl pouze 2,055 s loading času.
Není důkazem neúčinnosti konsolidace většího kompatibilního balíku.

## Rozsah a nedotknutelné kontrakty

V rozsahu jsou `test/**`, jejich explicitní registrace a dva existující JSON
manifesty. Pomocný report časů smí číst stávající JSONL a používat
`automation/client_test_inventory.py:is_semantic_case`; nevymýšlet druhou definici
skutečného testu. Produkční kód, SQL, síťové služby, release a deploy jsou mimo rozsah.

- Nejvýše jedna Flutter úloha na celém počítači, vždy `--concurrency=1`.
  Před spuštěním zkontrolovat běžící úlohy, cizí úlohu nezastavovat.
- Používat FVM. Neměnit limity souběhu, timeouty ani vypínat architekturu/inventář.
- Ponechat skutečné UI interakce, zamítnuté příkazy, právě-jednou zápisy a kontrolu
  refresh/rethrow. Výkon nezískávat odstraněním assertionů, případů nebo kombinací.
- Root Supabase/Auth klient, jiná binding implementace a neobnovitelné globální
  nastavení zůstávají oddělené, pokud nelze kompatibilitu doložit veřejným lifecycle.
- Nepřidávat live přístup, placené služby ani síť do offline benchmarku.

## Cílové uspořádání a vlastnictví

`test/sessions/shared_*_test.dart` zůstávají jedinými společnými vstupy.
`test/support/register_client_suites.dart:registerClientSuites` zůstává jediným
mechanismem explicitní registrace kompatibilních skupin a jejich obráceného pořadí.
Přesunutý původní `*_test.dart` se stane `*_cases.dart`; zachová `main()` a vlastní
setup/teardown. Je registrován právě jednou, pod stabilním jednoznačným prefixem.
Původní spustitelný kořen se odstraní, žádný přesměrovávací wrapper.

`automation/client_test_inventory.json` vlastní původ případu a explicitní migrace.
`automation/client_test_classification.json` vlastní popis každého zbývajícího
kořene a jeho zdrojů. Po přesunu změnit obě evidence. Nikdy nespustit inventory
`baseline`, nepřepsat seznam případů nově naměřeným výsledkem a nesmazat staré migrace.

Preferovat existující default nebo českou session podle skutečného kontraktu.
Nezaměňovat default-uninitialized za český katalog. Vytvořit další explicitní
session pouze pro doložený společný kontrakt několika sad, který žádná stávající
session nemá. Velikost skupiny ani vyrovnání počtu testů nejsou cíle: při jednom
workeru rozhoduje celkový čas, paměť a izolace.

## Rozhodnutí, předpoklady a hranice

- Rozhodnutí: hlavní změna bude větší přesun kompatibilních kořenů, nikoli dvě
  kosmetické migrace nebo přepis produkční architektury.
- Předpoklad: významná část kandidátů níže sdílí prostředí. Jde o shortlist,
  nikoli schválené slučování podle textových shod. Potvrdit vlnou 1.
- Předpoklad: main se může změnit. Na začátku jednou fetch/read-only porovnat
  aktuální main se snapshotem, prohlédnout jen dotčené soubory a aktualizovat plán.
  Regrese nového main neopravovat potichu jako součást optimalizace.
- Průzkum nepotvrdil blokující produktové rozhodnutí. Obsazený Flutter slot je
  důvod pokračovat statickou prací a počkat, nikoli měnit pravidla workstation.

## Vlna 1 - jednou rozhodnout kompatibilitu a uložit baseline

**Změna:** projít pouze shortlist A/B níže a existující cílové session. U každého
kandidáta doložit: binding, locale/fallback/katalog, SharedPreferences, timezone,
HttpOverrides/transport, root SDK identitu, font registry/cache, plugin mocky,
statické služby a registraci teardownu. Zkontrolovat i bezprostřední fixture/importy;
absence `Supabase.instance` v kořeni není důkaz absence v transitivní cestě.

Do malé tabulky v tomto plánu zapsat `source -> target/group` nebo konkrétní důvod
ponechání samostatně. Zvlášť projít timezone a globální locale, které předchozí
malý experiment narušil. Číst `tz.local` až po inicializaci timezone databáze;
obnovovat jen veřejně podporovaný stav. Neizolovat písma mazáním interní cache.

Výběr prvního koherentního balíku má pokrýt přibližně 20-30 s historického loading
času, je-li tolik kompatibilních kandidátů. Při menším bezpečném potenciálu to
zapsat ještě před úpravami a pokračovat největším bezpečným balíkem.

**Baseline:** po rezervaci volného slotu spustit existující
`python3 automation/benchmark_client.py --output "$PWD/.codex-artifacts/client-test-loading-20261021/baseline"`.
Použít nový adresář; pokud už obsahuje receipts, zvolit nový datovaný suffix,
původní receipts nepřepisovat. Příkaz má jeden warm-up a tři celé měřené běhy. Uložit přesný SHA, fingerprint,
SDK, JSONL a zatížení hostitele. Nepoužívat 204,85 s jako automatickou baseline.
Pokud baseline neprojde, výkon nelze poctivě vyhodnotit: doložit konkrétní regresi
nebo neúplné prostředí, neobcházet ji novým manifestem.

**Výstup:** cílová mapa kompatibility, seřazený balík a úspěšná nová baseline.
Průzkum ani baseline po každém jednotlivém přesunu neopakovat.

## Vlna 2 - hromadně odstranit dominantní načítání

**Změna:** přesunout schválený balík A a B do odpovídajících existujících sessions.
Upravit importy po přejmenování, explicitní registrace, `moves`, `migrations` a
klasifikaci v jedné koherentní změně. Zachovat původní těla případů a assertions.
Přidat jen úzké teardowny skutečně vlastněného stavu. Nezavádět sdílené mutable
objekty mezi případy a neobnovovat singletony přes privátní API.

**Validace:** až po celém balíku spustit dotčené sessions v normálním a obráceném
pořadí. Příkazy pro každý průchod sestavit z cílové mapy:

```sh
fvm flutter test --no-pub --concurrency=1 --reporter=json "${affected_sessions[@]}"
FESTAPP_FIXTURE_ORDER=reverse fvm flutter test --no-pub --concurrency=1 --reporter=json "${affected_sessions[@]}"
```

`affected_sessions` je shell pole konkrétních cílových souborů z dokončené mapy;
vytvořit je v shellu, nepřidávat discovery mechanismus do repozitáře. Přesměrovat
stdout každého příkazu do samostatného JSONL v adresáři měření.
Každý průchod má vlastní JSONL. Porovnat normalizovaný Counter případů v dotčeném
balíku před/po a normal/reverse existující funkcí `cases()` a mapou `moves`.
Při různé základní cestě worktree normalizovat jen přesný prefix původního rootu;
neopravovat identitu hledáním podobného názvu. Povolit jen explicitně přidané
regrese fixture. Ověřit původní skip stav. Obrácení top-level skupin doplnit
změnou pozice nových kohort vůči stávajícím, pokud jsou schované v jednom
vnořeném registrátoru; pouhé obrácení jeho obalu by izolaci neprokázalo.

**Při selhání:** jeden zaměřený cyklus diagnózy konkrétního vlastníka stavu.
Nevyřeší-li se veřejným lifecycle bez významného frameworku, vrátit danou
kohortu samostatně, zachovat ostatní bezpečné přesuny a zapsat důvod.

**Výstup:** větší balík prošel v obou pořadích, každý původní případ běží právě
jednou a žádný odstraněný kořen nezůstává spustitelný.

## Vlna 3 - pouze nákladově odůvodněné zrychlení těl

Po úspěšné vlně 2 jednou přečíst nové časy dotčených sessions. Jestliže jejich
úspora dává realistickou cestu k 15 %, rovnou přejít k finální validaci.
Jinak zpracovat nejvýše dva doložené náklady, bez širokého přepisování fixture:

1. `test/components/blueprint/blueprint_layout_ui_cases.dart`: česká session má
   historicky 29,496 s těl. Některé scénáře obsahují skutečné
   `tester.runAsync(Future.delayed(40 ms))`. Nahrazovat jen čekání na operaci,
   jejíž dokončení už fixture umí signalizovat Future/Completerem. Zachovat
   reálnou cestu přes UI a pending/failure stavy. Virtuální `tester.pump(Duration)`
   není automaticky wall-clock čekání; nemačkat plošně délky animací a timeoutů.
2. Z nového reportu vybrat nejdražší opakovaný render nebo načítání assetu.
   Historicky nejpomalejší jednotlivé případy: Google panel 2,535 s a Blueprint
   color-shell 2,377 s. To samo nezdůvodňuje refaktor. Google matice musí zachovat
   všechny šířky, jazyky, témata a stavy; Blueprint skutečné cancel/commit/undo
   přes veřejný editor. Produkční auth, font-admission a veřejné API neměnit.

Přijmout změnu těla pouze při prokazatelném zachování tvrzení a levnější cestě
stejným scénářem. Pokud dostupné dva kandidáty nevysvětlují podstatnou úsporu,
tuto vlnu přeskočit a uvést zbývající limit. Nové produkční rozhraní kvůli pár
sekundám testu není součástí tohoto plánu.

**Validace/výstup:** jediný cílený průchod upravených případů po celém balíku,
případně zahrnutý do dosud neprovedené normální/reverse validace dotčené session.
Žádné nové skipy, méně assertions ani nižší pokrytí matice.

## Vlna 4 - prokázat celé zrychlení a odstranit zbytky

Spustit stejný `python3 automation/benchmark_client.py --output "$PWD/.codex-artifacts/client-test-loading-20261021/candidate"`
na zmrazeném finálním zdroji, stejném SDK, jednom workeru a srovnatelně volném
hostiteli. Celý runner zahrnuje architekturu a inventář; nepřidávat po PASS ještě
duplicitní celý suite run. Runner kontrakty spouštět jen pokud se měnil runner;
tento plán jeho změnu standardně nevyžaduje.

Porovnat mediány baseline/candidate:
`speedup = 1 - candidate_median / baseline_median`. Doložit všechny jednotlivé
běhy, rozptyl, lane časy, součet loading/těl a měřenou peak RSS se stávající
výhradou součtu sdílených stránek. Odlišné zdroje uvnitř jedné série,
FAIL/INCOMPLETE nebo významné rozdíly zatížení nedávají platné procento.
Při nejasném přínosu neprovádět nekonečné opakování benchmarků.

- Alespoň 15 %: výkonový cíl splněn; 20 % označit jen pokud je doloženo.
- Menší kladný přínos: ponechat pouze jednoduché bezpečné kohorty s doloženým
  přínosem, uvést přesné procento a nesplněný cíl. Neoznačit celý plán za splněný.
- Nulový/nejistý přínos nebo regresní izolace/paměť: zamítnout dotčené přesuny,
  zachovat receipts a přiznat neprokázaný přínos. Vrácený zdroj vyžaduje validaci
  jeho vlastního fingerprintu; kandidátní PASS není potvrzením jiné kombinace.

Aktualizovat tento plán výsledkem a odkazem na receipts. Po skutečném dokončení
přesunout plán/prompt do `docs/archive/` a opravit odkazy. Nevytvářet dva aktivní
návody ani další blanket inventář.

## Deletion ledger a důkaz dokončení

| Artefakt | Akce | Důkaz |
|---|---|---|
| Každý přesunutý `*_test.dart` | Přejmenovat na `*_cases.dart`, původní kořen odstranit | Přesná mapa + seznam kořenů + architecture guard |
| Záznam starého kořene v klasifikaci | Nahradit cílovou session a všemi zdroji | Žádné stale/missing classified sources |
| Původ případů | Zachovat, doplnit explicitní migraci/prefix | Counter před/po shodný, bez duplicity a nových skipů |
| Neúspěšný pokus, pomocný reset, wrapper | Odstranit z finálního zdroje | Scoped diff/rg + žádná dvojí registrace |
| Staré inventáře/revision ledger | Zachovat historickou evidenci | Žádné přegenerování baseline |

Hotovo znamená: finální byte-identický zdroj má PASS celé validace, změněné
sessions prošly oběma pořadími, původní případy a skipy zůstaly, deletion ledger
je uzavřený a medián dokládá alespoň 15 %. Nižší bezpečná úspora je částečný
výsledek, který se uvede otevřeně. Žádný commit, push nebo deploy není k měření
potřeba ani tímto zadáním požadován.

## Shortlist s konkrétním vstupním pořadím

Oba pooly dohromady obsahují 40 kořenů a 37,691 s historického loading času.
To odpovídá 18,4 % historického celého běhu před režiemi konsolidace; samotný
shortlist tedy neslibuje 20% výsledek. Cílový potenciál první vlny není tvrdá
hranice: další bezpečné kandidáty z obou poolů přidat ve stejné koherentní vlně,
pokud jejich přínos a kompatibilita vycházejí lépe než úprava těl.
Časy jsou historický loading jednotlivých kořenů, nikoli očekávaná úspora.
Pool A neznamená čistý Dart: například `tickets_tab_data_test.dart` importuje
TrinaGrid. Nepřesouvat business logiku do core jen kvůli názvu testu.
Pool B obsahuje explicitní lokalizaci, ale shoda češtiny sama nezaručuje stejný
fallback, fonty ani lifecycle. SDK/Auth kořeny nejsou automaticky kandidáty.

### A - krátké scénáře a běžné widgety

20 kořenů; součet loading 17.593 s.

| Kandidát | Loading s |
|---|---:|
| `test/components/forms/admin_offer_form_link_test.dart` | 1.511 |
| `test/components/eshop/tickets_tab_data_test.dart` | 0.936 |
| `test/components/eshop/report_number_format_test.dart` | 0.750 |
| `test/components/occasion/occasion_setup_story_test.dart` | 0.959 |
| `test/components/occasion/demo_occasion_navigation_test.dart` | 0.765 |
| `test/components/bank_accounts/bank_sync_contacts_test.dart` | 0.295 |
| `test/components/groups/group_save_reconciliation_test.dart` | 0.689 |
| `test/components/activities/activity_commands_test.dart` | 1.292 |
| `test/past_occasion_years_test.dart` | 0.769 |
| `test/services/platform_request_headers_test.dart` | 0.755 |
| `test/services/bounded_database_opener_test.dart` | 0.893 |
| `test/services/last_administration_context_test.dart` | 1.096 |
| `test/data_services/client_sync/client_command_activation_test.dart` | 0.702 |
| `test/components/images/recovering_image_test.dart` | 0.891 |
| `test/components/html/html_image_preview_test.dart` | 0.920 |
| `test/components/forms/form_read_only_inspection_test.dart` | 1.115 |
| `test/components/eshop/order_delete_availability_test.dart` | 0.875 |
| `test/components/occasion/occasion_setup_invitations_test.dart` | 0.904 |
| `test/components/occasion/occasion_setup_communication_test.dart` | 0.751 |
| `test/components/occasion/occasion_setup_details_test.dart` | 0.725 |

### B - explicitní lokalizované prostředí

20 kořenů; součet loading 20.098 s.

| Kandidát | Loading s |
|---|---:|
| `test/components/forms/verification_review_test.dart` | 0.917 |
| `test/components/forms/form_capacity_settings_test.dart` | 1.054 |
| `test/components/forms/organization_identity_test.dart` | 1.164 |
| `test/components/forms/waitlist_offers_dialog_test.dart` | 0.917 |
| `test/components/bank_accounts/connection_refresh_test.dart` | 0.845 |
| `test/components/bank_accounts/bank_account_card_test.dart` | 0.974 |
| `test/components/bank_accounts/order_bank_sync_warning_test.dart` | 1.213 |
| `test/components/navigation/inventory_navigation_behavior_test.dart` | 1.159 |
| `test/components/navigation/unit_occasion_draft_navigation_test.dart` | 0.767 |
| `test/components/occasion_settings/advanced_link_visibility_test.dart` | 0.908 |
| `test/components/eshop/order_state_width_test.dart` | 1.449 |
| `test/components/eshop/history_delete_test.dart` | 1.161 |
| `test/components/eshop/waitlist_toolbar_test.dart` | 0.927 |
| `test/components/eshop/waitlist_history_test.dart` | 1.157 |
| `test/components/eshop/price_wave_availability_test.dart` | 0.843 |
| `test/components/eshop/waitlist_order_detail_test.dart` | 1.189 |
| `test/components/occasion/occasion_setup_draft_card_test.dart` | 0.740 |
| `test/components/occasion/occasion_cover_draft_test.dart` | 0.979 |
| `test/components/occasion/demo_occasions_section_test.dart` | 0.932 |
| `test/components/occasion/demo_occasion_banner_test.dart` | 0.803 |

### Záměrně nezačínat těmito cestami

`authorization_projection_test.dart`, `client_command_identity_test.dart`,
`rights_explicit_occasion_test.dart`, `sign_in_code_login_test.dart`,
`external_login_context_test.dart` a kořeny inicializující root SDK zůstanou
samostatně, dokud není doložen konkrétní veřejný lifecycle. Největší jednotlivý
loading 3,403 s v autorizační projekci není automaticky nejlevnější úspora.
Neslučovat locale matrix do výchozího prostředí. Stávající tři default sessions
lze posoudit až po shortlisted balíku; jejich vzájemné sloučení ušetří nanejvýš
několik dalších startů a není první prioritou.

## Zbytková rizika

Historické časy nemají opakovaný medián a neprokazují 74 s čistě odstranitelného
nákladu. Přesun může zvýšit kompilaci cílové session, paměť nebo odhalit skrytý
stav. To řeší větší koherentní balík, kontrola obou pořadí a finální měření;
žádná předem předepsaná minimální redukce počtu kořenů tato rizika neobejde.

## Execution evidence - 2026-10-21

Authoritative main: `c4fbf06642bb926d5fff3f5978d04e88b761c749`. Clean worktree:
`/Users/miakh/source/festapp-client-test-loading-20261021`.
Compared with planning snapshot: Blueprint UI/host/font fixtures, mobile pan,
route navigation and rights regressions advanced. No candidate bodies or
benchmark/inventory runner contracts changed. A new baseline is required.

First coherent batch: 34 roots, historical loading potential approximately
31 s. Six incompatible singleton/catalog roots remain standalone.
All candidates retain their own setup/teardown; public font admission remains
unchanged (no cache resets). SharedPreferences initialization stays in original
hooks. Widget view and plugin handlers retain their original cleanup.
Timezone writers will restore the previous public local location after
initializing the timezone database; rights writers will restore their previous
public context rather than assuming null. No shared reset framework is added.
The default target has no localization initialization; new groups register
directly alongside existing groups so reverse order crosses cohort boundaries.

| Source | Target / group | Compatibility decision |
|---|---|---|
| `test/components/forms/admin_offer_form_link_test.dart` | `test/sessions/shared_default_2_test.dart` / `admin_offer_form_link` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/eshop/tickets_tab_data_test.dart` | `test/sessions/shared_default_2_test.dart` / `tickets_tab_data` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/eshop/report_number_format_test.dart` | `test/sessions/shared_default_2_test.dart` / `report_number_format` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/occasion/occasion_setup_story_test.dart` | `test/sessions/shared_default_2_test.dart` / `occasion_setup_story` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/occasion/demo_occasion_navigation_test.dart` | `test/sessions/shared_default_2_test.dart` / `demo_occasion_navigation` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/bank_accounts/bank_sync_contacts_test.dart` | `test/sessions/shared_default_2_test.dart` / `bank_sync_contacts` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/groups/group_save_reconciliation_test.dart` | `test/sessions/shared_default_2_test.dart` / `group_save_reconciliation` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/activities/activity_commands_test.dart` | `test/sessions/shared_default_2_test.dart` / `activity_commands` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access; restore tz.local after database initialization |
| `test/past_occasion_years_test.dart` | `test/sessions/shared_default_2_test.dart` / `past_occasion_years` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/services/platform_request_headers_test.dart` | standalone | PackageInfo singleton mock persists; no public snapshot/restore API. |
| `test/services/bounded_database_opener_test.dart` | `test/sessions/shared_default_2_test.dart` / `bounded_database_opener` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/services/last_administration_context_test.dart` | `test/sessions/shared_default_2_test.dart` / `last_administration_context` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/data_services/client_sync/client_command_activation_test.dart` | `test/sessions/shared_default_2_test.dart` / `client_command_activation` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/images/recovering_image_test.dart` | `test/sessions/shared_default_2_test.dart` / `recovering_image` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/html/html_image_preview_test.dart` | `test/sessions/shared_default_2_test.dart` / `html_image_preview` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/forms/form_read_only_inspection_test.dart` | `test/sessions/shared_default_2_test.dart` / `form_read_only_inspection` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/eshop/order_delete_availability_test.dart` | `test/sessions/shared_default_2_test.dart` / `order_delete_availability` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/occasion/occasion_setup_invitations_test.dart` | `test/sessions/shared_default_2_test.dart` / `occasion_setup_invitations` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/occasion/occasion_setup_communication_test.dart` | `test/sessions/shared_default_2_test.dart` / `occasion_setup_communication` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/occasion/occasion_setup_details_test.dart` | `test/sessions/shared_default_2_test.dart` / `occasion_setup_details` | standard binding; no locale/catalog initialization; injected/local transport and models, no root SDK access |
| `test/components/forms/verification_review_test.dart` | standalone | English custom key catalog differs from existing sessions. |
| `test/components/forms/form_capacity_settings_test.dart` | `test/sessions/shared_czech_test.dart` / `form_capacity_settings` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/forms/organization_identity_test.dart` | standalone | English custom key catalog differs from existing sessions. |
| `test/components/forms/waitlist_offers_dialog_test.dart` | `test/sessions/shared_czech_test.dart` / `waitlist_offers_dialog` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/bank_accounts/connection_refresh_test.dart` | standalone | English empty/key catalog differs from existing sessions. |
| `test/components/bank_accounts/bank_account_card_test.dart` | standalone | English full catalog and Roboto rendering differ from existing sessions. |
| `test/components/bank_accounts/order_bank_sync_warning_test.dart` | standalone | RootSupabaseFixture plus English catalog; retain root SDK isolation. |
| `test/components/navigation/inventory_navigation_behavior_test.dart` | `test/sessions/shared_czech_test.dart` / `inventory_navigation_behavior` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/navigation/unit_occasion_draft_navigation_test.dart` | `test/sessions/shared_czech_test.dart` / `unit_occasion_draft_navigation` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/occasion_settings/advanced_link_visibility_test.dart` | `test/sessions/shared_czech_test.dart` / `advanced_link_visibility` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/eshop/order_state_width_test.dart` | `test/sessions/shared_czech_test.dart` / `order_state_width` | standard binding; cs full catalog through its existing public EasyLocalization root |
| `test/components/eshop/history_delete_test.dart` | `test/sessions/shared_czech_test.dart` / `history_delete` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/eshop/waitlist_toolbar_test.dart` | `test/sessions/shared_czech_test.dart` / `waitlist_toolbar` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/eshop/waitlist_history_test.dart` | `test/sessions/shared_czech_test.dart` / `waitlist_history` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/eshop/price_wave_availability_test.dart` | `test/sessions/shared_czech_test.dart` / `price_wave_availability` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/eshop/waitlist_order_detail_test.dart` | `test/sessions/shared_czech_test.dart` / `waitlist_order_detail` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/occasion/occasion_setup_draft_card_test.dart` | `test/sessions/shared_czech_test.dart` / `occasion_setup_draft_card` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/occasion/occasion_cover_draft_test.dart` | `test/sessions/shared_czech_test.dart` / `occasion_cover_draft` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/occasion/demo_occasions_section_test.dart` | `test/sessions/shared_czech_test.dart` / `demo_occasions_section` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |
| `test/components/occasion/demo_occasion_banner_test.dart` | `test/sessions/shared_czech_test.dart` / `demo_occasion_banner` | standard binding; cs full catalog through public widget/delegate lifecycle; no new root SDK identity |

### Baseline blocker before optimization

The first warm-up on c4fbf0664 failed the inventory gate. Core (7.13 s),
adapters (16.82 s) and Flutter (147.38 s) passed; complete command took 164.28 s
but is not an accepted timing baseline. Actual discovery: 1,904 cases, one skip.
Commit 7115f22ce intentionally replaced `denied context without a resolved link
stops reloading` with `failed context without a resolved link stops reloading`
and changed the expected label from Access denied to
CommonStrings.contextLoadFailed; the inventory still requires the old identity.
This is unrelated to loading consolidation. No optimization has been applied.
Receipts: `.codex-artifacts/client-test-loading-20261021/baseline/` and
`baseline-blocker.json`. Awaiting explicit authorization for one documented
contract revision before attempting a fresh, fully passing baseline.

User authorized the single explicit inventory correction and continuation.
Only the known renamed row and its baseline_revisions entry are changed;
no baseline is generated and no discovered list replaces the manifest.
Fresh baseline receipts use `baseline-corrected/`.

### Accepted baseline and coherent batch

`baseline-corrected/` completed PASS on all four runs with unchanged fingerprint
`5d98282c10c9cd766b2bcb5dfa69d0ce116c94bd1ae212ab4fc6d89b74e9952b`.
Warm-up 147.97 s; measured 175.50 / 198.42 / 171.94 s; median 175.50 s.
Peak summed RSS about 1.64 GiB. Timing variation is material and will be
reported alongside the final comparison.
Applied the mapped 34-root cohort into existing shared_default_2 and
shared_czech sessions, directly at top level to cross old/new groups in reverse.
The previous custom key fallback classification for order_state_width was
corrected during inspection: its loader actually reads the full cs catalog.
The main snapshot already reduced Blueprint's explicit 40 ms waits to four;
these cannot explain a substantial remaining gap, so no speculative body
rewrite is justified.

### Order and inventory proof

Normal and reverse passes both completed successfully. Existing `cases()`
compared the exact affected baseline suite set (34 old roots plus the two
shared sessions) against each result: 889 semantic cases, zero skips, no
missing/added/duplicated identities in either order. Receipts:
`normal.jsonl`, `reverse.jsonl`, `baseline-affected.jsonl`,
`order-inventory-comparison.json` in the artifact directory.
New groups are direct siblings of existing session groups; reversal therefore
changes cohort position relative to both old and new groups.
Combined session loading/body sums: normal 5.822/31.321 s, reverse
6.017/32.077 s (reporter intervals, not independent wall-time savings).
No test body optimization was needed before final measurement.

Final source is frozen while `candidate/` runs warm-up plus three measured
whole-suite passes. No additional whole-suite validation will follow its PASS.

## Výsledek implementace

Celý příkaz `./automation/test_client.sh`: medián **175,5026 s -> 142,9469 s**,
naměřená úspora **18,55 % (32,56 s)**. Cíl 15 % je splněn; 20 % dosaženo nebylo.
Finální benchmark má PASS warm-upu i všech tří měřených běhů včetně
architektury a inventáře, na jednom Flutter workeru a stejném SDK 3.47.2.
V každé sérii zůstal fingerprint neměnný.

| Série | Warm-up s | Měřené běhy s | Medián s | Peak summed RSS GiB |
|---|---:|---|---:|---:|
| Baseline | 147,97 | 175,50 / 198,42 / 171,94 | 175,50 | 1,64 |
| Kandidát | 124,84 | 135,03 / 163,23 / 142,95 | 142,95 | 1,92 |

Mediány lanes baseline -> kandidát: core 7,37 -> 7,12 s, adaptéry
13,98 -> 14,08 s, Flutter 161,50 -> 128,37 s. Překrývající se lanes
nesčítat. Medián součtu reporter loading intervalů Flutteru klesl
z 63,276 na 36,518 s; medián těl z 95,598 na 89,042 s. Tyto intervaly
nejsou samostatnou wall-clock úsporou.

Zachováno přesně **1 904 případů a jeden původní skip**, bez dodatečných
případů nebo duplicit oproti nové úspěšné baseline. Porovnání využilo
existující `cases()` a aktuální explicitní mapu `moves`. Dotčených
889 případů prošlo normal/reverse s identickými Countery. Assertiony
a UI scénáře zůstaly; změny těl se omezují na vlastnictví veřejného
timezone/rights stavu. Produkční kód ani benchmark runner se neměnily.

Odstraněno 34 původních kořenů, počet zbývajících kořenů 72 -> 38.
Všechny nové cases jsou právě jednou přímo registrovány ve dvou existujících
sessions. Oba manifesty obsahují fyzické přesuny a původní evidence zůstává
zachována. Jedinou nezávislou změnu historického případu tvoří předem
schválená oprava zastaralého záznamu navigace, doložená v baseline_revisions.
Žádný baseline seznam se negeneroval.

Paměť je vědomý kompromis konsolidace: sampled summed RSS vzrostla
z 1,64 na 1,92 GiB, stále pod neměnným limitem 3 GB. Součet může opakovaně
započíst sdílené stránky. Časy mají významný rozptyl; kandidát měl vyšší
load average přibližně 4,4-6,0 oproti 3,8-4,1 na 10 logických CPU,
bez další Flutter úlohy a pod saturací podle počtu CPU. Uvedené procento
je pozorovaná změna mediánu, nikoli statistický interval spolehlivosti.

Deletion ledger je uzavřen: 34 starých kořenů neexistuje, žádné stale Dart
importy, wrappery ani dvojí registrace; final architecture/inventory PASS.
Žádný commit, push ani deploy nebyl proveden.

[Souhrn výsledků a jednotlivé běhy](../client-test-loading-performance-2026-10-21/results.json).
Úplné lokální receipts včetně JSONL, logů, SDK, host load a fingerprintů:
`/Users/miakh/source/festapp-client-test-loading-20261021/.codex-artifacts/client-test-loading-20261021/`.
Neúspěšný původní warm-up je uchován v `baseline/`; úspěšná referenční
série je `baseline-corrected/`, finální série `candidate/`.

## Následná integrace na žádost uživatele

Uživatel následně požádal o merge. Změna byla bez konfliktů přenesena
na aktuální autoritativní main `53c32c458a80967432be859aff1331a7ea88060a`,
který přidal opravu dokončených occasion setup konceptů. Před publikací
obě dotčené sessions znovu prošly normal/reverse na tomto novém základu;
889 případů a jejich Countery zůstaly shodné s původní úspěšnou baseline.
Receipts: `.codex-artifacts/client-test-loading-20261021/merge-validation/`.
Výkonové měření výše nadále platí pro původní zaznamenaný zdroj; benchmark
nebyl na novém produkčním kódu opakován. Integrace neobsahuje produkční změny
navíc oproti upstream main a není deploymentem.
