# Tenant bez festivalové aplikace: pouze správa vstupenek

Navazuje na [první krok vypnutí veřejné aplikace](tenant-public-app-scope-2026-10-15.md). Stejná větev `fix/tenant-public-app-scope-20261015`, kanonický základ main `488988612`. Změny jsou lokální, nebyly nasazeny.

## Výsledný kontrakt IS_APP_SUPPORTED=false

Zůstává správa jednotky (`/unit/:id/edit`) a celá správa vstupenek (`/:link/reservations`): objednávky, formuláře, produkty, vstupenky, plány sálu, ubytovací inventář, reporty, e-maily a příslušná nastavení podle práv. Zachované jsou nákupní formuláře, přihlášení a kontrola vstupenek.

Celý druhý administrační strom `/:link/admin` není v tomto buildu registrován. Tím odpadají jeho informační obsah, program, místa a mapy, řečníci, skupiny, hra, služby a dobrovolníci. Také samostatné editory mapy a programové události a doprovodné aplikační stránky recepce/úklidu jsou vázané na podporu festivalové aplikace. Veřejné festivalové stránky zůstávají vypnuté podle předchozího kroku.

Příklady přesměrování při vypnutém flagu:

- `/akce/admin` -> `/akce/reservations`
- `/akce/admin/info/information` -> `/akce/reservations`
- `/akce/admin/volunteers` -> `/akce/reservations`
- veřejná aplikační obrazovka nebo oddělený editor -> `/`

Flutter matcher, generovaný Cloudflare worker a offline PWA worker mají pokrytá přesměrování. Web klient při handoffu nahrazuje obsahovou administraci správou vstupenek a zachovává existující přihlašovací handoff; společné a nákupní cesty si ponechávají úplné URL. Uživatel se stále musí prokázat původními právy pro rezervace/objednávky. Obnova uložené preference starého obsahového adminu při vypnutém flagu kontroluje práva pro rezervace.

Vnitřní navigační helper při výběru akce rovnou volí rezervace. Metadata obsahové administrace jsou při vypnutém flagu prázdná, aby ji nedržela ve společném kódu načítací obálka.

Při `IS_APP_SUPPORTED=true` se oba původní administrační stromy zachovávají. Read-only kontrola `origin/prod/festivalslunovrat:automation/project.conf` potvrdila pro `https://slunovrat.festapp.net` hodnotu `true`. Slunovratova konfigurace ani produkční větev se neměnily a nebyly pro něj spouštěny buildy nebo deploye.

## Skutečné srovnání buildů

Všechny varianty používají stejné zdroje a konfiguraci s compile-time hodnotou `isAppSupported=false`, Flutter 3.47.2 a Dart 3.13.2. Jediný produkční tenant v rozsahu je vstupenky.online; jde o místní porovnání proti stejnému základu, nikoli přesný tenant release nebo měření sekund.

| Hlavní JS | Původní stav | Jen vypnuté veřejné stránky | Bez veřejné aplikace i obsahového adminu |
| --- | ---: | ---: | ---: |
| Před kompresí | 10 960 139 B | 10 534 373 B | 9 760 678 B |
| Lokální Brotli Q9 | 2 477 147 B | 2 383 532 B | 2 199 164 B |

Celková úspora proti původnímu stavu: **1 199 461 B před kompresí (-10,94 %) a 277 983 B při stejné Brotli kompresi (-11,22 %)**. Samotné odstranění druhé administrace a jejích samostatných aplikačních editorů přidalo proti předchozímu kroku 773 695 B / 184 368 B úspory. Nejde o kompresní nastavení CDN a procenta se týkají hlavního JS, nikoli všech přenosů aplikace.

Dump-info potvrdilo nulový příspěvek těchto konkrétních knihoven ve finálním buildu: `activities_content.dart` (dobrovolnická časová osa), `schedule_content.dart` (správa programu), `map_page.dart` a `admin_page.dart`. Jejich knihovny nejsou jen přesunuté do odloženého chunku. Sdílené modely/služby potřebné pro ticketing a automaticky registrované pluginy mohou zůstat. Výsledek není kombinovaný s experimentem odložení textového editoru.

## Ověření a hranice

Finální web release build s vypnutým flagem prošel. Routerové testy v tomto režimu ověřily přesměrování obsahové administrace se zachováním odkazu na akci, odstranění samostatných editorů a zachování ticketingu. Se zapnutým flagem prošla běžná cílená sada 74 Flutter testů včetně admin/program/map deep linků. Dále byly ověřeny preference administrace v obou režimech.

Cílená Node sada prošla: 56/56. Zahrnuje skutečně vygenerovaný hosting worker, zachování obsahového adminu pro zapnutý flag, redirect starého adminu do rezervací, offline redirect PWA a webový přihlašovací handoff. PWA manifest, kořenový vstup a offline testy prošly. Web klient prošel `npm run build`.

Cílená Dart analýza nehlásila chyby. Při první analýze bylo 11 existujících informačních nálezů v routeru a jeden nový nález deprecated aliasu v testu; alias byl následně nahrazen `params` a oba režimy znovu otestovány. Známé nesouvisející selhání staršího testu HTTP hlaviček pro prázdné `/form/` je popsané v prvním záznamu a touto změnou se neřeší.

Nebyl proveden browser E2E ani produkční rollout. Změněná pravidla získá již nainstalovaná PWA aktualizací. Před nasazením zbývají obvyklé release gates a ověření hotového tenant buildu. Lokální kanonická konfigurace byla po testech vrácena na původní `isAppSupported=true`; false nadále určuje stávající konfigurace vybraného ticketového tenantu.

[Velikosti](tenant-ticketing-scope-2026-10-15/sizes.json), [největší změny knihoven](tenant-ticketing-scope-2026-10-15/largest-library-reductions.json). Celé buildy a logy: `/tmp/festapp-public-app-scope-20261015`.

## Zbývající závislosti a rozhodnutí před vydáním

Audit stejného ticketing-only compiler dump-info: všechny knihovny `components/features/` mají dohromady 59 394 B připsaného nekomprimovaného JS. Map/schedule/workshop/companion/counseling/import modely a jejich editační UI dohromady 31 785 B. Není to naměřená odstranitelná úspora: modely musí zachovat konfiguraci a sdílené závislosti mohou zůstat. Uživatel odmítl další refaktor tohoto modelového rozhraní.

Automatický web plugin registrant stále jmenuje MapLibre a geolokaci. Ve výsledném dump-info ale `maplibre_web` a `geolocator_web` mají každý jen 52 B a jejich platform interfaces každý 73 B. Samotný zápis v `pubspec.yaml` tedy neznamená, že se celý balíček dodává do hlavního JS. Přímé příspěvky knihoven nejsou zárukou celkové tranzitivní úspory nebo velikosti assetů.

`super_editor` zůstává s 416 334 B připsaného JS; `just_audio` 42 070 B a `just_audio_web` 14 191 B. Audio/video přehrávání používá sdílený HTML renderer, který potřebuje i ticketing. Tyto závislosti nelze prostě smazat z obecného pubspecu bez změny podporovaného obsahu. V tomto vydání se nemění pubspec ani automaticky generovaný plugin registrant. Odložené načítání textového editoru zůstává samostatnou příležitostí.

Uživatel následně autorizoval produkční nasazení pouze pro vstupenky.online. Release evidence bude uložena samostatně po ověření produkčního buildu.
