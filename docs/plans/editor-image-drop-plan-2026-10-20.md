# Přetažení obrázku přes celou plochu editoru

Datum: 2026-10-20
Stav: Implementováno a cíleně ověřeno; celé pojmenované sady mají tři reprodukovaná selhání palet mimo tuto změnu.
Ověření: low-risk pro tento plán; cílené standardní ověření při implementaci kvůli sdílenému importu a blokování souběžných změn.

## Výsledek a hranice

Uživatel přetáhne jeden podporovaný soubor z disku kamkoliv přes tělo editoru vstupenky nebo Blueprint editoru. Editor zvýrazní cílovou oblast a po úspěšném importu zobrazí nový podklad. Funguje to i při již nastaveném podkladu. Dosavadní výběr souboru zůstane dostupný a používá stejnou importní operaci jako drop.

Rozhodnutí: obrázek nastavuje či nahrazuje existující podklad, nevytváří nový samostatně polohovatelný objekt. Současné modely i importy pracují s jedním podkladem. Pozice upuštění proto nemění jeho umístění; zůstávají existující nástroje pro polohu/ořez a zobrazení.

„Celá plocha“ znamená celé tělo konkrétního editoru včetně plátna, postranních panelů a prázdných míst. Hlavička, globální navigace, spodní ukládací lišta a otevřené modální dialogy nejsou jeho drop oblastí. Na úzkém rozložení se zachová stejný kontrakt. Zákaznický výběr sedadel ani veřejný JS klient se nemění.

Bez změn SQL, datového schématu, Worker API, PDF rendereru, oprávnění nebo produkce. Bez nového balíčku, globálních DOM listenerů, importu URL, clipboardu, složek nebo hromadného vkládání.

## Zjištěný stav

| Fakt | Důkaz | Dopad |
|---|---|---|
| Oba editory používají sdílené editorské prvky externího balíčku. | `lib/components/ticket_layout/views/ticket_layout_editor.dart`, `lib/components/blueprint/views/blueprint_controls_bar.dart`; `package:venue_seat_picker/editor_ui.dart` exportuje barvy, fonty, paletu a číselné ovládání. | Sdílená vrstva existuje, nemá však obal pro externí drop souborů. |
| Festapp již používá `desktop_drop` a `cross_file`. | `pubspec.yaml`, `lib/widgets/drop_file.dart`: `DropFile`. | Použít existující technologii a `XFile`; `DropFile` nelze přímo použít jako průhledný obal, má vlastní pevnou upload UI. |
| Editor vstupenek má hotový import, render i uložení podkladu. | `TicketLayoutEditorState.upload` v `ticket_layout_editor.dart`, `TicketLayoutService.uploadBackground`, `TicketLayoutSaver`; `lib/components/ticket_layout/README.md`. | Drop volá stejnou operaci, zachová resolve, reset ořezu, dialog změny poměru stran a dosavadní save/cancel. |
| Blueprint import je nyní uvnitř ovládací lišty. | `BlueprintControlsBar._uploadSvgBackground`, `_uploadImageBackground`, `_removeBackground`. | Přesunout vlastnictví změn podkladu do stavu `BlueprintTab`, aby je volaly lišta i drop. |
| Blueprint ukládá inline SVG nebo URL do jednoho pole. | `BlueprintModel.backgroundSvg`, `BlueprintTab.loadData`, `_draft`, `VenueSeatController.setBackdrop(VenueBackdrop.parse(...))`. | Zachovat pole i způsob vykreslení; úspěšná změna musí aktualizovat model i controller a označit draft za změněný. |
| Rastrový upload rozpoznává PNG, JPEG, GIF, WebP podle bajtů, nikoliv SVG nebo HEIC. | `ImageFileFormat.detect`, `DbImages.uploadImage`, `workers/image-worker/src/upload-policy.ts:processUploadImage`. | Nenabízet formáty jen podle přípony nebo stávajícího seznamu pickeru. |
| `ImageArea` nabízí JPG/JPEG, PNG, WebP i HEIC, ale GIF chybí. | `lib/components/images/image_area.dart`: `DropFile.allowedExtensions`. | V editoru vstupenek sjednotit výběr i drop podle reálně podporovaných rastrů; globální chování ostatních použití neměnit. |
| Vnořené drop oblasti nejsou automaticky výlučné. | Lokální implementace `desktop_drop` 0.7.1, `lib/src/drop_target.dart:_onDropEvent`: jednotlivé listenery kontrolují vlastní bounds. | Nadřazený drop a vnořený `ImageArea` musí mít explicitně jediného příjemce. `IgnorePointer` samotný nestačí. |
| Aktivní lokální dependency se liší od deklarace Git ref. | `pubspec.yaml` připíná `c829a33...`, `pubspec_overrides.yaml` a `.dart_tool/package_config.json` odkazují na `../venue_seat_picker`. | Implementace zůstane ve Festapp; nebude záviset na novém lokálním API sourozeneckého repozitáře. |

## Formáty a produktová rozhodnutí

| Editor | Přijímané soubory | Operace |
|---|---|---|
| Vstupenka | PNG, JPG/JPEG, WebP, GIF | `uploadBackground`, profil `ticket-background`; Worker již převádí GIF/WebP na PNG pro tisk. |
| Blueprint | PNG, JPG/JPEG, WebP, GIF; SVG | Rastry přes `DbImages`, profil `blueprint-background`; SVG přes současnou lokální cestu inline podkladu. |

SVG tedy není dnes podporováno v editoru vstupenek. Plán tuto podporu nerozšiřuje: vyžadovala by samostatné rozhodnutí o konverzi či vektorovém zpracování a ověření PDF. HEIC se v těchto dvou importech nenabízí. Přípona/MIME pomáhá rychlému odmítnutí, autoritou pro rastry zůstávají bajty a stávající upload kontrakt.

Předpoklad: požadavek se týká existujícího podkladu a dnes podporovaných formátů každého editoru. Pokud cílem budou nezávislé obrazové objekty nebo SVG i ve vstupenkách, musí se před implementací změnit tento plán. Pro popsané řešení není technický blocker.

## Cílové vlastnictví a kontrakt

Nový interní `lib/components/_shared/editor_file_drop_region.dart`: `EditorFileDropRegion` obalí libovolný `child`. Přijme explicitní `enabled`, příznak dostupnosti aktivní oblasti, hint, seznam povolených přípon a asynchronní callback `Future<void> Function(XFile) onFileDropped`. Komponenta vlastní pouze detekci, zvýraznění, přijetí jednoho souboru a zámek po dobu callbacku. Nezná Supabase, Blueprint, ticket layout ani upload profily. Formátové/transportní chyby importu hlásí host přes stávající `ExceptionHandler` a toasty; chyby počtu souborů/typu hlásí obal lokalizovanou zprávou.

Obal použije `DropTarget(enable: ...)` a `Stack` s vizuální vrstvou přes `IgnorePointer`. Při opuštění, dokončení dropu i vypnutí se zvýraznění odstraní. Drag pohyby nevyžadují přestavování celého editoru. Hint před dropem smí být obecný, protože včasná dostupnost metadat se liší podle platformy.

Invariants:

1. Jedna externí drop událost spustí nejvýše jeden import. Složka nebo více souborů se odmítne jako celek, nic se tiše nevybírá ani nenahrazuje.
2. Bez aktivního dropu běžné klikání, pan, zoom, výběr, změny velikosti a interní přesuny fungují jako dosud.
3. Handler znovu kontroluje právo editovat, aktuální draft, mounted a busy stav. Samotná průhlednost nebo `AbsorbPointer` nejsou ochranou pluginového listeneru.
4. Drop je vypnut při ukládání, načítání, importu, blokující editorové operaci a překrytí dialogem či neaktivní záložkou. Podkladový editor nesmí reagovat na drop v otevřeném importním dialogu.
5. Výběr souboru, drop a odebrání podkladu sdílejí hostitelský importní zámek. Save/discard/reload nesmí závodit s importem; při zavření/změně draftu se pozdní výsledek neuplatní. Chyba importu ponechá dosavadní model i zobrazení.
6. Úspěch mění jen draft a vykreslení podle existujícího kontraktu; uložení zůstává explicitní. Zrušení neopravňuje mazat nahrané objekty.
7. Rastry respektují `ImageUploadLimits.maxInputBytes`; nečíst zjevně nadlimitní soubor před kontrolou `XFile.length()`. Backend zůstává autoritou limitů a oprávnění. SVG nezavádí nový serverový upload ani HTML/DOM rendering.

## Upřesnění z implementační evidence

- Stávající prototype menu mělo podmínku `allowRemoteUpload` u SVG místo rastru. Oprava skryje rastrový upload a ponechá lokální SVG; host rastr v prototype odmítne i při přímém zavolání.
- Modály mohou ležet nad kořenovým navigátorem, zatímco editor má vnořenou route. Aktivita proto ověřuje i nadřazené route, vedle `TickerMode` pro retained obrazovky.
- Závislost na aktivitě route nesmí spouštět opětovné načtení Blueprint draftu. První načtení je jednorázové; explicitní reload/discard zůstává samostatná operace.
- Importní dialog Blueprintu předává existujícímu `DropFile` omezení přípon a jednoho souboru; výchozí chování ostatních dialogů se nemění.

## Implementační kroky

### 1. Společná drop oblast a jediný příjemce

- Přidat `EditorFileDropRegion` podle kontraktu výše a potřebné texty přes `*_strings.dart` a překlady projektu.
- Do `DropFile` přidat volitelný příznak `dropEnabled` s původním výchozím chováním; napojit jej přímo na `DropTarget.enable`. Klikací picker funguje i při vypnutí dropu.
- Do `ImageArea` přidat průchozí `dropEnabled` a volitelný seznam podporovaných přípon. Ostatní volající zachovají současné výchozí nastavení.
- Udělat explicitní aktivaci oblasti pro modály a retained tabs podle existující navigace. Pokud `ModalRoute.isCurrent` nereflektuje retained tab, host dodá aktivitu vybrané záložky; nespoléhat na hit testing pluginu.
- Výstup: obal lze použít nad libovolným tělem editoru, disabled/modal stav nevydá callback a více souborů nemění data.

### 2. Vstupenka

- V `ticket_layout_editor.dart:_buildEditor` obalit celé `Scaffold.body`, nikoliv jen `TicketLayoutCanvas`.
- Callback směrovat do existujícího `upload`, zpřesnit argument na `XFile`; nezdvojovat upload/resolve ani pravidla poměru stran.
- V místním `ImageArea` vypnout vnořený drop a předat odpovídající seznam rastrů. Picker zachovat.
- Provázat aktivaci se `saving`, `imageBusy`, `fontBusy`, `pdfBusy` a otevřenými blokujícími dialogy. Tyto podmínky prověřit i v importním handleru. Zachovat keyboard a draft close guard.
- Výstup: drop na plátno i do panelu funguje s prázdným i existujícím podkladem, vždy přes jediný upload a dosavadní resolve/crop/save mechanismus.

### 3. Blueprint

- V `blueprint_editor_tab.dart` převzít import/odebrání podkladu z `BlueprintControlsBar`. Lišta bude volat předané callbacky; `_uploadSvgBackground`, `_uploadImageBackground`, `_removeBackground` nenechat jako druhé nezávislé implementace.
- Host nabídne jednotný `importBackground(XFile)` pro drop i soubor vybraný dialogem. SVG detekovat odděleně od rastrů a zachovat dosavadní `<svg` validaci a `VenueBackdrop.parse`; nerozšiřovat v tomto úkolu SVG parser ani pravidla externích zdrojů.
- Nejprve dokončit čtení/validaci/upload a vytvořit backdrop, teprve potom společně zapsat `backgroundSvg` a zavolat `setBackdrop`; obnovit UI a dirty indikaci. Chyba ponechá starý podklad.
- Obalit `Scaffold.body` společnou oblastí. Respektovat `_canEdit`, načtený blueprint, aktivitu tab, zámek importu a `allowRemoteUpload`/prototype režim. Produkční upload z prototype režimu musí zůstat zakázaný, nesmí se obejít přes drop.
- Po dobu importu blokovat konfliktní save/discard/reload/odebrání; při likvidaci nebo změně draftu ignorovat pozdní výsledek.
- Výstup: menu i drop vedou do stejného importu, změna je ihned viditelná a save/discard zachová dosavadní význam.

## Odstranění a kompatibilita

Odstranit pouze duplicitní těla importních operací z `BlueprintControlsBar` po přesunu do hosta a jejich nepoužívané importy. Obecný `DropFile`, `ImageArea`, současná menu i pickery zůstávají. Nevytvářet novou verzi ukládacího formátu, alternativní upload, feature flag ani změnu veřejného API `venue_seat_picker`. Žádná migrace dat.

## Ověření implementace

Implementace a výsledky kontrol jsou v [záznamu ověření](../archive/plans/editor-image-drop-implementation-2026-10-20.md). Níže je původní ověřovací kontrakt; nové cílené testy prošly 7/7, celé pojmenované sady 100/103. Tři chyby palet byly reprodukovány bez nového drop obalu.

- Nové `test/components/shared/editor_file_drop_region_test.dart`: přijme jeden soubor jednou, odmítne složku/více souborů/nepodporovaný typ, disabled a souběžný import nevydají callback, po chybě lze zkusit import znovu. Použít události pluginu nebo jeho existující testovací seam, ne pouze přímé volání callbacku.
- Rozšířit `test/components/ticket_layout/ticket_layout_cases.dart` s fake service: existující i prázdný podklad, přesně jeden upload přes vnořený `ImageArea`, zachování draftu při chybě a změna poměru stran.
- Rozšířit `test/components/blueprint/blueprint_editor_actions_cases.dart`: menu i drop používají import hosta, SVG bez remote uploadu, úspěch aktivuje dirty/save, failure a discard zachovají/obnoví podklad. Použít injekci uploaderu, nikoliv produkční backend; prototype pravidla se testem nesmí vypnout.
- V jednom cíleném běhu provést uvedené tři Flutter soubory s `fvm flutter test --concurrency=1 <soubory>`. Před spuštěním zkontrolovat, že na workstation neběží jiný Flutter task. Následně cílené `fvm dart analyze <změněné Dart soubory>` podle pravidel repo; také nezahajovat souběžně s Flutter taskem.
- Reálný web smoke v izolované background session: PNG/JPG v obou editorech, SVG v Blueprintu, nahrazení podkladu, drop přes panel, překryv modálem, deaktivovaný tab, selhání uploadu a běžný pan/zoom. Využít existující harness `test/components/ticket_layout/editor_preview.dart` a Blueprint prototype; síťové importy mockovat. Prototype s blokovaným uploadem ověřit jako blokovaný, ne jako důkaz produkčního uploadu. Pokud integrační harness pro tento seam chybí, doplnit úzce testovací injekci, bez produkčních dat. Neobcházet repository E2E pravidla ani spouštět další Flutter server souběžně.

## Hotovo a zbylá rizika

Hotovo znamená: drop přes celé tělo obou editorů, přesně jeden import, stejné chování jako picker, zachování draft/save/discard, chyby bez ztráty starého podkladu, blokování překrytých a neaktivních oblastí a cílené kontroly výše. Implementace musí ověřit skutečné OS/browser drop události; widget test samotný nestačí pro platformní chování.

Zbylá rizika: současná jednoduchá SVG validace Blueprintu není plnohodnotný XML parser a může odmítnout SVG s XML deklarací. Tento plán její podporu nerozšiřuje. Neúspěšný resolve po uploadu může zanechat nenavázaný objekt stejně jako dnes; automatický úklid není součástí. Dostupnost externího dropu na dotykových/mobile zařízeních závisí na platformě, picker zůstává dostupný.

Commit, push, změny sourozeneckého repozitáře ani deploy nejsou tímto plánovacím zadáním autorizované. Případný release řešit samostatně pro jeden vybraný tenant.
