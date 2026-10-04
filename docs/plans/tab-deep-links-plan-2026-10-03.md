# Vlastní URL záložek a podzáložek

Datum: 2026-10-03  
Stav: Lokálně implementováno a cíleně ověřeno; omezení E2E jsou uvedena v závěrečné evidenci.  
Ověřování implementace: standard (sdílená navigace, URL kontrakt a přístup do administrace).

## Výsledek a rozsah

Každá navigační záložka i její podzáložka má obnovitelnou, sdílitelnou URL. Kliknutí, přímé otevření, reload a historie prohlížeče zobrazí stejnou obrazovku. Řešení používá stávající AutoRoute a jednu společnou prezentační komponentu, kterou lze použít v dalších modulech.

Priorita implementace: administrace události a rezervací včetně všech jejich podzáložek. Do dokončení patří také sekce administrace jednotky a výběr dne na samostatných programových obrazovkách. Stávající hlavní záložky zůstávají kompatibilní. Dny uvnitř vložených editorů a panely otevřené v dialogu mají samostatně pojmenovaný URL stav, viz níže.

Mimo rozsah: změny objednávkových, platebních a rezervačních RPC, SQL migrace, redesign, synchronizace rozepsaných dat mezi zařízeními, plošný rollout tenantů. Tabulka, filtr nebo rozpracovaný formulář nemusí mít celý svůj obsah v URL.

## Potvrzený současný stav

| Důkaz | Důsledek |
|---|---|
| `lib/app_router.dart`: `AdminRoute` a `ReservationsRoute` jsou koncové routy bez children. | Router dnes nemůže rozlišit jejich záložky. |
| `lib/components/occasion/occasion_home_page.dart`: `AutoTabsRouter`, `setActiveIndex`, retenční stav hlavních záložek. | Existuje zavedený vzor; není potřeba nový router ani vlastní browser history. |
| `schedule/schedule_navigation_screen.dart`: `ScheduleNavigationPage` vrací pouze `const AutoRouter()`; `app_router.dart` registruje výchozí program a `EventRoute(:id)` pod tímto shellem. | Stejný nested stack vzor použít pro seznam/detail formuláře a poolu. |
| `schedule/schedule_page.dart`: `context.router.push(EventRoute(id: id))`; `RouterService.scheduleBack` rekonstruuje prázdnou canonical root routu i při přímém odkazu. | Interní navigace používá nejbližší nested router; Back z přímého objektového odkazu musí vést na skutečný seznam. |
| Lokální `auto_route-11.1.0`: `AutoTabsRouter.tabBar` vlastní a synchronizuje `TabController`; `TabsRouter.setActiveIndex` volá `notifyAll` a URL rebuild. | Použít knihovní propojení; nepřidávat vlastní synchronizační controller ani browser history. |
| `admin_page.dart`, `reservation_page.dart`: lokální `TabController`, seznamy záložek podmíněné features a právy. | Index není stabilní identita a dostupnost se musí vyhodnocovat pro aktuální událost. |
| `single_data_grid/admin_page_helper.dart`: `AdminTabDefinition` míchá label, widget a dostupnost; klíč `emailTemplates` je přeložený getter. | URL nesmí vznikat z tohoto klíče, labelu ani pořadí. Současný registr se nahradí typovanými metadaty. |
| `forms/views/forms_tab.dart`: `_selectedForm`, automatický výběr jediného formuláře, `FormTab(formLink: ...)`. | Nestačí URL podzáložky; musí obsahovat identitu formuláře. |
| `inventory/views/inventory_pools_tab.dart`: lokálně vložený `InventoryPoolDetailView`. | Obnovitelný detail musí obsahovat ID poolu. |
| `unit/views/unit_admin_page.dart`: `_currentMenu`, `_setCurrentScreen`, načítání podle ID jednotky. | Také menu administrace jednotky je navigační stav. |
| `main.dart`: `_resolveDeepLink` používá při prvním otevření `widget.initialRoute`. | Nestačí matcher test; ověřit celý startup, zda zachovává suffix a query. |
| `rights_service.dart`: `updateAppData` serializuje načítání, následně aktualizuje globální kontext a features. | Přímý odkaz musí nejprve načíst a ověřit svou událost; starý globální kontext není zdroj identity. |
| `router_service.dart`: navigace do administrace přednačítá kontext; `navigateToOccasionAdministration` rozlišuje `context.widget`. | Vnořené routy vyžadují identitu administrace z route hierarchy, nikoli typ aktuálního widgetu. |
| `web_client/src/services/router_service.js`: rozdělení JS/Flutter rout a předání runtime. | Celá nová cesta i query musí přežít předání do Flutteru. |
| `test/startup/app_router_deep_link_test.dart`: testuje matcher a render vstupní routy. | Přirozená testovací hranice pro rozšíření. |

Pracovní větev při průzkumu: `release/ticket-editor-ui-20261003`. Sdílený kód patří podle pravidel na `main`; při implementaci nejprve ověřit pracovní stav a zvolit čistý checkout/worktree. Nepřenášet automaticky změny z této větve ani existující necommitované soubory.

## Architektura a smlouva

### Jeden vlastník navigace

`AppRouter` a jeho generované typované routy jsou jediným zdrojem aktivní navigační záložky. Statický route tree popisuje všechny podporované routy; dostupnost podle features a práv se řeší až po načtení kontextu. Nevytvářet route tree z momentálních globálních features.

V `lib/components/navigation/` zavést malou komponentu `RoutedTabScaffold` a typovaná metadata `RoutedTabDefinition`: stabilní identita, konkrétní `PageRouteInfo`, lokalizovaný label, ikona. Metadata neobsahují předem vytvořené widgety. Feature obsah vlastní svou routovanou stránku; registr nevyrábí veškerý obsah administrace při každém buildu.

Společná komponenta vykresluje navigaci a child outlet přes existující `AutoTabsRouter.tabBar`. Jeho builder předává knihovnou spravovaný `TabController` stávajícímu `AppPanelHelper` i podtabové liště. Vlastní synchronizační adaptér není výchozí řešení ani samostatná implementační vlna; instalovaná knihovna už toto propojení obsahuje. Žádné obousměrné URL listenery v jednotlivých feature widgetech.

Pro seznam/detail převzít `ScheduleNavigationPage` jako vzor: malý feature shell s `AutoRouter`, seznam jako empty-path child a detail s path parametrem jako sibling child. Detail může mít vlastní routované podtaby. Vnitřní kliknutí používá `context.router.push(TypedDetailRoute(...))`; plná absolutní cesta patří pouze vnějším vstupům a přepnutí kontextu. Back z přímo otevřeného detailu při absenci předchozího seznamu rekonstruuje canonical empty-path child v příslušném nested stacku, obdobně jako `RouterService.scheduleBack`. Neremountovat celý shell ani všechny ostatní záložky. Sdílet pouze mechanickou operaci, pokud mají callers stejný kontrakt; nepřenášet programovou znalost `context.tabsRouter` do všech feature detailů.

`OccasionTab` už ukazuje potřebná metadata (stabilní key, label, ikona, typovaná route). Nový admin descriptor má stejnou jednoduchou podobu. Není důvod kvůli tomu přesouvat či přepisovat fungující public home navigaci, která navíc vlastní badge, search modal a map lifecycle. Nesdílet tyto produktové chování prostřednictvím nafouknutého obecného registru.

`AppPanelHelper` zůstává vlastníkem vzhledu hlavičky. Dostane prezentační seznam a routerem řízenou navigaci, bez znalosti formátování URL nebo vytváření feature obsahu. Registr sekcí administrace vlastní pouze pořadí, prezentaci a dostupnost. Route slugs definovat jako konstanty sdílené s route deklaracemi; nevytvářet paralelní obecný routing framework, string dispatcher ani switch nad všemi widgety.

Nové route wrappers mají být malé a zůstat u příslušné feature. Identitu události číst přes ověřený parametr rodičovské routy. Prověřit nynější `AppRouter.LINK` / `linkFormatted` a skutečnou podobu generovaných parametrů; tento plán nenařizuje neověřený plošný rename.

### URL

Anglické lowercase slugs jsou stabilní; názvy v UI se dále lokalizují.

| Kontext | Kanonický tvar |
|---|---|
| Administrace události | `/:occasionLink/admin/:section` |
| Podzáložka administrace | `/:occasionLink/admin/:section/:subsection` |
| Rezervace | `/:occasionLink/reservations/:section` |
| Objednávky | `/:occasionLink/reservations/orders/current`, `.../orders/history` |
| Formuláře | `.../reservations/forms` a `.../forms/:formLink/editor|settings|design|responses` |
| Inventář | `.../reservations/inventory-pools` a `.../inventory-pools/:poolId/occupancy|rooms|settings` |
| Jednotka | `/unit/:id/edit/occasions|users|quotes|settings|email-templates|bank-accounts` |
| Datum programu | Dosavadní cesta + `?day=YYYY-MM-DD` v časovém pásmu události |

Sekce události: `info`, `events`, `places`, `speakers`, `groups`, `game`, `services`, `volunteers`, `email-templates`, `users`, `changes`, `settings`.

Sekce rezervací: `orders`, `tickets`, `blueprint`, `forms`, `products`, `inventory-pools`, `report`, `email-templates`, `users`, `settings`. Sdílený obsah users/settings/email templates lze registrovat pod oběma rodiči; neklonovat implementaci kvůli jinému URL prefixu.

Podzáložky události: `info/information|songbook`; `events/schedule|suspicious|exclusivity|feedback`; `places/list|paths|types|icons`; `game/checkpoints|groups|settings`. Seznam odpovídá nynějším `InformationTab`, `ScheduleTab`, `PlacesTab`, `GameTab`.

Staré vstupy `/:occasionLink/admin`, `/:occasionLink/reservations`, `/unit/:id/edit` zůstávají vstupními body a přesměrují s replace na první povolenou kanonickou sekci. Stejně se doplní chybějící výchozí podzáložka. `forms` zůstává skutečným seznamem; při jediném formuláři je dovolen dosavadní automatický výběr, ale musí provést replace na URL s jeho identitou.

Kliknutí uživatele vytvoří jeden krok browser historie. Opakované kliknutí na aktivní admin záložku nic nepřidá. Automatické defaulty a normalizace používají replace. Při návratu do ponechané záložky se zachová její poslední podzáložka a URL ji přesně reprezentuje. `setActiveIndex` už aktualizuje navigační URL přes knihovní `notifyAll`; nevytvářet druhou URL aktualizaci po kliknutí. Browser Back/Forward ověřit v integračním scénáři, včetně vnořené podzáložky.

Veřejná hlavní navigace má jiný existující kontrakt: opětovný klik na aktivní Program/Map resetuje pouze daný nested stack na canonical root. Zachovat jej i testy `occasion_home_navigation_contract_test.dart`; admin no-op politika nemění chování public home. Search je modal action, nikoli routovatelná sekce, a zůstává výjimkou mimo navigační taby.

### Dostupnost, context a lifecycle

Routovaná administrace má jednu vstupní hranici, která načte kontext podle route identity přes `RightsService.updateAppData` a ověří `canSeeAdministration` nebo `canSeeReservations`. Dětský obsah se nevytváří před úspěšným výsledkem. Dostupnost sekce používá stejnou politiku jako menu; skrytí záložky samo není oprávnění. SQL/RPC kontroly zůstávají autoritou přístupu k datům.

Přihlášení zachová celou zamýšlenou interní URL včetně podzáložky/query a po dokončení znovu vyhodnotí přístup. Nepovolená administrace skončí stavem odepření přístupu. Známá sekce vypnutá featurem se po ověření kontextu přesměruje s replace na první dostupnou sekci daného shellu; není-li žádná, zobrazí stav nedostupnosti. Neznámý slug skončí lokálním not-found, nikoli globálním přesměrováním na program.

Formulář i pool se ověří proti načtené události; smazaný nebo cizí objekt nezobrazí obsah. Chybějící objekt a nedostatečné oprávnění mají řízený stav bez zobrazení cizích dat. Při rychlém přepnutí A -> B nesmí dokončení starého načtení zaktivovat obsah A; chránit commit UI výsledku route identitou/generací. Existující serializaci `RightsService` znovu neimplementovat.

Retence stavu platí uvnitř stejné události/objektu. Změna identity resetuje příslušný shell a jeho cache. Zachovat dnešní refresh hooks, např. `ScheduleContent.reloadIfClean` při aktivaci suspicious sekce, i při vstupu přes historii.

Před skutečným opuštěním identity s neuloženými změnami použít společnou existující ochranu, pokud je dostupná, jinak úzký navigation guard. Zrušená navigace ponechá původní obsah i URL. Pouhý přechod mezi ponechanými podzáložkami nesmí zahodit editor ani spouštět uložení.

### Dynamické a dialogové taby

Den v `schedule_page.dart`, `timetable_page.dart`, `timeline/light_timeline_view.dart`, `advanced_timeline_tab.dart` a `schedule_tab_view.dart` je hodnotový stav, proto query, nikoli routa pro každý datumový widget. Jeden malý typovaný adaptér parsuje datum a promítne router stav do `TabController`; změna dne žádá router o URL. Žádná ruční `window.history`. Neexistující den se po načtení dat normalizuje s replace na dostupný den; index/weekday nejsou identita. Zachovat ostatní query parametry a aktuální detail routu.

Pro vložený program editoru používat oddělený parametr `preview-day`, aby se nepletlo datum celé obrazovky a datum náhledu. Pokud existují dvě současně viditelné timeline, mají pojmenované nezávislé parametry, nikoli sdílený lokální index.

`bank_account_settings_screen.dart` má variantu dialog i obrazovka. Existující účet dostane obnovitelnou routu pod unit bank-accounts s ID a `general|connection|users`; stejný obsah a přístupové kontroly používá i případný route-backed dialog. Vytvoření nového účtu bez ID je dočasný dialog bez deep linku.

`ticket_layout_editor.dart: showMobilePanel` přepíná dočasný mobilní panel elements/properties. Evidovat jej jako prezentační panel, ne samostatnou stránku: otevřený editor může používat `panel=elements|properties`; reload obnoví panel pouze tam, kde daný layout dává smysl. Na desktopu parametr nesmí měnit identitu editoru nebo otevírat nesmyslný modal. Nové, dosud neuložené objekty se z URL nerekonstruují.

## Implementační vlny

### 1. Navigační základ a jeden funkční řez

- Ověřit instalované AutoRoute API v lokálním package cache a existující startup pipeline, JS/Flutter handoff a guardy. Sepsat konečný route/query kontrakt a dohledat zbývající navigační přepínače ve `unit_admin_page.dart`; menu není nutně `TabBar`.
- Zavést společný shell/metadata a vstupní context/access hranici. První řez: reservations/orders/current a history od typed navigation až po přímé otevření.
- Změnit `app_router.dart`, malé wrappers u eshop, `OrdersTab`, `ReservationsPage`; `AppPanelHelper` využije controller z knihovního builderu. Nepřepisovat jeho vzhled ani breadcrumb logiku kvůli routování. Regenerovat `app_router.gr.dart` standardním build_runnerem, nikdy ručně.
- Odstranit lokální autoritativní controller OrdersTab. Selhání auth/data má stabilní UI; test nesmí vyžadovat produkční data.
- Validace: route matcher + widget navigace oběma směry, nedostatečná práva, izolovaný browser Back/Forward/reload. Výstup: URL, aktivní obsah a historie souhlasí v tomto řezu; další vlny použijí stejný základ.

### 2. Všechny sekce obou administrací

- Převést `AdminPage`, zbytek `ReservationsPage`, `AdminTabDefinition` a šest statických podtab shells `InformationTab`, `ScheduleTab`, `PlacesTab`, `GameTab`, `OrdersTab`, `FormTab`.
- Přidat default children/redirecty a lokální not-found. Dostupnost počítat z načteného kontextu; sjednotit menu a routovací politiku, bez změny stávajících pravidel práv.
- `RouterService.navigateToOccasionAdministration` přestane určovat shell přes `context.widget`; použije nejbližší admin/reservations route ancestor a dosavadní produktový default mimo shell.
- Validace: parametrizovaný matcher test všech deklarovaných sekcí a podsekcí, widget test feature/práva/změna locale, aktivace suspicious refresh hook. Výstup: žádná navigační admin podzáložka nemá vlastní autoritativní index.

### 3. Identita formuláře a inventáře

- V `FormsTab` nahradit `_selectedForm` navigací seznam/detail ve feature `AutoRouter` shellu dle vzoru `ScheduleNavigationPage`. Výběr v kartě i popupu používá nejbližší nested router; breadcrumbs, copy/create/refresh a návrat po smazání používají typed routy a původní callbacks pro data. Přímý detail má Back na canonical seznam i bez předchozí položky v navigačním stacku.
- `FormTab` route children sdílejí kontext formuláře, dostupnost a dirty state. Nepředávat callbacks jako jedinou podmínku funkčnosti deep linku; routovaný shell vlastní reload/notifikace pro děti.
- Totéž pro `InventoryPoolsTab` a `InventoryPoolDetailView`: pool ID je route parametr, děti occupancy/rooms/settings, po smazání replace na seznam.
- Validace: přímý odkaz na responses druhého formuláře, pool settings, cizí/smazané ID, zrušení odchodu se změnami a přepnutí událostí během načítání. Výstup: reload nevybere jiný objekt a nikdy nezobrazí kontext předchozí události.

### 4. Jednotka, datum a zbývající taby

- Převést `_currentMenu`/`_currentScreen` v `UnitAdminPage` na child routy podle skutečného konečného seznamu menu. Zachovat sdílené načítání jednotky, přístup a existující obsah.
- Zavést datumový adaptér a přesunout persistentní výběr dne ve výše jmenovaných program/timeline souborech pod URL. Existující `TabController` může zůstat vykreslovací mechanismus, nikoli zdroj navigační identity.
- Přidat obnovitelný detail existujícího bankovního účtu; nepřenášet citlivé hodnoty, přístupové tokeny ani neuložené formuláře do URL. Přidat `panel` stav editoru ticket layoutu.
- Validace: datum při jiném pořadí dní a více týdnech, všechny programové varianty, browser návrat z unit sekce/detailu účtu a nepovolený účet. Výstup: konečný inventář tabů má vlastní URL nebo explicitně zdůvodněnou dočasnou výjimku.

### 5. Dokončení kontraktu a odstranění starých cest

- Rozšířit `test/startup/app_router_deep_link_test.dart`, `test/startup/router_service_post_login_test.dart`, přidat cílené navigation/widget testy. JS handoff testy upravit jen v dotčeném chování.
- Audit `rg -n 'TabController|DefaultTabController|TabBarView|selectedIndex|_currentMenu|_selectedForm' lib/components`: každou zbývající položku klasifikovat, ne mechanicky odstranit. Routovací controller adapter a dočasný dialog jsou oprávněné zbytky, paralelní navigační stav nikoli.
- Aktualizovat architektonickou dokumentaci krátkým kontraktem, příkladem nové routované sekce a hranicí path/query/transient state. Nevytvářet dočasný feature flag ani V1/V2 implementaci.
- Výstup: cílené testy a browser scénáře projdou, deletion ledger uzavřen, všechny existující vstupní odkazy zachovány.

## Odstranění a kompatibilita

| Artefakt | Konečná akce a důkaz |
|---|---|
| Lokální navigační controllers admin/reservations a statických podtabů | Uzavřeno: admin/reservations/statické podtaby používají `RoutedTabScaffold`; scoped rg nachází pouze knihovní/datumové/dialogové prezentace. |
| `AdminTabDefinition.availableTabs` s widgety a překládanými identifikátory | Uzavřeno: jediná `AdministrationTabs` registrace s typovanými routami a stabilními slugs; všechny callers převedeny. |
| `_selectedForm`, pool selection a `_currentMenu` jako navigační autorita | Uzavřeno: FormDetail/InventoryPoolDetail/BankAccountDetail vlastní identitu v path; UnitAdministrationTabsRoute vlastní menu. Scoped rg staré selected/current autority nenachází. |
| Rozpoznávání administrace podle `context.widget` | Uzavřeno: RouterService rozpoznává ancestors podle route names a inherited path params. |
| Staré admin/reservations/unit root URL | Záměrně zachovat pouze jako veřejné vstupní redirecty s replace. |
| Stávající veřejné main tab URL | Zachovat a regresně otestovat; nemigrovat je na nové názvy. |
| Ručně psané browser history/URL synchronizace | Nevytvářet. Zachovat pouze dosavadní JS/Flutter runtime boundary, která předává úplnou URL. |

## Ověřování

Při plánování nebyly spuštěny testy ani build. Implementaci kontrolovat po ucelených vlnách, ne po každé editaci. Použít lokální AutoRoute API/dokumentaci a package source; při potřebě online ověření jen primární dokumentaci.

- `fvm dart run build_runner build --delete-conflicting-outputs`: generovaný router bez ručních úprav.
- `fvm flutter test test/startup/app_router_deep_link_test.dart test/startup/router_service_post_login_test.dart test/router_reserved_paths_test.dart` plus konkrétní nové testy navigace a přístupové politiky.
- `fvm flutter test test/components/occasion/occasion_home_navigation_contract_test.dart`: stávající retence hlavních tabs, nested EventRoute a canonical root návrat mají zůstat funkční; nové admin testy mají ověřovat chování, nikoli jen text implementace.
- `fvm dart analyze <dotčené Dart soubory>`: cílená diagnostika nového rozhraní a callerů.
- Browser kontrola pouze izolovanou headless session dle repository rules: hlavní taby, obě administrace, nested tab, reload, Back/Forward, login návrat, feature-disabled URL, nesprávné objektové ID, query handoff. Použít existující dev server; nezatěžovat uživatelův Chrome ani produkční mutace.
- Před případným samostatně autorizovaným commitem/publikací dodržet úplné gates z `CONTRIBUTING.md`, včetně `./automation/test_all.sh`; tento plán jejich splnění nepředstírá.

## Předpoklady a rizika

- Path názvy jsou návrhové rozhodnutí, protože současné admin tab URL dosud neexistují. Finální kontrola konfliktů statických slugů s `:formLink`/`:id` a wildcardy patří do matcher testů v první vlně.
- Podoba browser historie a dynamicky dostupných tabs musí být prokázána na instalované AutoRoute verzi. Zachování widgetu samo nedokazuje správný Back/Forward.
- Startup, post-login a web handoff se při průzkumu neověřovaly runtime. Cílené integrační testy musí prokázat zachování celé URL.
- U dirty editorů nejprve dohledat existující ochranu v dané feature; změna navigace nesmí nepozorovaně zavést ztrátu dat.
- Aktuální globální `RightsService` vyžaduje opatrnost při přepínání událostí. Přechod na nový globální state management není součástí této práce.

## Hotovo znamená

- Všechny navigační taby a podtaby uvedené v plánu mají stabilní obnovitelný URL stav, včetně identity formuláře/poolu a dne.
- Route state vlastní výběr; label, pořadí, jazyk a lokální cache ho neurčují.
- Přímý odkaz, reload, login návrat a browser Back/Forward mají prokázané stejné chování jako kliknutí.
- Oprávnění a feature availability platí i při ručně vložené URL; přepnutí identity neukáže stará data.
- Staré vstupní URL fungují přes výslovně uvedené redirecty; ostatní nahrazené navigační mechanismy jsou odstraněné.
- Plán neautorizuje commit, push, deploy ani tenant rollout. Lokální implementaci autorizoval execution prompt a následné zadání uživatele.

## Oprava premisy při implementaci

`unit_admin_page.dart: SideMenu` obsahuje také Users a feature-gated Quotes. Routy `users` a `quotes` patří do úplného inventáře; bank-accounts dnes vstupuje z UnitSettingsScreen přes MaterialPageRoute a bude přesunut pod unit shell.

`auto_route-11.1.0/routing_controller.dart:295-305` hledá při `navigatePath`/`pushPath` nejbližší matcher od aktivního nested routeru. Lokální wildcard tedy zachytí i absolutní cestu; widget test pro návrat orders/current -> history prokázal původní no-op. Vnější vstupy používají `root.buildPageRoute(..., includePrefixMatches: false)` a nativní typed push/replace/navigate. Browser PlatformDeepLink používá přímo root `navigateAll` knihovny.

`routing_controller.dart:1460-1472` odstraňuje stránky v replaceAll před guardy. Kanonický Back objektů proto nejprve volá společný discard preflight; browser vstup používá stejnou hranici v deepLinkBuilder před změnou stacku.

Runtime ověření ukázalo, že `TabsRouter._navigateAll` ignoruje match neobsažený v jeho tab listech. Lokální not-found proto patří do stacku jako sibling prázdného child shellu s tabs, ne mezi podporované navigační taby. Toto přidává pouze malé nativní AutoRouter wrappers bez změny URL a uchovává tabs pod chybovou stránkou. `RouteMatcher._matchByRoute:214` navíc z wildcard routy vyrobí doslovné `*`; při vnějším catch-all vstupu se proto zachová původní RouteMatch přes root.navigateAll, stejně jako PlatformDeepLink.


## Doplňující důkaz a stav provedení

`auto_route-11.1.0/routing_controller.dart:844-857` při změně seznamu tabů zachová název aktivní routy, ale vymaže child controllers a volá `setActiveIndex(..., notify: false)`. Pouhé odebrání feature tak změnilo obsah bez změny URL. Sdílený shell nyní před výměnou knihovních tabů normalizuje i již aktivní zakázanou sekci native replace; behaviorální test ověřuje shodný obsah a URL.

Vlny 1-5 jsou implementované v izolovaném worktree `/tmp/festapp-tab-deep-links` z `main` `3912447c8`. Deletion ledger je uzavřen; oprava breadcrumb strut je zachovaná. Podrobné cílené ověření a přesná omezení browser scénářů jsou v [evidence/tab-deep-links-validation-2026-10-03.md](evidence/tab-deep-links-validation-2026-10-03.md). Commit/push/deploy/rollout nebyly provedeny. Připojení celé aplikace k přihlášeným testovacím tenantům a release gates zůstávají samostatnou validací, nikoli deklarovaným výsledkem fixture testů.

## Dodatek z plného lokálního E2E

Flutter 3.47.2 web engine při zpracování SystemNavigator route-information znovu skládá queryParametersAll a volá Uri.decodeComponent (SDK lib/web_ui/lib/src/engine/window.dart). Samotné widget testy proto neodhalily ztrátu preview-day ve vnořeném login redirectu. Native DefaultRouteParser má úzkou webovou transportní kompenzaci v PlatformRouteParser; AutoRoute zůstává jediným vlastníkem historie. Pro zachování query používat root.urlState.uri, protože currentUrl používá Uri.decodeFull. Regresní test simuluje konkrétní engine transport včetně rezervovaných znaků a opakovaných hodnot.

Bankovní detail ověřuje členství seznamem načteným pro unitId z UnitAdministrationScope. Globální RightsService.currentUnit může během obnovy kontextu přechodně ukazovat jinou jednotku; viditelnost a práva nadále hlídá UnitAdminPage. Detail proto nerozhoduje o členství z tohoto přechodného globálního stavu. Regresní test vrací platný účet během změny globálních práv a zachovává oddělený test odmítnutí cizího účtu.
