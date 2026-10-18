# Ověření nativní podpory tagů v Super Editoru

Datum: 2026-10-18. Průzkum zdrojů a příkladů, bez změn aplikace a bez spouštění testů. Tento dokument zpřesňuje technickou vlnu 2 autoritativního [plánu](email-template-mentions-plan-2026-10-18.md).

## Oprava původního závěru

Super Editor podporu `@` tagů **má přímo v balíčku, který Festapp již používá**. Původní hledání slova `mention` minulo implementaci pojmenovanou `text_tokenizing`, `stable_tags` a `action_tags`. Správný závěr: ve Festapp není podpora zapojená; knihovna nabízí potřebné pluginy i příklady. Není nutný upgrade, fork ani další mentions balíček.

## Zdroje a ověřená verze

- Festapp `pubspec.yaml`: přesně `super_editor: 0.3.0-dev.52`; odpovídající `pubspec.lock` a `.dart_tool/package_config.json` ukazují na instalovaný balíček.
- Lokální publikované zdroje: `/Users/miakh/.pub-cache/hosted/pub.dev/super_editor-0.3.0-dev.52/`.
- Oficiální repozitář byl skutečně naklonován a přečten, ne pouze hledán ve vyhledávači: [Flutter-Bounty-Hunters/super_editor](https://github.com/Flutter-Bounty-Hunters/super_editor).
- Ověřený upstream HEAD: `d75f2d89cf6d5072e81dac4b17817867423eb381`, commit z 2026-10-09. Čtecí checkout při průzkumu: `/tmp/festapp-super-editor-research.tqo9uW`; tento dočasný adresář není implementační závislost.
- Přímé porovnání bajtů: `stable_tags.dart`, `action_tags.dart`, `pattern_tags.dart`, `tags.dart` a demo `feature_stable_tags.dart` jsou mezi instalovanou dev.52 a tímto upstream SHA shodné. Příslušné API tedy není jen možností novější vývojové větve.
- Všechny čtyři tagovací zdroje jsou veřejně exportované z `lib/super_editor.dart` na řádcích 70-73 instalované verze. Nepoužívat importy `package:super_editor/src/...`.

## Co knihovna skutečně poskytuje

| Primitivum | Ověřené chování | Použití / limit pro Festapp |
|---|---|---|
| `StableTagPlugin` | Založení tagu přes `TagRule`, composing notifier, potvrzení, zrušení; `AdjustSelectionAroundTagReaction` brání částečnému výběru potvrzeného tagu. | Hotový základ běžných uživatelských mentions. Není však přímo vhodným modelem lokalizované proměnné. |
| `StableTagIndex.composingStableTag` | `ValueListenable<ComposingStableTag?>` s tokenem a rozsahem. | Nabídka může reagovat na již existující stav pluginu. |
| `FillInComposingStableTagRequest` | Nahrazuje rozpracovaný tag a přidává `CommittedStableTagAttribution`; příkaz má undoable historii. | Stejný řetězec používá pro viditelný text i identitu, přidává mezeru. Nezaměňovat lokalizovaný popisek za kanonický kód. |
| `ActionTagsPlugin` | Konfigurovatelné `TagRule`, `composingActionTag` s `IndexedTag`, cancel a reakce při psaní; samotný výběr akce patří aplikaci. | Doporučený detektor rozpracovaného `@dotazu` bez automatického potvrzování nevybraných hodnot. |
| `PatternTagPlugin` | Přiřazuje atributy tagům podle triggeru/patternu. | Neřeší výběr proměnné, atomickou identitu ani detekci doslovného názvu akce v běžném textu. Pro první implementaci nepřidávat. |
| `AttributedText` placeholders | Objekt na jedné pozici textu, `InsertInlinePlaceholderAtCaretRequest`, `inlineWidgetBuilders`. | Doporučená nedělitelná reprezentace proměnné; objekt drží kód, widget může zobrazit libovolný lokalizovaný popisek. |
| `SuperEditorPlugin.componentBuilders` | Registrace zobrazení vlastních typů bloků. | Složené samostatné proměnné zobrazit vlastním blokovým uzlem; export stále vrací původní token. |
| `AttributedTextBoundsOverlay`, `SuperEditorPopover` | Ukotvení nabídky k atributovanému textu a souhra focusu s editorem. | Převzít vzor z oficiálního dema; vlastní výsledky pocházejí z registru šablony. |
| `SuperTextField` | `AttributedTextEditingController`, `inlineWidgetBuilders`, vlastní keyboard handlers. | Umí inline tokeny i v samostatném poli. Nemá však `SuperEditor.plugins`; nelze tvrdit, že se do něj bez adaptéru předá stejný tagovací plugin. |

Zdroje: [stable tags](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/d75f2d89cf6d5072e81dac4b17817867423eb381/super_editor/lib/src/default_editor/text_tokenizing/stable_tags.dart), [action tags](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/d75f2d89cf6d5072e81dac4b17817867423eb381/super_editor/lib/src/default_editor/text_tokenizing/action_tags.dart), [pattern tags](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/d75f2d89cf6d5072e81dac4b17817867423eb381/super_editor/lib/src/default_editor/text_tokenizing/pattern_tags.dart).

## Příklady a testy přímo od autorů

- [feature_stable_tags.dart](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/d75f2d89cf6d5072e81dac4b17817867423eb381/super_editor/example/lib/demos/in_the_lab/feature_stable_tags.dart): `UserTagsFeatureDemo` instancuje plugin, poslouchá composing tag, zobrazuje seznam u místa psaní a používá fill/cancel requesty. Popisky a seznam nejsou součástí pluginu, jsou součástí příkladu aplikace.
- [feature_action_tags.dart](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/d75f2d89cf6d5072e81dac4b17817867423eb381/super_editor/example/lib/demos/in_the_lab/feature_action_tags.dart): stejný vzor pro akce, které nahradí napsaný příkaz výsledným obsahem.
- [popover_list.dart](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/d75f2d89cf6d5072e81dac4b17817867423eb381/super_editor/example/lib/demos/in_the_lab/popover_list.dart): focus, šipky, Enter a Escape. Není finální přístupná komponenta k prostému zkopírování - obsahuje pevné rozměry, ukázkový vzhled a TODO pro scroll.
- [stable_tags_test.dart](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/d75f2d89cf6d5072e81dac4b17817867423eb381/super_editor/test/super_editor/text_entry/tagging/stable_tags_test.dart): založení tagu, mezery, zrušení Escape, pohyb kurzoru, výběr a úplné smazání tagu napříč platformami.
- `test/super_editor/text_entry/inline_widgets_test.dart` v publikované dev.52: vložení placeholderu mezi psaný text, backspace, zachování při tučném formátování. `test/super_textfield/super_textfield_inline_widgets_test.dart`: vykreslování a interakce inline widgetů v samostatném poli.

Jde o přečtené upstream testy, nikoli o nově provedený důkaz funkčnosti Festapp. Vlastní import/export, historii a clipboard musí ověřit cílené testy adaptéru při implementaci.

## Konkrétní záludnosti ověřené ve zdrojích

### 1. Proč nepřevzít StableTagPlugin beze změny

`TagUserReaction._commitCompletedComposingTag` automaticky potvrzuje tag při opuštění rozsahu. `FillInComposingUserTagCommand` vytváří viditelný text `@tag` a jeho stejnou hodnotu ukládá do `CommittedStableTagAttribution.tagValue`. Reakce ověřuje shodu zobrazeného textu s identitou. Nejde tedy bezpečně vložit text `@Název akce` s jinou identitou `occasionTitle` jen výměnou attribution.

Výchozí pravidlo navíc končí na mezeře/tečce. Povolování mezer sice knihovna podporuje a testuje, ale samo neřeší rozdíl lokalizovaného názvu a kódu ani nežádoucí potvrzování běžného textu. Pro proměnné proto zvolit action composition a nativní objektové placeholdery; neudržovat paralelní upravenou kopii StableTagPluginu.

### 2. Stock submit action tagu používá natvrdo lomítko

V dev.52 `SubmitComposingActionTagCommand.execute` předává `_findTagUpstream` konstantu `defaultActionTagRule`, tedy `/`, místo konfigurovaného `@`. Stejný kód je v ověřeném upstream SHA. `ActionTagsPlugin(tagRule: TagRule(trigger: '@'))` může detekovat psaní, ale jeho výchozí submit nelze pro tento případ použít.

Řešení: vlastní `InsertTemplateTokenRequest`/command přijme kanonický kód a očekávaný `IndexedTag` + revizi. V jedné editorové transakci ověří rozsah, smaže `@dotaz`, nastaví výběr na začátek odstraněného rozsahu a vloží inline placeholder nebo blok stávajícími veřejnými příkazy. Stejný doménový příkaz používá vložení z tlačítka a přijetí doporučení s explicitním rozsahem. Nepotřebuje kopii soukromé `_findTagUpstream`.

### 3. TagRule samo nehlídá naši sémantiku

Prohledávání kolem kurzoru samo o sobě není dostatečný filtr e-mailových adres, odkazů a povolených kontextů. Adaptér před otevřením nabídky i před vložením kontroluje hranici před `@`, typ textového uzlu, absence URL/odkazu, aktivní IME composition a aktuální revizi. Nepřípustnou composition zruší přes `CancelComposingActionTagRequest` s týmž pravidlem; nejde jen o schování nabídky.

### 4. Escape má rozdílné fáze

Plugin reaguje na Escape až na key-up, zatímco `RichHtmlEditor._cancelShortcut` už na key-down volá zrušení celého editoru. Nativní pluginy navíc dostávají klávesy před běžnými `_keyboardActions`, a jejich Escape handler neověřuje, zda menu skutečně existuje.

Adaptér musí převzít Escape v obou fázích jen při aktivní nabídce a označit celé gesto za obsloužené; při zavřené nabídce musí zachovat běžné zavření/guard rodiče. Totéž pro šipky a Enter. Samotné předání stock pluginu do `plugins` bez úpravy routování nestačí.

### 5. Objektový placeholder se musí explicitně serializovat

`AttributedText.toPlainText()` a `substring` reprezentují objekt jako U+FFFC. Dnešní `_writeInline` a obecné copy operace s tímto formátem počítat neumějí. Export proto musí projít text a `placeholders`, objekt nahradit `{{code}}` a zachovat okolní HTML attribution/wrappers. Totéž HTML a plain-text clipboard, klávesové zkratky i floating/mobile toolbar; dnes volají `controller.operations.copy/cut` přímo.

Při importu sestavit tokenizovaný dokument před zachycením `_baseline` a `_baselineHtml`. Při exportu nerozšiřovat a znovu netokenizovat živý dokument, což by měnilo kurzor, historii a dirty stav. Hodnotová rovnost placeholderu se opírá o stabilní kód, nikoli identitu vytvořeného widgetu nebo popisek.

### 6. Životní cyklus pluginu vlastní controller

Nesmí vzniknout různé pluginy pro inline a fullscreen pohled nad stejným `Editor`. `SuperEditorPlugin` má pro widgetové připojení vlastní referenční počítání, ruční `attach()` ale touto ochranou neprochází.

Doporučené zapojení: doménově neutrální adaptér vlastněný controllerem ručně připojí pouze logickou část `ActionTagsPlugin` po existujícím odstranění default reakcí v `_load`, nepředává stejný stock plugin současně do `SuperEditor.plugins`. Vlastní keyboard/menu část se připojí v aktuálním pohledu. Při resetu nejprve detach starého editoru, ukončení composition a odpojení listenerů, pak attach nového; při dispose detach a dispose právě jednou. Tím logika přežije fullscreen přechod a neblokuje Escape na ostatních HTML polích.

## Doporučené minimum vlastní implementace

1. Malý volitelný adaptér `TemplateAuthoringSession` nad `ActionTagsPlugin` a existujícími veřejnými edit requesty. Sdílený editor má obecný provider, e-mailová doména metadata a pravidla.
2. `TemplateTokenPlaceholder(code)` + `inlineWidgetBuilders`; blokový uzel pouze pro samostatné rich fragmenty. Lokalizace se řeší při vykreslení, identita při serializaci.
3. Jedna nabídka podle oficiálního vzoru, se společným vyhledáváním, pořadím a přístupností dle UX specifikace.
4. Import/export a clipboard adaptér pro stávající HTML AST. To je hlavní zbývající práce, nikoli implementace tagovacího jádra od nuly.
5. Předmět sdílí doménový kontrakt a placeholdery; přesná prezentace a volba vstupní komponenty jsou uvedeny v aktualizované UX specifikaci od Astry medium.

Není třeba přidávat všechny tři pluginy. `StableTagPlugin` je důkaz hotové podpory mentions a referenční implementace, `ActionTagsPlugin` je zvolený mechanismus spouštění a `PatternTagPlugin` zůstává nepoužitý. Případný upstream fix hardcoded submit lze navrhnout samostatně; implementace Festapp na něm není závislá.
