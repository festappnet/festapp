# Nastavení celé akce - implementace B

Realizace podle zadání z 2026-11-11 je v čistém worktree
`/Users/miakh/source/festapp-occasion-settings-b`, větev
`feat/occasion-settings-layout-b-20261111`, výchozí main
`a0cc06649`. Původní rozpracovaná kopie zůstala nedotčena.
Původní provedení 2026-11-11 bylo lokální, bez publikace a nasazení.
V rámci sjednocení worktrees 2026-11-13 se změna přenesla na aktuální
canonical main; nové případy jsou registrované v kanonickém testovacím inventáři.

Desktop používá dokument s navigací nad scrollem, gridem 3/2/1 a skutečným
editorem pod vybraným řádkem. Telefon používá nezávislé kapitoly a jeden sloupec.
Původní dispatch všech specializovaných editorů, práva, datumové pickery,
ImageArea, EditableHtmlField, HtmlSaveCoordinator, Save/Discard a samostatný
TicketLayoutSaver zůstávají vlastníky svého chování. Časová zóna je u termínu.

Stabilní hosty mají veřejné FormState registry. Ukládání zachytí onSaved všech
navštívených editorů; validace zahrnuje všechny zapnuté funkce a vynechá vypnuté.
Neplatná skrytá funkce otevře příslušnou kapitolu i panel. Navigace nemění koncept.
Zahodit vytvoří novou generaci. Extension editory uchovávají své widgety, aby
přesun nebo filtrování znovu nevytvořily jejich lokální controllery.

Odstraněno: FeatureForm včetně kopie enabled stavu, starý lineární seznam,
vnější advanced ExpansionTile a jeho stav, celostránkový formMaxWidth,
původní forms/widgets_editor/form_editor_scroll.dart. Jeho algoritmus nyní
vlastní _shared/editor_scroll.dart a používají jej oba původní callers.

## Ověření

Všechny Flutter úlohy byly sekvenční, přes fvm; testy s --concurrency=1.
Preview byl během testů zastaven. Závěrečná analýza upravených souborů po vizuálním doladění je bez nálezů.

- Explicitní Dart analýza všech 23 změněných/nových existujících Dart souborů
  bez chyb či varování; po opravách analýza 5 dotčených souborů bez nálezů.
  Dodatečně upravený form_feature_editor.dart je součástí poslední analýzy.
- Osm nových klíčů existuje ve všech šesti parsovatelných JSON katalozích.
- shared_czech_test.dart, filtr occasion_settings_layout: 4 úspěšné testy.
- shared_czech_test.dart, filtr occasion_features_grid: 4 úspěšné testy.
- advanced_link_visibility: 1 úspěšný stávající test.
- forms_editor_widget: 62 úspěšných stávajících testů.
- FESTAPP_APP_SUPPORTED=false: occasion_features_grid 4 a
  advanced_link_visibility 1 úspěšný test.
- Celkem 71 cílených testů ve výchozím režimu a 5 v ticketing režimu.
  Passing evidence nezměněných starších suites byla zachována; opakovaly se
  pouze kontroly zneplatněné opravami.
- git diff --check bez nálezu.

Testy zahrnují skutečnou veřejnou save cestu stránky s blokujícím skrytým
validátorem, jeden zápis po opravě, oddělený ticket save, obnovení generace,
onSaved, close/search/regroup/resize, read-only a tenantový filtr, 3/2/1 grid,
zvětšené písmo, stejnou šířku a výšku všech dlaždic napříč skupinami,
kompaktní údaje, aktivní HTML koncept při 1300/390/820/1300 px a jeho skutečné
uložení přes rodiče, mobilní kapitoly a svislý reveal nad vodorovným PageView po framech.
První dávka odhalila opravenou chybu kopie dat v náhledu, neohraničenou výšku
karty, Material podklad panelů a přetečení dropdownu v původním Form editoru.

## Bezpečný skutečný Flutter náhled

Entrypoint: test/browser/occasion_settings_layout_preview.dart.
Route: /ples-u-lipy/settings, parametr používá skutečné AppRouter.linkFormatted.
Ukázková akce: Společenský ples U Lípy. Sdílí produkční stránku, skutečné editory,
téma, české lokalizace, validaci a save flow. Fixture explicitně nahrazuje
occasion load/update/refresh/reload, banner upload, HTML média, ticket readiness,
delivery preview, wallet upload a ticket layout service. Další nepodporovaná
operace skončí před transportem. Fixture neinicializuje produkční Supabase a
nezpřístupňuje smazání. Karta náhledu je neaktivní.

První headless browser průchod ve světlém a ztlumeném prostředí ověřil
390/820/1300 px, Formulář/Vstupenku, editaci, přepínání, hledání, změnu šířky,
Save a Discard. Zachycené požadavky mířily na localhost a veřejné vykreslovací
fonty/CanvasKit, žádný produkční backendový požadavek.

Tato fixture není backendový, OAuth ani produkční integrační test.
Některé pokročilé ticket operace bez lokálního ekvivalentu vracejí výslovnou
chybu nepřipojeného backendu namísto předstíraného serverového úspěchu.

## Vizuální doladění po připomínkách

Dlaždice mají jednotnou šířku i výšku v celém gridu. Společná výška vychází
z měření celého podporovaného katalogu při aktuální šířce, jazyku a velikosti
písma; hledání nebo přepnutí zapnutí ji nemění. Popisy nejsou ořezané a Nastavit
je zarovnané dole. Test porovnává skutečně vykreslené rozměry napříč řádky i
zapnutými/vypnutými skupinami.

Údaje o akci mají maximální šířku 720 px. Termín a podružné časové pásmo tvoří
vlastní kompaktní skupinu širokou nejvýše 520 px. Původní datumové a časové
komponenty i jejich logika jsou zachované. Referenční /pro-media stránka sloužila
jako produktový kontext, nikoli jako nový zdroj pravidel nebo další implementace.

Aktivní HTML koncept je doložen widget testem přes skutečný veřejný
RichHtmlEditorController.appendHtml, totožnou instanci při všech šířkách a
skutečné onSave stránky s lokální persistencí. Headless textový vstup do editoru
nebyl spolehlivý; toto omezení automatizace se neobchází privátním State.

Finální doladěné UI prošlo další izolovanou browser kontrolou v 390 a 1300 px,
bez Flutter výjimek nebo přetečení. Náhled byl otevřen v novém aktivním panelu
hlavního Google Chromu; headless relace byly ukončeny. Flutter runtime zůstává
spuštěný na http://127.0.0.1:59273/#/ples-u-lipy/settings .
Aktuální světlé snímky jsou v `docs/previews/occasion-settings-layout-b-final/`.
