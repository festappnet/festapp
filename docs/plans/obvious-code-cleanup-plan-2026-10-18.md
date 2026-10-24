# Úklid doloženého mrtvého kódu a lokálních duplicit

Datum: 2026-10-18  
Stav: Připraveno k implementaci; tento krok zapisuje pouze plán a exekuční prompt.  
Verifikace implementace: standard, protože soupis zasahuje i nevolané obaly autentizace a oprávnění a sdílený dialog docházky.  
Výchozí bod: pracovní strom `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`.

## Výsledek a rozsah

Odstranit doložené zbytky bez změny aktivních produktových toků. Rozsah odpovídá bodům 1-4 posledního shrnutí auditu: odpojené soubory, nevolané metody, přímé závislosti bez importu a malé duplicity. Nejde o body číslované uvnitř starého textového auditu.

Bod 5 shrnutí, tedy velké přechody synchronizace, backendu, storage a hostingu, je výslovně mimo rozsah. Mimo rozsah jsou také SQL cleanup, migrace, Edge/worker změny, aktivace tenantů, změny dat, překladových katalogů, generovaného routeru a vydání aplikace. Odstranění klientského RPC obalu nikdy samo o sobě neznamená odstranění RPC.

Tento plán nahrazuje závěry auditu z 15. října pro uvedený rozsah. Při novém průchodu byly čteny i `test_dart` a `packages/festapp_core`, které starší průchod nepokrýval. Implementace má zůstat v aktuálním stromu; nepřepínat větev, nestashovat ani nepřepisovat cizí práci. Na začátku průchodu bylo 664 změněných, 318 smazaných a 587 nesledovaných položek. Samotné HEAD tedy není úplný reprodukovatelný snapshot.

## Potvrzená zjištění a opravy starého auditu

| Fakt z aktuálního kódu | Důkaz | Rozhodnutí |
|---|---|---|
| Dva odpojené Dart soubory přetrvávají | `lib/components/images/image_model.dart:3`, `lib/components/map/offline_map_style_helper.dart:29`; žádný importující Dart soubor v aplikaci, core ani testech | Odstranit celé soubory |
| Kandidáti se změnili | 57 veřejných statických Dart metod v 33 souborech a 11 JS metod v 9 souborech má jediný výskyt názvu v příslušném klientovi a jeho testech | Uzavřený seznam níže, před mazáním ověřit identitu a volající |
| Stará kompresní duplicita již neexistuje | `image_compression_helper.dart` je smazaný; uploady volí `ImageUploadProfile`; formát detekuje `ImageFileFormat.detect` | Žádné nové slučování komprese, návrat helperu ani změny workeru |
| Čtyři přímé deklarace nemají import | Kořenový `pubspec.yaml`: `cupertino_icons`, `url_strategy`, `flutter_animate`, `flutter_widget_from_html_core`; kontrolovány `lib`, `test`, `test_dart`, core lib/test | Odstranit přímé deklarace, zachovat nutné tranzitivní závislosti |
| URL strategie nepotřebuje balíček `url_strategy` | `lib/config/url_strategy_web.dart:1` importuje přímo `flutter_web_plugins` | Vlastní URL strategii ponechat |
| Dialog doprovodů již vlastní svůj stav i reload | `lib/components/users/companion/companion_dialog.dart:134`, `_CompanionAttendanceDialogState._change` | Použít tento existující vlastník, nevytvářet další koordinátor |
| Nadbytečný dialogový obal je ve třech pohledech | `schedule_page.dart:351`, `my_schedule_page.dart:254`, `event_page.dart:1578` | Odstranit okolní `StatefulBuilder` a jeho vlastní refresh seznamu |
| Detail události používá doprovody i mimo dialog | `event_page.dart`: `_companions`, `loadData`, `_reloadCompanions`, `hasOwnedCompanions` | Zachovat stav stránky a jeho aktualizaci |

Počet výskytů je vyhledávací filtr, nikoli sémantický důkaz. Zahrnuje komentáře i stringy a neodhaluje všechny mrtvé cykly. Tento plán není požadavek na úplnou eliminaci veškerého mrtvého kódu. Neprovádět nový široký audit při implementaci.

## Cílové invarianty

1. Dva odpojené soubory a položky schváleného mazacího soupisu jsou odstraněny, nebo mají konkrétní doložený důvod ponechání podle aktuálního volajícího.
2. Aktivní přihlašování, oprávnění, ukládání osobního programu, cache, registrace, formuláře a hromadné storno se chovají stejně. Z metod nevyvozovat odstranění jejich backendů nebo aktivních kolegů.
3. Sdílený `CompanionAttendanceDialog` vlastní svůj seznam a jeho překreslení. Okolní stránky vlastní jen svůj program/detail a živý callback `canSignIn`.
4. `ImageFileFormat.detect`, `ImageUploadProfile` a stávající upload kontrakt zůstanou beze změn. Nové objekty se stále zpracovávají ve workeru.
5. Kořenový manifest neuvádí čtyři nadbytečné přímé závislosti. Lockfile může některé nadále obsahovat jako tranzitivní.
6. Nevznikne nový alias, fallback, generický dialogový framework ani paralelní obchodní logika. Zachovají se podporované Basic/Advanced/Light programy a jejich rozdílné směrování.

## Uzavřený mazací soupis

### Celé soubory a navazující lokální artefakty

| Artefakt | Akce a důkaz dokončení |
|---|---|
| `lib/components/images/image_model.dart` | Smazat soubor; žádná živá deklarace/import tohoto modelu |
| `lib/components/map/offline_map_style_helper.dart` | Smazat soubor; neodstraňovat aktivní legacy renderer nebo externí `StyleReader` |
| `lib/components/unit/db_units.dart`: `UnitEditDataBundle` | Smazat spolu s nevolaným `getUnitEditData`; dosavadní použití třídy jsou uvnitř tohoto mrtvého toku |
| Importy a soukromé helpery používané výhradně odstraněnými metodami | Odstranit pouze po doložení nulových zbývajících volajících; aktivní sdílené helpery zachovat |

U každé metody následujících tabulek je cílová akce odstranění celého členu v uvedeném souboru, nikoli stejně pojmenovaného symbolu jinde. Před odstraněním použít scoped `rg`, přečíst deklaraci a skutečné volající v aplikaci, core, testech a případných statických vstupních HTML souborech. Při nálezu nového živého volajícího položku ponechat, zapsat cestu a důvod přímo do tohoto soupisu a neodstraňovat volajícího jen kvůli dosažení počtu. Nedoložené položky nesmějí být vykázány jako hotové.

### Dart členy

| Soubor | Metody |
|---|---|
| `lib/theme_config.dart` | `surfaceColor`, `blueColor`, `timetableSelectedColor`, `timetableUnselectedColor`, `grey900` |
| `lib/services/utilities_all.dart` | `formatCurrencyCode`, `isValidUrl`, `isValidEmail`, `sanitizeFullUrl` |
| `lib/services/storage_helper.dart` | `removeByPrefix` |
| `lib/services/responsive_service.dart` | `isTablet` |
| `lib/widgets/buttons_helper.dart` | `bottomBarButton` |
| `lib/data_services/auth_service.dart` | `changeMyPassword` |
| `lib/data_services/rights_service.dart` | `currentUnitUser`, `getIsAdmin`, `canSignInOutUsersFromEvents` |
| `lib/data_services/offline_data_service.dart` | `addAllToMySchedule`, `saveInfoDescription`, `deleteUserInventoryBundle` |
| `lib/data_services/client_sync/client_sync_runtime.dart` | `patchPrivateComponent` |
| `lib/components/organization/db_organizations.dart` | `getOrganization` |
| `lib/components/unit/db_units.dart` | `getUnitEditData` |
| `lib/components/schedule/db_events.dart` | `loadAllMyScheduleOffline`, `hasEventAllowedRole` |
| `lib/components/forms/db_forms.dart` | `getAllFormsWithFieldsViaOccasionLink` |
| `lib/components/images/db_images.dart` | `cleanupRemovedImages` |
| `lib/components/single_data_grid/data_grid_helper.dart` | `returnQuestionMarkOnInvalid`, `backgroundFromText`, `orderStateRenderer` |
| `lib/components/features/feature_service.dart` | `isServiceCapacityGroupsEnabled` |
| `lib/components/email_templates/db_email_templates.dart` | `getAllEmailTemplates`, `sendCustomEmail` |
| `lib/components/html/html_helper.dart` | `stripHtml` |
| `lib/components/groups/db_groups.dart` | `replaceImportedUserGroups` |
| `lib/components/map/db_places.dart` | `getPlace`, `updatePlace` |
| `lib/components/map/offline_map_helper.dart` | `getOfflineSpriteJsonPath`, `getOfflineSpriteImagePath`, `loadOfflineMapStyle`, `getSpriteJson`, `getSpriteImage`, `removeOfflinePackage` |
| `lib/components/news/db_news.dart` | `sendGroupNotification` |
| `lib/components/users/occasion_user_model.dart` | `compareJson` |
| `lib/components/users/db_users.dart` | `updateUserInfo`, `unsafeCreateUser`, `getUserByEmail`, `getLastTimeSignIn` |
| `lib/components/users/import_helper.dart` | `getIndex` |
| `lib/components/activities/constants.dart` | `durationToPostgresInterval` |
| `lib/components/timeline/schedule_helper.dart` | `getTimetableItemTypeAsCanSignIn` |
| `lib/components/eshop/db_tickets.dart` | `stornoTicket` |
| `lib/components/eshop/orders_strings.dart` | `stornoCompleted` |
| `lib/components/occasion/occasion_home_page.dart` | `getTabRoutes` |
| `lib/components/event_feedback/db_event_feedback.dart` | `isEnabledOnOccasion` |
| `lib/components/users/views/users_tab_helper.dart` | `importUsers` |
| `lib/components/forms/widgets_view/form_helper.dart` | `buildDescriptionButton` |

### JavaScript členy

| Soubor | Metody |
|---|---|
| `web_client/src/services/auth_service.js` | `isLoggedIn` |
| `web_client/src/services/rights_service.js` | `isUnitManager` |
| `web_client/src/services/supabase_service.js` | `getLocalUser`, `validateSession` |
| `web_client/src/services/router_service.js` | `navigateToOccasion`, `navigateToLogin` |
| `web_client/src/components/ui/toast.js` | `showInfo` |
| `web_client/src/components/forms/order_preview.js` | `_getAutoTitle` |
| `web_client/src/components/forms/form_helper.js` | `replaceSpotWithId` |
| `web_client/src/components/forms/db_forms.js` | `getAllFormFields` |
| `web_client/src/components/feedback/feedback_fab.js` | `sendMail` |

### Výslovně zachovat

- Dart `FormHelper.replaceSpotWithId` v `lib/components/forms/widgets_view/form_helper.dart` používá Flutter formulář. Mazat jen JS stub v tabulce.
- `DbTickets.stornoTickets` a kanonické ticket commands; mazat pouze nevolaný singulární obal `stornoTicket`.
- `Utilities.removeDiacritics`: po odstranění `sanitizeFullUrl` ho stále používá vyhledávání a další UI.
- Překladový klíč `FeatureOrders.stornoCompletedItem`: používá jej i JS. Odstranění Dart metody není povolení mazat katalogy.
- Aktivní `OfflineMapHelper.getOrDownloadFile`, `getOfflinePackagePath`, `getOfflineStyleFilePath`, `getOfflineMapPackage`, mapové balíky a renderery.
- SQL `get_all_email_templates` volané z `get_entity_email_templates`, `get_all_forms_with_fields` volané z `get_orders_tab_data`, `get_all_form_fields` používané z Dart a `create_user_in_organization_with_data_ws` používané z SQL `update_user`.
- Edge `send-custom-email`, emailová fronta a všechny databázové procedury odkazované odstraňovanými klientskými obaly. Žádný `DROP FUNCTION`.
- `patchPrivateComponent` lze odstranit pouze jako nevolanou metodu; ostatní Client Sync runtime/projekce/capability a legacy větve zůstávají.
- `packages/festapp_core` veřejná rozhraní a data modelů; nová extrakce pravidel do balíčku není součástí úklidu.

## Implementační vlny

### Vlna 1 - Odpojené soubory a nevolané členy

**Cíl:** zmenšit pouze neaktivní klientskou plochu.

Zachytit výchozí diff dotčených souborů, protože řada z nich už obsahuje cizí rozpracované změny. Provést ověření deklarací a volajících pro uzavřený soupis. Smazat uvedené členy, celé dva soubory a `UnitEditDataBundle`. Vyčistit jen nově osiřelé importy/helpery. Například po odstranění `loadOfflineMapStyle` z `offline_map_helper.dart` odstranit jeho `dart:convert` a `vector_tile_renderer` importy; nenarušit download/cache.

**Kompatibilita:** mazání klientského obalu nepřenáší autoritu na backend, tabulku, protokol, lokalizační klíč nebo podobně pojmenovanou metodu. U auth/rights odstranit jen uvedené nevolané členy; nezasahovat do inicializace, tokenů, refreshů ani aktivních kontrol.

**Důkaz při závěrečné validaci:** scoped absence kontrola uvedených deklarací a importů, cílový analyzer zbývajících změněných souborů a klientské testy. Počet odstraněných metod není náhradou za funkční důkaz.

**Výstup:** všechny položky soupisu mají stav odstraněno nebo přesný aktuální volající, kvůli kterému zůstaly. Žádná neodůvodněná „pro jistotu“ kopie.

### Vlna 2 - Nadbytečné přímé závislosti

**Cíl:** manifest obsahuje pouze potřebné přímé deklarace.

Odstranit z kořenového `pubspec.yaml` deklarace `cupertino_icons`, `url_strategy`, `flutter_animate`, `flutter_widget_from_html_core` a přímo související výchozí komentář o Cupertino ikonách. Před úpravou potvrdit i package URI a případné asset/font reference v aplikaci a testech. Neodstraňovat `flutter_web_plugins`, `flutter_widget_from_html` ani `image` používané v testech.

Spustit jednou `fvm flutter pub get` a zachovat cílený `pubspec.lock` diff. Pokud resolver navrhne nesouvisející upgrade nebo vznikne chybějící přímý import, vyřešit jen tuto konkrétní závislost; nespouštět `pub upgrade`, neobnovovat cizí manifest přes checkout. Neměnit core manifest/lockfile bez konkrétní resolverové potřeby.

**Kompatibilita:** tranzitivní `flutter_widget_from_html_core` nebo `flutter_animate` může zůstat potřebné pro jiný balíček. Nepožadovat zmizení těchto názvů z lockfile. Nezasahovat do fontového optimalizátoru ani publikovaných fontových souborů. Netvrdit předem úsporu velikosti buildu.

**Důkaz při závěrečné validaci:** čtyři závislosti nejsou přímými deklaracemi; resolver, analyzer a klientské testy projdou. Žádný nesouvisející upgrade.

**Výstup:** upravený manifest a konzistentní lockfile bez změny URL strategie nebo HTML rendereru.

### Vlna 3 - Nadbytečné řízení dialogu docházky

**Cíl:** jeden vlastník stavu seznamu doprovodů, který už existuje.

Upravit pouze otevírání `CompanionAttendanceDialog` ve `schedule_page.dart`, `my_schedule_page.dart` a `event_page.dart`. V každém odstranit vnější `StatefulBuilder` a jeho vlastní `setDialogState`/lokální reload seznamu. Před zobrazením po async načtení zkontrolovat `mounted`/platnost kontextu. Zachovat stávající `showDialog`, `AppAlertDialog`, data eventu a způsob předávání živého `canSignIn`.

- Ve dvou seznamech programu ponechat počáteční načtení a přímou konstrukci sdíleného dialogu. `refreshData` má obnovit stránku přes `loadData`; dialog pak ve svém `_change` načte a překreslí svůj seznam. Smazat dodatečné načítání v někdejším vnějším builderu.
- V detailu události zachovat `_companions`, protože napájí i tlačítka a průběžné změny projekcí. `refreshData` zavolá existující `loadData(widget.id!)`, které už `_companions` obnovuje. Využít existující parametr `reloadCompanions: () async => _companions`, aby dialog po této obnově nepřidával další identický dotaz. Nepřepisovat `loadData` ani jeho error handling.
- Zachovat pořadí `_change`: provést docházkovou akci, obnovit stránku, získat aktuální seznam, překreslit jen připojený dialog. Nedělat optimistickou registraci, vlastní autorizační rozhodování nebo retry.
- Callback `canSignIn` stále čte aktuální `_dots` nebo `_event`, nikoli boolean zachycený při otevření. Změna kapacity po refreshi musí být vidět v dialogu.

Tři malé konstrukce dialogu zůstávají záměrnými vstupy tří pohledů. Neslučovat celé stránky a nevytvářet nový obecný controller/helper kvůli krátkým handlerům sign-in, mapy nebo skenování. Jejich navigace a stav se liší. Dříve nalezená kompresní duplicita je už vyřešena a nepatří do změnového diffu.

Rozšířit existující `test/components/users/companion_dialog_cases.dart` o chování, ne o porovnávání zdrojových řetězců:

1. Jedna docházková akce vyvolá jednou `changeAttendance`, jednou `refreshData`, jednou `reloadCompanions`; pořadí je správné a nový seznam i změněné `canSignIn` se projeví.
2. Zavření dialogu během čekajícího reloadu nevyvolá pozdní `setState` ani výjimku z odpojeného kontextu.
3. Zachovat existující test cílového companion ID a existující offline blokování. Nový offline test přidat jen pokud aktuální suite toto chování neověřuje a změna ho může ovlivnit.

Nepřidávat zbytečné integrační prostředí nebo test-only globální produkční konfiguraci. Stávající konstruktor již má potřebné injekce. Tyto případy jsou registrovány v `shared_default_1_test.dart`; samotný `_cases.dart` není kompletní klientská validační smlouva. Neměnit registraci, společné fixture prostředí ani pořadí suites.

**Kompatibilita:** globální obnova stránky může mít vlastní legitimní čtení doprovodů pro viditelnost tlačítek. Nejde o slib jednoho síťového dotazu v celé aplikaci; odstraňují se konkrétní nadbytečné reloady ve vnějším dialogovém obalu. Chyba refresh má zachovat dosavadní zpracování chyb.

**Výstup:** žádný z uvedených tří call sites neobaluje docházkový dialog vlastní stavovou replikou seznamu. Změna docházky i dostupnost přihlášení fungují po obnově a po zavření dialogu nevzniká pozdní update.

## Jedna závěrečná validační dávka

Při tvorbě tohoto plánu se žádné testy, buildy ani analyzer nespouštěly. Při implementaci dokončit všechny tři vlny před běžnou validací; resolver ve vlně 2 je nutný přípravný krok. Kontroly neopakovat, pokud se jejich vstupy nezměnily.

1. Zkontrolovat diff proti výchozímu pracovnímu stromu; ověřit pouze vlastní změny, odstraněné deklarace/importy a žádné zásahy do zakázaného rozsahu. Pro seznamy používat scoped `rg`, pro skutečnou správnost analyzer. Řetězce plánu se nepočítají jako živé reference.
2. Cílový `fvm dart analyze` pro každý zbývající změněný Dart soubor, například `fvm dart analyze lib/components/map/offline_map_helper.dart`. Seznam sestavit z vlastních úprav, nikoli celého již špinavého `git diff`. Smazané soubory analyzeru nepředávat. Lze dávkovat přes smyčku s kompaktním souhrnem; nerozšiřovat na repo-wide lint. Nové importní chyby musí být odstraněny, původní nesouvisející diagnostiku oddělit.
3. `./automation/test_client.sh` jednou. To je existující kompletní klientská smlouva: core guard, portable testy, `test_dart` adaptéry a Flutter, s ověřením semantického discovery. Kvůli rozsahu 33 Dart souborů, manifestu a auth/rights nelze nahradit pouze jedním dialogovým testem. Zachovat výchozí limit dvou workerů.
4. `(cd web_client && npm test)` jednou. Zahrnuje regression seams routeru, auth bridge, storage, oprávnění, formulářů a výsledku objednávky. Při chybě loaderu či jiného existujícího nastavení vyjít z aktuálního kanonického runneru, neobcházet ho upraveným testem.

Nepouštět SQL/Edge/produkční integrační sady, browser ani release build jen pro tento klientský úklid. Případný commit/publikace není v aktuálním zadání; pokud ji uživatel později vyžádá, dodržet v té chvíli platné publikační brány včetně `CONTRIBUTING.md` a ancestry pravidel. Při skutečné chybě opravit dotčenou příčinu a opakovat jen invalidované kontroly; nezamlčet předchozí chybu ani nezačít nesouvisející refaktor.

## Rozhodnutí, předpoklady a rizika

- **Rozhodnutí:** plánovat a poté předat exekuční prompt. V této fázi neimplementovat ani nepublikovat.
- **Rozhodnutí:** seznamy jsou konkrétní lokální mazací cíle, nikoli souhlas s backendovým cutoverem. Neplatné kandidáty opravit v tomto plánu, ne v odděleném komentáři.
- **Předpoklad:** aplikace nemá externí runtime konzumenty uvedených interních Dart/JS metod. Kontrola klientských importů a HTML nenašla registraci těchto tříd na `window`/`globalThis`; při implementaci ověřit pouze dotčené vstupy. Pokud se objeví skutečný externí kontrakt, ponechat jej s důkazem a nezavádět nový alias.
- **Předpoklad:** další souběžná práce nezmění volající. Ověřit stav dotčených členů těsně před editací, zvlášť u nedávno měněných `db_places.dart`, `db_forms.dart`, `rights_service.dart` a programových stránek. Neobnovovat staré verze těchto souborů.
- **Riziko:** grafový a textový průchod není plná sémantická analýza. Vymezený seznam, čtení konkrétních deklarací, cílový analyzer a kompletní klientský runner jsou konečný důkaz implementace.
- **Riziko:** část metadat testů se právě přesunula do core a společných sessions. Nevracet staré testové soubory ani neprovádět novou testovou migraci.
- **Blokery:** pro přípravu a lokální implementaci nejsou známy. Produkční stav není potřeba a nepovoluje se jeho zjišťování v rámci tohoto úklidu.

## Definice dokončení implementace

- [ ] Dva odpojené soubory chybí a neexistují jejich osiřelé importy.
- [ ] Všech 57 Dart a 11 JS položek má doložené odstranění nebo aktualizovaný konkrétní důvod ponechání; `UnitEditDataBundle` a nově mrtvé lokální importy jsou vyřešeny.
- [ ] Čtyři přímé závislosti jsou vyřešeny, lockfile je konzistentní a nevznikly nesouvisející upgrady.
- [ ] Tři docházkové vstupy používají stav existujícího dialogu; rodičovské seznamy nejsou druhým vlastníkem stavu dialogu.
- [ ] Nové behaviorální dialogové případy jsou skutečně sesbírány a projdou spolu s klientským a JS runnerem; cílový analyzer nehlásí nové chyby.
- [ ] Image detekce, profily, aktivní backendy, synchronizační režimy, tenant konfigurace a uživatelská data zůstaly mimo změnu.
- [ ] Závěrečný handoff uvádí vlastní změny, skutečně spuštěné kontroly a případný konkrétní blocker. Nepředstírá nasazení nebo čistý celý pracovní strom.


### Ověření původu selhání proti stavu před úklidem

Následné běhové srovnání použilo izolovanou kopii zdrojů se všemi dotčenými soubory obnovenými z předúpravového snapshotu, bez vracení pracovního stromu a bez změny verzí závislostí. Na této kopii byly spuštěny stejné kanonické klientské a JS příkazy.

- Před úklidem: core 157/0 selhání, adaptéry 80/0, Flutter 1103/7. Po úklidu: core 157/0, adaptéry 80/0, Flutter 1106/7. Porovnání přesných názvů potvrdilo totožných sedm selhávajících Flutter případů. Rozdíl tří případů tvoří nové úspěšné dialogové testy.
- Před úklidem se reprodukovaly obě neklasifikované kořenové sady, chybějící klasifikovaný zdroj a jeho čtyři chybějící semantické případy.
- JS před úklidem i po něm: 338 případů, 317 PASS, 20 skip, stejné jediné selhání `home_startup.test.js:61`.
- Cílový analyzer tří souborů s diagnostikami měl před úklidem 14 diagnostik, po úklidu 13. Žádná nepřibyla; kontrola připojeného kontextu navíc odstranila původní `use_build_context_synchronously` v `my_schedule_page.dart`.

Původ zbývajících selhání je tím doložen běhovým srovnáním. Nově osiřelé importy vzniklé úklidem byly odstraněny už během jeho validace; žádná nová diagnostika ani nové selhání z této změny nezůstává.
