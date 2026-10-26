# Jeden HTML editor pro web, Android a iOS a úpravy přímo v kontextu

Datum: 2026-09-30
Stav: lokální kanonická implementace dokončena; reálná zařízení a live backend gates otevřené
Verification: standard — společné UI, uložený HTML kontrakt a autorizovaný import médií
Provedení: úsporné, po ucelených změnách; cílené ověření podle rizika, bez opakovaných průzkumů a kontrol
Rozsah větví: main. Žádný tenant, build ani nasazení nejsou tímto plánem autorizovány.

### Implementační checkpoint 2026-09-30 - kanonická implementace

**Lokální implementace a odstranění starých cest jsou dokončené. Připravenost
k vydání zůstává podmíněná reálnými zařízeními a nasazeným backendem.** Tento
checkpoint nahrazuje původní rozpracovaný stav; plán pod ním zachovává zadání a
výchozí inventář, nikoli tvrzení o současném pracovním stromu.

Jedinou editační cestou je `RichHtmlEditorController` + `RichHtmlEditor` nad
Super Editorem. `EditableHtmlField` poskytuje inline režim, společný
`RichHtmlEditorDialog` dialog i rozšíření téhož editoru. `HtmlView` zůstává
čtečkou. Persistovaný/public kontrakt je stále HTML string; žádná migrace dat,
Delta/Markdown persistence ani druhý platformní editor nevznikly.

#### Dokončené hranice

- DOM codec a Super Editor bridge zachovávají bezpečný no-op přesně, HTML
  envelope, inline styly, whitespace/pre, alignment, seznamy a atributy obrázků.
  Reprezentativní email umožňuje skutečnou editaci textu/proměnné v nested
  layoutu i uvnitř th/td a undo/redo. Komplexní vložené bloky lze upravit stejným
  dialogem. Přesun přes různé layout kontejnery je explicitně odmítnut, nikoli
  exportován se ztrátou struktury. Corpus je anonymně autorský reprezentativní
  vzorek, nikoli doložený produkční dump.
- Profily app/song/email oddělují normalizaci od fidelity. App normalizuje až
  změněný obsah; song/email zachovávají typography a whitespace. Upstream
  Markdown/link/image-url reactions jsou odstraněné. HTML/bitmap clipboard
  prochází jednou pipeline a respektuje změny selection/draftu během await.
- Media draft používá skutečný occasion/unit scope, ověření vlastnictví,
  autorizovaný temporary fetch, decode a byte/pixel limity, MIME podle bytes,
  původní GIF/WebP bytes, dedupe a single-flight. Apply nezpůsobí upload; ten
  začíná až při rodičovském writeru. Známé selhání writeru využije upload cache,
  neznámý upload vyžaduje výslovný retry. Obrázky odstraněné z HTML se fyzicky
  nemažou. Upload a entity save nejsou serverově atomické/idempotentní a může
  zůstat orphan asset; tato změna neslibuje přesně jeden upload při ztrátě odpovědi.
- `fetch-http-data` vyžaduje právě jeden kladný safe integer occasionId/unitId,
  caller JWT a `check_upload_permission` přes veřejný anon API key. Žádná
  request-secret/service-role větev ani změna globálního authorizeRequest.
  SafeFetch zachovává SSRF/redirect/size/timeout ochrany a blokuje image control
  plane včetně trailing-dot varianty. Existující SQL RPC dovoluje occasion
  editor/orderEditor a unit editor; nová SQL migrace nebyla potřeba.

#### Caller a writer ledger

| Místo | Kanonická cesta a persistence |
| --- | --- |
| Form editor | Inline header/headerOff, schedule countdown, field/option descriptions, birth-date message, product type/product descriptions; explicitní traversal všech nested HTML polí před existujícím DbForms writerem. |
| Occasion, event edit, speaker, inventory pool | Inline společné pole; validace a případné potvrzení deletion před přípravou médií, původní writer, dirty/cancel ochrana. |
| Email templates | Inline email profil; scope cílové šablony occasion/unit, zachovaná dědičnost, subject/wrapper a původní writer. |
| News composer | Jediný editor, typed async publish seam, potvrzení před uploadem, await writeru a zachování draftu při chybě; unknown publish blokuje nový invoke. Stávající retry se stejným command UUID zůstává. |
| News, information, event/group detail | Inline u obsahu, entity ID a původní aggregateVersion zachované v edit session; původní write seam, bez nové DB locking migrace. |
| Gridy - eshop, quotes, songbook, map/info/schedule, groups | Společný lazy dialog, stabilní row/field binding; header/custom saveAction připravují jen nové/změněné nezrušené řádky před původním writerem. Quote používá unit scope, songbook song profil. |
| Activities | Stejný dialog a parent coordinator; media připravuje cloned bundle až pro autosave/publish, zachovává history a version; publish čeká na běžící autosave. |
| Option/product dialogy | Oba select-one/many i ticket-row caller předávají parent coordinator; lokální Apply bez uploadu. |

#### Deletion ledger a povolené zbývající hranice

Odstraněné soubory: `html_editor_page.dart`, `html_editor_widget.dart`,
`native_html_editor_widget.dart`. Odstraněn `HtmlEditorRoute` v routeru i jeho
regenerovaném výstupu, platformní selektor, FlutterQuill localization delegate,
starý `storeImagesToOccasion` a legacy konverzní/upload helper pipeline.
`quill_html_editor`, `flutter_quill` a `vsc_quill_delta_to_html` nejsou v pubspec
ani locku. V lib/test není reachable caller těchto starých symbolů.

Package resolution původně selhalo kvůli společné přítomnosti Flutter Quill
(Delta 10) a Super Editoru (Delta 9). Konflikt byl odstraněn atomickou migrací
callerů a odebráním starých dependencies, bez dependency override. `pub get`
a regenerace routeru prošly. Pin: `super_editor 0.3.0-dev.52`,
`super_editor_clipboard 0.2.10`, `super_clipboard 0.9.1`.

Záměrně zůstává transitivní **dart_quill_delta 9.4.1**, který vyžaduje upstream
Super Editor; není to Flutter Quill, alternativní UI ani aplikační persistence.
Historické `ql-*` atributy v existujícím HTML a fixtures jsou čtecí HTML
kompatibilita, nikoli editor fallback. Starší klienti stále dostávají HTML.

#### Ověření a otevřené release gates

Závěrečná cílená evidence:

| Kontrola | Výsledek |
| --- | --- |
| `fvm flutter test test/components/html test/components/forms/form_html_content_test.dart test/components/news test/components/images/image_control_client_test.dart test/components/single_data_grid` | 75 passed, 0 failed; poslední běh po poslední funkční změně. |
| `fvm flutter test --platform chrome test/components/html/rich_html_editor_lifecycle_test.dart` | 5 passed, 0 failed; headless izolovaný profil. |
| `deno test --allow-env --allow-net --allow-read supabase/functions/fetch-http-data` | 19 passed, 0 failed; backend kód od tohoto běhu nezměněn. |
| Cílený `fvm dart analyze` editorů, migrovaných callerů a relevantních testů | 0 errors. Po odstranění nového redundantního null guardu zůstává 5 existujících warnings v InfoPage/EventEditPage/EventPage/MyApp a stylové info včetně braces v novém kódu; není vykazováno jako lint-clean. Upravený rich_html_editor.dart samostatně: 0 errors/warnings. |
| `fvm flutter pub get`, router build_runner | Prošlo, lock i generated routes aktualizované. |
| `rg` starých dependencies, tříd/callerů a route v lib/test/pubspec/lock | Bez shody; tři odstraněné editorové soubory neexistují. |
| JSON translations a `git diff --check` | Prošlo; HtmlEditor má stejných 25 keys v en/cs/de/pl/sk/uk, Flutter/web en/cs synchronizované. |

Lokální logy: `/tmp/festapp-html-tests-final.log`,
`/tmp/festapp-html-chrome-final.log`, `/tmp/festapp-html-fetch-tests.log`,
`/tmp/festapp-html-analyze-final.log`, `/tmp/festapp-html-analyze-editor-final.log`,
`/tmp/festapp-html-pub-final.log`, `/tmp/festapp-html-router-final.log`.
Testy jsou lokální; backend RPC/network odpovědi jsou mockované. Widget tests
nenahrazují systémový clipboard ani live authorization.

| Platformní/externí gate | Skutečná hranice důkazu |
| --- | --- |
| Desktop web Chrome | Headless Flutter web widget runner s izolovaným profilem, společný editor/lifecycle. Skutečný OS/browser clipboard tím není doložen. |
| Android web | Kompaktní šířka a Android controls ve widget testu; skutečný Android browser, clipboard/IME/picker neověřené. |
| iOS web | Kompaktní šířka a iOS controls ve widget testu; skutečný iOS browser, clipboard/IME/picker neověřené. |
| Android native | TargetPlatformVariant + mock IME connection; není skutečný device/native build. |
| iOS native | TargetPlatformVariant + mock IME connection; není skutečný device/native build. |
| Live authorization a deploy | JWT/RPC fail-closed testy a čtení SQL kontraktu; žádný live role test ani deployment. Unit temporary fetch potřebuje tuto backendovou změnu před rolloutem. |
| Vizuální fidelity | Light/dark a 360/1000 layout/overflow widget checks, zachovaná HtmlView/field konstrukce. Historické before/after screenshots a skutečné mobilní vizuální posouzení nejsou doložené. |

`fvm flutter devices` našel pouze macOS a Chrome, žádný připojený Android/iPhone.
Skutečné clipboard/gallery, HEIC/orientation, VoiceOver/TalkBack, large-document
paměťové profilování a mobilní web/native smoke zůstávají otevřené. HEIC cesta
je podmíněná decoder podporou dané platformy a při chybě odmítne import; není
vykazována jako ověřená na telefonu. Bez těchto důkazů se tento checkpoint nesmí
použít jako povolení produkčního vydání.

Žádný commit/push/build tenantů/deploy ani produkční upload, email/notifikace
neproběhl. Souběžné blueprint změny, form prototype, wizard artefakty a cizí
`20260930140000_restore_slunovrat_unit_management.sql` byly ponechány.

Výchozí průzkum: main `abf36440f`, lokální pracovní strom obsahuje souběžné změny blueprint UI, FormEditorContent a occasion wizard prototypu. Implementátor před první editací zkontroluje aktuální diff; nevrací ani nepřepisuje nesouvisející změny a nepovažuje tento SHA za neměnný aktuální HEAD.

## Výsledek a neměnný kontrakt

Nahradit iframe editor `quill_html_editor` a zvláštní mobilní Quill editor jedním Flutter editorem postaveným na Super Editoru. V administrativních formulářích upravovat HTML přímo u příslušného pole. V tabulkách a časových osách používat dialog nad týmž editorem. Android a iOS jsou plnohodnotné cílové platformy, nikoli pozdější doplněk.

**V databázi, RPC, modelech, návratových hodnotách a e-mailech zůstává HTML string.** Neukládat Markdown, Delta ani JSON dokument Super Editoru. Interní dokument existuje pouze po dobu editace. Neprovádět hromadný přepis existujících dat ani měnit schéma databáze.

Přechod je dokončen až po migraci všech níže uvedených míst a odstranění obou starých implementací. `HtmlView` je čtečka HTML a zůstává kanonickým zobrazením mimo aktivní editaci.

## Doložený výchozí stav

| Fakt | Důkaz | Důsledek |
|---|---|---|
| Iframe editor používá Quill controller a dvousekundový inicializační timer. | `lib/components/html/html_editor_widget.dart` | Nepřenášet timer ani controller do nové komponenty. |
| `HtmlEditorPage` má dynamickou mapu content/load a vrací HTML; při occasion ukládá obrázky. | `lib/components/html/html_editor_page.dart`, `savePressed` | Nahradit mapu typovaným rozhraním a oddělit editaci od uložení vlastníka. |
| Nová zpráva má dvě platformní implementace a vlastní HTML normalizaci. | `lib/components/news/news_form_page.dart`, `_sendPressed`, `_usesNativeHtmlEditor`; `native_html_editor_widget.dart` | Migrovat i tuto druhou cestu, zachovat potvrzení notifikací. |
| Aktuální výběrová funkce vrací `isWeb`, tedy aktivuje native Quill na celém webu. | `news_form_page.dart: shouldUseNativeNewsEditor`; `news_form_page_layout_test.dart` | Historický komentář o Android webu není současná selection policy; odebrat i tuto funkci a její platformní testy. |
| Formuláře skrývají editor i za `DescriptionWithEdit` a společným sestavováním polí. | `description_with_edit.dart`, `form_fields_generator.dart`, `product_type_editor.dart`, `form_editor_content.dart` | Samotné nahrazení přímých importů nestačí. |
| Tabulky mají společný HTML edit button a skupiny vlastní obdobný renderer. | `single_data_grid/data_grid_helper.dart`, `groups/user_groups_tab.dart` | Upravit společnou cestu a samostatnou výjimku. |
| HTML obrázky mají již opravený web byte loader. | `html_view.dart`, commit `d6b877680`; `test/components/html/html_view_test.dart` | Použít stejný renderer pro URL, paměťové bajty pro dočasné obrázky. |
| Serverové stažení existuje a kontroluje occasion oprávnění i veřejný cíl. | `html_helper.dart: fetchImageData`; `supabase/functions/fetch-http-data/{index.ts,safeFetch.ts}` | Neřešit CORS anonymním proxy ani přímým fetch z webu. |
| Nahrání obrázku podporuje occasion nebo unit, vrací veřejnou URL. | `DbImages.uploadImage`, `ImageControlClient`, `workers/image-worker/src/{upload.ts,auth.ts}` | Zachovat vlastnictví i serverové autorizace. |
| Staré ukládání odstraňuje barvy, upravuje odkazy a styly obrázků. | `HtmlEditorPage.savePressed`, `HtmlHelper`, `NewsFormPage._sendPressed` | Zachovat účelové politiky, neaplikovat jednu destruktivní normalizaci na vše. |
| Původní helper tiše přeskočí neúspěšné stažení obrázku. | `HtmlHelper.storeImagesToOccasion` | Nové uložení musí chybu vrátit a držet draft. |
| E-shopový grid předává jako occasionId hodnotu popisu produktu. | `lib/components/eshop/eshop_columns.dart`, renderer `PRODUCT_DESCRIPTION` | Opravit kontext; nikdy jej odvozovat z HTML nebo náhodné aktivní occasion. |
| Fetch kontroluje jen `occasion_users.is_editor_order`, upload dovoluje occasion editor nebo order editor. | `_shared/auth.ts`, `_shared/supabaseUtil.ts: isUserEditorOrder`; `database/functions/user_permissions/check_upload_permission.sql` | Sjednotit permission seam pro fetch a upload, nikoli jen přidat unit parametr. |
| Worker upload vytváří náhodný klíč a image record ještě před uložením HTML entity. | `workers/image-worker/src/upload.ts: handleUpload, addImageRecord` | Nelze slibovat atomickou transakci ani přesně jeden upload při ztracené odpovědi. |
| DB chyba při registraci obrázku má kompenzační smazání nového objektu. | Stejný worker: větev `db_failed_compensated` | Tuto existující záruku zachovat; nevydávat ji za kompenzaci pozdější chyby save HTML. |
| Grid potvrzení upraví jen buňku; skutečný save vzniká v headeru přes `updateMethod`. | `single_table_data_grid.dart: onChanged`; `single_data_grid_header.dart: _saveChanges`; `InformationModel.updateMethod` | Přípravu obrázků napojit na header i custom saveAction, ne na zavření dialogu. |
| News composer nyní popne route před vlastním publish zápisem. | `NewsFormPage._sendPressed`; `NewsPage._showMessageDialog`; `DbNews.insertNewsMessage` | Pro nový asynchronní save musí formulář zůstat otevřený až do potvrzení writerem. |
| Při update zprávy existuje aggregateVersion a conflict/rejected výsledek. | `DbNews.updateNewsMessage`, `news_commands.dart` | Nezahodit původní verzi a nepřepsat novější obsah na pozadí inline úpravy. |
| Client command transport drží UUID v rámci vlastních retry, ale nové invoke vytvoří nové UUID. | `client_command_transport.dart: invoke`; `client_command_transport_test.dart` | Zachovat současné transport retry; nespustit nový publish automaticky po vyčerpaných retry s neurčitým výsledkem. |
| HTML option dialog je `OptionDetailEditorDialog`, jeho callery jsou select-one/many editory. | `option_editor_dialog.dart`, `select_one_editor.dart`, `select_many_editor.dart` | Migrovat obě option cesty i jejich callbacks, ne pouze soubor dialogu. |
| Product/option dialog nemá samostatný celý form save/cancel; některá jiná pole mutují parent model živě. | `ProductDetailEditorDialog.initState`; `OptionDetailEditorDialog._editContent` | Zavést Apply/Cancel pro HTML pole, neslibovat rollback ostatních produktových polí. |
| `DbImages.isImageUploaded` kontroluje jen occasion, data URI původní helper rozpoznává jen JPEG/PNG. | `db_images.dart: isImageUploaded`; `html_helper.dart: storeImagesToOccasion` | Potřebný je scoped resolver assetů a obecný data URI parser, ne reuse helperu bez změny. |
| Upload klient neposílá explicitní MIME multipart file a extension fallback je JPG. | `ImageControlClient.upload`; `DbImages._detectExtension` | Ověřit MIME/bytes/extension zejména GIF/HEIC/WebP, neopakovat chybný JPG fallback. |
| Image deletion ověřuje vlastnictví, ne reference ve všech HTML polích. | `database/functions/others/authorize_image_deletion.sql` | Odstranění obrázku z draftu neautorizuje fyzické smazání uloženého sdíleného assetu. |
| Media cache pro client-sync má svůj existující omezený download lifecycle. | `lib/data_services/client_sync/occasion_media_cache.dart`, test `occasion_media_cache_test.dart` | Po save ponechat existující sync invalidaci; nezavést druhý offline cache subsystem. |
| V checkoutu není Flutter integration_test harness ani dependency. | `pubspec.yaml`, inventura integration_test/ | Neuvádět neexistující mobilní E2E příkaz jako již funkční gate. Device evidence zapsat; harness přidat pouze pro skutečné repeatable flows. |

### Co prototyp prokázal a co ne

`prototypes/html_editor_super_editor` běží s Flutter 3.47.2, Super Editor 0.3.0-dev.52 a clipboard 0.2.10. Testy prokázaly základní formátování, ztrátu barvy při cestě HTML → Markdown, změnu prvního řádku tabulky na záhlaví, potřebu vlastního exportu `BitmapImageNode` a výběr byte rendereru. Konkrétní Rufus Miller obrázek byl v prohlížeči vizuálně ověřen z **ručně stažené lokální kopie**.

To není důkaz obecného importu externích URL ani funkční mobilní schránky. Mapování jedné URL, demonstrační počáteční obsah a lokální JPEG nesmí vstoupit do produkční implementace. Nezaměňovat vykreslení lokální kopie za vyřešení paste/upload toku.

## Cílový modul a rozhraní

Kanonický vlastník je `lib/components/html/`. Níže jsou odpovědnosti a orientační umístění, **nikoli povinnost založit osm veřejných tříd či souborů**. Rozhraní má skrýt složitost, ne ji rozdělit do nových kroků, které musí každý caller obsluhovat. Sdružené odpovědnosti lze implementovat jako privátní funkce ve stejném souboru; oddělit je teprve kvůli skutečně odlišnému lifecycle, platformě nebo testovací seam.

- `rich_html_editor_controller.dart`: session, dokument, selection, undo/redo, dirty stav, načtení HTML a export. Controller vytvoří rodič a dispose provede vlastník; rebuild nesmí resetovat text/fokus.
- `rich_html_editor.dart`: Flutter UI, toolbar a adaptivní layout. Vstupy controller, enabled/readOnly a profil povolených funkcí. Neprovádí DB zápisy.
- `editable_html_field.dart`: přepínání `HtmlView` ↔ editor, lokální potvrzení/zrušení a zvětšení plochy. Rodiči předává HTML/draft; nesmí svévolně ukládat entitu.
- `rich_html_editor_dialog.dart`: stejná session v dialogu, na úzké obrazovce ve fullscreen prezentaci. Vrací potvrzený draft; zavření vrací null. Žádná další implementace editoru.
- `html_document_codec.dart`: HTML ↔ dokument, zachování existujícího obsahu, import fragmentů, HTML export všech používaných node/attribution typů.
- `html_media_service.dart`: autorizované načtení externích bajtů, dočasné náhledy, dokončení uploadu a výměna zdrojů při uložení. Explicitní typovaný vlastník `occasion` / `unit` / kontext bez možnosti importu médií.
- `html_content_preparer.dart`: `prepareForSave(draft, owner, profile)` vrátí HTML s trvalými URL nebo chybu. Rodič poté volá stávající doménový save/RPC.
- `html_save_coordinator.dart`: parent-owned registry HTML polí a SaveAttempt. Připraví aktuální snapshot všech HTML polí v jednom parent save; registrace podle identity entity a pole, ne podle pozice widgetu.

HTML string zůstává veřejnou hodnotou. Draft může vedle něj držet dočasná média, původní HTML a změny; tyto údaje se neposílají jako nový databázový formát. Asynchronní příprava při uložení nesmí ztratit média jen proto, že bylo inline pole sbaleno.

### Architektonická kvalita a úsporný kód

- Jeden modul skrývá HTML import/export, selection, dočasná média a přípravu save. Caller zná initial HTML, owner, profil a svůj stávající writer; nezná jednotlivé paste konvertory, media node typy nebo pořadí serializerů.
- `HtmlEditSession` je pracovní stav controlleru, ne druhý controller nad prvním. `HtmlSaveCoordinator` je nutný skutečný parent lifecycle pro více polí/řádků, ale může být malou implementací v controller souboru. `HtmlContentPreparer` je operace media/save části; nezavádět samostatný service jen pro předání stejných argumentů dál.
- Zachovat reálně potřebné oddělení codec od UI a platformního inputu od společného dokumentu. Nevytvářet abstraktní base editor, plugin registry, generický workflow engine, repository/factory pro každý typ node ani konfigurační DSL pro budoucí neexistující callery.
- Závislost na Super Editor types zůstává uvnitř HTML modulu. Doménové modely, grid writers a stránky mimo editor nemají pracovat s jeho document/selection objekty. Common form/grid volající používají shared field/dialog integraci; nemají kopie paste/save/error pipeline.
- Adapter nebo interface zavést tam, kde je skutečný rozdíl (web/native clipboard, testovatelný síťový transport). Na testovatelnost použít malou injektovanou funkci/existující klient, pokud plní potřebnou seam; nepřidávat interface + factory + wrapper s jedinou pass-through implementací.
- Zachované HTML bloky a vlastní serializers doplnit jen pro konkrétní fixture potřeby. Nevytvářet obecný alternativní rich-text engine ani přepisovat upstream package jen kvůli odlišnému názvu metody. Případný úzký fork musí nahradit původní dependency, nikoli přidat paralelní editor.
- Save snapshot, HTML a původní baseline jsou rozdílné účelové hodnoty; nekopírovat celý DOM/dokument, všechny bajty a celou form bundle při každém znaku. Registry ukládá identity a nutná data; serializovat/cacheovat po změně revision a na Apply/Save, ne v každém build.
- HTML profil je malá explicitní politika. Tři profily nejsou důvod pro tři toolbar/controller/codec implementations. Stejné current HTML má jediný kanonický export, bez druhé mutable HTML cache v každé vrstvě.
- Hodnotit kód tím, zda odstranil opakovanou složitost callerů a zpřesnil jejich kontrakt. Nehonit nízký počet řádků na úkor čitelnosti, typů, lifecycle nebo chybových stavů. Neoptimalizovat naslepo; memory/typing nález řešit na jeho skutečné seam.
- Před uzavřením každé ucelené vlny provést krátký vlastní průchod jejího diffu: nový helper musí mít konkrétní odpovědnost/caller, změna nesmí sahat přes private internals balíčku a stará nahrazená cesta má být odstraněná. Žádný další nezávislý agent audit nebo mnohonásobný design/review cyklus bez nového důvodu.

### Vzhled a interakce navazují na současnou aplikaci

Výchozí rozhodnutí je vizuální kontinuita. Migrace mění engine a místo editace, nepřináší redesign obrazovek. Prototypový Material vzhled, název testu, dvojpanel HTML output a předvyplněný obrázek se do app UI nepřenášejí.

- Zachovat existující ThemeConfig/theme, typografii, velikosti textu v daném calleru, barvy, spacing, šířku obsahu, styl tlačítek/ikon a tmavý režim. `EditableHtmlField` má používat současný rámec pole; nepřidávat druhý border/padding nebo novou kartu kolem původní karty.
- Toolbar používá známé ikony a stejné aktivní/disabled stavy. Umístění navazuje na současný kontext: běžný desktop editor má kompaktní nástroje u plochy, composer toolbar zůstává u obsahu zprávy. Inline nebo mobilní omezený prostor dovoluje horizontální lištu/overflow; neduplikovat toolbar pro každou platformu.
- Nové funkce, které nejsou na původní základní liště, umístit kompaktně do overflow nebo rozšíření lišty. Nezvětšovat trvale všechny formuláře kvůli image/list/undo ovládání.
- V inactive stavu zachovat současný HtmlView náhled a edit affordance. Při aktivaci nahradit pouze příslušný obsah, držet scroll a okolní pole. Na mobilu zvětšení plochy zlepší vstup, ale okolní navigace, Save/Cancel a design systému zůstávají známé.
- Čtecí HTML po save musí vypadat stejně jako před editací stejného obsahu; neměnit globální HtmlView renderer/text styly jako vedlejší efekt engine migrace.
- Ve vlně 1 zachytit malý baseline existujícího composeru, jednoho běžného admin formuláře a grid dialogu; reprezentativní desktop a úzká obrazovka, light/dark podle dostupného kontextu. Ve vlně 5 porovnat stejné obsahové fixtures a stavy. Ověřit typografii, spacing, layout, viditelnost akcí a čtecí výsledek; nepořizovat screenshot každého calleru a nebudovat rozsáhlou křehkou pixel-golden sadu.

Přijatelný rozdíl je inline umístění, lepší focus/keyboard nebo nezbytné nativní touch controls. Změna značky, barev, layoutu celého formuláře nebo nová design soustava je mimo tuto práci.

### Efektivní průběh implementace

1. Přečíst plán a jednou ověřit aktuální rozdíl proti jeho inventuře. Znovu prozkoumávat jen změněný nebo dosud nedoložený bod. Výsledek nálezu zapisovat do tohoto plánu; nezakládat další paralelní plány/review dokumenty.
2. Postupovat po svislých cestách: společný modul a jednu form/save cestu ověřit před mechanickou migrací podobných callerů. Opakované callery stejné shared field/grid integrace migrovat souvisle v jedné dávce. Neotevírat nové „prototypy prototypu“ pro každý formulář.
3. Po souvislé změně spustit jednu nejlevnější významnou cílenou validační dávku pro covered seams. Netestovat po každém souboru. Už passing check neopakovat bez změny covered code, nového selhání nebo věcné nejistoty. Celorepo test/build není běžný mezikrok.
4. Fixture matrix je coverage checklist, ne povinnost mnohokrát ověřit stejný invariant různými nástroji. Společné codec/media chování testovat na kanonické seam jednou; u callerů navíc jen jejich save/owner/lifecycle rozdíl. Widget testy zbytečně nekopírují texty a konstrukci widgetů.
5. Gate HTML fidelity, media auth a skutečný nativní vstup se nevynechávají kvůli úspoře. Selhání řešit jedním cíleným hypothesis/probe/fix cyklem; další průzkum musí mít konkrétní nevyřešený signál. Nedostupné zařízení/e-mail fixture označit jako blocker místo nekonečných pokusů nebo falešného úspěchu.
6. Při migraci kontrolovat scoped rg/importy a targeted reads; nedumpovat celé modely/logy/pub resolution opakovaně. Úspěšný command output má být jedna řádka nebo stručný verdict, plný log otevřít až při failure.
7. Neprovádět subagent delegaci, paralelní nezávislé reviews, více variant návrhu nebo široký benchmark bez explicitní další instrukce nebo konkrétního nového rizika. Průběžný handoff obsahuje dokončenou vlnu, změněné seams, výsledek a přesný gate; nepřepisuje celou historii.

Verification zůstává standard pro společné HTML a auth kontrakty. Úsporné provedení omezuje nadbytečnou práci a opakování, nesnižuje potřebné bezpečnostní, datové a mobilní gates. Release kontroly pouze pro explicitně autorizované vydání.

### Přesná hranice session, draftu a writeru

`HtmlEditSession` drží původní HTML, aktuální HTML snapshot, revision, undo a média. Její životnost je parent formulář nebo otevřená read-page editace, nikoli vnitřní editor widget. Čisté HTML pole nepotřebuje session, dokud uživatel nezvolí editaci. Na jednom parentovi současně aktivovat jeden toolbar/fokus; rozpracované ostatní HTML hodnoty zůstávají v registry.

Inline Apply/Cancel pracuje se záložním snapshotem pole. Apply mění jen parent draft; Cancel vrací toto pole na stav při aktivaci. Při uložení parent formuláře se nejprve zahrne právě aktivní text/IME kompozice a validují všechny běžné hodnoty; uživatel nemusí před Save klikat na Apply každého pole. Parent Cancel neukládá nic nového. Nezavádět globální singleton registry ani service locator pro drafty.

Ve stávajících modelech/callbacks může rozpracované HTML dočasně obsahovat data URI, stejně jako dřívější Quill obsah. Bajty, origin metadata a cache uploadů zůstávají u parent-owned session/coordinatoru. **Blob URL ani interní session ID nesmí být jediným zdrojem parent draftu**: zavření dialogu nesmí znehodnotit obrázek. U výsledku dialogu vrátit typovaný interní `HtmlEditResult` s HTML a vlastnictvím media snapshotu; koordinátor přebírá snapshot, ostatní doménové/RPC rozhraní zůstávají HTML string.

SaveAttempt je immutable snapshot `{owner, entityId/localDraftId, revisions, original aggregateVersion, fieldHtml, preparedMedia}`. Během přípravy nesmí uživatel uložit novější text pod starými výsledky; editaci dočasně zamknout nebo zahodit zastaralý výsledek. Před mutací rodičovského modelu připravit všechny HTML hodnoty, poté předat kopii payloadu stávajícímu writeru. Success aktualizuje baseline a dirty stav; error zachová draft a dostupné upload výsledky. Při změně entity, occasion/unit, odhlášení nebo ztrátě práv session ukončit a zrušit pending input operace.

Stavy: `loading → ready/dirty → validating → preparingMedia → savingOwner → saved`. Chyba načtení není prázdný dokument; `loadFailed` nabízí opakovat načtení a nedovolí omylem uložit prázdno. `prepareFailed`/`saveFailed` vrací k rozpracovanému obsahu. `conflict` nechá původní draft a verzi; uživatel může obnovit aktuální obsah nebo kopírovat své změny, bez automatického last-write-wins. `cancelled/disposed` ignoruje pozdní callbacky a nevydává další writer.

### Profily obsahu a konkrétní HTML fidelity smlouva

Profily jsou politiky jednoho codec/editoru, ne jiné editory:

- `appContent`: obecný popis, zpráva, bio, pole formuláře. Nabídnout bold/italic/underline/strike, link, h2/h3, ordered/bullet seznam, indent/outdent, align, undo/redo, image insert/paste. Toolbar nesmí při toggle pouze změnit vizuální stav; každý příkaz má HTML test a zachová selection.
- `songContent`: navíc věrné nové řádky, mezery a preformatted bloky; song text nesmí zkolabovat whitespace.
- `emailContent`: zachování layoutu, CSS a proměnných. Žádné globální `removeColor`, `htmlTrim` ani app-only link normalization nad celým email dokumentem. Úpravy wrapperu jsou mimo tuto migraci.

| HTML konstrukce | Import/UI | Export a důkaz |
|---|---|---|
| p, div, br; české znaky, emoji, entities a NBSP | Text + explicitní block/soft breaks, korektní offsety selection. | Žádné double escaping nebo slučování významných řádků; fixture česky/emoji/NBSP. |
| strong/b, em/i, u, s/strike | Attributions a stejné editor commands. | Sémanticky ekvivalentní markup; nezměněné původní HTML přesně zachované. |
| H1–H6, blockquote, code/pre | Importovat existující úrovně; UI minimálně h2/h3, ostatní uchovat. | Zachovat kód a whitespace bez auto-link přepisů uvnitř code/pre. |
| Nested ul/ol, start/value, Quill data-list/ql-indent | Jeden normalizovaný list model se zachováním nesting/order. | Neměnit bullet na čísla; případné složitější atributy zachovat v metadatech. |
| ql-align-* a style text-align | Metadata odstavce + align UI. | Vlastní serializer: default Super Editor paragraph serializer vrací jen p a metadata align neexportuje. |
| span, color, background, font size/family | Uchovat relevantní existing attrs; toolbar může být užší. | Vlastní inline serializers; default chain nemá color/background/font serializers. Legacy app color policy se aplikuje jen na potvrzené dirty změny tam, kde ji stávající save vyžaduje. |
| a: href, target, rel a šablonové URL | URL validator, odkaz toolbar; placeholder nezměnit. | Povolené http(s)/mailto/tel a legitimní app links; javascript a event attributes nevykonat. `{{resetLink}}` nezměnit na chybně escapovaný URL string. |
| img: src/alt/title/dimensions/style | URL, memory/bitmap a placeholder stavy; media loader. | Vlastní URL serializer uchová atributy; default exportuje pouze src. Úspěšný persisted save má skutečnou trvalou URL. |
| Table: thead/tbody/tfoot, th/td, rowspan/colspan, nested content | Native simple table tam, kde odpovídá model; komplexní layout jako zachovaný HTML blok. | Neupravovaný blok beze změny; změna sousedního textu jej nezničí. Převod nepromuje první td řádek na th. |
| Unknown safe HTML, containers, email-specific markup | Zachovaný blok s čtecím preview, explicitní delete/move; ne předstíraně editovatelný text. | Export původního bezpečného fragmentu i po změně sousedního obsahu. Blocked edit může vyžadovat dopracování pluginu, ne druhý editor. |
| script/onerror/iframe a nedůvěryhodné URL | Nespouštět při paste, preview ani blob decode. | Sanitizace nově vloženého/změněného obsahu má explicitní seznam povolených prvků/attrs/protokolů; celý HTML dokument nelze bezmyšlenkovitě odstranit style tagy potřebné emailu. |

HTML parser musí rozlišit fragment a full document; email body se nesmí obalit náhodnými html/head/body tagy z parseru a připojit ke wrapperu dvakrát. Relativní src/href přepočítat jen pokud clipboard obsahuje doložený source base; jinak zobrazit unresolved source, nedosazovat localhost nebo náhodnou tenant doménu. Ošetřit srcset/lazy data-src a DOM img bez src tak, aby nedošlo k pádu. Původní uložené odkazy se nesmí hromadně kanonizovat bez editace.

Factory metadat a bloků v codec modulu je vlastníkem mapování; nezávislé paste/load/HTML serializers si nesmí definovat další význam týchž atributů. Mapu dokumentových node ID udržet stabilní uvnitř session; změny HTML offsetů nepočítat jako byte offsety vůči Unicode grapheme textu.

### Import a export HTML

1. **Nepoužít cestu přes Markdown jako kanonický import.** Zachovat přinejmenším odstavce, nadpisy, bold/italic/underline/strike, odkazy, seznamy a úrovně, zarovnání, obrázky, tabulky s původním th/td, span a relevantní inline styly. Pravidla pro barvu oddělit podle profilu obsahu; nedědit ztrátu barvy prototypu.
2. Načtení uloženého HTML a vložení fragmentu mají stejný parser a normalizační politiku. Původní HTML, které se nezměnilo, se nesmí při otevření/potvrzení znovu destruktivně serializovat.
3. Needitovatelné části bohatšího HTML uchovat jako zachované bloky v dokumentu. Export je obnoví. Úprava sousedního odstavce nesmí smazat strukturu nebo atributy takového bloku. Nepřidávat druhý editor jako fallback.
4. E-mailové šablony musí zachovat `{{var}}`, tabulky, rozložení a inline CSS. Obsah šablony a wrapper zůstávají oddělené, dědičnost occasion → unit → organization se nemění. Pokud importer nedokáže zachovat zjištěné struktury, je to blokátor přechodu tohoto místa a musí se dopracovat před odstraněním starého editoru.
   Zachování celého email body jako jediného read-only bloku není úspěšná náhrada editoru. Reprezentativní body musí dovolit upravit skutečný obsah a proměnnou i uvnitř používaného layoutu. Pro komplexní kontejnery zachovat HTML AST/envelope a stabilní editovatelné sloty; měnit text/atributy jen mapováním parseru, nikoli string-offset patchem. Statický needitovaný footer nebo dekorace může zůstat zachovaným blokem. Pokud potřebná editace není možná, jde o vstupní codec blocker.
5. Export musí pokrýt `BitmapImageNode` i URL obrázky; neznámý node nikdy tiše nepřeskočit. Uživatele nesmí připravit o draft chyba serializace.
6. Úpravu odkazů, odstranění barev a emailový image style provádět podle profilu, idempotentně. Prázdnost obsahu posuzovat s ohledem na obrázky, ne pouze textovým snippetem. Uživatelský obsah nesmí spouštět skripty; sanitizaci URL/HTML provést na parseru, bez slepého přepisování HTML regulárními výrazy.

### Obrázky a asynchronní životní cyklus

- Obrázek ze schránky, výběru galerie/souboru i obrázek v HTML jsou vstupy jedné media session. Zachovat text i pořadí obrázků v jednom paste. HTML + bitmap v jedné schránce nesmí vést ke ztrátě textu nebo duplicitě obrázku.
- Pro externí URL načíst bajty přes současný `fetch-http-data`, uchovat originální zdroj a zobrazit `Image.memory`. Lokální náhled není upload. Obsah bez CORS, například dodaná slunovratská URL, musí fungovat obecně, bez seznamu ručních výjimek.
- Bílé místo / zakázané čtení schránky není úspěšný paste. Nabídnout vložení URL nebo výběr obrázku, zobrazit chybu a zachovat draft. Při pomalém načítání držet původní selection; po await nevložit obrázek na novou pozici kurzoru. Při dispose nebo novém načtení ignorovat zastaralé výsledky.
- `prepareForSave` nahraje pouze nová média přes existující image worker a přepíše HTML na trvalé URL. Již uložené URL znovu nenahrávat po scoped ověření vlastnictví. Save je single-flight; retry používá již známé dokončené uploady v session. Síťové/autorizační selhání nepovažovat za úspěšné uložení. Ztracená odpověď uploadu je odlišný neurčitý výsledek, viz níže.
- Teprve po úspěšné přípravě volat stávající save vlastníka. Při selhání tohoto zápisu uchovat draft a výsledky uploadů pro retry. Nepřidávat automatické mazání sdílených obrázků ani celé occasion; dosud nedoložený reference-aware lifecycle nesmí být předstíranou garancí cleanup.
- Zrušení editace před save uvolní lokální bajty/object URL. Nepotřebuje produkční upload ani delete. Offline dovolí lokální editaci a podporovaný existující save tok; dokončení nové vzdálené image vyžaduje připojení. Nepřidávat samostatnou perzistentní frontu jen pro tento editor.
- Každý call site předává skutečného vlastníka a capability. `fetch-http-data` nyní přijímá jen occasionId a používá užší `is_editor_order` kontrolu. Ve stejném existujícím endpointu přejít na caller-JWT RPC `check_upload_permission` a přijmout právě jeden kladný bezpečný integer occasionId/unitId; zachovat occasion-only request kontrakt stávajících klientů. Neměnit globální výchozí `authorizeRequest` pro ostatní funkce. Unit obsah musí mít funkční media import ve svém scope; nejde o optional dokončení. Organization-only editor bez unit/occasion writeru není doložený současný vstup, nezavádět nové globální image ownership.
- Group admin oprávnění v `event_page.dart` nejsou totožná s occasion editor oprávněním endpointu. Zachovat právo upravit text; možnost importu médií musí odpovídat serverové autorizaci, ne být automaticky rozšířena změnou UI.

### Scope a autorizace médií

| Vlastník obsahu | Zdroj identity | Fetch + upload | Pravidlo |
|---|---|---|---|
| Occasion description/form/event/news/bio/pool | Model nebo explicitní parent occasionId, zafixovaný při aktivaci session. | `check_upload_permission(p_occasion_id)` caller JWT. | Occasion editor a order editor mají shodný media kontrakt. UI capability není autorizace serveru. |
| Unit quote/content | `QuotesTab.unitId` / InformationModel.unit. | Stejné RPC s p_unit_id, nikdy současně p_occasion_id. | Nulový aktuální occasion není důvod zablokovat oprávněného unit editora. |
| Email body z dědičné šablony | Cílový scope `_saveSettings`/EmailTemplatesResponse, nikoli scope zdrojového zděděného záznamu. | Vybraný destination occasion; jinak unit. | HTML může vytvářet override; obrázek patří tomu stejnému cíli jako uložené HTML. Nezměnit dědičnost. |
| Product grid/detail | ProductModel.occasion nebo ověřený parent form occasion. | Occasion RPC. | Opravit `occasionId: data[PRODUCT_DESCRIPTION]`; neparsovat ID z HTML. |
| Group event popis | Group model + oprávnění writeru. | Group-only admin nemá automaticky upload právo. | Text editovat; nový image import v UI vypnout, pokud media RPC právo nedovolí. Existující obrázky uchovat. |

Existující image URL ve zdrojovém nezměněném HTML zachovat. Pro nově vloženou URL zjistit její původ a vlastnictví: vlastní asset stejného ownera reuse; obrázek jiného ownera nebo externí URL importovat jako nový asset oprávněného destination ownera. Pouhé `host == img.festapp.net` není důkaz vlastnictví. Neprovádět mnoho nezávislých isImageUploaded dotazů na stejnou URL; resolver v SaveAttempt cachuje scope+URL. Při clone/duplicate entity ponechat doménové kopírování médií u současného vlastníka, ne v HTML editoru.

Fetch žádost nesmí přijmout request secret/service-role bypass, nepovoluje privátní rozsahy ani privátní image-api URL, nepředává uživatelovy credentials na externí host. Zachovat safeFetch 10 MiB, max 3 redirects, 15s timeout jednotlivého requestu a veřejné DNS kontroly; změna permission seam nemění bezpečnost stažení. Invalid owner, oba/neither scope, neplatný token, cizí unit/occasion a pouze group-admin musí mít cílené endpoint testy.

### Formáty obrázků, paměť a neurčité výsledky

- Pro načtení používat skutečné MIME z magic bytes a detekovaný formát, ne filename. `ImageControlClient.upload` má předávat ověřený MIME v multipart souboru a matching extension; nepřepisovat všechny ne-PNG/WebP bajty na JPG filename. Běžné PNG/JPEG/WebP musí zachovat dekódovatelný výsledek a PNG alpha.
- GIF/animované WebP: zachovat animaci, když existující upload jde bez transformace; jinak před potvrzenou konverzí ukázat, že se použije statický obrázek. HEIC z iOS normalizovat na otestované PNG/JPEG pomocí platformního decode adaptéru s orientací; neukládat nezobrazený HEIC jako JPG. SVG z clipboardu/externího importu v první verzi nepřijímat jako aktivní HTML; zachování existujícího bezpečného obsahu řeší codec, ne nový upload bez validace.
- Per-image vstup nejvýše 10 MiB podle fetch/worker kontraktu. Výchozí produktová mez decode 16 MP, jediný současný decode, compressed pending media session nejvýše 32 MiB; měřit skutečný peak na referenčním mobilu a upravit zdokumentovaný limit ve vlně 5, než povolit větší dokumenty. Kontrolovat limity před base64 kopiemi/decode, včetně data URI v pasted HTML. Základní memory preview nemá duplikovat decoded bajty při každém keystroke.
- Deduplicace stejného vstupu v jednom draftu podle digest bajtů + destination scope, nikoli pouze filename. Po odstranění obrázku z dokumentu držet lokální data, dokud je může obnovit Undo, a uvolnit je při zavření session. Nepřidávat perzistentní image cache s tokenem do public URL.
- U známého upload success + HTML save failure se retry opře o uloženou URL. U upload timeoutu po možné serverové success není URL známá: stav `uploadOutcomeUnknown`, žádné automatické blind retry ani tvrzení „nic se nenahrálo“. Zachovat draft; explicitní uživatelský retry může vytvořit nový objekt a musí být tak evidovaný. Exactly-once upload není součástí současného worker kontraktu. Pokud implementace potřebuje automatický retry tohoto stavu, nejprve aktualizovat plán o skutečný serverový idempotency protokol a jeho deployment; samotný client digest nestačí.
- Při pozdějším Cancel po neúspěšném HTML save zůstávají již zaregistrované uploady: neodstraňovat je naslepo. `cleanupRemovedImages` není reference-aware a v editorových callsitech se nyní nepoužívá; tento plán nezavádí GC job. Zbytkové osiřelé assety jsou pojmenované riziko, bez automatického mazání sdílených obrázků.

### Android / iOS / mobilní web

Stejný controller a codec všude. Webový clipboard a nativní clipboard mají pouze platformní vstupní adaptéry. iOS musí ověřit `SuperEditorIosControlsControllerWithNativePaste`, systémovou nabídku Vložit a permission chování; Android systémový paste, IME a nativní dekódování. Nezaměnit Android web za Android aplikaci.

Repo iOS deployment target je 15.6 (`ios/Podfile`, Runner project); má photo-library/camera usage strings. Android minSdk je převzatý z Flutter konfigurace; aktuální `super_native_extensions` 0.9.1 požaduje minSdk 23. Ověřit resolved hodnoty, CocoaPods/Gradle plugin registration a native library packaging v debug buildů ve vlně 1/5; neměnit podporované minimum OS bez konkrétního nutného důvodu. Repo již má FilePicker; preferovat jeho image selection a stávající permission texty. `ImageArea` má upload callback a nesmí se celé reuse jako okamžitě uploadující ovládání pro nový dočasný draft. Pokud picker nedokáže potřebný photo-library tok na zařízení, doplnit cílený native picker adapter a potřebné usage strings s doloženým device testem.

Ověřit soft keyboard, českou diakritiku/IME composing, víceřádkový text, selection handles, kopírování, undo/redo, cursor scrolling, viewport insets a back gesture. Inline editor nesmí bojovat s rodičovským scrollováním. Úzká obrazovka má kompaktní toolbar a zvětšení editoru se stejným draftem/undo stackem. Zvětšení není nový HTML route ani nový controller. Galerie/soubor je explicitní cesta pro obrázky i tam, kde OS nenabídne bohatou schránku.

## Rozhodnutí pro všechna současná místa

Inline znamená editor v místě příslušného obsahu, aktivovaný edit akcí. Na čtecích obrazovkách nevytvářet trvale živé editory. Ve formulářích potvrzení pole aktualizuje rodičovský draft a **až save formuláře** ukládá data. Na čtecí stránce má inline úprava vlastní Uložit/Zrušit a zachová současný doménový zápis. Tabulkové buňky nemají dost prostoru pro rich editor.

| Místo / vstup | Cílová prezentace a konkrétní rozhodnutí | Uložení |
|---|---|---|
| `news/news_form_page.dart` | Inline stále otevřený editor v existující stránce nové zprávy; zrušit platformní Quill split. | Validovat draft → potvrdit audience/preview → připravit média → stávající publish writer → teprve potom zavřít. Neuploadovat při zrušeném potvrzení. |
| `news/news_page.dart` | Editovat konkrétní zprávu inline v její kartě; ostatní zprávy zůstávají čtečky. | `DbNews.updateNewsMessage`, následný refresh. |
| `information/info_page.dart` | Inline v právě otevřené informaci/sekci; žádný přechod na HtmlEditorPage. | `DbInformation.updateInformation`, až po potvrzení. |
| `occasion_settings/occasion_settings_tab.dart` | Inline pole popisu v nastavení. | Rodičovský save occasion, nezměnit validace/dirty/cancel. |
| `schedule/event_edit_page.dart` | Inline popis v existujícím formuláři události. | Dosavadní save event formuláře. |
| `schedule/event_page.dart` | Group-admin úprava popisu inline v detailu; přesně zachovat group-event větev. | `DbGroups.updateUserGroupInfo` a refresh; nezaměnit s event description writerem. |
| `speakers/admin/speaker_editor_dialog.dart` | Inline bio uvnitř existujícího dialogu řečníka, zrušit `_editBio` navigaci. | Stávající save řečníka; před jeho potvrzením jen draft. |
| `inventory/views/inventory_pool_settings_view.dart` | Inline pool description v nastavení. | Zachovat original description, cancel a současné pool commands. |
| `forms/views/form_editor_content.dart` — společné HTML pole | Inline obsah hlášek / off textu / dalších polí generovaných společným builderem. | Dosavadní form draft/callback; zachovat enabled, `_prototype`, `_canEdit`. |
| Stejný soubor — form header | Inline header v místě preview, stejné oprávnění a save formuláře. | Rodičovský draft a form save. |
| `forms/widgets_editor/description_with_edit.dart` | Nahradit vnitřek sdíleným inline polem. | `onDescriptionChanged`; prázdný obsah a placeholder se nesmí uložit jako výchozí text. |
| `form_fields_generator.dart`, `product_type_editor.dart` | Nepřímé uživatele DescriptionWithEdit převést týmž sdíleným polem. | Zachovat současné callbacky a form/product modely. |
| `forms/widgets_editor/birth_date_editor.dart` | Inline editace vlastní age/message hlášky přímo u nastavení věku. | Současná vlastnost pole, žádné změny věkové business logiky. |
| `forms/widgets_editor/option_editor_dialog.dart` | Inline uvnitř OptionDetailEditorDialog; migrovat oba callery v select_one_editor/select_many_editor, bez vnořeného HTML route. | HTML Apply změní parent form option draft, HTML Cancel nikoli; žádný DB save při dialog close. |
| `forms/widgets_editor/product_detail_editor_dialog.dart` | Inline popis uvnitř produktu; caller ticket_product_editor_row.dart předá parent coordinator. | HTML Apply/Cancel izoluje popis; ponechat současné live změny quantity/shortTitle. Persist až ve skutečném parent save. |
| `email_templates/views/email_templates_settings_page.dart` | Inline body šablony vedle subject a ostatních nastavení; volitelně zvětšit tutéž session. | `_saveSettings` / `DbEmailTemplates.updateEmailTemplate`, zachovat dědičnost a proměnné. |
| `activities/activities_content.dart` | Kompaktní dialog/popover ukotvený k aktivitě, na mobilu fullscreen stejného editoru. Nevložit editory do každého timeline bloku. | `_recordStateChange` a existující activity draft save; cancel beze změny. |
| `single_data_grid/data_grid_helper.dart` | Jeden sdílený dialog editoru s typovaným lazy load, title a owner. Neexpandovat HTML přímo v buňce. | Předat HTML + media snapshot parent controlleru a `changeCellValue` až po Apply; upload až ve grid header save/custom saveAction. |
| `schedule/schedule_content.dart` | Události v gridu používají společný dialog; detailový formulář je inline. | Stávající grid writer; zachovat lazy `loadContent`. |
| `map/places_content.dart` | Popis místa v gridu: společný dialog. | Dosavadní place writer a skutečný occasion owner. |
| `information/information_content.dart` | Grid informací: společný dialog; čtecí InfoPage je inline. | Dosavadní writer. |
| `information/song/songbook_content.dart` | Grid písní: dialog; zachovat dlouhé texty/zalomení. | Dosavadní song writer a scope. |
| `unit/views/quotes_tab.dart` | Grid citátů: dialog se skutečným unit kontextem. | Dosavadní unit/information writer. |
| `eshop/eshop_columns.dart` | Product description grid: společný dialog, opravit chybný owner argument. | Dosavadní produktový writer; žádná změna objednávek/cen. |
| `groups/user_groups_tab.dart` | Převést vlastní button renderer na společný dialog. | Zachovat group cell writer a oprávnění. |

### Další místa, která mají zůstat čtečkou, a podmíněné nové inline vstupy

`HtmlView` v `form_page.dart`, `forms/widgets_view/*`, `form_creation_helper.dart`, `form_design_settings.dart`, `form_settings_content.dart`, `description_tooltip.dart`, `form_message_widget.dart` je náhled nebo runtime obsah; inline změna patří jeho existujícímu admin vlastníkovi, ne zákaznickému formuláři. Totéž platí pro `map_description_popup.dart`, `speaker_medallion.dart`, `occasion_detail_dialog.dart`, timeline seznamy, ticket/scan výsledek, countdown, red strip a `widgets/detail_dialog.dart`.

`unit_page_base.dart`, `occasion_creation_helper.dart` a případné nové stránky setup wizardu: nevytvořit editor na veřejném detailu nebo v pickeru jen proto, že obsahují HtmlView. Pokud již existuje administrativní pole HTML popisu s writerem, osadit jej stejným inline polem. Rozpracovaný `lib/components/occasion/prototype/occasion_setup_demo.dart` už používá FormEditorContent: získá změnu sdílenou komponentou; nepřepisovat samostatný wizard ani jeho plán v rámci této práce.

Implementátor na začátku caller vlny zopakuje omezenou inventuru `rg -n 'HtmlEditorRoute|HtmlEditorWidget|NativeHtmlEditor|buildHtmlEditorButton|DescriptionWithEdit|HtmlView\(' lib`. Každé nově nalezené admin použití zapíše do tabulky s writerem a důvodem volby. Read-only použití nepřevádět na editor. Tato tabulka obsahuje rozhodnutí, ne automatické povolení měnit business logiku jiných funkcí.

### Seznam HTML polí parent bundle a commit hranice

| Parent / writer | Příprava obsahu musí zahrnout | Specifická save pravidla |
|---|---|---|
| `FormEditorContent.saveChanges → DbForms.updateForm` | header, headerOff, countdownTitle, další HTML metadata v FormModel.data včetně payment_message, field.description, option.description, birth-date HTML hlášky, product.description v related product types. | Ve vlně 3 identifikovat každou hodnotu z modelových konstant a builderů a registrovat stable field keys. Nested snapshot nesmí ignorovat popis produktu jen proto, že dialog už není otevřený. `_prototype` pouze předá bundle do onPrototypeSave bez network/DB uploadu. |
| `SingleDataGridHeader._saveChanges → element.updateMethod` | HTML buňky všech new/updated řádků a jejich parent-owned media snapshoty. | Neuploadovat deletedRows ani filtrem schované nezměněné řádky. Zachovat deleted-row potvrzení a custom saveAction. Po Apply může uživatel sort/filter; field key používá stable entity/localRow ID, ne row index. |
| `NewsFormPage / NewsPage → DbNews.insertNewsMessage` | Composer HTML pro publish; čistý text pro notification dle současné audience logiky. | Stávající callback ve NewsPage změnit na typed async submit callback a vstup přes typed NewsFormRoute. Composer čeká na writer success, error zůstává v composeru. Nevytvářet druhý publish writer. Self-test bez publikované news nepotřebuje upload obrázků do trvalého HTML záznamu. |
| `NewsPage → DbNews.updateNewsMessage` | Upravený message s původní aggregateVersion. | Otevřený draft se nesmí přepsat loadData/projection update. Konflikt nezahazuje editaci. Mutation payload je snapshot, ne předem mutovaný čtecí model zprávy. |
| `EmailTemplatesSettingsPage._saveSettings → update_email_template` | Subject validace a HTML body; wrapper mimo editor. | Destination occasion/unit z EmailTemplatesResponse, preserve code/subs/inheritance. Sanitizace/proměnné bez automatické interpolace v editoru. |
| `InventoryPoolSettingsView._saveChanges → updateInventoryPoolBundle` | Pool description spolu s existujícími contexts/products změnami. | Zachovat rollback `_originalDescription`, error bundle/partial-success handling writeru; HTML prepare nesmí přidat vlastní SQL transakci. |
| Speaker, event, occasion settings | Příslušný description na svém existujícím modelu. | Validace title/time/entity před media upload; návrat z Save až po dokončeném původním writeru. |
| ActivitiesContent + parent activity save | Description každé změněné aktivity z celého editovaného bundle. | HTML Apply vytvoří jednu `_recordStateChange`, ne záznam na každý znak. Ctrl/Cmd+Z v editoru řeší text; mimo něj activity history. Parent undo nesmí nechat media registry ve stavu jiného snapshotu. |

Neukládat do bundle jen naposledy otevřený editor. Jediný helper pro extrakci HTML polí registruje cesty do metadata map podle existujících modelových konstant; ne rekurzivní heuristiku „všechny stringy s `<` jsou HTML“. DescriptionWithEdit callbacks a dynamické field reorder/delete musí přenášet správné identity a dispose vyřazených session.

Nová zpráva s pouze obrázkem je validní HTML pro publish bez notifikace. Při odeslání notifikace musí být neprázdný textový souhrn: validovat před potvrzením a uploadem, nedávat base64/image URL do push body. Stávající audience, self-only a notifikační potvrzení se nemění. `ClientCommandTransport.invoke` již opakuje transport request se stejným p_command_id; tyto existující retry zachovat. Po vyčerpání transport retry unknown publish outcome nesmí spustit automatické další invoke, protože to vygeneruje nové p_command_id. Zapsat neurčitý výsledek a zachovat draft; žádný slib exactly-once notifikací mimo doloženou backend command seam.

### Synchronizace, offline a accessibility

Pro čtecí inline editor držet původní aggregateVersion a entity ID po celou session. Nový serverový HTML/projection epoch nesmí přepsat aktivní editor; čtecí preview se aktualizuje až po Apply/Save nebo Cancel. U dat bez verzované write seam zachovat existující writer a neprohlašovat ochranu proti všem concurrent edits. Nepřidávat DB migraci na optimistic locking v rámci UI cutoveru.

Offline cache `OccasionMediaCache` je samostatná existující čtecí služba. Po úspěšném uploadu jsou image records součástí současné client-sync cesty; ověřit běžnou invalidaci a načtení uloženého obrázku, ne dvojí download pipeline. Offline změny se nesmí tvářit jako synchronizované uložené HTML; respektovat schopnosti jednotlivého writeru. Refresh/process death neslibuje obnovení neuložených editor draftů, protože nová perzistentní draft služba je mimo rozsah. Back/close s dirty obsahem nabízí opustit nebo pokračovat; při save běžícím na pozadí nesmí UI předstírat rollback již provedeného writeru.

Toolbar má lokalizované názvy přes `*_strings.dart`, tooltip/semantics, disabled stavy a viditelný focus. Podporovat tab navigation, keyboard shortcuts a screen-reader text/selection na webu a mobilech. Toolbar click nezahodí výběr textu; picker/link dialog po zavření obnoví předchozí selection. Zoom/text scale a landscape nesmí schovat Save/Cancel pod soft keyboard. Nepřetahovat drag handles form designeru při práci s touch selection uvnitř editoru.

### Fixture corpus a důkazy přechodu

Uložit anonymní deterministické fixtures do `test/components/html/fixtures/` a dokument jejich očekávaného chování. Současný checkout neobsahuje doložený reprezentativní dump skutečných email body HTML; syntetická tabulka sama není důkaz produkční fidelity. Pro email bránu potřebovat bezpečně získaný reprezentativní obsah šablon nebo explicitně evidovat, že brána není uzavřená. Nečíst produkční DB jen kvůli domněnce, že je to automaticky povoleno plánem; nejprve ověřit canonical target a oprávnění podle repo pravidel.

| Fixture/scénář | Musí prokázat |
|---|---|
| Prázdné/null HTML, `<p><br></p>`, pouze image | Empty validation, žádné uložení placeholderu, image-only publish správné podle profilu. |
| Čeština, emoji, NBSP, ampersand/quotes, pasted entity | Round-trip a pozice kurzoru; single escaping v textu/atributech. |
| Quill align/indent/data-list, nested seznam a song/pre | Zachované HTML semantics a whitespace při editaci sousedního odstavce. |
| PNG alpha/JPEG/WebP, bitmap caret insert, HTML text+2 images | Stejné pořadí a žádná image/text ztráta; correct MIME a platná persisted URL. |
| Bez CORS/redirect/corrupt image/missing src/relative URL | Vlastní authorized fetch, explicitní error místo blank image; bezpečný fetch test používá mocks. |
| Email `{{name}}`, `{{resetLink}}`, tables/spans/style | No-op exact HTML a edit skutečného body textu/proměnné uvnitř používaného layoutu bez ztráty okolí. Pouhý read-only export celého body nestačí. |
| Více HTML polí formu, option/product dialog close, reorder/delete | Parent Save připraví všechny dirty hodnoty; Cancel pole/parent, registry identita a dispose. |
| Grid new/updated/deleted/filtered row a custom Save | Upload až v save boundary; nikdy záměna ownera; Apply zachová row versions. |
| Loading exception vs empty result, double Save, late async paste | Nevynucené prázdné uložení, single-flight a správná selection/revision. |
| Upload success + owner save failure; timeout unknown; conflict | Zachovaný draft a retry cache; žádný automatický duplicitní upload/publish nebo wipe content. |
| Group admin, editor/orderEditor/unitEditor, cizí owner/no token | Stejné media auth fetch/upload; zakázané scénáře skutečně odmítnuté endpointem. |
| Existing own/shared/legacy stored images; remove+Undo | Bez zbytečného reuploadu, bez mazání sdílených referencí, Undo zobrazí stejné lokální bajty. |
| Dirty edit + incoming client-sync projection | Draft a baseline verze zůstanou; conflict/pending current content je viditelný. |
| Mobile IME/keyboard/gallery/back/rotate/scroll | Skutečný nativní vstup a HTML reload podle platformní matice níže. |

Každý významný gate má konkrétní test nebo označený manuální důkaz s platformou/SDK/device a výsledkem. Test nesmí jen assertovat, že byl vytvořen widget. Webový screenshot ukazuje skutečný načtený obrázek a HTML výstup, ale nenahrazuje HTML codec ani auth testy.

## Vlny implementace

### 1. Vstupní brány a HTML fixture kontrakt

**Změny:** kompletní fixture corpus z uvedené matice, nový codec a testovací harness ve `test/components/html/`. Projít HTML parser/serializer seam balíčku: aktuální `serialization/html/` obsahuje exportery, `pasteHtml` v clipboard balíčku jde přes html2md. Nepředpokládat hotový lossless HTML importer ani použitelné default inline serializers. Ověřit native TableBlockNode, vlastní preserved-block component a jejich edit/undo/export. Inventarizovat nativní clipboard API a potřeby toolbaru na Android/iOS. Připnout otestované verze SDK/packages a lock, nepovažovat dev verzi za automaticky produkčně vhodnou.

**Ověření:** HTML round-trip sémantiky a nezměněného obsahu, úprava jednoho bloku při zachování sousedních/needitovatelných bloků, bitmap export, stejné th/td. Izolovaný malý nativní smoke na Androidu a iOS a web paste text+image. Bez produkčního obsahu/credentials v artefaktech. Neprovádět repo-wide testy kvůli fixture.

**Výstup:** žádná tichá ztráta obsahu, známá clipboard omezení s funkční image-picker cestou. Pokud Super Editor nutné formátování/needitovatelné bloky nedokáže obsloužit, aktualizovat plán; neprovést plošný cutover na ztrátový importer.

Rozhodovací checkpoint vlny 1 musí zapsat: které fixtures jsou editovatelné, které zůstávají statickými zachovanými bloky, které vlastní komponenty/serializers jsou nutné, zda lze skutečně editovat email body a zda package/SDK/native plugin kombinace prošla smoke. Nelze vlnu uzavřít větou „API vypadá kompatibilně“. Případný fork musí mít pojmenovaného vlastníka/verzi a úzký nutný patch; neudržovat zároveň upstream a fork implementaci jako platformní fallback.

### 2. Kanonický editor a media/save kontrakt

**Změny:** implementovat výše pojmenované rozhraní a parent HtmlSaveCoordinator, HTML profily, toolbar, read-only/disabled, lifecycle, zachování selection při paste, obrazový renderer a media session. Reuse fetch-http-data/safeFetch a ImageControlClient. Sjednotit fetch autorizaci na `check_upload_permission` a doplnit unit scope v existujícím endpointu; neměnit sdílený authorizeRequest globálně. Opravit MIME předávaný upload klientem, scoped known-image resolution a limity. Worker random-key upload nepovažovat za idempotentní. Žádné změny SQL implicitně.

**Ověření:** controller/codec/media cílené testy pro CORS-free URL, bitmap + HTML, známý success retry a unknown upload outcome, chybu uložení vlastníka, dvojklik Save, Cancel, dispose a scope. Endpoint změna je povinná: targeted Deno testy role matrix editor/orderEditor/unitEditor, current occasion-only request kompatibility, both/neither scope a odmítnutí cizího scope, privátní URL, redirectu a limitů. Unit tests nesmí volat veřejnou síť.

**Výstup:** jediná komponenta načte HTML, exportuje HTML, zpracuje obecný image input, drží draft při chybě. Lokální hardcoded kopie z prototypu není součástí produkční cesty.

### 3. Inline formuláře a první svislé cesty

**Změny:** NewsFormPage, OccasionSettingsTab, EventEditPage, sdílený EditableHtmlField, FormEditorContent a DescriptionWithEdit. NewsFormPage dostane typed async submit callback na stávající NewsPage writer, který se awaituje před route pop; `pushPath` nahradit typed NewsFormRoute a potřebné args regenerovat. Confirm před uploadem, self-test bez zbytečných image uploadů. FormEditorContent.saveChanges připraví všechna uvedená nested HTML pole před DbForms.updateForm; prototype branch zůstává bez network writes. Přenést media session i při sbalení inline pole, zachovat práva a parent draft semantics.

**Ověření:** cílené testy news/form/occasion draftu a potvrzení, klávesnice a scrollbar na úzkém viewportu, disabled/prototype stav, Cancel/Back a nevynucené DB zápisy. Neupravovat notifikační publika ani formulářový SQL tok.

**Výstup:** edit/save/reload HTML v těchto cestách, žádný starý editor ve formulářích první vlny; nová zpráva nemá platformní dual editor.

### 4. Zbývající inline vstupy a tabulkové dialogy

**Změny:** všechny další řádky rozhodovací tabulky — především speaker, pool, OptionDetailEditorDialog a oba select one/many callery, product/ticket row, birthday message, email template, read-page inline edits, activities a šest grid callerů plus group renderer. Grid parent controller drží media registry; `_saveChanges` v SingleDataGridHeader a custom saveAction připraví jen HTML políčka skutečně ukládaných řádků před jejich existujícími `updateMethod`. Zachovat row versions a partial-success batch handling. Nahradit lazy map load typovaným kontraktem, rozlišit null/prázdný obsah od load failure. Průběžně evidovat migrované writer/owner.

**Ověření:** stávající cílené testy dotčených oblastí; parent-form multi-field save/cancel, HTML Apply/Cancel v option/product, okamžitý read-page save, news aggregate conflict/projection refresh, lazy grid load/header-save/custom-save a activity text-versus-parent undo. Částečně uložený batch nesmí znovu uploadovat úspěšně připravená média při opakování zbývajících řádků. E-mailový reprezentativní fixture musí projít import/edit/export a zachovat proměnné/markup. Žádné skutečné emaily/notifikace.

**Výstup:** všechna známá edit použití mají rozhodnutou prezentaci a společný controller/codec. Vlastníci mají validní scope, včetně opraveného product gridu. Nemigrovaný řádek znamená nedokončenou vlnu.

### 5. Android, iOS a web skutečné cesty

**Změny:** dopracovat platformní paste adaptéry a touch fullscreen chování podle nálezů, odstranit provizorní workaroundy. Testovat společný HTML kontrakt i při platformních UI odlišnostech.

**Ověření:** web desktop, Android web, Android aplikace, iOS web/Safari a iOS aplikace odděleně: nový i existující HTML obsah, text + image paste, URL bez CORS, image picker, selection, diakritika/IME, undo, focus, Cancel/Back, přepnutí/zvětšení editoru, Save a znovunačtení. Reprezentativně form + dialog + čtecí inline edit. VoiceOver/TalkBack a desktop keyboard navigation. Dostupný simulátor ověřuje UI; real-device clipboard/gallery důkaz vyžaduje zařízení, nikoli pouze widget testy. Zaznamenat peak paměti při velké bitmapě a odezvu psaní v dlouhém HTML; nepoužívat serializer celého dokumentu v každém widget build.

**Výstup:** zapsaný výsledek pěti platforem; nedostupný iPhone/device je přesný neuzavřený gate, nesmí být označen jako otestované. Žádné Play/App Store release ani jiné tenant Flutter builds.

### 6. Odstranění staré cesty a handoff

**Změny:** provést ledger níže, regenerovat AutoRoute z `app_router.dart`, aktualizovat novou feature README a testy. Zdokumentovat HTML/media kontrakt a inline/dialog pravidla pro budoucí callery.

**Ověření:** targeted analyze změněných Dart souborů a všechny dotčené testy v jedné závěrečné dávce; absence starých importů, dependency, route registrací a generated args. Znovu nespouštět již úspěšné testy beze změny covered code.

**Výstup:** jediná editor cesta, žádné fallbacky ani platformní Quill split, plánová tabulka uzavřená. Prototyp lze ponechat jen jako označenou historickou ukázku mimo runtime; jeho hardcoded image map nesmí být importován aplikací.

## Ledger odstranění

| Artefakt | Konečný stav / důkaz |
|---|---|
| `html_editor_widget.dart`, QuillEditorController | Odstranit po posledním calleru; rg v lib/test nenajde použití. |
| `native_html_editor_widget.dart`, NativeHtmlEditorController/Widget | Odstranit; NewsFormPage má jednu komponentu. |
| `HtmlEditorPage`, `/htmlEditor`, content/load dynamická mapa | Odstranit starý route/soubor; dialog/fullscreen používá jediný controller. Ověřit externí deep-link registrace před odstraněním, statický repo route inventář zatím nedokládá veřejný kontrakt. |
| `app_router.gr.dart` staré args / useNativeHtmlEditor | Odstranit regenerací, ne ručně. Nové read-page nebo nav routes nepřidávat bez potřeby. |
| `quill_html_editor`, `flutter_quill`, `vsc_quill_delta_to_html` | Odstranit z pubspec a aktualizovat lock po potvrzení nulových jiných konzumentů. |
| `FlutterQuillLocalizations.delegate` v main.dart | Odstranit s posledním Quill konzumentem. |
| `_usesNativeHtmlEditor`, test-only platform selector | Odstranit; layout testy převést na novou komponentu a behavior seam. |
| `shouldUseNativeNewsEditor`, platform-switch assertions | Odstranit společně s `_usesNativeHtmlEditor`, zachovat meaningful news layout/HTML/save testy. |
| Raw HTML debug logs a dvousekundový Quill init timer | Odstranit s původním widgetem; nový editor neloguje vložený obsah, base64 ani tokeny. |
| Nyní nepoužívané Quill transitive libs/webview support | Odstranit jen pokud dependency graph už nemá jiného vlastníka; nelikvidovat obecné webview/image balíčky podle názvu. |
| Původní HTML page save pipeline | Sloučit přípravu do HtmlContentPreparer; staré duplicity odstranit. Zachovat veřejně používané HtmlHelper snippet/render utilities. |
| URL map, ruční JPEG, bootstrap draft z prototypu | Nikdy nepřenášet do produkční cesty. Případné test fixture jsou izolované a nejsou workaround pro obecný import. |

## Postup přechodu, nasazení a návratu

Lokální implementace vln 1–6 se vyvíjí na main bez aktivace dalších tenantů. Dočasná coexistence starého/new editoru je dovolena jen během nepublikované migrace callerů; konečný merge/publikovaný změnový balík nesmí ponechat platformní fallback ani runtime výběrový feature flag. Stávající vydané mobilní klienty nelze z repozitáře odstranit; musí nadále číst a zapisovat platné HTML, což je externí compatibility hranice, nikoli druhý editor v novém kódu.

1. Nejprve dokončit codec/media/permission testy a ověřit backend změnu lokálně nebo na explicitně autorizovaném test targetu. Nová UI cesta nesmí předpokládat, že unit fetch je již nasazen.
2. Je-li později autorizovaný rollout, nasadit rozšířený **existující** fetch-http-data před novým frontendem/mobilními klienty. Endpoint stále přijímá occasion-only žádosti starších instalovaných klientů; nové unit žádosti používají tentýž endpoint, žádný V2 alias. Ověřit canonical activation target a povolení role matrix, ne jen HTTP 200 pro admina.
3. Potom vydat nový klient pouze pro explicitně vybranou tenant větev. Web cache/version a mobile store release používají současný repo workflow; neřeší se ručním přepisem cache nebo distribucí prototypu.
4. První autorizovaný smoke provést s kontrolovanou test entitou/obrázkem, save/reload a cancel; neodešle news notification/email. Ve výsledku rozlišit local implementation complete, device gates a rollout complete.

Návrat před rolloutem znamená revert kompletního nepublikovaného code balíku, žádný databázový restore. Po chybě zjištěné při rolloutu primárně opravit kanonickou cestu. Případný rollback na předchozí vydaný klient je explicitní release rozhodnutí; starší klient musí rozumět novému uloženému HTML. Nevytvářet za tím účelem legacy editor uvnitř nového klienta. Rollback UI nemaže nové uložené HTML ani nové assety. Permission seam backendu se nevrací automaticky jako vedlejší účinek UI rollbacku.

## Ověřovací příkazy a hranice autority

- Průzkum a tento plán jsou pouze read-only + docs; žádné testy/buildy pro napsání plánu nebyly vyžadovány.
- Implementace: `fvm flutter test test/components/html`, dále cílené soubory příslušných migrated callsite testů; `fvm dart analyze <changed-file>` dle významu změny.
- AutoRoute: `fvm dart run build_runner build --delete-conflicting-outputs`; zkontrolovat jen očekávané generated diffy.
- Při úpravě image fetch endpointu: `deno test --allow-env --allow-net --allow-read supabase/functions/fetch-http-data` a cílené nové authorization testy; síť v testech řídit fixture/mocks, nedotýkat se produkce.
- Při úpravě upload klienta: `fvm flutter test test/components/images/image_control_client_test.dart`; pokud se mění worker, `npm --prefix workers/image-worker run test:unit` a `npm --prefix workers/image-worker run typecheck`, integration tests dle změněného kontraktu. Nespouštět náhodně placený image transform smoke na produkci.
- Migrace grid save: `fvm flutter test test/components/single_data_grid` a nové behavior testy registry/header/custom Save. Zachovat ostatní grid icon/SVG testy; jejich úspěch není důkaz HTML save.
- Composer + notifikace: `fvm flutter test test/components/news`, včetně layout, audience, confirmation a commands. Falešný transport musí potvrdit pořadí confirm → prepare → publish a nulový publish při Cancel.
- Client-sync/media: cílené `occasion_media_cache_test.dart`, news/versioned admin conflict testy podle změněných seam; neprovádět celou synchronizační migraci.
- Browser checks v izolovaném headless session s explicitní konfigurací bez globálního Panerelay provideru. Neovládat uživatelovy taby. Pro lokální Flutter app použít stávající server; všechny pomocné testovací session zavřít. Nativní `fvm flutter devices` discovery a development run pouze na vybraném zařízení pro tento app scope, žádný implicitní tenant release.
- Protože checkout nemá integration_test harness, nejprve založit malý Flutter integration test jen pokud ověřuje skutečné mobile flow; nepřeskočit device smoke kvůli neexistujícímu harnessu. Testování clipboardu reálného OS nelze vydávat za deterministické pouhou simulací key eventu.
- Repo `CONTRIBUTING.md` číst spolu s novějšími `ai_context.md` pravidly: live target je canonical activation; starší zmínky o legacy cloud cíli nepoužít jako oprávnění k zápisům.
- Nasazení backendové změny je samostatný explicitně autorizovaný krok, až po review a cílených gates. Případný release pouze pro aktuálně vybraného tenanta. Tento požadavek na plán neautorizuje deploy, push, posílání notifikací, produkční uploady ani více tenantů.

## Předpoklady a rozhodovací brány

- **A1:** Super Editor umožní potřebný codec a zachované bloky; resolve ve vlně 1. Prototyp neprokázal úplný HTML import.
- **A2:** Organization-only editor není současným doloženým callerem; šablony zde ukládají destination occasion/unit z response. Pokud se při implementaci objeví skutečný org-only writer, aktualizovat owner tabulku a auth návrh před připojením; nehádat ID. Unit import a role matrix mají již konkrétní řešení ve vlně 2. Group-only admin má textové právo bez implicitního media práva.
- **A3:** Existující široké dirty/save workflow se zachová. Nové inline pole může mít explicitní Apply/Cancel, ale nepřidává autosave do DB.
- **A4:** Scoped search web/web_client/docs doložil jen plánové zmínky HTML editor route, nikoli deklarovanou veřejnou integraci. Odstranit interní route po migraci callsites; případné osobní bookmarky nejsou důvod pro novou compatibility route. Nově objevená skutečná externí registrace při implementaci vyžaduje změnu plánu s explicitním rozhodnutím.
- **Gate:** nativní clipboard/IME a reálný image import zatím nebyly v této session prokázány. Nedostupné zařízení/backend test scope uvést jako konkrétní zbývající ověření, ne jako hotovou podporu.

## Hotovo znamená

- Všichni současní edit callery z tabulky používají jediný Flutter editor; inline nebo dialog podle schválené tabulky.
- Vzhled navazuje na současné téma, typografii, rozestupy a akce; porovnání reprezentativních stavů proti baseline potvrzuje téměř shodný design. Prototypové rozvržení se do aplikace nepřenáší.
- Callery používají malé společné rozhraní; konverze a media lifecycle zůstávají uvnitř modulu. Nejsou přidané duplicitní pipeline, průchozí servisní vrstvy ani abstrakce bez doložené potřeby.
- Web, Android a iOS mají funkční editor a ověřenou HTML save/reload cestu. Mobilní web je otestovaný zvlášť.
- Existující HTML se při otevření ani úpravě sousedního bloku tiše neznehodnotí; žádný JSON/Markdown persisted formát.
- Reprezentativní email body lze skutečně upravit včetně proměnných, nejen otevřít jako zachovaný read-only blok; app/song/email profily mají doloženou fidelity matici.
- Obecné obrázky bez CORS mají autorizovaný dočasný náhled a při save trvalou vlastní URL, bez hardcoded výjimek.
- Parent cancel/draft, permissions, email/notifikace, retry a disposal odpovídají uvedeným invariantům.
- Form save zahrnuje všechna nested HTML pole; grid header/custom Save je jediná skutečná image upload hranice tabulek. News composer zůstává otevřený při writer failure a neuploaduje při zrušeném potvrzení.
- Ledger starých editorů/dependency/route je uzavřen a targeted checks prošly. Zbylé device/deployment gates jsou explicitně vykázané; bez nich se nedeklaruje production rollout complete.

## Zbytková rizika

Největší riziko je HTML věrnost, zejména šablony a tabulky; další jsou dev verze Super Editoru, mobilní systémová schránka a rozsah image autorizací. Proto jsou zařazené před plošným cutoverem. Reprezentativní skutečné email HTML zatím není doložené; mobile real-device smoke nebyl proveden. Velké bitmapy vyžadují limity paměti a měření; ruční prototyp neměřil výkon velkých dokumentů. Upload a save entity nejsou atomické a random-key upload nemá serverovou idempotenci; neznámá odpověď nebo pozdější opuštění draftu může zanechat orphan image record, který tento UI plán automaticky nemaže. U neversioned writerů neprohlašovat ochranu proti všem concurrent edits. Neověřený live backend se nenahrazuje přímým veřejným fetch nebo service-token obchvatem.
